import Foundation
import Accelerate

@main
struct VerifySpeechListening {
    static func measure(_ settings: MobileEQSettings, frequency: Double) -> Double {
        let sampleRate = 48_000.0
        let sections = settings.bands.flatMap { FilterDesigner.sections(for: $0, sampleRate: sampleRate) }
        let coefficients = sections.flatMap { [Double($0.b0), Double($0.b1), Double($0.b2), Double($0.a1), Double($0.a2)] }
        let setup = coefficients.withUnsafeBufferPointer {
            vDSP_biquadm_CreateSetup($0.baseAddress!, vDSP_Length(sections.count), 1)!
        }
        defer { vDSP_biquadm_DestroySetup(setup) }
        let input = (0..<24_000).map { Float(sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
        var output = [Float](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                var x = inputBuffer.baseAddress!
                var y = outputBuffer.baseAddress!
                vDSP_biquadm(setup, &x, 1, &y, 1, vDSP_Length(input.count))
            }
        }
        let tail = 12_000..<24_000
        let inputEnergy = tail.reduce(0.0) { $0 + Double(input[$1] * input[$1]) }
        let outputEnergy = tail.reduce(0.0) { $0 + Double(output[$1] * output[$1]) }
        return 10 * log10(outputEnergy / inputEnergy) + Double(settings.preamp)
    }

    static func main() {
        for profile in SpeechListening.allCases {
            let settings = profile.settings
            precondition(settings.isValid && !settings.bypassed, "Invalid profile: \(profile.title)")
            let low = measure(settings, frequency: 62.5)
            let voice = measure(settings, frequency: 2_000)
            precondition(low.isFinite && voice.isFinite && low < voice, "Unexpected response: \(profile.title)")
            print(String(format: "%@: 62.5 Hz %.2f dB, 2 kHz %.2f dB", profile.title, low, voice))
        }
        for preset in SoundStarterPreset.allCases {
            let settings = preset.makeSettings(sampleRate: 48_000)
            precondition(settings.isValid && !settings.bypassed, "Invalid preset: \(preset.title)")
            let response = FrequencyResponse.curve(bands: settings.bands, sampleRate: 48_000)
            let peakWithPreamp = (response.map(\.db).max() ?? 0) + Double(settings.preamp)
            precondition(peakWithPreamp <= -0.99, "Insufficient headroom: \(preset.title)")
            print(String(format: "%@: estimated peak with preamp %.2f dB", preset.title, peakWithPreamp))
        }
        for preset in Presets.all {
            let settings = MobileEQSettings.startingPoint(bands: preset.bands, sampleRate: 48_000)
            precondition(settings.isValid && !settings.bypassed, "Invalid built-in preset: \(preset.name)")
            let response = FrequencyResponse.curve(bands: settings.bands, sampleRate: 48_000)
            let peakWithPreamp = (response.map(\.db).max() ?? 0) + Double(settings.preamp)
            precondition(peakWithPreamp <= -0.99, "Insufficient headroom: \(preset.name)")
        }
        print("PASS: speech curves and everyday/built-in presets render with valid settings and peak headroom")
    }
}
