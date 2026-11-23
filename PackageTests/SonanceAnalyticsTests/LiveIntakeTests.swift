import XCTest
@testable import SonanceAnalytics

/// Explicitly enabled acceptance check against the real insert-only project.
/// All rows are environment=test and carry a unique build ID for owner verification.
@MainActor
final class LiveIntakeTests: XCTestCase {
    func testEveryAppDeliversUsageAndFeedbackToRealIntake() async throws {
        guard let key = ProcessInfo.processInfo.environment["SONANCE_ANALYTICS_LIVE_KEY"],
              let run = ProcessInfo.processInfo.environment["SONANCE_ANALYTICS_LIVE_RUN"] else {
            throw XCTSkip("Set the documented live-acceptance environment to exercise Supabase")
        }
        for app in SonanceApp.allCases {
            let suite = "SonanceAnalyticsLive.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let config = AnalyticsConfiguration(endpoint: AnalyticsConfiguration.intake,
                publishableKey: key, appVersion: "analytics-acceptance", buildNumber: run,
                environment: "test", platform: app == .align ? "ios" : "macos")
            let collector = ProductAnalytics(app: app, configuration: config, defaults: defaults)
            XCTAssertTrue(collector.isAvailable)
            collector.setSharingEnabled(true)
            let feature = try XCTUnwrap(app.features.first { $0 != .appOpen })
            collector.capture(feature)
            XCTAssertTrue(collector.submitFeedback(feature: feature, reason: .worksWell))
            for _ in 0..<100 {
                if collector.pendingCount == 0 || collector.deliveryStatus.contains("Not sent") { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(collector.pendingCount, 0, "\(app.rawValue): \(collector.deliveryStatus)")
            XCTAssertTrue(collector.deliveryStatus.hasPrefix("Sent"), "\(app.rawValue): \(collector.deliveryStatus)")
            collector.setSharingEnabled(false)
        }
    }
}
