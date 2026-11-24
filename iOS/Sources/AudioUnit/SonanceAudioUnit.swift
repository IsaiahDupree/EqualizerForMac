import AudioToolbox
import AVFAudio
import os

private final class RenderStorage {
    let pointer: OpaquePointer

    init() throws {
        guard let pointer = SonanceRenderCreate() else { throw auError(kAudioUnitErr_FailedInitialization) }
        self.pointer = pointer
    }

    deinit { SonanceRenderDestroy(pointer) }
}

private func auError(_ status: OSStatus) -> NSError {
    NSError(domain: NSOSStatusErrorDomain, code: Int(status))
}

final class SonanceAudioUnit: AUAudioUnit {
    private struct ControlState {
        // Hosts can restore the extra bands' parameters before restoring the count.
        var settings = MobileEQSettings()
        var bandCount = MobileEQ.initialBandCount
        var sideBandCount = MobileEQ.initialBandCount
        var sampleRate = 48_000.0

        init() {
            for _ in MobileEQ.initialBandCount..<MobileEQ.maximumBandCount {
                settings.bands.append(MobileEQ.newBand())
                settings.sideBands.append(MobileEQ.newBand())
            }
        }

        var visibleSettings: MobileEQSettings {
            var visible = settings
            visible.bands = Array(settings.bands.prefix(bandCount))
            visible.sideBands = Array(settings.sideBands.prefix(sideBandCount))
            return visible
        }

        mutating func setValue(_ value: AUValue, at address: AUParameterAddress) {
            if address == MobileEQ.bandCountAddress {
                guard value.isFinite else { return }
                bandCount = Int(min(max(value, 0), Float(MobileEQ.maximumBandCount)).rounded())
            } else if address == MobileEQ.sideBandCountAddress {
                guard value.isFinite else { return }
                sideBandCount = Int(min(max(value, 0), Float(MobileEQ.maximumBandCount)).rounded())
            } else {
                settings.setValue(value, at: address)
            }
        }
    }

    private let control = OSAllocatedUnfairLock(initialState: ControlState())
    private let storage: RenderStorage
    private let render: AUInternalRenderBlock
    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        let storage = try RenderStorage()
        self.storage = storage
        render = SonanceRenderMakeBlock(storage.pointer)
        guard MobileEQ.maximumBandCount == SonanceRenderBands,
              let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else {
            throw auError(kAudioUnitErr_FormatNotSupported)
        }
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        try super.init(componentDescription: componentDescription, options: options)

