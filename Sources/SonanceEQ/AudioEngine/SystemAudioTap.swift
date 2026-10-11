import AudioToolbox
import CoreAudio
import Foundation
import OSLog

private struct RouteSnapshot {
    let format: AudioStreamBasicDescription?
    let outputName: String
}

/// Owns route intent and callback health on the main actor. Core Audio's synchronous
/// permission/device IPC runs only on one serial worker, including rebuild and Stop.
@MainActor
final class SystemAudioTap {
    private let operation = AudioRouteOperation<RouteSnapshot?>(label: "\(kSubsystem).route-control")
    private let route: SystemAudioRoute
    private let watchdog = AudioRouteWatchdog()
    private var desiredRunning = false
    private var pendingRebuild = false
    private var needsCleanup = false
    private var routeGeneration: UInt64 = 0

    private(set) var tapFormat: AudioStreamBasicDescription?
    private(set) var outputDeviceName = "—"
    private(set) var isRunning = false
    var isAudioFlowing: Bool { isRunning && watchdog.state == .flowing }
    var isFinishingOperation: Bool { operation.inFlight }

    var target: EQTarget = .allApps
    var excludedBundleIDs: Set<String> = [] {
        didSet {
            guard desiredRunning, oldValue != excludedBundleIDs else { return }
            rebuild()
        }
    }
    var onRebuild: ((Result<String, Error>) -> Void)?
    var onAudioFlowChange: (() -> Void)?

    init(eq: EQEngine) {
        route = SystemAudioRoute(eq: eq, controlQueue: operation.queue)
        route.onDeviceChange = { [weak self] expectedGeneration in
            DispatchQueue.main.async {
                guard let self, self.routeGeneration == expectedGeneration else { return }
                self.rebuild()
            }
        }
    }

    /// Admission is immediate; success/failure arrives through onRebuild. A previous
    /// timed-out or stopped operation must actually finish cleanup before another start.
    func start() throws {
        guard !desiredRunning else { return }
        guard !operation.inFlight else {
            throw RouteError.finishing
        }
        desiredRunning = true
        submitRoute()
    }

    func stop() {
        routeGeneration &+= 1
        desiredRunning = false
        pendingRebuild = false
        clearFlow()
        if operation.inFlight {
            operation.cancel()
        } else if needsCleanup {
            let route = route
            operation.run(work: { _ in route.stop(); return nil }, cleanup: { route.stop() },
                          outcome: { [weak self] result in
                guard let self else { return }
                if case let .failure(error) = result, !(error is CancellationError) {
                    self.onRebuild?(.failure(error))
                }
            }, finished: { [weak self] in
                self?.needsCleanup = false
                self?.onAudioFlowChange?()
            })
        }
    }

    func retarget(_ newTarget: EQTarget) {
        guard target != newTarget else { return }
        target = newTarget
        rebuild()
    }

    private func rebuild() {
        guard desiredRunning else { return }
        if operation.inFlight {
            pendingRebuild = true
        } else {
            submitRoute()
        }
    }

    private func submitRoute() {
        routeGeneration &+= 1
        let generation = routeGeneration
        let heartbeat = watchdog.beginRoute()
        isRunning = false
        tapFormat = nil
        onAudioFlowChange?()
        needsCleanup = true
        let route = route
        let target = target
        let excluded = excludedBundleIDs
        operation.run(work: { cancellation in
            try route.start(target: target, excludedBundleIDs: excluded,
                            heartbeat: heartbeat, generation: generation, cancellation: cancellation)
        }, cleanup: { route.stop() }, outcome: { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(snapshot):
                guard self.desiredRunning, let snapshot else { return }
                if self.pendingRebuild {
                    self.pendingRebuild = false
                    self.submitRoute()
                    return
                }
                self.tapFormat = snapshot.format
                self.outputDeviceName = snapshot.outputName
                self.isRunning = true
                self.watchdog.arm { [weak self] flowing in
                    guard let self, self.desiredRunning else { return }
                    if flowing {
                        self.onAudioFlowChange?()
                    } else {
                        self.stop()
                        self.onRebuild?(.failure(CoreAudioError.create("Couldn't route audio on this output device", -1)))
                    }
                }
                self.onRebuild?(.success(snapshot.outputName))
            case let .failure(error):
                if error is CancellationError, !self.desiredRunning { return }
                self.desiredRunning = false
                self.pendingRebuild = false
                self.clearFlow()
                let reported = error is AudioRouteOperation<RouteSnapshot?>.Failure
                    ? RouteError.timedOut : error
                self.onRebuild?(.failure(reported))
            }
        }, finished: { [weak self] in
            guard let self else { return }
            if !self.desiredRunning { self.needsCleanup = false }
            self.onAudioFlowChange?()
        })
    }

    private func clearFlow() {
        watchdog.stop()
        isRunning = false
        tapFormat = nil
        onAudioFlowChange?()
    }

    deinit {
        // Never perform potentially blocking OS destruction on the main thread.
        let route = route
        operation.queue.async { route.stop() }
    }

    private enum RouteError: LocalizedError {
        case finishing, timedOut
        var errorDescription: String? {
            switch self {
            case .finishing: return EQText.string("Audio routing is still finishing. Try again when it stops.")
            case .timedOut: return EQText.string("Audio routing took too long. Check Audio Capture permission, then try again.")
            }
        }
    }
}

