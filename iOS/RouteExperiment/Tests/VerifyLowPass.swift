import Foundation

@main
struct VerifyLowPass {
    static func measure(_ frequency: Double) -> Double {
        let frames = 24_000
        let filter = LowPass(cutoff: 1_000)
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: frames * 2)
        defer { samples.deallocate() }
        for i in 0..<frames {
            let value = Float(sin(2 * Double.pi * frequency * Double(i) / 48_000))
            samples[i] = value
            samples[frames + i] = value
        }
        filter.process(samples, frames: frames, sampleRate: 48_000)
        var inputEnergy = 0.0
        var leftEnergy = 0.0
        var rightEnergy = 0.0
        for i in (frames / 2)..<frames {
            let input = sin(2 * Double.pi * frequency * Double(i) / 48_000)
            inputEnergy += input * input
            leftEnergy += Double(samples[i] * samples[i])
            rightEnergy += Double(samples[frames + i] * samples[frames + i])
        }
        precondition(abs(leftEnergy - rightEnergy) < 0.0001, "Stereo channels differ")
        return 10 * log10(leftEnergy / inputEnergy)
    }

    static func main() {
        let low = measure(100)
        let high = measure(8_000)
        precondition(low.isFinite && high.isFinite && low > -1 && high < -10, "Unexpected filter response")
        let filter = LowPass()
        filter.cutoff = .nan
        precondition(filter.cutoff == 20_000, "Non-finite cutoff must reset")
        print(String(format: "100 Hz %.2f dB, 8 kHz %.2f dB; stereo and non-finite cutoff checks passed", low, high))
    }
}
