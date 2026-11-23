import SwiftUI
import UniformTypeIdentifiers

struct TrackStudyView: View {
    @EnvironmentObject private var store: TrackStudyStore
    @State private var showingImporter = false
    @State private var markerTitle = ""
    @State private var showingRemoveConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if let error = store.errorMessage { errorCard(error) }
                    if let track = store.track {
                        playbackCard(track)
                        analysisCard(track)
                        markersCard(track)
                        Button("Remove imported track", systemImage: "trash", role: .destructive) {
                            showingRemoveConfirmation = true
                        }
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        importCard
                    }
                    privacyNote
                }
                .padding(20)
                .padding(.bottom, 32)
            }
            .background(Color(red: 0.045, green: 0.06, blue: 0.09).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio]) { result in
                switch result {
                case .success(let url):
                    Task { await store.importTrack(from: url) }
                case .failure(let error):
                    store.errorMessage = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Remove this track and its practice markers?",
                isPresented: $showingRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove track", role: .destructive) { store.removeTrack() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("TRACK STUDY")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(2.4)
                        .foregroundStyle(.mint)
                    Text("Practice the\nmusic itself.")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(-0.7)
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "music.note.list")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(.mint)
                    .frame(width: 66, height: 66)
                    .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 21))
            }
            Text("Bring in an audio file, find the part you want to practice, and save a marker to return to it.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(3)
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your file stays on this device", systemImage: "lock.shield")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Choose an audio file you own or have permission to use. Track Study copies it into its private app storage so playback and practice markers stay together.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showingImporter = true
            } label: {
                Label(store.isImporting ? "Importing…" : "Choose an audio file", systemImage: "folder")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(Color(red: 0.03, green: 0.11, blue: 0.08))
                    .background(.mint, in: RoundedRectangle(cornerRadius: 15))
            }
            .disabled(store.isImporting)
        }
        .padding(18)
        .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 21))
    }

    private func playbackCard(_ track: PracticeTrack) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.mint)
                    .frame(width: 46, height: 46)
                    .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text("\(timeString(track.duration)) · Imported \(track.importedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }

            Slider(
                value: Binding(get: { store.currentTime }, set: { store.seek(to: $0) }),
                in: 0...max(track.duration, 1)
            )
            .tint(.mint)
            HStack {
                Text(timeString(store.currentTime))
                Spacer()
                Text(timeString(track.duration))
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.54))

            HStack(spacing: 12) {
                Button {
                    store.seek(to: max(store.currentTime - 5, 0))
                } label: {
                    Label("Back 5 seconds", systemImage: "gobackward.5")
                }
                .accessibilityLabel("Back five seconds")
                Spacer()
                Button {
                    store.togglePlayback()
                } label: {
                    Label(store.isPlaying ? "Pause" : "Play", systemImage: store.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .foregroundStyle(Color(red: 0.03, green: 0.11, blue: 0.08))
                        .background(.mint, in: Capsule())
                }
                Spacer()
                Button {
                    store.seek(to: min(store.currentTime + 5, track.duration))
                } label: {
                    Label("Forward 5 seconds", systemImage: "goforward.5")
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Forward five seconds")
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .tint(.mint)
        }
        .padding(17)
        .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 21))
    }

    private func analysisCard(_ track: PracticeTrack) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading("MUSIC UNDERSTANDING", symbol: "waveform.path.ecg")
            if let analysis = track.analysis {
                HStack(spacing: 10) {
                    metricCard("TEMPO", value: analysis.tempoBPM.map { "\($0) BPM" } ?? "Not found")
                    metricCard("KEY", value: analysis.keySpans.first?.key ?? "Not found")
                }
                Text("\(analysis.sectionSpans.count) song sections · \(analysis.paceSpans.count) pace ranges")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.59))
                ForEach(Array(analysis.sectionSpans.prefix(12).enumerated()), id: \.offset) { index, span in
                    HStack {
                        Text("Section \(index + 1)").foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Text("\(timeString(span.startSeconds)) – \(timeString(span.startSeconds + span.durationSeconds))")
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
            } else {
                Text(MusicUnderstandingAnalyzer.isAvailable
                     ? "Analyze tempo, key, musical sections, and pace from this imported file on device."
                     : "Tempo, key, section, and pace analysis requires the iOS 27 SDK. Playback and practice markers work in this build.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.61))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await store.analyzeTrack() }
                } label: {
                    HStack {
                        if store.isAnalyzing { ProgressView().tint(.black) }
                        Label(store.isAnalyzing ? "Analyzing on device…" : "Analyze this track", systemImage: "sparkles")
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(Color(red: 0.03, green: 0.11, blue: 0.08))
                    .background(MusicUnderstandingAnalyzer.isAvailable ? Color.mint : Color.gray.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!MusicUnderstandingAnalyzer.isAvailable || store.isAnalyzing)
            }
        }
        .padding(17)
        .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 21))
    }

    private func markersCard(_ track: PracticeTrack) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionHeading("PRACTICE MARKERS", symbol: "bookmark")
                Spacer()
                Text("\(track.markers.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.mint)
            }
            HStack(spacing: 9) {
                TextField("Verse entry, difficult bar…", text: $markerTitle)
                    .font(.system(size: 13, design: .rounded))
                    .padding(12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    store.addMarker(title: markerTitle)
                    markerTitle = ""
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.03, green: 0.11, blue: 0.08))
                        .frame(width: 42, height: 42)
                        .background(.mint, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Add practice marker at current time")
            }
            if track.markers.isEmpty {
                Text("Pause anywhere, name the passage, and save a point to return to during practice.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                ForEach(track.markers.sorted { $0.seconds < $1.seconds }) { marker in
                    HStack(spacing: 10) {
                        Text(timeString(marker.seconds))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.mint)
                        Text(marker.title)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Jump") { store.jumpToMarker(marker) }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .tint(.mint)
                        Button(role: .destructive) { store.removeMarker(marker) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                        }
                        .accessibilityLabel("Remove \(marker.title)")
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
                }
            }
        }
        .padding(17)
        .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 21))
    }

    private var privacyNote: some View {
        Label("Only files you choose are indexed. Imported audio and practice notes remain in Track Study's app storage.", systemImage: "lock.shield")
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(.white.opacity(0.47))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionHeading(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(.mint)
    }

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(.white.opacity(0.45))
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.orange.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00" }
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remaining)
            : String(format: "%02d:%02d", minutes, remaining)
    }
}
