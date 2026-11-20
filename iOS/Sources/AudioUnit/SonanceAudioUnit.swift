import AudioToolbox
import AVFAudio
import os

final class SonanceAudioUnitFactory: NSObject, AUAudioUnitFactory {
    func beginRequest(with context: NSExtensionContext) {
        // A headless Audio Unit has no view to prepare. Core Audio calls createAudioUnit for playback.
    }

    func createAudioUnit(with description: AudioComponentDescription) throws -> AUAudioUnit {
        try SonanceAudioUnit(componentDescription: description, options: [])
    }
}

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
        guard Presets.isoCenters.count == SonanceRenderSections,
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
            return SonanceRenderPrepare(storage.pointer, maximumFramesToRender, output.channelCount)
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
        var coefficients = [Double]()
        coefficients.reserveCapacity(Int(SonanceRenderCoefficientCount))
        for (index, band) in settings.bands.enumerated() {
            let inactive = settings.bypassed || band.gain == 0 || band.frequency > state.sampleRate / 2 - 1
            let section = inactive ? .identity : RBJ.coeffs(
                type: .peaking, sampleRate: state.sampleRate, freq: band.frequency,
                gainDb: Double(band.gain), q: band.q
            )
            let scale = index == 0 && !settings.bypassed ? pow(10, Double(settings.preamp) / 20) : 1
            coefficients.append(contentsOf: [Double(section.b0) * scale, Double(section.b1) * scale,
                                            Double(section.b2) * scale, Double(section.a1), Double(section.a2)])
        }
        coefficients.withUnsafeBufferPointer { SonanceRenderStage(storage.pointer, $0.baseAddress!) }
    }

    private func makeParameterTree() -> AUParameterTree {
        let initial = MobileEQSettings()
        func parameter(_ identifier: String, _ name: String, _ address: AUParameterAddress,
                       _ range: ClosedRange<Float>, _ unit: AudioUnitParameterUnit,
                       logarithmic: Bool = false) -> AUParameter {
            // Host UI edits use the parameter tree. Sample-accurate automation is not supported.
            var flags: AudioUnitParameterOptions = [.flag_IsReadable, .flag_IsWritable, .flag_NonRealTime]
            if logarithmic { flags.insert(.flag_DisplayLogarithmic) }
            let parameter = AUParameterTree.createParameter(withIdentifier: identifier, name: name,
                address: address, min: range.lowerBound, max: range.upperBound, unit: unit,
                unitName: nil, flags: flags, valueStrings: nil, dependentParameters: nil)
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
