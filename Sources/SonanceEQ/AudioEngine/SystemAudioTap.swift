import AudioToolbox
import CoreAudio
import Foundation
import OSLog

/// Captures all system audio with a Core Audio process tap, runs it through the EQ,
/// and writes the processed result back out to the real output device — no driver.
///
/// Pipeline:
///   apps → [global tap, muted-when-tapped] → private aggregate device
///        → IOProc (copy tap input → EQ → output) → real output device → speakers
///
/// We exclude our own process from the tap so the re-injected audio is never re-captured
/// (feedback). The aggregate uses the real output device as its main/clock sub-device so
/// there is a single shared clock and no drift.
final class SystemAudioTap {
    private let eq: EQEngine
    private let log = Logger(subsystem: kSubsystem, category: "SystemAudioTap")
    private let ioQueue = DispatchQueue(label: "\(kSubsystem).io", qos: .userInteractive)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var deviceChangeBlock: AudioObjectPropertyListenerBlock?

    private(set) var tapFormat: AudioStreamBasicDescription?
    private(set) var outputDeviceName = "—"
    private(set) var isRunning = false

    /// Called on the main queue when the engine rebuilds itself (e.g. output device changed).
    var onRebuild: ((Result<String, Error>) -> Void)?

    init(eq: EQEngine) { self.eq = eq }

    // MARK: Lifecycle

    func start() throws {
        guard !isRunning else { return }
        try build()
        installDefaultDeviceListener()
        isRunning = true
    }

    func stop() {
        removeDefaultDeviceListener()
        teardown()
        isRunning = false
    }

    deinit { stop() }

    // MARK: Build / teardown

    private func build() throws {
        // 1. Exclude ourselves from the global tap to prevent feedback.
        var exclude: [AudioObjectID] = []
        if let selfObject = try? AudioObjectID.system.translatePID(getpid()), selfObject.isValid {
            exclude = [selfObject]
        }

        // 2. Create a stereo global tap of every (other) process, muted while we read it.
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: exclude)
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

        // 3. Read the tap's format and prime the EQ.
        let format = try tapID.readTapStreamFormat()
        tapFormat = format
        eq.resetState()

        // 4. Resolve the real output device we re-route into.
        let outputDevice = try AudioObjectID.system.readDefaultOutputDevice()
        guard outputDevice.isValid else { throw CoreAudioError.create("No default output device", -1) }
        let outputUID = try outputDevice.readDeviceUID()
        outputDeviceName = (try? outputDevice.readDeviceName()) ?? "Output"

        // 5. Build a private aggregate: real output as main/clock sub-device + the tap.
        let aggregateUID = UUID().uuidString
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

        // 6. Install the render block and start.
        let engine = eq
        var newProc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&newProc, aggregateID, ioQueue) { _, inInput, _, outOutput, _ in
            SystemAudioTap.route(engine, input: inInput, output: outOutput)
        }
        guard status == noErr, let proc = newProc else {
            throw CoreAudioError.create("AudioDeviceCreateIOProcIDWithBlock", status)
        }
        procID = proc

        status = AudioDeviceStart(aggregateID, proc)
        guard status == noErr else { throw CoreAudioError.create("AudioDeviceStart", status) }

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

        var channelOffset = 0
        for i in 0..<outList.count {
            let outBuffer = outList[i]
            guard let outData = outBuffer.mData else { continue }
            let outBytes = Int(outBuffer.mDataByteSize)

            // 1. Copy the matching tap input buffer into the output buffer (silence if absent).
            if i < inList.count, let inData = inList[i].mData {
                let copyBytes = min(outBytes, Int(inList[i].mDataByteSize))
                memcpy(outData, inData, copyBytes)
                if copyBytes < outBytes {
                    memset(outData.advanced(by: copyBytes), 0, outBytes - copyBytes)
                }
            } else {
                memset(outData, 0, outBytes)
            }

            // 2. EQ each channel of the output buffer in place.
            let channels = Int(outBuffer.mNumberChannels)
            guard channels > 0 else { continue }
            let frames = outBytes / (MemoryLayout<Float>.size * channels)
            let samples = outData.assumingMemoryBound(to: Float.self)
            for ch in 0..<channels {
                eq.process(channel: channelOffset + ch, data: samples + ch, frames: frames, stride: channels)
            }
            channelOffset += channels
        }
    }

    // MARK: Output-device change handling

    private func installDefaultDeviceListener() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.rebuild()
        }
        deviceChangeBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
    }

    private func removeDefaultDeviceListener() {
        guard let block = deviceChangeBlock else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        deviceChangeBlock = nil
    }

    /// Rebuild the tap + aggregate after the output device or its format changes
    /// (works around the known "all zeros after device/sample-rate change" behavior).
    private func rebuild() {
        guard isRunning else { return }
        log.info("Default output device changed — rebuilding tap")
        teardown()
        do {
            try build()
            onRebuild?(.success(outputDeviceName))
        } catch {
            log.error("Rebuild failed: \(error.localizedDescription, privacy: .public)")
            isRunning = false
            onRebuild?(.failure(error))
        }
    }
}
