import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import OSLog

/// Records system audio (or a chosen set of apps) to a file. Unlike `SystemAudioTap`/`MixerChannelTap`,
/// this tap is **unmuted** (`muteBehavior = .unmuted`): the user keeps hearing their audio normally and
/// we capture a copy. Because our IOProc never feeds live playback, file-writing latency can't glitch the
/// sound, so we write to disk directly on the (serial) IO queue — same pattern as insidegui/AudioCap.
///
/// Records the audio *as the apps produce it* (pre-EQ). Recording the EQ'd result is a v2 concern that
/// would route the EQ output through a sub-device; the common ask ("capture what's playing") is this.
final class AudioRecorder {
    private let log = Logger(subsystem: kSubsystem, category: "AudioRecorder")
    private let ioQueue = DispatchQueue(label: "\(kSubsystem).recorder", qos: .userInitiated)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var writer: AudioFileWriter?

    private let renderCount = OSAllocatedUnfairLock(initialState: 0)
    /// Frames written so far — read on the main thread for the elapsed-time display.
    private let framesWritten = OSAllocatedUnfairLock(initialState: AVAudioFramePosition(0))
    private var captureSampleRate: Double = 48_000

    private(set) var isRecording = false
    private(set) var outputURL: URL?

    /// Called (main queue) if recording fails to start or dies mid-capture.
    var onFailure: ((String) -> Void)?

    /// Seconds captured so far (thread-safe; updated on the IO queue).
    var elapsedSeconds: Double {
        let frames = framesWritten.withLock { $0 }
        return captureSampleRate > 0 ? Double(frames) / captureSampleRate : 0
    }

    deinit { stop() }

    // MARK: Lifecycle

    func start(target: EQTarget, format: RecordingFormat, url: URL) throws {
        guard !isRecording else { return }
        do {
            try build(target: target, format: format, url: url)
            renderCount.withLock { $0 = 0 }
            framesWritten.withLock { $0 = 0 }
            outputURL = url
            isRecording = true
            startWatchdog()
        } catch {
            teardown()
            log.error("recording failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @discardableResult
    func stop() -> URL? {
        guard isRecording || procID != nil else { return outputURL }
        teardown()
        isRecording = false
        return outputURL
    }

    // MARK: Build / teardown

    private func build(target: EQTarget, format: RecordingFormat, url: URL) throws {
        // Capture-only tap: exclude ourselves (global) so our own audio isn't recorded; a per-app capture
        // is a mixdown of the chosen processes. Unmuted so the user keeps hearing everything.
        var exclude: [AudioObjectID] = []
        if let selfObject = try? AudioObjectID.system.translatePID(getpid()), selfObject.isValid {
            exclude = [selfObject]
        }
        let desc: CATapDescription
        switch target {
        case .allApps:
            desc = CATapDescription(stereoGlobalTapButExcludeProcesses: exclude)
        case let .apps(bundleIDs):
            let objects = AudioProcesses.processObjectIDs(forBundleIDs: bundleIDs)
            desc = objects.isEmpty
                ? CATapDescription(stereoGlobalTapButExcludeProcesses: exclude)
                : CATapDescription(stereoMixdownOfProcesses: objects)
        }
        desc.name = "Sonance Recorder Tap"
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted      // observer only — don't mute the user's audio
        desc.isPrivate = true

        var newTap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(desc, &newTap)
        guard status == noErr, newTap.isValid else {
            throw CoreAudioError.create("Recorder process tap (check Audio Capture permission)", status)
        }
        tapID = newTap

        let asbd = try tapID.readTapStreamFormat()
        captureSampleRate = asbd.mSampleRate

        // Open the destination file before the IOProc starts delivering audio.
        let fileWriter = try AudioFileWriter(url: url, asbd: asbd, format: format)
        writer = fileWriter

        // Aggregate with the tap + the default output as main/clock sub-device (capture needs a clock).
        let outputDevice = try AudioObjectID.system.readDefaultOutputDevice()
        guard outputDevice.isValid else { throw CoreAudioError.create("No default output device", -1) }
        let outputUID = try outputDevice.readDeviceUID()

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sonance Recorder",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]

        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregate)
        guard status == noErr, newAggregate.isValid else {
            throw CoreAudioError.create("Recorder aggregate", status)
        }
        aggregateID = newAggregate

        let counter = renderCount
        let frames = framesWritten
        let log = log
        var newProc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&newProc, aggregateID, ioQueue) { [weak self] _, inInput, _, _, _ in
            counter.withLock { $0 &+= 1 }
            guard let writer = self?.writer else { return }
            do {
                try writer.write(bufferList: inInput)
                frames.withLock { $0 = writer.frameCount }
            } catch {
                // Stop on the first write error rather than spinning; report on the main queue.
                DispatchQueue.main.async {
                    guard let self, self.isRecording else { return }
                    log.error("recorder write failed: \(error.localizedDescription, privacy: .public)")
                    self.stop()
                    self.onFailure?("Couldn't write the recording file")
                }
            }
        }
        guard status == noErr, let proc = newProc else {
            throw CoreAudioError.create("Recorder IOProc", status)
        }
        procID = proc

        status = AudioDeviceStart(aggregateID, proc)
        guard status == noErr else { throw CoreAudioError.create("Recorder AudioDeviceStart", status) }

        log.info("recording → \(url.lastPathComponent, privacy: .public) @ \(asbd.mSampleRate, privacy: .public) Hz")
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
        // Release the writer last so any in-flight IOProc write has finished and the file flushes to disk.
        ioQueue.sync { writer?.finish(); writer = nil }
    }

    private func startWatchdog() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.isRecording else { return }
            guard self.renderCount.withLock({ $0 }) == 0 else { return }
            self.log.error("recorder never received audio — stopping.")
            self.stop()
            self.onFailure?("No audio was captured (is anything playing?)")
        }
    }
}
