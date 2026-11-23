import SwiftUI
import UniformTypeIdentifiers

private enum TrackLibrarySort: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case title = "Title"
    case key = "First key"
    case tempo = "Tempo"

    var id: String { rawValue }
}

struct TrackStudyView: View {
    @EnvironmentObject private var store: TrackStudyStore
    @State private var showingImporter = false
    @State private var markerTitle = ""
    @State private var loopTitle = "Practice loop"
    @State private var loopStartDraft: TimeInterval?
    @State private var loopEndDraft: TimeInterval?
    @State private var showingRemoveConfirmation = false
    @State private var librarySort: TrackLibrarySort = .recent
    @State private var librarySearchText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if let error = store.errorMessage { errorCard(error) }
                    if let status = store.importStatusMessage {
                        Text(status)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.mint)
                    }
                    if store.isImporting {
                        Button(store.isCancellingImport ? "Stopping after current file…" : "Stop after current file") {
                            store.cancelImport()
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.mint)
                        .disabled(store.isCancellingImport)
                    }
                    if !store.tracks.isEmpty { trackLibraryCard }
                    if let track = store.track {
                        playbackCard(track)
                        analysisCard(track)
                        markersCard(track)
                        loopsCard(track)
                        exportCard(track)
                        Button("Remove selected track", systemImage: "trash", role: .destructive) {
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
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    Task { await store.importTracks(from: urls) }
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
            .onDisappear { store.cancelAnalysis() }
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
            Text("Build a local music shelf, choose a track to practice, and save markers for the passages you want to revisit.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(3)
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your audio stays on this device", systemImage: "lock.shield")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Choose audio files you own or have permission to use. Track Study keeps private copies for playback and on-device analysis, with your practice markers and loops. These files are excluded from device backups.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showingImporter = true
            } label: {
                Label(store.isImporting ? "Importing…" : "Import audio files", systemImage: "folder")
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

    private var trackLibraryCard: some View {
        let visibleTracks = sortedLibraryTracks
        let query = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let libraryCount = query.isEmpty ? "\(store.tracks.count)" : "\(visibleTracks.count) OF \(store.tracks.count)"
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionHeading("TRACKS · \(libraryCount)", symbol: "music.note.list")
                Spacer(minLength: 8)
                Button {
                    showingImporter = true
                } label: {
                    Label(store.isImporting ? "Importing…" : "Add audio files", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bordered)
                .tint(.mint)
                .disabled(store.isImporting)
            }

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.mint.opacity(0.8))
                TextField("Search title, key, BPM, instrument, or marker", text: $librarySearchText)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search local tracks by title, key, tempo, instrument, pace, marker, or loop")
                if !librarySearchText.isEmpty {
                    Button {
                        librarySearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear track search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 13))

            Picker("Sort local tracks", selection: $librarySort) {
                ForEach(TrackLibrarySort.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)

            if visibleTracks.isEmpty {
                Text("No tracks match “\(librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines))”.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.vertical, 8)
            } else {
                ForEach(visibleTracks) { item in
                    let selected = store.selectedTrackID == item.id
                    Button {
                        store.selectTrack(item.id)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(selected ? .mint : .white.opacity(0.35))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    if let key = item.analysis?.firstKeySpan?.key {
                                        Text(key)
                                    } else {
                                        Text("Key not analyzed")
                                    }
                                    if let tempo = item.analysis?.tempoBPM {
                                        Text("· \(tempo) BPM")
                                    }
                                    Text("· \(timeString(item.duration))")
                                }
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.white.opacity(0.54))
                                if let matchHint = searchMatchHint(for: item) {
                                    Text(matchHint)
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(.mint.opacity(0.82))
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            if selected {
                                Text("SELECTED")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(0.7)
                                    .foregroundStyle(.mint)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(libraryTrackAccessibilityLabel(for: item, selected: selected))
                    .accessibilityHint("Double-tap to select this track for practice.")
                    if item.id != visibleTracks.last?.id {
                        Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
                    }
                }
            }
            Text("Files stay in Track Study. First-key and tempo sorting uses on-device Music Understanding analysis when available.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(17)
        .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 21))
    }

    private var sortedLibraryTracks: [PracticeTrack] {
        let query = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryTerms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let matchingTracks = store.tracks.filter { track in
            guard !queryTerms.isEmpty else { return true }
            let searchableValues = [
                track.title,
                track.analysis?.tempoBPM.map { "\($0) BPM" } ?? ""
            ]
                + (track.analysis?.keySpans.map(\.key) ?? [])
                + (track.analysis?.paceSpans.map { "\(Int($0.pace.rounded())) events/min" } ?? [])
                + (track.analysis?.instrumentSpans?.map { instrumentDisplayName($0.instrument) } ?? [])
                + track.markers.map(\.title)
                + track.loops.map(\.title)
            return queryTerms.allSatisfy { term in
                searchableValues.contains { $0.localizedStandardContains(term) }
            }
        }

        return matchingTracks.sorted { left, right in
            switch librarySort {
            case .recent:
                if left.importedAt != right.importedAt { return left.importedAt > right.importedAt }
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            case .title:
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            case .key:
                let leftKey = left.analysis?.firstKeySpan?.key ?? "~"
                let rightKey = right.analysis?.firstKeySpan?.key ?? "~"
                let order = leftKey.localizedCaseInsensitiveCompare(rightKey)
                if order != .orderedSame { return order == .orderedAscending }
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            case .tempo:
                let leftTempo = left.analysis?.tempoBPM ?? Int.max
                let rightTempo = right.analysis?.tempoBPM ?? Int.max
                if leftTempo != rightTempo { return leftTempo < rightTempo }
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }
        }
    }

    private func searchMatchHint(for track: PracticeTrack) -> String? {
        let queryTerms = librarySearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !queryTerms.isEmpty else { return nil }
        func matches(_ value: String) -> Bool {
            queryTerms.contains { value.localizedStandardContains($0) }
        }

        var hints: [String] = []
        if let marker = track.markers.first(where: { matches($0.title) }) {
            hints.append("MARKER · \(marker.title)")
        }
        if let loop = track.loops.first(where: { matches($0.title) }) {
            hints.append("LOOP · \(loop.title)")
        }
        if let key = track.analysis?.keySpans.first(where: {
            matches($0.key)
        })?.key {
            hints.append("KEY · \(key)")
        }
        if let tempo = track.analysis?.tempoBPM,
           matches("\(tempo) BPM") {
            hints.append("TEMPO · \(tempo) BPM")
        }
        if let pace = track.analysis?.paceSpans.first(where: {
            matches("\(Int($0.pace.rounded())) events/min")
        }) {
            hints.append("PACE · \(Int(pace.pace.rounded())) events/min")
        }
        if let instrument = track.analysis?.instrumentSpans?.first(where: {
            matches(instrumentDisplayName($0.instrument))
        }) {
            hints.append("INSTRUMENT · \(instrumentDisplayName(instrument.instrument))")
        }
        guard !hints.isEmpty else { return nil }
        return hints.prefix(2).joined(separator: " · ")
    }

    private func libraryTrackAccessibilityLabel(for track: PracticeTrack, selected: Bool) -> String {
        var details = ["Select \(track.title)"]
        if selected { details.append("currently selected") }
        details.append("duration \(timeString(track.duration))")
        if let key = track.analysis?.firstKeySpan?.key {
            details.append("key \(key)")
        }
        if let tempo = track.analysis?.tempoBPM {
            details.append("\(tempo) beats per minute")
        }
        if let matchHint = searchMatchHint(for: track) {
            details.append("search match \(matchHint.replacingOccurrences(of: " · ", with: ", "))")
        }
        return details.joined(separator: ", ")
    }

    private func instrumentDisplayName(_ rawName: String) -> String {
        rawName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
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

            Menu {
                ForEach(PracticePlaybackRate.allCases, id: \.rawValue) { choice in
                    Button {
                        store.setPlaybackRate(choice.rawValue)
                    } label: {
                        if abs(store.playbackRate - choice.rawValue) < 0.001 {
                            Label(choice.title, systemImage: "checkmark")
                        } else {
                            Text(choice.title)
                        }
                    }
                }
            } label: {
                Label("Speed · \(selectedPlaybackRateTitle)", systemImage: "speedometer")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.mint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityHint("Choose a pitch-preserving playback speed for practice")

            Text("Slower playback uses pitch-preserving audio processing; very slow playback may add artifacts.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
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
                    metricCard("KEY", value: analysis.firstKeySpan?.key ?? "Not found")
                }
                HStack(spacing: 10) {
                    metricCard(
                        "INTEGRATED LUFS",
                        value: analysis.integratedLoudnessLUFS.map { String(format: "%.1f", $0) } ?? "Not found"
                    )
                    metricCard(
                        "PEAK dB",
                        value: analysis.peakDecibels.map { String(format: "%.1f", $0) } ?? "Not found"
                    )
                }
                Text("\(analysis.sectionSpans.count) sections · \(analysis.paceSpans.count) pace ranges · \(analysis.instrumentSpans?.count ?? 0) instrument ranges")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.59))
                if !analysis.paceSpans.isEmpty {
                    Text("PACE WINDOWS · perceived events/min, separate from BPM")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    ForEach(analysis.paceSpans.prefix(8)) { span in
                        Button {
                            store.seek(to: span.startSeconds)
                        } label: {
                            HStack {
                                Text(String(format: "%.0f events/min", span.pace))
                                    .foregroundStyle(.white.opacity(0.85))
                                Spacer()
                                Text("\(timeString(span.startSeconds)) – \(timeString(span.startSeconds + span.durationSeconds))")
                                    .foregroundStyle(.white.opacity(0.55))
                                Image(systemName: "arrow.uturn.forward").foregroundStyle(.mint)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Jump to pace range at \(timeString(span.startSeconds)), \(Int(span.pace.rounded())) perceived events per minute")
                    }
                }
                if let instrumentSpans = analysis.instrumentSpans, !instrumentSpans.isEmpty {
                    let instruments = Array(Set(instrumentSpans.map(\.instrument))).sorted()
                    Text("Detected groups: \(instruments.map(instrumentDisplayName).joined(separator: ", "))")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("Instrument entrances · tap to jump")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    ForEach(instruments.prefix(8), id: \.self) { instrument in
                        if let firstSpan = instrumentSpans
                            .filter({ $0.instrument == instrument })
                            .min(by: { $0.startSeconds < $1.startSeconds }) {
                            Button {
                                store.seek(to: firstSpan.startSeconds)
                            } label: {
                                HStack {
                                    Text(instrumentDisplayName(instrument))
                                        .foregroundStyle(.white.opacity(0.85))
                                    Spacer()
                                    Text(timeString(firstSpan.startSeconds))
                                        .foregroundStyle(.white.opacity(0.55))
                                    Image(systemName: "arrow.uturn.forward").foregroundStyle(.mint)
                                }
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Jump to first detected \(instrument) at \(timeString(firstSpan.startSeconds))")
                        }
                    }
                }
                if !analysis.sectionSpans.isEmpty {
                    Text("Sections · tap to jump")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    ForEach(Array(analysis.sectionSpans.prefix(12).enumerated()), id: \.offset) { index, span in
                        Button {
                            store.seek(to: span.startSeconds)
                        } label: {
                            HStack {
                                Text("Section \(index + 1)").foregroundStyle(.white.opacity(0.85))
                                Spacer()
                                Text("\(timeString(span.startSeconds)) – \(timeString(span.startSeconds + span.durationSeconds))")
                                    .foregroundStyle(.white.opacity(0.55))
                                Image(systemName: "arrow.uturn.forward").foregroundStyle(.mint)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Jump to section \(index + 1) at \(timeString(span.startSeconds))")
                    }
                }
                if analysis.keySpans.count > 1 {
                    Text("Key changes · tap to jump")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    ForEach(analysis.keySpans.prefix(12)) { span in
                        Button {
                            store.seek(to: span.startSeconds)
                        } label: {
                            HStack {
                                Text(span.key).foregroundStyle(.white.opacity(0.85))
                                Spacer()
                                Text("\(timeString(span.startSeconds)) · \(timeString(span.durationSeconds))")
                                    .foregroundStyle(.white.opacity(0.55))
                                Image(systemName: "arrow.uturn.forward").foregroundStyle(.mint)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Jump to \(span.key) at \(timeString(span.startSeconds))")
                    }
                }
            } else {
                Text(MusicUnderstandingAnalyzer.isAvailable
                     ? "Analyze rhythm, key, structure, pace, instrument activity, and loudness from this imported file on device."
                     : "Six-dimension music analysis requires the iOS 27 SDK. Playback and practice markers work in this build.")
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
                if store.isAnalyzing {
                    Button("Cancel analysis", systemImage: "xmark.circle") {
                        store.cancelAnalysis()
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
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

    private func loopsCard(_ track: PracticeTrack) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionHeading("PRACTICE LOOPS", symbol: "repeat")
                Spacer()
                Text("Set A and B while paused or playing")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }

            HStack(spacing: 9) {
                pointButton("Set A", value: loopStartDraft) {
                    loopStartDraft = min(max(store.currentTime, 0), track.duration)
                }
                pointButton("Set B", value: loopEndDraft) {
                    loopEndDraft = min(max(store.currentTime, 0), track.duration)
                }
            }

            HStack(spacing: 9) {
                TextField("Loop name", text: $loopTitle)
                    .font(.system(size: 13, design: .rounded))
                    .padding(12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    guard let loopStartDraft, let loopEndDraft else { return }
                    store.saveLoop(title: loopTitle, startSeconds: loopStartDraft, endSeconds: loopEndDraft)
                    if store.errorMessage == nil {
                        loopTitle = "Practice loop"
                        self.loopStartDraft = nil
                        self.loopEndDraft = nil
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.03, green: 0.11, blue: 0.08))
                        .frame(width: 42, height: 42)
                        .background(.mint, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Save practice loop")
                .disabled(!hasValidLoopDraft)
                .opacity(hasValidLoopDraft ? 1 : 0.48)
            }

            if let loopStartDraft, let loopEndDraft, loopEndDraft <= loopStartDraft {
                Text("Set B after Set A to create a loop.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.9))
            }

            if track.loops.isEmpty {
                Text("Mark a passage with A and B, then save it for repeat practice.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                ForEach(track.loops.sorted { $0.startSeconds < $1.startSeconds }) { loop in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(loop.title)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(1)
                            Text("\(timeString(loop.startSeconds)) – \(timeString(loop.endSeconds))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                        Button {
                            store.toggleLoopPlayback(loop)
                        } label: {
                            Label(
                                store.activeLoopID == loop.id ? "Repeat on" : "Repeat",
                                systemImage: store.activeLoopID == loop.id ? "repeat.circle.fill" : "repeat"
                            )
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .tint(.mint)
                        .accessibilityLabel(store.activeLoopID == loop.id ? "Turn off repeat for \(loop.title)" : "Repeat \(loop.title)")
                        Button(role: .destructive) { store.removeLoop(loop) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .accessibilityLabel("Remove \(loop.title)")
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
                }
            }
        }
        .padding(17)
        .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 21))
    }

    private func exportCard(_ track: PracticeTrack) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeading("SHARE A PRACTICE PLAN", symbol: "square.and.arrow.up")
            Text("Share your markers, A/B repeat ranges, and available music summary as text. The audio file is never attached.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.61))
                .fixedSize(horizontal: false, vertical: true)
            ShareLink(item: PracticePlanFormatter.text(for: track)) {
                Label("Share practice plan", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(Color(red: 0.03, green: 0.11, blue: 0.08))
                    .background(.mint, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(track.markers.isEmpty && track.loops.isEmpty && track.analysis == nil)
            .accessibilityLabel("Share practice markers and repeat ranges as text without the audio file")
        }
        .padding(17)
        .background(Color(red: 0.105, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 21))
    }

    private func pointButton(_ title: String, value: TimeInterval?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(value.map { timeString($0) } ?? "—")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.88))
            .padding(12)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var hasValidLoopDraft: Bool {
        guard let loopStartDraft, let loopEndDraft else { return false }
        return loopEndDraft - loopStartDraft >= 0.5
    }

    private var privacyNote: some View {
        Label("Only files you choose are indexed. Audio and practice notes stay on this device and are excluded from device backups.", systemImage: "lock.shield")
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

    private var selectedPlaybackRateTitle: String {
        PracticePlaybackRate.allCases
            .first(where: { abs($0.rawValue - store.playbackRate) < 0.001 })?.title
            ?? PracticePlaybackRate.normal.title
    }
}
