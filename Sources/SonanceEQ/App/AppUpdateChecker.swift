import AppKit
import Foundation
import OSLog

/// Lightweight App Store update discovery for both Mac App Store and direct builds.
///
/// The Mac App Store remains the update authority. Sonance EQ never downloads or installs an
/// executable itself: it compares the public App Store marketing version with the running version,
/// then opens the canonical App Store product page when an update is available.
@MainActor
@Observable
final class AppUpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String)
        case failed
    }

    static let appStoreID = "6782463839"
    static let productPage = URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
    private static let appStoreDeepLink = URL(
        string: "macappstore://itunes.apple.com/app/id\(appStoreID)"
    )!

    private struct LookupResponse: Decodable {
        struct Result: Decodable {
            let version: String
        }

        let results: [Result]
    }

    private let currentVersion: String
    private let log = Logger(subsystem: kSubsystem, category: "Updates")
    private var hasChecked = false

    var state: State = .idle

    init(currentVersion: String = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "0") {
        self.currentVersion = currentVersion
    }

    var availableVersion: String? {
        guard case let .updateAvailable(version) = state else { return nil }
        return version
    }

    /// Check once per launch unless the user explicitly requests another check from About.
    func check(force: Bool = false) async {
        guard state != .checking else { return }
        guard force || !hasChecked else { return }

        hasChecked = true
        state = .checking

        do {
            var components = URLComponents(string: "https://itunes.apple.com/lookup")!
            components.queryItems = [
                URLQueryItem(name: "id", value: Self.appStoreID),
                URLQueryItem(name: "entity", value: "macSoftware")
            ]
            guard let url = components.url else { throw URLError(.badURL) }

            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let release = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let latest = release.results.first?.version else {
                throw URLError(.resourceUnavailable)
            }

            state = Self.isVersion(latest, newerThan: currentVersion)
                ? .updateAvailable(version: latest)
                : .upToDate
        } catch {
            state = .failed
            log.error("App Store update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func openAppStore() {
        if !NSWorkspace.shared.open(Self.appStoreDeepLink) {
            NSWorkspace.shared.open(Self.productPage)
        }
    }

    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        candidate.compare(current, options: [.numeric, .caseInsensitive]) == .orderedDescending
    }
}
