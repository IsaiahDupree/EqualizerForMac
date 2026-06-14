import AVFoundation
import CoreAudio
import Foundation
import Testing
@testable import SonanceEQ

// Broad parameterized coverage of the model/recording/mixer layers.

private let sampleRates: [Double] = [8_000, 16_000, 22_050, 32_000, 44_100, 48_000, 88_200, 96_000, 176_400, 192_000]

@Suite struct RecordingSettingsCoverage {
    struct Case { let rate: Double; let channels: Int; let format: RecordingFormat }
    // Swift Testing takes at most two argument collections, so precompute the rate × channel × format grid.
    static let cases: [Case] = sampleRates.flatMap { rate in
        [1, 2].flatMap { ch in RecordingFormat.allCases.map { Case(rate: rate, channels: ch, format: $0) } }
    }

    /// Every format propagates sample rate + channel count and tags the right codec.
    @Test(arguments: cases)
    func settingsPropagate(c: Case) {
        let s = c.format.settings(sampleRate: c.rate, channels: c.channels)
        #expect(s[AVSampleRateKey] as? Double == c.rate)
        #expect(s[AVNumberOfChannelsKey] as? Int == c.channels)
        let id = s[AVFormatIDKey] as? AudioFormatID
        switch c.format {
        case .wav: #expect(id == kAudioFormatLinearPCM)
        case .alac: #expect(id == kAudioFormatAppleLossless)
        case .aac: #expect(id == kAudioFormatMPEG4AAC)
        }
    }
}

@Suite struct WriterRoundTripCoverage {
    private func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sonance-cov-\(UUID().uuidString).\(ext)")
    }

    private func buffer(_ format: AVAudioFormat, frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        if let raw = buf.audioBufferList.pointee.mBuffers.mData {
            let p = raw.assumingMemoryBound(to: Float.self)
            let n = Int(frames) * Int(format.channelCount)
            for i in 0..<n { p[i] = sin(Float(i) * 0.01) * 0.5 }
        }
        return buf
    }

    /// Write N frames in each format and confirm a readable file of the expected length results.
    @Test(arguments: RecordingFormat.allCases, [512, 2_048, 9_600])
    func roundTrip(format: RecordingFormat, frames: Int) throws {
        let url = tempURL(format.fileExtension)
        defer { try? FileManager.default.removeItem(at: url) }
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true)!
        let writer = try AudioFileWriter(url: url, processingFormat: fmt, format: format)
        try writer.write(buffer(fmt, frames: AVAudioFrameCount(frames)))
        #expect(writer.frameCount == AVAudioFramePosition(frames))
        writer.finish()

        let read = try AVAudioFile(forReading: url)
        if format == .wav {
            #expect(read.length == AVAudioFramePosition(frames))   // lossless PCM: exact
        } else {
            #expect(read.length > 0)                               // compressed: framed, ~exact
            #expect(abs(read.length - AVAudioFramePosition(frames)) < 4_096)
        }
    }
}

@Suite struct MixerGainCoverage {
    static let volumes: [Float] = Array(stride(from: Float(0), through: 1.25, by: 0.05))

    /// Unmuted gain follows volume across the full 0…1.25 sweep.
    @Test(arguments: volumes)
    func unmutedGainEqualsVolume(volume: Float) {
        var c = MixerChannel(bundleID: "a", name: "A")
        c.volume = volume
        #expect(abs(c.gain - volume) < 1e-6)
        #expect(!c.isPassthrough || abs(volume - 1) < 0.001)
    }

    /// A muted channel is silent regardless of volume.
    @Test(arguments: volumes)
    func mutedGainIsZero(volume: Float) {
        var c = MixerChannel(bundleID: "a", name: "A")
        c.volume = volume; c.muted = true
        #expect(c.gain == 0)
        #expect(!c.isPassthrough)
    }

    /// Out-of-range volumes clamp into [0, maxVolume].
    @Test(arguments: [Float(-5), -1, 1.5, 2, 10])
    func volumeClamps(volume: Float) {
        var c = MixerChannel(bundleID: "a", name: "A")
        c.volume = volume
        #expect(c.gain >= 0 && c.gain <= MixerChannel.maxVolume)
    }
}

