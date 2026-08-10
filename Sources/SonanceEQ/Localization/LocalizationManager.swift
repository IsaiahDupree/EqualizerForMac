import Foundation
import SwiftUI

/// Manages app localization and selected language persistence.
@Observable
final class LocalizationManager {
    private static let userDefaultsKey = "SonanceEQ_SelectedLanguage"

    /// Current app locale based on selected language.
    var locale: Locale {
        didSet { updateLocale() }
    }

    /// Supported language codes (BCP 47).
    let supportedLanguages: [String] = ["en", "es", "fr", "pt-BR", "ja"]

    /// Human-readable names for each language.
    let languageNames: [String: String] = [
        "en": "English",
        "es": "Español",
        "fr": "Français",
        "pt-BR": "Português (Brasil)",
        "ja": "日本語",
    ]

    /// The currently selected language code (e.g., "en", "es").
    var selectedLanguageCode: String {
        didSet {
            persistSelectedLanguage()
            locale = Locale(identifier: selectedLanguageCode)
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.userDefaultsKey) ?? "en"
        selectedLanguageCode = saved
        locale = Locale(identifier: saved)
    }

    private func persistSelectedLanguage() {
        UserDefaults.standard.set(selectedLanguageCode, forKey: Self.userDefaultsKey)
    }

    private func updateLocale() {
        // Propagate the locale to the environment so SwiftUI respects it.
        // This is handled via .environment(\.locale, ...) in the app.
    }

    /// Return the display name for a language code.
    func displayName(for languageCode: String) -> String {
        languageNames[languageCode] ?? languageCode
    }
}
