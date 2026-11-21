import SwiftUI
import UniformTypeIdentifiers

struct PresetLibraryView: View {
    let library: PresetLibrary
    let session: EqualizerSession
    @Environment(\.dismiss) private var dismiss

    @State private var naming = false
    @State private var renaming: UUID?
    @State private var name = ""
    @State private var importingFiles = false
    @State private var readingFiles = false
    @State private var exporting = false
    @State private var document: PresetDocument?
    @State private var exportName = ""
    @State private var message: String?
    @State private var confirmation: PresetChange?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Save Current EQ", systemImage: "bookmark") { promptForName() }
                        .accessibilityIdentifier("saveCurrentPreset")
                    Button("Import Presets", systemImage: "square.and.arrow.down") { importingFiles = true }
                        .disabled(readingFiles)
                    Button("Export Library", systemImage: "square.and.arrow.up") {
                        export(PresetCollection(presets: library.entries.map(\.file)), name: "Sonance Presets")
                    }
                    .disabled(library.entries.isEmpty)
                }
                .disabled(library.unavailable)

                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                if readingFiles { ProgressView("Importing presets…") }

                Section("Saved Presets") {
                    if library.unavailable {
                        Text(PresetError.libraryUnavailable.localizedDescription)
                    } else if library.entries.isEmpty {
                        Text("Save the current EQ or import a preset from Files.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(library.entries) { entry in
                            presetRow(entry)
                        }
                    }
                }
            }
            .navigationTitle("Preset Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .alert(renaming == nil ? "Save Preset" : "Rename Preset", isPresented: $naming) {
            TextField("Preset name", text: $name)
                .accessibilityIdentifier("presetName")
            Button("Cancel", role: .cancel) {}
            Button("Save", action: saveName)
        }
        .confirmationDialog("Change saved preset", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        ), titleVisibility: .visible, presenting: confirmation) { change in
            switch change {
            case .replace(let entry):
                Button("Replace with Current EQ") {
                    perform { try library.replace(entry.id, with: session.snapshot.settings) }
                }
            case .delete(let entry):
                Button("Delete Preset", role: .destructive) {
                    perform { try library.delete(entry.id) }
                }
            }
        } message: { change in
            Text(change.preset.file.name)
        }
        .fileImporter(isPresented: $importingFiles, allowedContentTypes: [.json], allowsMultipleSelection: true,
                      onCompletion: importFiles)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: exportName) { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
    }

    private func presetRow(_ entry: SavedPreset) -> some View {
        HStack(spacing: 10) {
            Button {
                perform {
                    let settings = try MobileEQSettings(preset: entry.file)
                    session.auditionReference(false)
                    session.editingChanged(true)
                    session.updateEQ {
                        $0.bands = settings.bands
                        $0.preamp = settings.preamp
                    }
                    session.selectBand(settings.bands.firstIndex(where: \.enabled) ?? 0)
                    session.editingChanged(false)
                    dismiss()
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.file.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text("\(entry.file.bands.filter(\.enabled).count) active · \(entry.file.preampDb.formatted(.number.precision(.fractionLength(1)))) dB preamp")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("savedPreset")
            Menu {
                Button("Rename") { promptForName(entry) }
                Button("Replace with Current EQ") { confirmation = .replace(entry) }
                Button("Export Preset") { export(entry.file, name: entry.file.name + ".sonanceeq") }
                Button("Delete Preset", role: .destructive) { confirmation = .delete(entry) }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Actions for \(entry.file.name)")
        }
    }

    private func promptForName(_ entry: SavedPreset? = nil) {
        renaming = entry?.id
        name = entry?.file.name ?? ""
        naming = true
    }

    private func saveName() {
        perform {
            if let renaming {
                try library.rename(renaming, to: name)
            } else {
                try library.save(session.snapshot.settings, name: name)
            }
        }
    }

    private func importFiles(_ selection: Result<[URL], Error>) {
        perform {
            let urls = try selection.get()
            guard !urls.isEmpty else { return }
            readingFiles = true
            Task { @MainActor in
                let batch = await Task.detached(priority: .userInitiated) { PresetImport.read(urls) }.value
                readingFiles = false
                perform {
                    let added = try library.append(batch.files)
                    let kept = batch.files.count - added
                    var report = ["Saved \(added) \(added == 1 ? "preset" : "presets")."]
                    if kept > 0 { report.append("\(kept) already in the library.") }
                    report.append(contentsOf: batch.problems)
                    message = report.joined(separator: "\n")
                }
            }
        }
    }

    private func export<T: Encodable>(_ value: T, name: String) {
        perform {
            document = PresetDocument(data: try PresetLibrary.encoder().encode(value))
            exportName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            exporting = true
        }
    }

    private func perform(_ action: () throws -> Void) {
        message = nil
        do { try action() } catch { message = error.localizedDescription }
    }
}

private enum PresetChange {
    case replace(SavedPreset), delete(SavedPreset)

    var preset: SavedPreset {
        switch self {
        case .replace(let entry), .delete(let entry): return entry
        }
    }
}

private struct PresetDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw PresetError.invalidFile }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