/// Resources and OS calls are confined to the route-control queue. Only the
/// heartbeat crosses onto the render queue; immutable snapshots return to the UI.
private final class SystemAudioRoute: @unchecked Sendable {
    private let eq: EQEngine
    private let log = Logger(subsystem: kSubsystem, category: "SystemAudioTap")
    private let ioQueue = DispatchQueue(label: "\(kSubsystem).io", qos: .userInteractive)
    private let controlQueue: DispatchQueue
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var deviceChangeBlock: AudioObjectPropertyListenerBlock?
    private var sessionGeneration: UInt64 = 0
    private var tapFormat: AudioStreamBasicDescription?
    private var outputDeviceName = "—"
    var onDeviceChange: ((UInt64) -> Void)?

    init(eq: EQEngine, controlQueue: DispatchQueue) {
        self.eq = eq
        self.controlQueue = controlQueue
    }

    func start(target: EQTarget, excludedBundleIDs: Set<String>,
               heartbeat: AudioRouteWatchdog.Heartbeat,
               generation: UInt64,
               cancellation: AudioRouteOperation<RouteSnapshot?>.Cancellation) throws -> RouteSnapshot {
        stop()
        try cancellation.check()
        try build(target: target, excludedBundleIDs: excludedBundleIDs,
                  heartbeat: heartbeat, cancellation: cancellation)
        try installDefaultDeviceListener(routeGeneration: generation)
        try cancellation.check()
        return RouteSnapshot(format: tapFormat, outputName: outputDeviceName)
    }

    func stop() {
        sessionGeneration &+= 1
        removeDefaultDeviceListener()
        teardown()
    }

