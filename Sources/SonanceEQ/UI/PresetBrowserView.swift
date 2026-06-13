import SwiftUI

/// Searchable browser over the bundled AutoEq library (8,850 headphone corrections).
/// Selecting a headphone loads its parametric bands + safety preamp into the live EQ.
struct PresetBrowserView: View {
    @Bindable var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var category: String?
    @State private var results: [AutoEqPreset] = []

    private let store = PresetStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if app.license.canUse(.autoEqLibrary) {
                searchBar
                categoryChips
                Divider()
                resultsList
            } else {
                proLock
            }
        }
        .frame(width: 460, height: 540)
        .onAppear(perform: refresh)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Headphone Presets").font(.headline)
                Text("\(store.totalCount) corrections · AutoEq")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: Search + filters

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search e.g. HD 600, AirPods, Moondrop…", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12).padding(.top, 8)
        .onChange(of: searchText) { _, _ in refresh() }
    }

    private var categoryChips: some View {
        HStack(spacing: 6) {
            chip("All", value: nil)
            ForEach(store.categories(), id: \.self) { chip($0.capitalized, value: $0) }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func chip(_ label: String, value: String?) -> some View {
        let selected = category == value
        return Button(label) { category = value; refresh() }
            .buttonStyle(.plain)
            .font(.caption.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(selected ? Color.accentColor.opacity(0.25) : Color.clear,
                        in: Capsule())
            .overlay(Capsule().stroke(.quaternary, lineWidth: selected ? 0 : 1))
    }

    // MARK: Results

    private var resultsList: some View {
        Group {
            if results.isEmpty {
                ContentUnavailableView("No matches", systemImage: "headphones",
                                       description: Text("Try a different model name."))
            } else {
                List(results) { preset in
                    Button { apply(preset) } label: { row(preset) }
                        .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    private func row(_ preset: AutoEqPreset) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.model).font(.callout)
                Text(preset.source).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(preset.category)
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary.opacity(0.5), in: Capsule())
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    // MARK: Pro lock

    private var proLock: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
            Text("The headphone library is a Pro feature.").font(.callout)
            Button("Unlock Pro") { Task { await app.license.purchasePro() } }
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func refresh() {
        results = store.search(searchText, category: category)
    }

    private func apply(_ preset: AutoEqPreset) {
        app.applyAutoEq(preset)
        dismiss()
    }
}
