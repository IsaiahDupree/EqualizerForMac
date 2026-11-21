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
    static let initialBandCount = Presets.isoCenters.count
    static let maximumBandCount = 32
    static let filterTypes: [FilterType] = [.peaking, .lowShelf, .highShelf, .lowPass, .highPass, .notch, .bandPass, .allPass]

    static func highestFrequency(at sampleRate: Double) -> Double {
        min(Double(frequencyRange.upperBound), sampleRate / 2 - 1)
    }

    enum Control: AUParameterAddress, CaseIterable {
        case frequency, gain, quality, type, slope, enabled
    }

    private static let originalControls: AUParameterAddress = 3
    private static let extraControls: AUParameterAddress = 3
    private static let controlsPerBand = originalControls + extraControls
    // Builds 1–4 used separate address ranges for the original ten bands.
    private static let firstExtraAddress = 2 + AUParameterAddress(initialBandCount) * originalControls
    static let bandCountAddress = 2 + AUParameterAddress(initialBandCount) * controlsPerBand
    private static let firstAdditionalBand = bandCountAddress + 1

    static func newBand() -> EQBand {
        EQBand(frequency: 1_000, gain: 0, q: 1, type: .peaking)
    }

    static func address(_ control: Control, band: Int) -> AUParameterAddress {
        if band >= initialBandCount {
            return firstAdditionalBand + AUParameterAddress(band - initialBandCount) * controlsPerBand + control.rawValue
        }
        if control.rawValue < originalControls {
            return 2 + AUParameterAddress(band) * originalControls + control.rawValue
        }
        return firstExtraAddress + AUParameterAddress(band) * extraControls + control.rawValue - originalControls
    }

    static func bandControl(at address: AUParameterAddress) -> (Int, Control)? {
        guard address >= 2, address != bandCountAddress else { return nil }
        if address >= firstAdditionalBand {
            let offset = address - firstAdditionalBand
            let band = initialBandCount + Int(offset / controlsPerBand)
            guard band < maximumBandCount else { return nil }
            return Control(rawValue: offset % controlsPerBand).map { (band, $0) }
        }
        if address < firstExtraAddress {
            let offset = address - 2
            return Control(rawValue: offset % originalControls).map { (Int(offset / originalControls), $0) }
        }
        let offset = address - firstExtraAddress
        return Control(rawValue: originalControls + offset % extraControls).map { (Int(offset / extraControls), $0) }
    }
}

struct MobileEQSettings: Codable, Equatable {
    var bands = Presets.flat
    var preamp: Float = 0
    var bypassed = false

    private static let unusedBand = MobileEQ.newBand()

    var isValid: Bool {
        MobileEQ.preampRange.contains(preamp) && bands.count <= MobileEQ.maximumBandCount &&
            Set(bands.map(\.id)).count == bands.count && bands.allSatisfy {
            MobileEQ.frequencyRange.contains(Float($0.frequency)) &&
                MobileEQ.gainRange.contains($0.gain) && MobileEQ.qualityRange.contains(Float($0.q)) &&
                (!$0.type.supportsSlope || FilterDesigner.slopes.contains($0.slopeDbPerOct))
        }
    }

    func selection(_ index: Int?) -> Int? {
        guard !bands.isEmpty else { return nil }
        return min(max(index ?? 0, 0), bands.count - 1)
    }

    func value(at address: AUParameterAddress) -> AUValue {
        switch address {
        case MobileEQ.preampAddress: return preamp
        case MobileEQ.bypassAddress: return bypassed ? 1 : 0
        case MobileEQ.bandCountAddress: return Float(bands.count)
        default:
            guard let (index, control) = MobileEQ.bandControl(at: address) else { return 0 }
            let band = bands.indices.contains(index) ? bands[index] : Self.unusedBand
            switch control {
            case .frequency: return Float(band.frequency)
            case .gain: return band.gain
            case .quality: return Float(band.q)
            case .type: return Float(MobileEQ.filterTypes.firstIndex(of: band.type) ?? 0)
            case .slope: return Float(FilterDesigner.slopes.firstIndex(of: band.slopeDbPerOct) ?? 1)
            case .enabled: return band.enabled ? 1 : 0
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
            guard let (band, control) = MobileEQ.bandControl(at: address), bands.indices.contains(band) else { return }
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

    func apply(to tree: AUParameterTree, changedFrom previous: MobileEQSettings? = nil, originator: AUParameterObserverToken? = nil) {
        let previousCount = previous?.bands.count ?? MobileEQ.initialBandCount
        let count = tree.parameter(withAddress: MobileEQ.bandCountAddress)
        if bands.count < previousCount { count?.setValue(Float(bands.count), originator: originator) }

        for parameter in tree.allParameters where parameter.address != MobileEQ.bandCountAddress {
            let index = MobileEQ.bandControl(at: parameter.address)?.0
            if let index, index >= bands.count { continue }
            let value = value(at: parameter.address)
            // An index brought back into use may still hold values from a deleted band in the host.
            if (index.map { $0 >= previousCount } ?? false) || previous?.value(at: parameter.address) != value {
                parameter.setValue(value, originator: originator)
            }
        }

        if bands.count > previousCount { count?.setValue(Float(bands.count), originator: originator) }
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
