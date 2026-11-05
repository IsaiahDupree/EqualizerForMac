import Foundation
import Combine

public enum AnalyticsSharing {
    public static let preferenceKey = "sonance.analytics.sharing.v1"
    public static let didChange = Notification.Name("sonance.analytics.sharing.didChange")
    public static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
    public static var isEnabled: Bool { !isTestHost && UserDefaults.standard.bool(forKey: preferenceKey) }
}

public struct AnalyticsConfiguration: Sendable {
    public static let intake = URL(string: "https://ivhfuhxorppptyuofbgq.supabase.co/rest/v1/app_product_events")!
    public let endpoint: URL
    public let publishableKey: String
    public let appVersion: String
    public let buildNumber: String
    public let environment: String
    public let platform: String
    public var isConfigured: Bool {
        let destination = endpoint == Self.intake || (environment == "test" && endpoint.scheme == "http"
            && ["127.0.0.1", "::1"].contains(endpoint.host ?? ""))
        return destination && publishableKey.hasPrefix("sb_publishable_")
            && (32...512).contains(publishableKey.utf8.count)
            && ["production", "development", "test"].contains(environment)
            && ["macos", "ios"].contains(platform)
            && !appVersion.isEmpty && appVersion.utf8.count <= 40
            && !buildNumber.isEmpty && buildNumber.utf8.count <= 40
    }
    public static func bundled(_ bundle: Bundle = .main) -> Self {
        func setting(_ name: String, _ env: String) -> String {
            let value = ProcessInfo.processInfo.environment[env]
                ?? bundle.object(forInfoDictionaryKey: name) as? String ?? ""
            return value.contains("$(") ? "" : value
        }
#if DEBUG
        let environment = "development"
#else
        let environment = "production"
#endif
#if os(iOS)
        let platform = "ios"
#else
        let platform = "macos"
#endif
        return Self(endpoint: Self.intake,
                    publishableKey: setting("SonanceAnalyticsPublishableKey", "SONANCE_ANALYTICS_PUBLISHABLE_KEY"),
                    appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                    environment: environment, platform: platform)
    }
}