    private func build(target: EQTarget, excludedBundleIDs: Set<String>,
                       heartbeat: AudioRouteWatchdog.Heartbeat,
                       cancellation: AudioRouteOperation<RouteSnapshot?>.Cancellation) throws {
        try cancellation.check()
        // 1. Exclude ourselves from the global tap to prevent feedback.
        var exclude: [AudioObjectID] = []
        if let selfObject = try? AudioObjectID.system.translatePID(getpid()), selfObject.isValid {
            exclude = [selfObject]
        }
        // Exclude sibling Sonance audio-tool apps (e.g. Sonance Mixer) so we never re-capture THEIR
        // re-injected audio — otherwise, with both apps running, each processes the other's output and the
        // user hears doubling / silence when toggling either app.
        exclude += AudioProcesses.processObjectIDs(forBundleIDs: AudioProcesses.siblingBundleIDs)
        // Also exclude any apps the per-app mixer owns, so they're not double-tapped/double-muted.
        if !excludedBundleIDs.isEmpty {
            exclude += AudioProcesses.processObjectIDs(forBundleIDs: excludedBundleIDs)
        }

        try cancellation.check()

        // 2. Create the tap. Global (all apps) excludes ourselves to prevent feedback; a per-app tap is
        //    a mixdown of just the chosen processes (we're not in it, so no feedback). If the chosen apps
        //    aren't producing audio right now, fall back to a global tap.
        let desc: CATapDescription
        switch target {
        case .allApps:
            desc = CATapDescription(stereoGlobalTapButExcludeProcesses: exclude)
        case let .apps(bundleIDs):
            let objects = AudioProcesses.processObjectIDs(forBundleIDs: bundleIDs)
            if objects.isEmpty {
                desc = CATapDescription(stereoGlobalTapButExcludeProcesses: exclude)
            } else {
                desc = CATapDescription(stereoMixdownOfProcesses: objects)
            }
        }
        desc.name = "Sonance EQ Tap"
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true

        var newTap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(desc, &newTap)
        guard status == noErr, newTap.isValid else {
            throw CoreAudioError.create("AudioHardwareCreateProcessTap (check Audio Capture permission)", status)
        }
        tapID = newTap
        try cancellation.check()

        // 3. Read the tap's format and prime the EQ.
        let format = try tapID.readTapStreamFormat()
        tapFormat = format
        try cancellation.check()
        eq.resetState()

        // 4. Resolve the real output device we re-route into.
        let outputDevice = try AudioObjectID.system.readDefaultOutputDevice()
        guard outputDevice.isValid else { throw CoreAudioError.create("No default output device", -1) }
        let outputUID = try outputDevice.readDeviceUID()
        outputDeviceName = (try? outputDevice.readDeviceName()) ?? "Output"
        try cancellation.check()

        // 5. Build a private aggregate: real output as main/clock sub-device + the tap.
        // A private aggregate is visible to its OWN process, so the UID carries the "SonanceEQ" marker
        // `AudioDevices` filters on — otherwise it phantoms into the per-app mixer's Output picker.
        let aggregateUID = "SonanceEQ-Output-\(UUID().uuidString)"
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sonance EQ Output",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: desc.uuid.uuidString,
                ],
            ],
        ]

        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregate)
        guard status == noErr, newAggregate.isValid else {
            throw CoreAudioError.create("AudioHardwareCreateAggregateDevice", status)
        }
        aggregateID = newAggregate
        try cancellation.check()

        // 6. Install the render block and start.
        let engine = eq
        var newProc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&newProc, aggregateID, ioQueue) { _, inInput, _, outOutput, _ in
            SystemAudioRoute.route(engine, input: inInput, output: outOutput)
            heartbeat.recordRender()
        }
        guard status == noErr, let proc = newProc else {
            throw CoreAudioError.create("AudioDeviceCreateIOProcIDWithBlock", status)
        }
        procID = proc
        try cancellation.check()

        status = AudioDeviceStart(aggregateID, proc)
        guard status == noErr else { throw CoreAudioError.create("AudioDeviceStart", status) }
        try cancellation.check()

        log.info("Tap running → \(self.outputDeviceName, privacy: .public) @ \(format.mSampleRate, privacy: .public) Hz, \(format.mChannelsPerFrame, privacy: .public) ch")
    }

    private func teardown() {
        if aggregateID.isValid {
            if let proc = procID {
                AudioDeviceStop(aggregateID, proc)
                AudioDeviceDestroyIOProcID(aggregateID, proc)
                procID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        tapFormat = nil
    }

    // MARK: Render (audio thread)

    /// Copy tapped input into the output buffers, then EQ in place.
    /// Handles both interleaved (1 buffer, N channels) and planar (N buffers, 1 channel) layouts.
    private static func route(_ eq: EQEngine,
                              input: UnsafePointer<AudioBufferList>,
                              output: UnsafeMutablePointer<AudioBufferList>) {
        eq.beginRender()

        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outList = UnsafeMutableAudioBufferListPointer(output)

        // 1. Copy each tap input buffer into the matching output buffer (silence if absent).
        for i in 0..<outList.count {
            let outBuffer = outList[i]
            guard let outData = outBuffer.mData else { continue }
            let outBytes = Int(outBuffer.mDataByteSize)
            if i < inList.count, let inData = inList[i].mData {
                let copyBytes = min(outBytes, Int(inList[i].mDataByteSize))
                memcpy(outData, inData, copyBytes)
                if copyBytes < outBytes {
                    memset(outData.advanced(by: copyBytes), 0, outBytes - copyBytes)
                }
            } else {
                memset(outData, 0, outBytes)
            }
        }

        // 2a. Mid-Side decoding needs the L/R pair together.
        if eq.isMidSide, let pair = stereoPair(outList) {
            eq.processMidSide(left: pair.left, right: pair.right, frames: pair.frames,
                              strideL: pair.strideL, strideR: pair.strideR)
            return
        }

        // 2b. Otherwise EQ each channel of each output buffer in place.
        var channelOffset = 0
        for i in 0..<outList.count {
            let outBuffer = outList[i]
            guard let outData = outBuffer.mData else { continue }
            let channels = Int(outBuffer.mNumberChannels)
            guard channels > 0 else { continue }
            let frames = Int(outBuffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            let samples = outData.assumingMemoryBound(to: Float.self)
            for ch in 0..<channels {
                eq.process(channel: channelOffset + ch, data: samples + ch, frames: frames, stride: channels)
            }
            channelOffset += channels
        }
    }

    /// Returns L/R pointers + strides if the output is exactly 2 channels (interleaved or planar), else nil.
    private static func stereoPair(_ outList: UnsafeMutableAudioBufferListPointer)
        -> (left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
            frames: Int, strideL: Int, strideR: Int)? {
        // Interleaved: 1 buffer, 2 channels.
        if outList.count == 1, outList[0].mNumberChannels == 2, let d = outList[0].mData {
            let base = d.assumingMemoryBound(to: Float.self)
            let frames = Int(outList[0].mDataByteSize) / (MemoryLayout<Float>.size * 2)
            return (base, base + 1, frames, 2, 2)
        }
        // Planar: 2 buffers, 1 channel each.
        if outList.count == 2, outList[0].mNumberChannels == 1, outList[1].mNumberChannels == 1,
           let l = outList[0].mData, let r = outList[1].mData {
            let frames = Int(outList[0].mDataByteSize) / MemoryLayout<Float>.size
            return (l.assumingMemoryBound(to: Float.self), r.assumingMemoryBound(to: Float.self), frames, 1, 1)
        }
        return nil
    }

    // MARK: Output-device change handling

    private func installDefaultDeviceListener(routeGeneration: UInt64) throws {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let expectedSession = sessionGeneration
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.sessionGeneration == expectedSession else { return }
            self.onDeviceChange?(routeGeneration)
        }
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, controlQueue, block)
        guard status == noErr else { throw CoreAudioError.create("Default output device listener", status) }
        deviceChangeBlock = block
    }

    private func removeDefaultDeviceListener() {
        guard let block = deviceChangeBlock else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, controlQueue, block)
        deviceChangeBlock = nil
    }

}
