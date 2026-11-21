import AudioToolbox
import Foundation

enum MobileEQ {
    static let component = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x536E4551, // SnEQ
        componentManufacturer: 0x49734470, // IsDp
        componentFlags: 0,
        componentFlagsMask: 0
    )

    static let preampAddress: AUParameterAddress = 0
    static let bypassAddress: AUParameterAddress = 1
    static let frequencyRange: ClosedRange<Float> = 20...20_000
    static let gainRange: ClosedRange<Float> = -12...12
    static let qualityRange: ClosedRange<Float> = 0.25...8
    static let preampRange: ClosedRange<Float> = -24...6

    static func highestFrequency(at sampleRate: Double) -> Double {
        min(Double(frequencyRange.upperBound), sampleRate / 2 - 1)
    }

    enum Control: AUParameterAddress, CaseIterable {
        case frequency, gain, quality
    }

    static func address(_ control: Control, band: Int) -> AUParameterAddress {
        2 + AUParameterAddress(band) * AUParameterAddress(Control.allCases.count) + control.rawValue
    }

    static func bandControl(at address: AUParameterAddress) -> (Int, Control)? {
        guard address >= 2 else { return nil }
        let offset = address - 2
        let controls = AUParameterAddress(Control.allCases.count)
        let index = offset / controls
        guard index < Presets.isoCenters.count, let control = Control(rawValue: offset % controls) else { return nil }
        return (Int(index), control)
    }
}

struct MobileEQSettings: Codable, Equatable {
    var bands = Presets.flat
    var preamp: Float = 0
    var bypassed = false

    var isValid: Bool {
        MobileEQ.preampRange.contains(preamp) && bands.count == Presets.isoCenters.count && bands.allSatisfy {
            $0.type == .peaking && $0.enabled &&
                MobileEQ.frequencyRange.contains(Float($0.frequency)) &&
                MobileEQ.gainRange.contains($0.gain) && MobileEQ.qualityRange.contains(Float($0.q))
        }
    }

    func value(at address: AUParameterAddress) -> AUValue {
        switch address {
        case MobileEQ.preampAddress: return preamp
        case MobileEQ.bypassAddress: return bypassed ? 1 : 0
        default:
            guard let (band, control) = MobileEQ.bandControl(at: address) else { return 0 }
            switch control {
            case .frequency: return Float(bands[band].frequency)
            case .gain: return bands[band].gain
            case .quality: return Float(bands[band].q)
            }
        }
    }

    mutating func setValue(_ value: AUValue, at address: AUParameterAddress) {
        guard value.isFinite else { return }
        func clamped(_ range: ClosedRange<Float>) -> Float { min(max(value, range.lowerBound), range.upperBound) }
        switch address {
        case MobileEQ.preampAddress: preamp = clamped(MobileEQ.preampRange)
        case MobileEQ.bypassAddress: bypassed = value >= 0.5
        default:
            guard let (band, control) = MobileEQ.bandControl(at: address) else { return }
            switch control {
            case .frequency: bands[band].frequency = Double(clamped(MobileEQ.frequencyRange))
            case .gain: bands[band].gain = clamped(MobileEQ.gainRange)
            case .quality: bands[band].q = Double(clamped(MobileEQ.qualityRange))
            }
        }
    }
}
