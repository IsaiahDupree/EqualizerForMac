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
    static let gainRange: ClosedRange<Float> = -24...24
    static let qualityRange: ClosedRange<Float> = 0.1...18
    static let preampRange: ClosedRange<Float> = -24...6
    static let bandCount = Presets.isoCenters.count
    static let filterTypes: [FilterType] = [.peaking, .lowShelf, .highShelf, .lowPass, .highPass, .notch, .bandPass, .allPass]

    static func highestFrequency(at sampleRate: Double) -> Double {
        min(Double(frequencyRange.upperBound), sampleRate / 2 - 1)
    }

    enum Control: AUParameterAddress, CaseIterable {
        case frequency, gain, quality, type, slope, enabled
    }

    private static let originalControls: AUParameterAddress = 3
    private static let extraControls: AUParameterAddress = 3
    private static let firstExtraAddress = 2 + AUParameterAddress(bandCount) * originalControls

    static func address(_ control: Control, band: Int) -> AUParameterAddress {
        if control.rawValue < originalControls {
            return 2 + AUParameterAddress(band) * originalControls + control.rawValue
        }
        return firstExtraAddress + AUParameterAddress(band) * extraControls + control.rawValue - originalControls
    }

    static func bandControl(at address: AUParameterAddress) -> (Int, Control)? {
        guard address >= 2 else { return nil }
        if address < firstExtraAddress {
            let offset = address - 2
            return Control(rawValue: offset % originalControls).map { (Int(offset / originalControls), $0) }
        }
        let offset = address - firstExtraAddress
        let band = Int(offset / extraControls)
        guard band < bandCount else { return nil }
        return Control(rawValue: originalControls + offset % extraControls).map { (band, $0) }
    }
}

struct MobileEQSettings: Codable, Equatable {
    var bands = Presets.flat
    var preamp: Float = 0
    var bypassed = false

    var isValid: Bool {
        MobileEQ.preampRange.contains(preamp) && bands.count == MobileEQ.bandCount && bands.allSatisfy {
            MobileEQ.frequencyRange.contains(Float($0.frequency)) &&
                MobileEQ.gainRange.contains($0.gain) && MobileEQ.qualityRange.contains(Float($0.q)) &&
                (!$0.type.supportsSlope || FilterDesigner.slopes.contains($0.slopeDbPerOct))
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
            case .type: return Float(MobileEQ.filterTypes.firstIndex(of: bands[band].type) ?? 0)
            case .slope: return Float(FilterDesigner.slopes.firstIndex(of: bands[band].slopeDbPerOct) ?? 1)
            case .enabled: return bands[band].enabled ? 1 : 0
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
            case .type: bands[band].type = MobileEQ.filterTypes[Int(clamped(0...Float(MobileEQ.filterTypes.count - 1)).rounded())]
            case .slope: bands[band].slopeDbPerOct = FilterDesigner.slopes[Int(clamped(0...Float(FilterDesigner.slopes.count - 1)).rounded())]
            case .enabled: bands[band].enabled = value >= 0.5
            }
        }
    }
}

extension FilterType {
    var mobileName: String {
        switch self {
        case .peaking: return "Bell"
        case .lowShelf: return "Low Shelf"
        case .highShelf: return "High Shelf"
        case .lowPass: return "Low Pass"
        case .highPass: return "High Pass"
        case .notch: return "Notch"
        case .bandPass: return "Band Pass"
        case .allPass: return "All Pass"
        }
    }
}
