import SwiftUI

/// Shared rendering for a failure surfaced via `AppState.errorMessage`. Used inside every
/// window/sheet that can trigger one of those failures — `ContentView`, `MixerView`, `RecorderView` —
/// so an error raised by an action taken *inside* a modal sheet (denied permission, a mixer/recorder
/// tap failure, a file-write error) is visible right there, instead of only in the main window, which
/// the sheet dims/covers while it's open.
struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
