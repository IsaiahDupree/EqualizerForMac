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
    // New controls live after every address used by builds 1–5. Keep the original
    // ten-band host layout stable so existing AUv3 sessions continue to restore.
    static let midSideEnabledAddress = firstAdditionalBand + AUParameterAddress(maximumBandCount - initialBandCount) * controlsPerBand
    static let firstSideBandAddress = midSideEnabledAddress + 1
    static let sideBandCountAddress = firstSideBandAddress + AUParameterAddress(maximumBandCount) * controlsPerBand
    static let linearPhaseEnabledAddress = sideBandCountAddress + 1

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

    static func sideAddress(_ control: Control, band: Int) -> AUParameterAddress {
        firstSideBandAddress + AUParameterAddress(band) * controlsPerBand + control.rawValue
    }

    static func sideBandControl(at address: AUParameterAddress) -> (Int, Control)? {
        guard address >= firstSideBandAddress, address < sideBandCountAddress else { return nil }
        let offset = address - firstSideBandAddress
        let band = Int(offset / controlsPerBand)
        guard band < maximumBandCount else { return nil }
        return Control(rawValue: offset % controlsPerBand).map { (band, $0) }
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
    var sideBands = Presets.flat
    var preamp: Float = 0
    var bypassed = false
    var midSideEnabled = false
    var linearPhaseEnabled = false

    private static let unusedBand = MobileEQ.newBand()

    init(bands: [EQBand] = Presets.flat, sideBands: [EQBand] = Presets.flat,
         preamp: Float = 0, bypassed: Bool = false, midSideEnabled: Bool = false,
         linearPhaseEnabled: Bool = false) {
        self.bands = bands
        self.sideBands = sideBands
        self.preamp = preamp
        self.bypassed = bypassed
        self.midSideEnabled = midSideEnabled
        self.linearPhaseEnabled = linearPhaseEnabled
    }

    static func startingPoint(bands: [EQBand], sampleRate: Double) -> Self {
        let usableSampleRate = sampleRate.isFinite && sampleRate > 42 ? sampleRate : 48_000
        let maximumFrequency = min(Double(MobileEQ.frequencyRange.upperBound), usableSampleRate / 2 - 1)
        let peakDb = FrequencyResponse.curve(
            bands: bands,
            sampleRate: usableSampleRate,
            points: 512,
            fMax: maximumFrequency
        ).map(\.db).max() ?? 0
        let preamp = peakDb > 0 ? -Float(ceil(peakDb + 1)) : 0
        return MobileEQSettings(bands: bands, preamp: preamp, bypassed: false)
    }

    var isValid: Bool {
        MobileEQ.preampRange.contains(preamp) && bands.count <= MobileEQ.maximumBandCount &&
            sideBands.count <= MobileEQ.maximumBandCount &&
            Set(bands.map(\.id)).count == bands.count && Set(sideBands.map(\.id)).count == sideBands.count &&
            bands.allSatisfy(Self.validBand) && sideBands.allSatisfy(Self.validBand)
    }

    private static func validBand(_ band: EQBand) -> Bool {
        MobileEQ.frequencyRange.contains(Float(band.frequency)) &&
            MobileEQ.gainRange.contains(band.gain) && MobileEQ.qualityRange.contains(Float(band.q)) &&
            (!band.type.supportsSlope || FilterDesigner.slopes.contains(band.slopeDbPerOct))
    }

    private enum CodingKeys: String, CodingKey { case bands, sideBands, preamp, bypassed, midSideEnabled, linearPhaseEnabled }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bands = try values.decode([EQBand].self, forKey: .bands)
        sideBands = try values.decodeIfPresent([EQBand].self, forKey: .sideBands) ?? Presets.flat
        preamp = try values.decode(Float.self, forKey: .preamp)
        bypassed = try values.decodeIfPresent(Bool.self, forKey: .bypassed) ?? false
        midSideEnabled = try values.decodeIfPresent(Bool.self, forKey: .midSideEnabled) ?? false
        linearPhaseEnabled = try values.decodeIfPresent(Bool.self, forKey: .linearPhaseEnabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(bands, forKey: .bands)
        try values.encode(sideBands, forKey: .sideBands)
        try values.encode(preamp, forKey: .preamp)
        try values.encode(bypassed, forKey: .bypassed)
        try values.encode(midSideEnabled, forKey: .midSideEnabled)
        try values.encode(linearPhaseEnabled, forKey: .linearPhaseEnabled)
    }

    func selection(_ index: Int?) -> Int? {
        guard !bands.isEmpty else { return nil }
        return min(max(index ?? 0, 0), bands.count - 1)
    }

    func value(at address: AUParameterAddress) -> AUValue {
        switch address {
        case MobileEQ.preampAddress: return preamp
        case MobileEQ.bypassAddress: return bypassed ? 1 : 0
        case MobileEQ.midSideEnabledAddress: return midSideEnabled ? 1 : 0
        case MobileEQ.linearPhaseEnabledAddress: return linearPhaseEnabled ? 1 : 0
        case MobileEQ.bandCountAddress: return Float(bands.count)
        case MobileEQ.sideBandCountAddress: return Float(sideBands.count)
        default:
            if let (index, control) = MobileEQ.sideBandControl(at: address) {
                let band = sideBands.indices.contains(index) ? sideBands[index] : Self.unusedBand
                return Self.value(control, band: band)
            }
            guard let (index, control) = MobileEQ.bandControl(at: address) else { return 0 }
            let band = bands.indices.contains(index) ? bands[index] : Self.unusedBand
            return Self.value(control, band: band)
        }
    }

    private static func value(_ control: MobileEQ.Control, band: EQBand) -> AUValue {
        switch control {
        case .frequency: return Float(band.frequency)
        case .gain: return band.gain
        case .quality: return Float(band.q)
        case .type: return Float(MobileEQ.filterTypes.firstIndex(of: band.type) ?? 0)
        case .slope: return Float(FilterDesigner.slopes.firstIndex(of: band.slopeDbPerOct) ?? 1)
        case .enabled: return band.enabled ? 1 : 0
        }
    }

    mutating func setValue(_ value: AUValue, at address: AUParameterAddress) {
        guard value.isFinite else { return }
        func clamped(_ range: ClosedRange<Float>) -> Float { min(max(value, range.lowerBound), range.upperBound) }
        switch address {
        case MobileEQ.preampAddress: preamp = clamped(MobileEQ.preampRange)
        case MobileEQ.bypassAddress: bypassed = value >= 0.5
        case MobileEQ.midSideEnabledAddress: midSideEnabled = value >= 0.5
        case MobileEQ.linearPhaseEnabledAddress: linearPhaseEnabled = value >= 0.5
        default:
            if let (band, control) = MobileEQ.sideBandControl(at: address), sideBands.indices.contains(band) {
                Self.setValue(value, control: control, band: &sideBands[band])
                return
            }
            guard let (band, control) = MobileEQ.bandControl(at: address), bands.indices.contains(band) else { return }
            Self.setValue(value, control: control, band: &bands[band])
        }
    }

    private static func setValue(_ value: AUValue, control: MobileEQ.Control, band: inout EQBand) {
        func clamped(_ range: ClosedRange<Float>) -> Float { min(max(value, range.lowerBound), range.upperBound) }
        switch control {
        case .frequency: band.frequency = Double(clamped(MobileEQ.frequencyRange))
        case .gain: band.gain = clamped(MobileEQ.gainRange)
        case .quality: band.q = Double(clamped(MobileEQ.qualityRange))
        case .type: band.type = MobileEQ.filterTypes[Int(clamped(0...Float(MobileEQ.filterTypes.count - 1)).rounded())]
        case .slope: band.slopeDbPerOct = FilterDesigner.slopes[Int(clamped(0...Float(FilterDesigner.slopes.count - 1)).rounded())]
        case .enabled: band.enabled = value >= 0.5
        }
    }

    func apply(to tree: AUParameterTree, changedFrom previous: MobileEQSettings? = nil, originator: AUParameterObserverToken? = nil) {
        let previousCount = previous?.bands.count ?? MobileEQ.initialBandCount
        let previousSideCount = previous?.sideBands.count ?? MobileEQ.initialBandCount
        let count = tree.parameter(withAddress: MobileEQ.bandCountAddress)
        let sideCount = tree.parameter(withAddress: MobileEQ.sideBandCountAddress)
        if bands.count < previousCount { count?.setValue(Float(bands.count), originator: originator) }
        if sideBands.count < previousSideCount { sideCount?.setValue(Float(sideBands.count), originator: originator) }

        for parameter in tree.allParameters where parameter.address != MobileEQ.bandCountAddress && parameter.address != MobileEQ.sideBandCountAddress {
            let sideIndex = MobileEQ.sideBandControl(at: parameter.address)?.0
            let mainIndex = MobileEQ.bandControl(at: parameter.address)?.0
            if let sideIndex, sideIndex >= sideBands.count { continue }
            if let mainIndex, mainIndex >= bands.count { continue }
            let value = value(at: parameter.address)
            // An index brought back into use may still hold values from a deleted band in the host.
            let newlyAllocated = sideIndex.map { $0 >= previousSideCount } ?? mainIndex.map { $0 >= previousCount } ?? false
            if newlyAllocated || previous?.value(at: parameter.address) != value {
                parameter.setValue(value, originator: originator)
            }
        }

        if bands.count > previousCount { count?.setValue(Float(bands.count), originator: originator) }
        if sideBands.count > previousSideCount { sideCount?.setValue(Float(sideBands.count), originator: originator) }
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
