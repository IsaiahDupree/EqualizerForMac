import AVFoundation
import CoreAudio
import Foundation
import Testing
@testable import SonanceEQ

@Suite struct RecordingFormatTests {
    @Test func fileExtensions() {
        #expect(RecordingFormat.wav.fileExtension == "wav")
        #expect(RecordingFormat.alac.fileExtension == "m4a")
        #expect(RecordingFormat.aac.fileExtension == "m4a")
    }

    @Test func wavSettingsAreLosslessFloat() {
        let s = RecordingFormat.wav.settings(sampleRate: 48_000, channels: 2)
        #expect(s[AVFormatIDKey] as? AudioFormatID == kAudioFormatLinearPCM)
        #expect(s[AVSampleRateKey] as? Double == 48_000)
        #expect(s[AVNumberOfChannelsKey] as? Int == 2)
        #expect(s[AVLinearPCMIsFloatKey] as? Bool == true)
        #expect(s[AVLinearPCMBitDepthKey] as? Int == 32)
    }

    @Test func compressedFormatsCarryRateAndChannels() {
        #expect(RecordingFormat.aac.settings(sampleRate: 44_100, channels: 2)[AVFormatIDKey] as? AudioFormatID == kAudioFormatMPEG4AAC)
        #expect(RecordingFormat.alac.settings(sampleRate: 44_100, channels: 1)[AVFormatIDKey] as? AudioFormatID == kAudioFormatAppleLossless)
        #expect(RecordingFormat.alac.settings(sampleRate: 96_000, channels: 2)[AVSampleRateKey] as? Double == 96_000)
    }

    @Test func allCasesHaveDistinctLabels() {
        let labels = Set(RecordingFormat.allCases.map(\.label))
        #expect(labels.count == RecordingFormat.allCases.count)
    }
}

@Suite struct AudioFileWriterTests {
    /// A float32 interleaved stereo buffer filled with a known ramp, for round-trip checks.
    private func rampBuffer(format: AVAudioFormat, frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let ch = Int(format.channelCount)
        if let data = buf.floatChannelData {
            // Non-interleaved: per-channel pointers.
            for c in 0..<ch {
                for i in 0..<Int(frames) { data[c][i] = Float(i) / Float(frames) }
            }
        } else if let raw = buf.audioBufferList.pointee.mBuffers.mData {
            // Interleaved: one buffer, ch samples per frame.
            let p = raw.assumingMemoryBound(to: Float.self)
            for i in 0..<(Int(frames) * ch) { p[i] = Float(i) / Float(Int(frames) * ch) }
        }
        return buf
    }

    private func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sonance-test-\(UUID().uuidString).\(ext)")
    }

    @Test func wavRoundTripPreservesFramesAndSamples() throws {
        let url = tempURL("wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true)!
        let writer = try AudioFileWriter(url: url, processingFormat: fmt, format: .wav)
        let frames: AVAudioFrameCount = 4_800   // 0.1 s
        try writer.write(rampBuffer(format: fmt, frames: frames))
        try writer.write(rampBuffer(format: fmt, frames: frames))
        #expect(writer.frameCount == AVAudioFramePosition(frames) * 2)
        #expect(abs(writer.durationSeconds - 0.2) < 1e-6)
        writer.finish()

        // Read it back: a real file with the expected length exists on disk.
        let read = try AVAudioFile(forReading: url)
        #expect(read.length == AVAudioFramePosition(frames) * 2)
        #expect(read.fileFormat.channelCount == 2)
    }

    @Test func emptyWriteIsIgnored() throws {
        let url = tempURL("wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true)!
        let writer = try AudioFileWriter(url: url, processingFormat: fmt, format: .wav)
        let empty = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 512)!
        empty.frameLength = 0
        try writer.write(empty)
        #expect(writer.frameCount == 0)
    }

    @Test func aacWritesAPlayableFile() throws {
        let url = tempURL("m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: true)!
        let writer = try AudioFileWriter(url: url, processingFormat: fmt, format: .aac)
        for _ in 0..<10 { try writer.write(rampBuffer(format: fmt, frames: 4_410)) }  // ~1 s
        writer.finish()

        let read = try AVAudioFile(forReading: url)
        // AAC is lossy + framed, so length is approximate — assert it's within ~0.2 s of 1 s.
        let seconds = Double(read.length) / read.fileFormat.sampleRate
        #expect(seconds > 0.8 && seconds < 1.2)
    }

    @Test func buildsFromCoreAudioASBD() throws {
        let url = tempURL("wav")
        defer { try? FileManager.default.removeItem(at: url) }
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let writer = try AudioFileWriter(url: url, asbd: asbd, format: .wav)
        #expect(writer.sampleRate == 48_000)
        #expect(writer.channelCount == 2)
        _ = asbd   // silence unused-mutation warning
    }
}

@MainActor
@Suite struct RecorderStateTests {
    @Test func defaultsToAllAppsAndWav() {
        let app = AppState()
        #expect(app.recordTarget.isAllApps)
        #expect(app.recordingFormat == .wav)
        #expect(!app.isRecording)
        #expect(app.recordTargetLabel == "All Apps")
    }

    @Test func toggleRecordAppBuildsAndCollapsesSelection() {
        let app = AppState()
        app.toggleRecordApp("com.example.a")
        #expect(app.isRecordAppSelected("com.example.a"))
        #expect(!app.recordTarget.isAllApps)
        app.toggleRecordApp("com.example.a")   // removing the last one falls back to All Apps
        #expect(app.recordTarget.isAllApps)
    }

    @Test func setRecordAllAppsResets() {
        let app = AppState()
        app.toggleRecordApp("com.example.a")
        app.setRecordAllApps()
        #expect(app.recordTarget.isAllApps)
        #expect(!app.isRecordAppSelected("com.example.a"))
    }
}
