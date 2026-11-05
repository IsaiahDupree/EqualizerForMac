import XCTest
@testable import SonanceAnalytics

@MainActor
final class ProductAnalyticsTests: XCTestCase {
    private var process: Process!
    private var folder: URL!
    private var endpoint: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "SonanceAnalyticsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let portFile = folder.appendingPathComponent("port")
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/intake.py")
        process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, portFile.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        for _ in 0..<100 {
            if let text = try? String(contentsOf: portFile), let port = Int(text) {
                endpoint = URL(string: "http://127.0.0.1:\(port)/events")!; return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(domain: "SonanceAnalyticsTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Required loopback intake failed to start"])
    }

    override func tearDown() async throws {
        process?.terminate(); process?.waitUntilExit()
        if let suite { defaults?.removePersistentDomain(forName: suite) }
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    private func client(path: String = "/events", app: SonanceApp = .eq) -> ProductAnalytics {
        let config = AnalyticsConfiguration(endpoint: endpoint.deletingLastPathComponent().appendingPathComponent(String(path.dropFirst())),
            publishableKey: "sb_publishable_integration_test_loopback_only", appVersion: "1.2.3", buildNumber: "4",
            environment: "test", platform: "macos")
        return ProductAnalytics(app: app, configuration: config, defaults: defaults)
    }
    private func rows() async throws -> [[String: Any]] {
        let (data, _) = try await URLSession.shared.data(from: endpoint)
        return (try JSONSerialization.jsonObject(with: data) as! [String: Any])["events"] as! [[String: Any]]
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for real HTTP delivery")
    }

    func testDisabledByDefaultDoesNotCreateIdentityOrSend() async throws {
        let analytics = client()
        analytics.didOpen(); analytics.capture(.equalizer)
        XCTAssertFalse(analytics.sharingEnabled)
        XCTAssertNil(defaults.string(forKey: "analytics.anonymousID.v2"))
        XCTAssertEqual(analytics.pendingCount, 0)
        let delivered = try await rows(); XCTAssertTrue(delivered.isEmpty)
    }

    func testOptInDeliversActualFeatureAndVersionEnvelope() async throws {
        let analytics = client()
        analytics.setSharingEnabled(true)
        analytics.capture(.headphonePresets)
        try await waitFor { analytics.pendingCount == 0 }
        let delivered = try await rows()
        XCTAssertEqual(delivered.count, 2)
        XCTAssertEqual(delivered.last?["app_id"] as? String, "sonance_eq")
        XCTAssertEqual(delivered.last?["environment"] as? String, "test")
        XCTAssertEqual(delivered.last?["schema_version"] as? Int, 2)
        XCTAssertEqual(delivered.last?["app_version"] as? String, "1.2.3")
        XCTAssertEqual((delivered.last?["properties"] as? [String: String])?["feature_id"], "headphone_presets")
        XCTAssertEqual(Set(delivered.compactMap { $0["anonymous_id"] as? String }).count, 1)
        XCTAssertNil(delivered.last?["user_id"])
    }

    func testFeedbackWithoutUsageConsentIsUnlinkedAndExplicit() async throws {
        let analytics = client()
        XCTAssertTrue(analytics.submitFeedback(feature: .equalizer, reason: .missingOption))
        try await waitFor { analytics.pendingCount == 0 }
        XCTAssertTrue(analytics.submitFeedback(feature: .headphonePresets, reason: .worksWell))
        try await waitFor { analytics.pendingCount == 0 }
        let delivered = try await rows()
        XCTAssertEqual(delivered.count, 2)
        XCTAssertNotEqual(delivered[0]["anonymous_id"] as? String, delivered[1]["anonymous_id"] as? String)
        XCTAssertEqual((delivered[0]["properties"] as? [String: String])?["collection_basis"], "explicit_feedback")
        XCTAssertFalse(analytics.sharingEnabled)
        XCTAssertNil(defaults.string(forKey: "analytics.anonymousID.v2"))
    }

    func testRejectsOtherAppFeatureAndInvalidOutcomeBeforeNetwork() async throws {
        let analytics = client(app: .preflight)
        analytics.setSharingEnabled(true)
        try await waitFor { analytics.pendingCount == 0 }
        analytics.capture(.transcription)
        analytics.capture(.analysis, outcome: .failed)
        XCTAssertFalse(analytics.submitFeedback(feature: .diagramExport, reason: .worksWell))
        let delivered = try await rows(); XCTAssertEqual(delivered.count, 1)
    }

    func testTemporaryFailureKeepsExactIDAndRetries() async throws {
        let analytics = client(path: "/fail-once")
        XCTAssertTrue(analytics.submitFeedback(feature: .equalizer, reason: .permissionProblem))
        try await waitFor { analytics.deliveryStatus.contains("503") }
        let key = "sonance.analytics.outbox.v1.sonance_eq"
        let stored = try JSONDecoder.iso8601.decode([ProductEvent].self, from: XCTUnwrap(defaults.data(forKey: key)))
        XCTAssertEqual(stored.count, 1)
        analytics.retry()
        try await waitFor { analytics.pendingCount == 0 }
        let delivered = try await rows()
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual((delivered[0]["event_id"] as? String)?.lowercased(), stored[0].eventID.uuidString.lowercased())
    }

    func testDuplicateResponseAcknowledgesOnlyDeliveredRow() async throws {
        let analytics = client(path: "/already-delivered")
        analytics.submitFeedback(feature: .equalizer, reason: .savesTime)
        analytics.submitFeedback(feature: .headphonePresets, reason: .betterSound)
        try await waitFor { analytics.pendingCount == 0 }
        let delivered = try await rows(); XCTAssertEqual(delivered.count, 2)
    }

    func testRedirectIsNotFollowedAndQueueIsRetained() async throws {
        let analytics = client(path: "/redirect")
        analytics.submitFeedback(feature: .equalizer, reason: .unexpectedResult)
        try await waitFor { analytics.deliveryStatus.contains("307") }
        XCTAssertEqual(analytics.pendingCount, 1)
        let delivered = try await rows(); XCTAssertTrue(delivered.isEmpty)
        analytics.setSharingEnabled(false)
    }

    func testRevocationCancelsDrainAndPurgesPersistentIdentifiersAndBothOutboxes() async throws {
        let analytics = client(path: "/slow")
        analytics.setSharingEnabled(true)
        analytics.capture(.equalizer)
        defaults.set(Data([1]), forKey: "analytics.outbox.v2")
        try await Task.sleep(nanoseconds: 100_000_000)
        analytics.setSharingEnabled(false)
        XCTAssertEqual(analytics.pendingCount, 0)
        XCTAssertNil(defaults.data(forKey: "sonance.analytics.outbox.v1.sonance_eq"))
        XCTAssertNil(defaults.data(forKey: "analytics.outbox.v2"))
        XCTAssertNil(defaults.string(forKey: "analytics.anonymousID.v2"))
        try await Task.sleep(nanoseconds: 1_100_000_000)
        let delivered = try await rows()
        XCTAssertLessThanOrEqual(delivered.count, 1) // A request already received cannot be recalled.
        XCTAssertTrue(analytics.deliveryStatus.contains("off"))
    }

    func testConfigurationRejectsForeignHostsAndReaderKeys() {
        let c = AnalyticsConfiguration(endpoint: URL(string: "https://example.com/events")!,
            publishableKey: "sb_publishable_integration_test_loopback_only", appVersion: "1", buildNumber: "1",
            environment: "production", platform: "macos")
        XCTAssertFalse(c.isConfigured)
        let k = AnalyticsConfiguration(endpoint: AnalyticsConfiguration.intake, publishableKey: "service_role_secret",
            appVersion: "1", buildNumber: "1", environment: "production", platform: "macos")
        XCTAssertFalse(k.isConfigured)
    }

    func testCatalogAndReasonMatrixAreStrict() {
        XCTAssertEqual(Set(SonanceApp.allCases.map(\.rawValue)).count, 8)
        for app in SonanceApp.allCases {
            XCTAssertEqual(Set(app.features).count, app.features.count)
            XCTAssertTrue(app.features.contains(.appOpen))
        }
        XCTAssertFalse(FeatureReason.permissionDenied.supports(.succeeded))
        XCTAssertTrue(FeatureReason.permissionDenied.supports(.blocked))
        XCTAssertFalse(FeatureReason.none.supports(.failed))
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}
