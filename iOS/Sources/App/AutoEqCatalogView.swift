import SwiftUI

@MainActor
struct AutoEqCatalogView: View {
    let session: EqualizerSession
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: String?
    @State private var presets: [MobileAutoEqPreset] = []
    @State private var errorMessage: String?
    @State private var showingNotices = false

    private let catalog = AutoEqCatalog.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                categoryPicker
                if !catalog.isAvailable {
                    ContentUnavailableView(
                        "Headphone Library Unavailable",
                        systemImage: "headphones",
                        description: Text("The bundled correction catalog could not be opened.")
                    )
                } else if presets.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(presets) { preset in
                        HStack(spacing: 4) {
                            Button { select(preset) } label: { row(preset) }
                                .buttonStyle(.plain)
                            Menu {
                                Button("Load into Main EQ", systemImage: "slider.horizontal.3") {
                                    select(preset)
                                }
                                Button("Assign as Output Correction", systemImage: "headphones") {
                                    assign(preset)
                                }
                                .disabled(session.player.currentOutput == nil)
                                if let sourceURL = preset.sourceURL {
                                    Link("Published Preset", destination: sourceURL)
                                }
                                if preset.dataLicense == "CC BY-SA 4.0" {
                                    Link("CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Actions for \(preset.model)")
                            .accessibilityIdentifier("headphonePresetActions")
                        }
                    }
                    .listStyle(.plain)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
                attribution
            }
            .navigationTitle("Headphone Corrections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Headphone Corrections").font(.headline)
                        Text("\(catalog.totalCount.formatted()) offline profiles")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                session.player.refreshOutput()
                refresh()
            }
            .onChange(of: query) { _, _ in refresh() }
            .sheet(isPresented: $showingNotices) {
                NavigationStack {
                    ScrollView {
                        Text(licenseNotices)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle("Data Licenses")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingNotices = false }
                        }
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search brand or model", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("headphoneCatalogSearch")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton("All", value: nil)
                ForEach(catalog.categories(), id: \.self) { value in
                    categoryButton(value.capitalized, value: value)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
    }

    private func categoryButton(_ title: String, value: String?) -> some View {
        let selected = value == category
        return Button(title) {
            category = value
            refresh()
        }
        .font(.caption.weight(selected ? .semibold : .regular))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(selected ? EqualizerEditor.accent.opacity(0.2) : Color(uiColor: .secondarySystemGroupedBackground),
                    in: Capsule())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func row(_ preset: MobileAutoEqPreset) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.model).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(preset.source).font(.caption).foregroundStyle(.secondary)
                Text("\(preset.brand) · \(preset.category.capitalized) · \(preset.preampDb.formatted(.number.precision(.fractionLength(1)))) dB preamp")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Image(systemName: "arrow.down.to.line")
                .foregroundStyle(EqualizerEditor.accent)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Loads this correction into the main equalizer.")
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Corrections are measurement-based starting points; fit and listening conditions vary.")
            Link("AutoEq data · MIT License", destination: URL(string: "https://github.com/jaakkopasanen/AutoEq")!)
            Link("OPRA supplemental data and attribution", destination: URL(string: "https://github.com/opra-project/OPRA")!)
            Button("View bundled license notices") { showingNotices = true }
                .font(.caption2)
                .accessibilityIdentifier("headphoneDataLicenses")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 9)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func refresh() {
        presets = catalog.search(query, category: category)
    }

    private var licenseNotices: String {
        let names = [
            ("THIRD-PARTY-NOTICES", "md"),
            ("OPRA-LICENSE", "txt"),
            ("openEq-LICENSE", "txt"),
        ]
        let documents = names.compactMap { item -> String? in
            let (name, ext) = item
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return documents.isEmpty
            ? "The bundled data sources are AutoEq (MIT), OPRA (CC BY-SA 4.0), and Songbird / openEq (MIT)."
            : documents.joined(separator: "\n\n---\n\n")
    }

    private func select(_ preset: MobileAutoEqPreset) {
        errorMessage = nil
        do {
            try session.applyHeadphoneCorrection(preset)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func assign(_ preset: MobileAutoEqPreset) {
        errorMessage = nil
        guard let output = session.player.currentOutput else {
            errorMessage = "Connect one audio output before assigning its correction."
            return
        }
        do {
            let correction = try OutputCorrection(preset: preset)
            guard session.setCorrection(correction, for: output) else {
                errorMessage = "The audio output changed. Refresh the current route and try again."
                return
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
