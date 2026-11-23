import AppIntents
import Foundation

struct EnableSonanceBypassIntent: AppIntent {
    static var title: LocalizedStringResource = "Enable EQ Bypass"
    static var description = IntentDescription("Turn off EQ processing for audio played in Sonance EQ.")

    static var openAppWhenRun: Bool { true }

    #if compiler(>=6.4)
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        EqualizerSession.shared.setEQBypass(true)
        return .result(dialog: "EQ bypass is on in Sonance EQ.")
    }
}

struct DisableSonanceBypassIntent: AppIntent {
    static var title: LocalizedStringResource = "Disable EQ Bypass"
    static var description = IntentDescription("Apply the current EQ settings to audio played in Sonance EQ.")

    static var openAppWhenRun: Bool { true }

    #if compiler(>=6.4)
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        EqualizerSession.shared.setEQBypass(false)
        return .result(dialog: "EQ bypass is off in Sonance EQ.")
    }
}

struct SonanceAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EnableSonanceBypassIntent(),
            phrases: [
                "Enable EQ bypass in \(.applicationName)",
                "Turn off the EQ in \(.applicationName)"
            ],
            shortTitle: "Enable EQ Bypass",
            systemImageName: "waveform.slash"
        )
        AppShortcut(
            intent: DisableSonanceBypassIntent(),
            phrases: [
                "Disable EQ bypass in \(.applicationName)",
                "Turn on the EQ in \(.applicationName)"
            ],
            shortTitle: "Disable EQ Bypass",
            systemImageName: "waveform"
        )
    }
}
