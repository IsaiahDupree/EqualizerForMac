import AVFAudio
import SwiftUI
import UniformTypeIdentifiers

@main
struct SonanceEQApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = EqualizerSession()

    var body: some Scene {
        WindowGroup { EqualizerView(session: session) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { session.checkpointForBackground() }
            }
    }
}

private struct EqualizerView: View {
    private static let accent = Color(light: Color(red: 0.12, green: 0.35, blue: 0.83),
                                      dark: Color(red: 0.58, green: 0.71, blue: 1))

    let session: EqualizerSession
    @State private var pickingFile = false

    private var settings: MobileEQSettings { session.snapshot.settings }
    private var selectedBand: Int { session.snapshot.selectedBand }
    private var player: PreviewPlayer { session.player }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    playback
                    equalizer
                    controls
                    pluginHelp
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Sonance EQ")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Self.accent)
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): player.select(url)
            case .failure: player.error = "The audio file couldn’t be opened."
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            Task { @MainActor in player.handleInterruption(notification) }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            Task { @MainActor in player.handleRouteChange(notification) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange)) { notification in
            Task { @MainActor in player.handleConfigurationChange(notification) }
        }
    }

    private var playback: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(player.fileName ?? "Local audio", systemImage: "waveform")
                .font(.headline)
                .lineLimit(1)
                .accessibilityIdentifier("audioFileName")
            Text(playbackStatus)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { playbackButtons }
                VStack(alignment: .leading, spacing: 10) { playbackButtons }
            }
            if let error = player.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var playbackStatus: String {
        switch player.state {
        case .idle: return player.fileName == nil ? "Choose an audio file to hear your EQ." : "Ready to play"
        case .starting: return "Starting playback…"
        case .playing: return player.outputName.map { "Playing on \($0)" } ?? "Playing"
        }
    }

    @ViewBuilder private var playbackButtons: some View {
        Button { pickingFile = true } label: {
            Label("Open Audio", systemImage: "folder")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("openAudio")

        Button {
            if player.state == .idle {
                Task { await player.play() }
            } else {
                player.stop()
            }
        } label: {
            switch player.state {
            case .idle: Label("Play", systemImage: "play.fill")
            case .starting: Label("Cancel", systemImage: "xmark")
            case .playing: Label("Stop", systemImage: "stop.fill")
            }
        }
        .buttonStyle(.bordered)
        .disabled(player.fileName == nil)
        .accessibilityIdentifier("playAudio")
    }

    private var equalizer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Equalizer")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Menu {
                    ForEach(Presets.all) { preset in
                        Button(preset.name) {
                            session.updateEQ {
                                $0.bands = preset.bands
                                $0.preamp = 0
                            }
                        }
                    }
                } label: {
                    Label("Presets", systemImage: "square.stack")
                }
            }

            ResponsePlot(bands: settings.bands, sampleRate: player.sampleRate,
                         selection: selectedBand, bypassed: settings.bypassed)

            Toggle("Bypass EQ", isOn: eqBinding(\.bypassed))
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("bypassEQ")

            if let message = session.storageMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Filter Bands")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 5)], spacing: 5) {
                ForEach(settings.bands.indices, id: \.self) { index in
                    Button {
                        session.selectBand(index)
                    } label: {
                        Text(settings.bands[index].freqLabel)
                            .font(.subheadline.monospacedDigit().weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selectedBand == index ? Self.accent : .primary)
                            .background(selectedBand == index ? Self.accent.opacity(0.13) :
                                            Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Band \(index + 1), \(settings.bands[index].frequency.formatted(.number.precision(.fractionLength(0)))) hertz")
                    .accessibilityIdentifier("eqBand\(index)")
                    .accessibilityAddTraits(selectedBand == index ? .isSelected : [])
                }
            }

            let band = settings.bands[selectedBand]
            sliderRow("Frequency", id: "eqFrequency", value: "\(band.frequency.formatted(.number.precision(.fractionLength(0)))) Hz") {
                Slider(value: frequency, in: log10(20)...log10(20_000), onEditingChanged: session.sliderEditingChanged)
            }
            sliderRow("Gain", id: "eqGain", value: "\(band.gainLabel) dB") {
                Slider(value: eqBinding(\.bands[selectedBand].gain), in: MobileEQ.gainRange, step: 0.5,
                       onEditingChanged: session.sliderEditingChanged)
            }
            sliderRow("Width (Q)", id: "eqQuality", value: band.q.formatted(.number.precision(.fractionLength(2)))) {
                Slider(value: eqBinding(\.bands[selectedBand].q),
                       in: Double(MobileEQ.qualityRange.lowerBound)...Double(MobileEQ.qualityRange.upperBound), step: 0.05,
                       onEditingChanged: session.sliderEditingChanged)
            }
            Divider()
            sliderRow("Preamp", id: "eqPreamp", value: "\(settings.preamp.formatted(.number.precision(.fractionLength(1)))) dB") {
                Slider(value: eqBinding(\.preamp), in: MobileEQ.preampRange, step: 0.5,
                       onEditingChanged: session.sliderEditingChanged)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var frequency: Binding<Double> {
        let band = selectedBand
        return Binding(get: { log10(settings.bands[band].frequency) }, set: { value in
            let range = MobileEQ.frequencyRange
            session.updateEQ {
                $0.bands[band].frequency = min(max(pow(10, value), Double(range.lowerBound)), Double(range.upperBound))
            }
        })
    }

    private func eqBinding<Value>(_ key: WritableKeyPath<MobileEQSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: key] }, set: { value in session.updateEQ { $0[keyPath: key] = value } })
    }

    private func sliderRow(_ label: String, id: String, value: String, @ViewBuilder slider: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            slider().accessibilityLabel(label).accessibilityValue(value).accessibilityIdentifier(id)
        }
    }

    private var pluginHelp: some View {
        DisclosureGroup("Use Sonance EQ in another app") {
            Text("In an app that hosts AUv3 effects, add Sonance EQ as an effect. The host controls playback and manages its own EQ settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

private extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in UIColor(traits.userInterfaceStyle == .dark ? dark : light) })
    }
}