        inputBus.maximumChannelCount = 2
        outputBus.maximumChannelCount = 2
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        parameterTree = makeParameterTree()
    }

    override var inputBusses: AUAudioUnitBusArray { inputs }
    override var outputBusses: AUAudioUnitBusArray { outputs }
    override var internalRenderBlock: AUInternalRenderBlock { render }

    var settings: MobileEQSettings { control.withLock { $0.visibleSettings } }
    var analysisCapture: OpaquePointer { SonanceRenderAnalysis(storage.pointer) }

    override var shouldBypassEffect: Bool {
        get { control.withLock { $0.settings.bypassed } }
        set { parameterTree?.parameter(withAddress: MobileEQ.bypassAddress)?.value = newValue ? 1 : 0 }
    }

    override func shouldChange(to format: AVAudioFormat, for bus: AUAudioUnitBus) -> Bool {
        Self.supports(format)
    }

    private static func supports(_ format: AVAudioFormat) -> Bool {
        (1...2).contains(format.channelCount) && format.commonFormat == .pcmFormatFloat32 &&
            !format.isInterleaved && (8_000...192_000).contains(format.sampleRate)
    }

    override func allocateRenderResources() throws {
        let input = inputBus.format
        let output = outputBus.format
        guard Self.supports(input), Self.supports(output),
              input.channelCount == output.channelCount, input.sampleRate == output.sampleRate else {
            throw auError(kAudioUnitErr_FormatNotSupported)
        }
        try super.allocateRenderResources()
        let prepared = control.withLock { state in
            state.sampleRate = output.sampleRate
            stage(state)
            return SonanceRenderPrepare(storage.pointer, maximumFramesToRender, output.channelCount, output.sampleRate)
        }
        if !prepared {
            super.deallocateRenderResources()
            throw auError(kAudioUnitErr_FailedInitialization)
        }
    }

    override func deallocateRenderResources() {
        SonanceRenderReleaseResources(storage.pointer)
        super.deallocateRenderResources()
    }

    override func reset() {
        super.reset()
        SonanceRenderReset(storage.pointer)
    }

    private func stage(_ state: ControlState) {
        let settings = state.settings
        let highestFrequency = MobileEQ.highestFrequency(at: state.sampleRate)
        func coefficients(for bands: [EQBand], count: Int) -> [Double] {
            var result = Array(repeating: 0.0, count: Int(SonanceRenderCoefficientCount))
            for section in 0..<Int(SonanceRenderSections) { result[section * 5] = 1 }
            guard !settings.bypassed else { return result }
            var nextSection = 0
            for band in bands.prefix(count) where band.enabled && band.frequency <= highestFrequency && (!band.type.usesGain || band.gain != 0) {
                for section in FilterDesigner.sections(for: band, sampleRate: state.sampleRate) {
                    guard nextSection < Int(SonanceRenderSections) else { break }
                    let offset = nextSection * 5
                    result[offset] = Double(section.b0)
                    result[offset + 1] = Double(section.b1)
                    result[offset + 2] = Double(section.b2)
                    result[offset + 3] = Double(section.a1)
                    result[offset + 4] = Double(section.a2)
                    nextSection += 1
                }
            }
            let scale = pow(10, Double(settings.preamp) / 20)
            for index in 0..<3 { result[index] *= scale }
            return result
        }
        let mid = coefficients(for: settings.bands, count: state.bandCount)
        let side = coefficients(for: settings.sideBands, count: state.sideBandCount)
        let firLength = Int(SonanceFIRLength)
        let midFIR = settings.linearPhaseEnabled
            ? FIRDesigner.design(bands: settings.bands, preampDb: settings.preamp,
                                 sampleRate: state.sampleRate, length: firLength, bypassed: settings.bypassed)
            : Self.firIdentity
        let sideFIR = settings.linearPhaseEnabled && settings.midSideEnabled
            ? FIRDesigner.design(bands: settings.sideBands, preampDb: settings.preamp,
                                 sampleRate: state.sampleRate, length: firLength, bypassed: settings.bypassed)
            : midFIR
        mid.withUnsafeBufferPointer { midBuffer in
            side.withUnsafeBufferPointer { sideBuffer in
                midFIR.withUnsafeBufferPointer { midFIRBuffer in
                    sideFIR.withUnsafeBufferPointer { sideFIRBuffer in
                        SonanceRenderStage(storage.pointer, midBuffer.baseAddress!, sideBuffer.baseAddress!,
                                           settings.midSideEnabled, midFIRBuffer.baseAddress!, sideFIRBuffer.baseAddress!,
                                           settings.linearPhaseEnabled)
                    }
                }
            }
        }
    }

    private static let firIdentity: [Float] = {
        var result = Array(repeating: Float.zero, count: Int(SonanceFIRLength))
        result[(Int(SonanceFIRLength) - 1) / 2] = 1
        return result
    }()

    private func makeParameterTree() -> AUParameterTree {
        let initial = MobileEQSettings()
        func parameter(_ identifier: String, _ name: String, _ address: AUParameterAddress,
                       _ range: ClosedRange<Float>, _ unit: AudioUnitParameterUnit,
                       logarithmic: Bool = false, labels: [String]? = nil) -> AUParameter {
            // Host UI edits use the parameter tree. Sample-accurate automation is not supported.
            var flags: AudioUnitParameterOptions = [.flag_IsReadable, .flag_IsWritable, .flag_NonRealTime]
            if logarithmic { flags.insert(.flag_DisplayLogarithmic) }
            let parameter = AUParameterTree.createParameter(withIdentifier: identifier, name: name,
                address: address, min: range.lowerBound, max: range.upperBound, unit: unit,
                unitName: nil, flags: flags, valueStrings: labels, dependentParameters: nil)
            parameter.value = initial.value(at: address)
            return parameter
        }

        var nodes: [AUParameterNode] = [
            parameter("preamp", "Preamp", MobileEQ.preampAddress, MobileEQ.preampRange, .decibels),
            parameter("bypass", "Bypass", MobileEQ.bypassAddress, 0...1, .boolean),
            parameter("midSideEnabled", "Mid-Side Processing", MobileEQ.midSideEnabledAddress, 0...1, .boolean),
            parameter("linearPhaseEnabled", "Linear-Phase FIR", MobileEQ.linearPhaseEnabledAddress, 0...1, .boolean),
        ]
        for band in 0..<MobileEQ.maximumBandCount {
            let number = band + 1
            let controls = [
                parameter("frequency", "Band \(number) Frequency", MobileEQ.address(.frequency, band: band),
                          MobileEQ.frequencyRange, .hertz, logarithmic: true),
                parameter("gain", "Band \(number) Gain", MobileEQ.address(.gain, band: band),
                          MobileEQ.gainRange, .decibels),
                parameter("quality", "Band \(number) Q", MobileEQ.address(.quality, band: band),
                          MobileEQ.qualityRange, .generic, logarithmic: true),
                parameter("type", "Band \(number) Filter", MobileEQ.address(.type, band: band),
                          0...Float(MobileEQ.filterTypes.count - 1), .indexed, labels: MobileEQ.filterTypes.map(\.mobileName)),
                parameter("slope", "Band \(number) Slope", MobileEQ.address(.slope, band: band),
                          0...Float(FilterDesigner.slopes.count - 1), .indexed,
                          labels: FilterDesigner.slopes.map { "\(Int($0)) dB/oct" }),
                parameter("enabled", "Band \(number) Enabled", MobileEQ.address(.enabled, band: band), 0...1, .boolean),
            ]
            nodes.append(AUParameterTree.createGroup(withIdentifier: "band\(number)",
                                                     name: "Band \(number)", children: controls))

            let sideControls = [
                parameter("sideFrequency", "Side Band \(number) Frequency", MobileEQ.sideAddress(.frequency, band: band),
                          MobileEQ.frequencyRange, .hertz, logarithmic: true),
                parameter("sideGain", "Side Band \(number) Gain", MobileEQ.sideAddress(.gain, band: band),
                          MobileEQ.gainRange, .decibels),
                parameter("sideQuality", "Side Band \(number) Q", MobileEQ.sideAddress(.quality, band: band),
                          MobileEQ.qualityRange, .generic, logarithmic: true),
                parameter("sideType", "Side Band \(number) Filter", MobileEQ.sideAddress(.type, band: band),
                          0...Float(MobileEQ.filterTypes.count - 1), .indexed, labels: MobileEQ.filterTypes.map(\.mobileName)),
                parameter("sideSlope", "Side Band \(number) Slope", MobileEQ.sideAddress(.slope, band: band),
                          0...Float(FilterDesigner.slopes.count - 1), .indexed,
                          labels: FilterDesigner.slopes.map { "\(Int($0)) dB/oct" }),
                parameter("sideEnabled", "Side Band \(number) Enabled", MobileEQ.sideAddress(.enabled, band: band), 0...1, .boolean),
            ]
            nodes.append(AUParameterTree.createGroup(withIdentifier: "sideBand\(number)",
                                                     name: "Side Band \(number)", children: sideControls))
        }
        nodes.append(parameter("bandCount", "Band Count", MobileEQ.bandCountAddress,
                               0...Float(MobileEQ.maximumBandCount), .indexed))
        nodes.append(parameter("sideBandCount", "Side Band Count", MobileEQ.sideBandCountAddress,
                               0...Float(MobileEQ.maximumBandCount), .indexed))
        func telemetry(_ identifier: String, _ name: String, _ address: AUParameterAddress,
                       _ maximum: Float) -> AUParameter {
            AUParameterTree.createParameter(withIdentifier: identifier, name: name,
                address: address, min: 0, max: maximum, unit: .generic, unitName: nil,
                flags: [.flag_IsReadable, .flag_NonRealTime], valueStrings: nil, dependentParameters: nil)
        }
        nodes.append(contentsOf: [
            telemetry("renderBlocks", "Completed Render Blocks", MobileEQ.renderBlocksAddress, 16_777_216),
            telemetry("deadlineMisses", "Render Deadline Misses", MobileEQ.deadlineMissesAddress, 16_777_216),
            telemetry("maximumRenderMicroseconds", "Maximum Render Time (µs)", MobileEQ.maximumProcessingMicrosecondsAddress, 60_000_000),
            telemetry("lastDeadlineMicroseconds", "Last Buffer Deadline (µs)", MobileEQ.lastDeadlineMicrosecondsAddress, 60_000_000),
        ])

        let tree = AUParameterTree.createTree(withChildren: nodes)
        tree.implementorValueObserver = { [weak self] parameter, value in
            guard let self else { return }
            self.control.withLock { state in
                state.setValue(value, at: parameter.address)
                if let (band, _) = MobileEQ.bandControl(at: parameter.address), band >= state.bandCount { return }
                if let (band, _) = MobileEQ.sideBandControl(at: parameter.address), band >= state.sideBandCount { return }
                self.stage(state)
            }
        }
        tree.implementorValueProvider = { [weak self] parameter in
            self?.control.withLock { state in
                switch parameter.address {
                case MobileEQ.bandCountAddress: return Float(state.bandCount)
                case MobileEQ.sideBandCountAddress: return Float(state.sideBandCount)
                case MobileEQ.renderBlocksAddress: return Float(SonanceRenderCompletedBlocks(self.storage.pointer))
                case MobileEQ.deadlineMissesAddress: return Float(SonanceRenderDeadlineMisses(self.storage.pointer))
                case MobileEQ.maximumProcessingMicrosecondsAddress:
                    return Float(SonanceRenderMaximumProcessingNanoseconds(self.storage.pointer)) / 1_000
                case MobileEQ.lastDeadlineMicrosecondsAddress:
                    return Float(SonanceRenderLastDeadlineNanoseconds(self.storage.pointer)) / 1_000
                default: return state.settings.value(at: parameter.address)
                }
            } ?? 0
        }
        return tree
    }
}
