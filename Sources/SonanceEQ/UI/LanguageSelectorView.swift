import SwiftUI

/// Language selector UI component showing supported languages with current selection.
struct LanguageSelectorView: View {
    @Bindable var localization: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("about.language", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                ForEach(localization.supportedLanguages, id: \.self) { languageCode in
                    Button {
                        localization.selectedLanguageCode = languageCode
                    } label: {
                        HStack {
                            Text(localization.displayName(for: languageCode))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if localization.selectedLanguageCode == languageCode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        localization.selectedLanguageCode == languageCode ?
                        Color.accentColor.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        localization.displayName(for: languageCode) +
                        (localization.selectedLanguageCode == languageCode ? ", selected" : "")
                    )
                    .accessibilityAddTraits(
                        localization.selectedLanguageCode == languageCode ? .isSelected : []
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    LanguageSelectorView(localization: LocalizationManager())
        .padding()
}
