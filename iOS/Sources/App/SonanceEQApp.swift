import AVFAudio
import SwiftUI
import UniformTypeIdentifiers

@main
struct SonanceEQApp: App {
    var body: some Scene {
        WindowGroup { EqualizerView() }
    }
}

private struct EqualizerView: View {
    private static let settingsKey = "sonance.eq.settings.v1"
    private static let accent = Color(light: Color(red: 0.12, green: 0.35, blue: 0.83),
                                      dark: Color(red: 0.58, green: 0.71, blue: 1))

    @State private var settings = loadSettings()
    @State private var player = PreviewPlayer()
    @State private var selectedBand = 5
    @State private var pickingFile = false

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
        .onChange(of: settings, initial: true) { _, value in
            player.apply(value)
            if let data = try? JSONEncoder().encode(value) {
                UserDefaults.standard.set(data, forKey: Self.settingsKey)
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
                            settings.bands = preset.bands
                            settings.preamp = 0
                        }
                    }
                } label: {
                    Label("Presets", systemImage: "square.stack")
                }
            }

            ResponsePlot(bands: settings.bands, sampleRate: player.sampleRate,
                         selection: selectedBand, bypassed: settings.bypassed)

            Toggle("Bypass EQ", isOn: $settings.bypassed)
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("bypassEQ")
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
                        selectedBand = index
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
                    .accessibilityAddTraits(selectedBand == index ? .isSelected : [])
                }
            }

            let band = settings.bands[selectedBand]
            sliderRow("Frequency", value: "\(band.frequency.formatted(.number.precision(.fractionLength(0)))) Hz") {
                Slider(value: frequency, in: log10(20)...log10(20_000))
            }
            sliderRow("Gain", value: "\(band.gainLabel) dB") {
                Slider(value: $settings.bands[selectedBand].gain, in: MobileEQ.gainRange, step: 0.5)
            }
            sliderRow("Width (Q)", value: band.q.formatted(.number.precision(.fractionLength(2)))) {
                Slider(value: $settings.bands[selectedBand].q,
                       in: Double(MobileEQ.qualityRange.lowerBound)...Double(MobileEQ.qualityRange.upperBound), step: 0.05)
            }
            Divider()
            sliderRow("Preamp", value: "\(settings.preamp.formatted(.number.precision(.fractionLength(1)))) dB") {
                Slider(value: $settings.preamp, in: MobileEQ.preampRange, step: 0.5)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var frequency: Binding<Double> {
        Binding(get: { log10(settings.bands[selectedBand].frequency) }, set: { value in
            let range = MobileEQ.frequencyRange
            settings.bands[selectedBand].frequency = min(max(pow(10, value), Double(range.lowerBound)),
                                                          Double(range.upperBound))
        })
    }

    private func sliderRow(_ label: String, value: String, @ViewBuilder slider: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            slider().accessibilityLabel(label).accessibilityValue(value)
        }
    }

    private var pluginHelp: some View {
        DisclosureGroup("Use Sonance EQ in another app") {
            Text("In an app that hosts AUv3 effects, add Sonance EQ as an effect. The host supplies the audio and controls playback.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private static func loadSettings() -> MobileEQSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let saved = try? JSONDecoder().decode(MobileEQSettings.self, from: data), saved.isValid else {
            return MobileEQSettings()
        }
        return saved
    }
}

private extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in UIColor(traits.userInterfaceStyle == .dark ? dark : light) })
    }
}
