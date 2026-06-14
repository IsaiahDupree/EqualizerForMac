import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import OSLog

/// One per-app mixer pipeline: tap a single app's audio, scale it by a live gain, and play it out to a
/// chosen output device (or the system default). The app's normal output is muted (`mutedWhenTapped`),
/// so only our scaled/re-routed copy is heard. Mirrors `SystemAudioTap`'s safety: teardown on any build
/// failure + a watchdog, so a channel can never leave the app silently muted.
final class MixerChannelTap {
    let bundleID: String

    private let log = Logger(subsystem: kSubsystem, category: "MixerChannelTap")
    private let ioQueue: DispatchQueue

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    private let gain = OSAllocatedUnfairLock(initialState: Float(1))
    private let renderCount = OSAllocatedUnfairLock(initialState: 0)
    private(set) var isRunning = false

    /// Called (main queue) if this channel's routing fails so the mixer can drop it.
    var onFailure: ((String) -> Void)?

    init(bundleID: String) {
        self.bundleID = bundleID
        ioQueue = DispatchQueue(label: "\(kSubsystem).mixer", qos: .userInteractive)
    }

    deinit { stop() }

    /// Update the live volume (0…) applied on the audio thread.
    func setGain(_ value: Float) { gain.withLock { $0 = value } }

    func start(processObjectID: AudioObjectID, outputDeviceUID: String?) {
        guard !isRunning else { return }
        do {
            try build(process: processObjectID, outputUID: outputDeviceUID)
            renderCount.withLock { $0 = 0 }
            isRunning = true
            startWatchdog()
        } catch {
            teardown()   // never leave a muted tap behind
            log.error("mixer channel \(self.bundleID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            onFailure?(error.localizedDescription)
        }
    }

    func stop() {
        teardown()
        isRunning = false
    }

    // MARK: Build / teardown

    private func build(process: AudioObjectID, outputUID: String?) throws {
        let desc = CATapDescription(stereoMixdownOfProcesses: [process])
        desc.name = "Sonance Mixer Tap"
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true

        var newTap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(desc, &newTap)
        guard status == noErr, newTap.isValid else { throw CoreAudioError.create("mixer process tap", status) }
        tapID = newTap

        // Resolve the destination (chosen device, else the current default output).
        let outputDevice: AudioObjectID
        if let outputUID, let id = AudioDevices.deviceID(forUID: outputUID) {
            outputDevice = id
        } else {
            outputDevice = try AudioObjectID.system.readDefaultOutputDevice()
        }
        guard outputDevice.isValid else { throw CoreAudioError.create("mixer output device", -1) }
        let outUID = try outputDevice.readDeviceUID()

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sonance Mixer Output",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]

        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregate)
        guard status == noErr, newAggregate.isValid else { throw CoreAudioError.create("mixer aggregate", status) }
        aggregateID = newAggregate

        let gainLock = gain
        let counter = renderCount
        var newProc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&newProc, aggregateID, ioQueue) { _, inInput, _, outOutput, _ in
            counter.withLock { $0 &+= 1 }
            let g = gainLock.withLock { $0 }
            MixerChannelTap.route(gain: g, input: inInput, output: outOutput)
        }
        guard status == noErr, let proc = newProc else { throw CoreAudioError.create("mixer IOProc", status) }
        procID = proc

        status = AudioDeviceStart(aggregateID, proc)
        guard status == noErr else { throw CoreAudioError.create("mixer AudioDeviceStart", status) }
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
    }

    private func startWatchdog() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.isRunning else { return }
            guard self.renderCount.withLock({ $0 }) == 0 else { return }
            self.log.error("mixer channel \(self.bundleID, privacy: .public) never delivered audio — stopping.")
            self.stop()
            self.onFailure?("Couldn't route this app's audio")
        }
    }

    // MARK: Render

    /// Copy tap input → output and scale by gain. Split out as `scale(...)` for unit testing.
    private static func route(gain: Float, input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outList = UnsafeMutableAudioBufferListPointer(output)
        for i in 0..<outList.count {
            let outBuffer = outList[i]
            guard let outData = outBuffer.mData else { continue }
            let outBytes = Int(outBuffer.mDataByteSize)
            if i < inList.count, let inData = inList[i].mData {
                let copyBytes = min(outBytes, Int(inList[i].mDataByteSize))
                memcpy(outData, inData, copyBytes)
                if copyBytes < outBytes { memset(outData.advanced(by: copyBytes), 0, outBytes - copyBytes) }
            } else {
                memset(outData, 0, outBytes)
                continue
            }
            let frames = outBytes / MemoryLayout<Float>.size
            scale(outData.assumingMemoryBound(to: Float.self), frames: frames, gain: gain)
        }
    }

    /// Multiply `frames` interleaved samples in place by `gain` (testable, no Core Audio).
    static func scale(_ samples: UnsafeMutablePointer<Float>, frames: Int, gain: Float) {
        guard frames > 0 else { return }
        if gain == 1 { return }
        var g = gain
        vDSP_vsmul(samples, 1, &g, samples, 1, vDSP_Length(frames))
    }
}
