import AVFoundation
import CoreAudio
import Foundation

/// Container/codec the recorder writes. WAV is lossless float (largest); ALAC is lossless compressed;
/// AAC is lossy (smallest). All are written through `AVAudioFile`, which encodes on write.
enum RecordingFormat: String, CaseIterable, Identifiable, Codable {
    case wav            // Linear PCM 32-bit float, .wav
    case alac           // Apple Lossless, .m4a
    case aac            // AAC, .m4a

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wav: return "WAV (lossless)"
        case .alac: return "Apple Lossless"
        case .aac: return "AAC (compact)"
        }
    }

    var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .alac, .aac: return "m4a"
        }
    }

    /// `AVAudioFile` writing settings for this format at the given sample rate / channel count.
    func settings(sampleRate: Double, channels: Int) -> [String: Any] {
        switch self {
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        case .alac:
            return [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
            ]
        case .aac:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
            ]
        }
    }
}

/// Wraps `AVAudioFile` for writing captured tap audio to disk. Split out from `AudioRecorder` so the
/// buffer→file path is unit-testable offline (no Core Audio tap needed): feed it `AVAudioPCMBuffer`s and
/// read the file back. Not real-time-safe — written on the recorder's (observer-only) IO queue, which
/// never feeds the user's live playback, so disk latency can't glitch their audio.
final class AudioFileWriter {
    /// Float32 buffers we hand to `AVAudioFile` (it transcodes to the file's container/codec).
    let processingFormat: AVAudioFormat
    let url: URL
    /// Released by `finish()` — `AVAudioFile` only flushes/finalizes (e.g. the AAC moov atom) on release.
    private var file: AVAudioFile?
    private(set) var frameCount: AVAudioFramePosition = 0

    /// Capture format the recorder writes from.
    var sampleRate: Double { processingFormat.sampleRate }
    var channelCount: Int { Int(processingFormat.channelCount) }

    /// Seconds of audio written so far.
    var durationSeconds: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }

    /// Build a writer from a Core Audio tap stream format.
    convenience init(url: URL, asbd: AudioStreamBasicDescription, format: RecordingFormat) throws {
        var asbd = asbd
        guard let processing = AVAudioFormat(streamDescription: &asbd) else {
            throw CoreAudioError.create("Unsupported capture format for recording", -1)
        }
        try self.init(url: url, processingFormat: processing, format: format)
    }

    /// Build a writer from an `AVAudioFormat` directly (used by tests).
    init(url: URL, processingFormat: AVAudioFormat, format: RecordingFormat) throws {
        self.url = url
        self.processingFormat = processingFormat
        let settings = format.settings(sampleRate: processingFormat.sampleRate,
                                        channels: Int(processingFormat.channelCount))
        // Write in the same channel layout we capture so AVAudioFile transcodes losslessly to the container.
        self.file = try AVAudioFile(forWriting: url, settings: settings,
                                    commonFormat: processingFormat.commonFormat,
                                    interleaved: processingFormat.isInterleaved)
    }

    /// Append one PCM buffer (must be in `processingFormat`).
    func write(_ buffer: AVAudioPCMBuffer) throws {
        guard buffer.frameLength > 0, let file else { return }
        try file.write(from: buffer)
        frameCount += AVAudioFramePosition(buffer.frameLength)
    }

    /// Append raw tap audio: wrap the IOProc's buffer list (no copy — valid only for this call) and write.
    func write(bufferList: UnsafePointer<AudioBufferList>) throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat,
                                            bufferListNoCopy: bufferList, deallocator: nil) else { return }
        try write(buffer)
    }

    /// Finalize the file: releasing the `AVAudioFile` flushes buffered audio and writes the container's
    /// trailer (the AAC/ALAC `moov` atom) so the file is readable. Idempotent.
    func finish() { file = nil }
}
