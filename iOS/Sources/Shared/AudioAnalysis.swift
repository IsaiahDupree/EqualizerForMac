import Accelerate
import Foundation

struct AudioAnalysisFrame: Equatable {
    struct WaveformPoint: Equatable {
        let minimum: Float
        let maximum: Float
    }

    struct Channel: Equatable {
        let peak: Float
        let rms: Float
        let waveform: [WaveformPoint]
    }

    let spectrum: [Float]
    let highestFrequency: Double
    let dominantFrequency: Double?
    let left: Channel
    let right: Channel?
}

@MainActor
final class AudioAnalysisMonitor {
    private let count = Int(SonanceAnalysisFrameCount)
    private let transform: vDSP_DFT_Setup?
    private let window: [Float]
    private let normalization: Float
    private let zeros: [Float]
    private var input: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var power: [Float]
    private var left: [Float]
    private var right: [Float]
    private var latest: AudioAnalysisFrame?
    private var updatedAt = 0.0

    init() {
        let count = Int(SonanceAnalysisFrameCount)
        transform = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(count), .FORWARD)
        zeros = Array(repeating: 0, count: count)
        input = zeros
        real = zeros
        imaginary = zeros
        left = zeros
        right = zeros
        power = Array(repeating: 0, count: count / 2 + 1)
        var window = zeros
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
        self.window = window
        normalization = 2 / window.reduce(0, +)
    }

    deinit {
        if let transform { vDSP_DFT_DestroySetup(transform) }
    }

    func reset() { latest = nil }

    func read(_ capture: OpaquePointer) -> AudioAnalysisFrame? {
        var info = SonanceAnalysisInfo()
        let ready = SonanceAnalysisRead(capture, &left, &right, &info)
        SonanceAnalysisRequest(capture)
        let now = ProcessInfo.processInfo.systemUptime
        if ready, (8_000...192_000).contains(info.sampleRate), let transform {
            let stereo = info.channelCount == 2
            accumulate(left, transform: transform, combine: false)
            if stereo { accumulate(right, transform: transform, combine: true) }
            let upper = MobileEQ.highestFrequency(at: info.sampleRate)
            let step = info.sampleRate / Double(count)
            let lastBin = min(power.count - 1, max(1, Int(upper / step)))
            let dominant = power[1...lastBin].indices.max { power[$0] < power[$1] }
            let spectrum = (0..<48).map { index in
                let first = 20 * pow(upper / 20, Double(index) / 48)
                let last = 20 * pow(upper / 20, Double(index + 1) / 48)
                let minBin = min(lastBin, max(1, Int(ceil(first / step))))
                let maxBin = min(lastBin, max(minBin, Int(floor(last / step))))
                return powerDB(power[minBin...maxBin].max() ?? 0)
            }
            latest = AudioAnalysisFrame(spectrum: spectrum, highestFrequency: upper,
                                        dominantFrequency: dominant.flatMap { powerDB(power[$0]) > -75 ? Double($0) * step : nil },
                                        left: channel(left), right: stereo ? channel(right) : nil)
            updatedAt = now
        }
        return now - updatedAt < 0.45 ? latest : nil
    }

    private func accumulate(_ samples: [Float], transform: vDSP_DFT_Setup, combine: Bool) {
        vDSP_vmul(samples, 1, window, 1, &input, 1, vDSP_Length(count))
        vDSP_DFT_Execute(transform, input, zeros, &real, &imaginary)
        let scale = normalization * normalization
        for index in power.indices {
            let magnitude = (real[index] * real[index] + imaginary[index] * imaginary[index]) * scale
            power[index] = combine ? (power[index] + magnitude) * 0.5 : magnitude
        }
    }

    private func channel(_ samples: [Float]) -> AudioAnalysisFrame.Channel {
        var peak: Float = 0
        var meanSquare: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(count))
        let waveform = (0..<112).map { index in
            let slice = samples[(index * count / 112)..<((index + 1) * count / 112)]
            return AudioAnalysisFrame.WaveformPoint(minimum: slice.min() ?? 0, maximum: slice.max() ?? 0)
        }
        return AudioAnalysisFrame.Channel(peak: powerDB(peak * peak), rms: powerDB(meanSquare), waveform: waveform)
    }

    private func powerDB(_ power: Float) -> Float {
        guard power.isFinite, power > 0 else { return -96 }
        return max(-96, 10 * log10(power))
    }
}