@MainActor
@Suite struct MixerStatePersistenceCoverage {
    /// Set a non-unity volume, reload from the same defaults, and confirm it persisted.
    @Test(arguments: [Float(0), 0.1, 0.33, 0.5, 0.75, 0.9, 1.1, 1.25])
    func volumePersistsAcrossReload(volume: Float) {
        let suite = "test.mixer.cov.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let a = MixerState(defaults: defaults)
        a.setVolume(volume, for: "com.x", name: "X")
        let reloaded = MixerState(defaults: defaults)
        #expect(abs(reloaded.channel("com.x", name: "X").volume - volume) < 1e-6)
    }
}

@Suite struct PresetRoundTripCoverage {
    /// Every built-in preset survives a PresetFile JSON encode/decode at every preamp, byte-for-band.
    @Test(arguments: Presets.all, [Float(-12), -6, 0, 6, 12])
    func presetSurvivesJSON(preset: Presets.Item, preamp: Float) throws {
        let file = PresetFile(name: preset.name, preampDb: preamp, bands: preset.bands)
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(PresetFile.self, from: data)
        #expect(decoded.preampDb == preamp)
        let bands = decoded.eqBands()
        #expect(bands.count == preset.bands.count)
        for (a, b) in zip(bands, preset.bands) {
            #expect(a.frequency == b.frequency)
            #expect(a.gain == b.gain)
            #expect(a.q == b.q)
            #expect(a.type == b.type)
        }
    }

    /// Presets written before `slopeDbPerOct` existed decode with the 12 dB/oct default.
    @Test(arguments: FilterType.allCases)
    func legacyDecodeDefaultsSlope(type: FilterType) throws {
        let json = """
        {"type":"\(type.rawValue)","frequency":1000,"gain":3,"q":1,"enabled":true}
        """
        let band = try JSONDecoder().decode(PortableBand.self, from: Data(json.utf8))
        #expect(band.slopeDbPerOct == 12)
        #expect(band.type == type)
    }
}

@Suite struct BandLabelCoverage {
    struct FreqCase { let freq: Double; let label: String }
    static let freqCases: [FreqCase] = [
        .init(freq: 20, label: "20"), .init(freq: 100, label: "100"), .init(freq: 125, label: "125"),
        .init(freq: 250, label: "250"), .init(freq: 500, label: "500"), .init(freq: 999, label: "999"),
        .init(freq: 1000, label: "1k"), .init(freq: 2000, label: "2k"), .init(freq: 4000, label: "4k"),
        .init(freq: 8000, label: "8k"), .init(freq: 16000, label: "16k"), .init(freq: 20000, label: "20k"),
    ]

    @Test(arguments: freqCases)
    func freqLabelFormats(c: FreqCase) {
        let band = EQBand(frequency: c.freq, gain: 0, q: 1, type: .peaking)
        #expect(band.freqLabel == c.label)
    }

    struct GainCase { let gain: Float; let label: String }
    static let gainCases: [GainCase] = [
        .init(gain: 0, label: "+0.0"), .init(gain: 3, label: "+3.0"), .init(gain: -3, label: "-3.0"),
        .init(gain: 6.5, label: "+6.5"), .init(gain: -6.5, label: "-6.5"), .init(gain: 12, label: "+12.0"),
        .init(gain: -12, label: "-12.0"), .init(gain: 1.25, label: "+1.2"), .init(gain: -0.5, label: "-0.5"),
        .init(gain: 9, label: "+9.0"),
    ]

    @Test(arguments: gainCases)
    func gainLabelFormats(c: GainCase) {
        let band = EQBand(frequency: 1000, gain: c.gain, q: 1, type: .peaking)
        #expect(band.gainLabel == c.label)
    }
}

@Suite struct FilterTypeMetadataCoverage {
    /// Only peaking/shelf use gain; only low/high pass support a variable slope. Short labels are unique.
    @Test(arguments: FilterType.allCases)
    func gainAndSlopeFlags(type: FilterType) {
        let usesGain = [.peaking, .lowShelf, .highShelf].contains(type)
        #expect(type.usesGain == usesGain)
        #expect(type.supportsSlope == (type == .lowPass || type == .highPass))
        #expect(!type.shortLabel.isEmpty)
    }

    @Test func shortLabelsAreUnique() {
        let labels = Set(FilterType.allCases.map(\.shortLabel))
        #expect(labels.count == FilterType.allCases.count)
    }
}