struct ProductEvent: Codable, Equatable {
    let eventID: UUID
    let eventName: String
    let occurredAt: Date
    let appID: String
    let platform: String
    let appVersion: String
    let buildNumber: String
    let sessionID: UUID
    let anonymousID: UUID
    let properties: [String: String]
    let schemaVersion: Int
    let environment: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id", eventName = "event_name", occurredAt = "occurred_at", appID = "app_id"
        case platform, appVersion = "app_version", buildNumber = "build_number", sessionID = "session_id"
        case anonymousID = "anonymous_id", properties, schemaVersion = "schema_version", environment, source
    }
    func isValid(for app: SonanceApp, configuration: AnalyticsConfiguration) -> Bool {
        guard appID == app.rawValue, environment == configuration.environment,
              platform == configuration.platform, schemaVersion == 2, source == "client",
              let feature = properties["feature_id"].flatMap(SonanceFeature.init(rawValue:)),
              app.features.contains(feature) else { return false }
        switch eventName {
        case "product_feature_used":
            guard Set(properties.keys) == Set(["feature_id", "outcome", "reason_code", "collection_basis"]),
                  properties["collection_basis"] == "explicit_opt_in",
                  let outcome = properties["outcome"].flatMap(FeatureOutcome.init(rawValue:)),
                  let reason = properties["reason_code"].flatMap(FeatureReason.init(rawValue:)) else { return false }
            return reason.supports(outcome)
        case "product_feedback_submitted":
            return Set(properties.keys) == Set(["feature_id", "feedback_reason", "collection_basis"])
                && properties["collection_basis"] == "explicit_feedback"
                && properties["feedback_reason"].flatMap(FeatureFeedback.init(rawValue:)) != nil
        default: return false
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Content-free product observations. No background collector, user identification,
/// advertising, cross-app ID, session replay, or free-text properties.
@MainActor
public final class ProductAnalytics: ObservableObject {
    private static var instances: [SonanceApp: ProductAnalytics] = [:]
    public static func shared(for app: SonanceApp) -> ProductAnalytics {
        if let client = instances[app] { return client }
        let client = ProductAnalytics(app: app, configuration: .bundled())
        instances[app] = client
        return client
    }
    public let app: SonanceApp
    public let configuration: AnalyticsConfiguration
    @Published public private(set) var sharingEnabled: Bool
    @Published public private(set) var deliveryStatus = ""
    @Published public private(set) var pendingCount = 0
    public var isAvailable: Bool { configuration.isConfigured && !disabledInTests }

    private let defaults: UserDefaults
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let outboxKey: String
    private let disabledInTests: Bool
    private let sessionID = UUID()
    private var pending: [ProductEvent] = []
    private var drainTask: Task<Void, Never>?
    private var generation = 0
    private var launchRecorded = false
    private static let identityKey = "analytics.anonymousID.v2"
    private static let capacity = 200

    init(app: SonanceApp, configuration: AnalyticsConfiguration, defaults: UserDefaults = .standard) {
        self.app = app
        self.configuration = configuration
        self.defaults = defaults
        self.outboxKey = "sonance.analytics.outbox.v1.\(app.rawValue)"
        self.disabledInTests = AnalyticsSharing.isTestHost && configuration.environment != "test"
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        self.encoder = encoder; self.decoder = decoder
        let network = URLSessionConfiguration.ephemeral
        network.timeoutIntervalForRequest = 5
        network.timeoutIntervalForResource = 10
        network.httpCookieStorage = nil; network.urlCache = nil
        network.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: network, delegate: NoRedirects(), delegateQueue: nil)
        self.sharingEnabled = defaults.bool(forKey: AnalyticsSharing.preferenceKey)
        if !disabledInTests, let data = defaults.data(forKey: outboxKey),
           let rows = try? decoder.decode([ProductEvent].self, from: data) {
            // Explicit feedback is retried even when ongoing usage sharing is off.
            pending = Array(rows.filter {
                $0.isValid(for: app, configuration: configuration)
                    && (sharingEnabled || $0.eventName == "product_feedback_submitted")
            }.suffix(Self.capacity))
        }
        pendingCount = pending.count
        if !disabledInTests { persist() }
    }

    public func setSharingEnabled(_ enabled: Bool) {
        guard !disabledInTests else { return }
        sharingEnabled = enabled
        defaults.set(enabled, forKey: AnalyticsSharing.preferenceKey)
        if !enabled {
            generation += 1
            drainTask?.cancel(); drainTask = nil
            pending.removeAll()
            defaults.removeObject(forKey: Self.identityKey)
            // Stop pending observations from the older first-party collector too.
            defaults.removeObject(forKey: "analytics.outbox.v2")
            persist()
            deliveryStatus = "Sharing is off. Unsent observations were removed."
        } else {
            deliveryStatus = isAvailable ? "Sharing is on." : "Delivery is unavailable in this build."
            didOpen()
        }
        NotificationCenter.default.post(name: AnalyticsSharing.didChange, object: nil)
    }

    public func didOpen() {
        retry()
        guard !launchRecorded, sharingEnabled, isAvailable else { return }
        launchRecorded = true
        // These apps already have a verified lifecycle collector. Keep one launch signal.
        guard ![SonanceApp.mixer, .recorder, .voice, .diagram].contains(app) else { return }
        capture(.appOpen)
    }

    public func capture(_ feature: SonanceFeature, outcome: FeatureOutcome = .succeeded,
                        reason: FeatureReason = .none) {
        guard sharingEnabled, isAvailable, app.features.contains(feature), reason.supports(outcome) else { return }
        enqueue(name: "product_feature_used", feature: feature, properties: [
            "outcome": outcome.rawValue, "reason_code": reason.rawValue, "collection_basis": "explicit_opt_in"
        ], anonymousID: installationID())
    }

    /// Pressing Submit grants consent for this one fixed-choice feedback item.
    /// With ongoing sharing off, use a fresh ID, never a persistent installation ID.
    @discardableResult public func submitFeedback(feature: SonanceFeature, reason: FeatureFeedback) -> Bool {
        guard isAvailable, app.features.contains(feature) else {
            deliveryStatus = "Feedback delivery is unavailable in this build."
            return false
        }
        return enqueue(name: "product_feedback_submitted", feature: feature, properties: [
            "feedback_reason": reason.rawValue, "collection_basis": "explicit_feedback"
        ], anonymousID: sharingEnabled ? installationID() : UUID())
    }

    private func installationID() -> UUID {
        if let raw = defaults.string(forKey: Self.identityKey), let id = UUID(uuidString: raw) { return id }
        let id = UUID(); defaults.set(id.uuidString.lowercased(), forKey: Self.identityKey); return id
    }

    @discardableResult private func enqueue(name: String, feature: SonanceFeature, properties: [String: String], anonymousID: UUID) -> Bool {
        var fields = properties; fields["feature_id"] = feature.rawValue
        let event = ProductEvent(eventID: UUID(), eventName: name, occurredAt: Date(), appID: app.rawValue,
                                 platform: configuration.platform, appVersion: configuration.appVersion,
                                 buildNumber: configuration.buildNumber, sessionID: sessionID,
                                 anonymousID: anonymousID, properties: fields, schemaVersion: 2,
                                 environment: configuration.environment, source: "client")
        guard event.isValid(for: app, configuration: configuration) else { return false }
        guard pending.count < Self.capacity else {
            deliveryStatus = "The sending queue is full. Retry before submitting again."
            return false
        }
        pending.append(event); persist()
        deliveryStatus = "Queued for sending."
        retry()
        return true
    }

    public func retry() {
        guard isAvailable, drainTask == nil, !pending.isEmpty else { return }
        let currentGeneration = generation
        drainTask = Task { [weak self] in await self?.drain(generation: currentGeneration) }
    }

    private func drain(generation startedGeneration: Int) async {
        defer { if generation == startedGeneration { drainTask = nil } }
        // A bounded batch prevents sustained background work when an old queue exists.
        for _ in 0..<20 {
            guard !Task.isCancelled, generation == startedGeneration, let row = pending.first else { return }
            guard row.eventName == "product_feedback_submitted" || sharingEnabled else { return }
            do {
                var request = URLRequest(url: configuration.endpoint)
                request.httpMethod = "POST"; request.timeoutInterval = 5
                request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
                request.httpBody = try encoder.encode(row)
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled, generation == startedGeneration else { return }
                guard let http = response as? HTTPURLResponse, data.count <= 65_536 else {
                    deliveryStatus = "Sending paused. Retry later."; return
                }
                let errorCode = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? String
                let duplicate = http.statusCode == 409 && errorCode == "23505"
                guard (200..<300).contains(http.statusCode) || duplicate else {
                    deliveryStatus = "Not sent (HTTP \(http.statusCode)). Retry later."; return
                }
                pending.removeAll { $0.eventID == row.eventID }; persist()
                deliveryStatus = pending.isEmpty ? "Sent. Thank you for helping improve \(app.title)." : "Sending…"
            } catch {
                guard generation == startedGeneration, !Task.isCancelled else { return }
                deliveryStatus = "Not sent. It will retry when you reopen the app or choose Retry."
                return
            }
        }
        if !pending.isEmpty { deliveryStatus = "Some items are queued. Choose Retry to continue." }
    }

    private func persist() {
        pendingCount = pending.count
        if pending.isEmpty { defaults.removeObject(forKey: outboxKey) }
        else if let data = try? encoder.encode(pending) { defaults.set(data, forKey: outboxKey) }
    }
}
