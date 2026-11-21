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
        var settings = MobileEQSettings()
        var sampleRate = 48_000.0
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
        guard MobileEQ.bandCount == SonanceRenderBands,
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

    var settings: MobileEQSettings { control.withLock { $0.settings } }
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
        var coefficients = [Double]()
        coefficients.reserveCapacity(Int(SonanceRenderCoefficientCount))
        for (index, band) in settings.bands.enumerated() {
            let inactive = settings.bypassed || !band.enabled || band.frequency > highestFrequency ||
                (band.type.usesGain && band.gain == 0)
            let sections = inactive ? [] : FilterDesigner.sections(for: band, sampleRate: state.sampleRate)
            for slot in 0..<Int(SonanceSectionsPerBand) {
                let section = slot < sections.count ? sections[slot] : .identity
                let scale = index == 0 && slot == 0 && !settings.bypassed ? pow(10, Double(settings.preamp) / 20) : 1
                coefficients.append(contentsOf: [Double(section.b0) * scale, Double(section.b1) * scale,
                                                Double(section.b2) * scale, Double(section.a1), Double(section.a2)])
            }
        }
        coefficients.withUnsafeBufferPointer { SonanceRenderStage(storage.pointer, $0.baseAddress!) }
    }

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
        ]
        for band in initial.bands.indices {
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
        }

        let tree = AUParameterTree.createTree(withChildren: nodes)
        tree.implementorValueObserver = { [weak self] parameter, value in
            guard let self else { return }
            self.control.withLock { state in
                state.settings.setValue(value, at: parameter.address)
                self.stage(state)
            }
        }
        tree.implementorValueProvider = { [weak self] parameter in
            self?.control.withLock { $0.settings.value(at: parameter.address) } ?? 0
        }
        return tree
    }
}
