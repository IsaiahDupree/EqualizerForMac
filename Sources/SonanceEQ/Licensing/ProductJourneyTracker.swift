import Foundation
import Observation

/// Consented native observations. A proposed campaign URL is never a verified
/// acquisition, and successful HTTP delivery is never a purchase/profit claim.
@MainActor @Observable
final class ProductJourneyTracker {
    struct Configuration: Equatable {
        let projectToken: String
        let endpoint: URL

        init?(projectToken: String, origin: String) {
            guard projectToken.hasPrefix("phc_"), projectToken.count <= 256,
                  let url = URL(string: origin), url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil, url.port == nil,
                  url.path == "" || url.path == "/",
                  url.scheme == "https",
                  ["us.i.posthog.com", "eu.i.posthog.com"].contains(url.host) else { return nil }
            self.projectToken = projectToken
            endpoint = url.appendingPathComponent("batch/")
        }

        static var bundled: Configuration? {
            Configuration(projectToken: Bundle.main.object(forInfoDictionaryKey: "PostHogProjectToken") as? String ?? "",
                          origin: Bundle.main.object(forInfoDictionaryKey: "PostHogIngestOrigin") as? String ?? "")
        }
    }

    struct Handoff: Codable, Equatable {
        let clickID: String
        let campaignID: String

        init?(url: URL) {
            guard url.absoluteString.utf8.count <= 1024,
                  let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  parts.scheme == "sonanceeq", parts.host == "campaign",
                  parts.path.isEmpty, parts.user == nil, parts.password == nil,
                  parts.port == nil, parts.fragment == nil,
                  let items = parts.queryItems, items.count == 3 else { return nil }
            var fields: [String: String] = [:]
            for item in items {
                guard fields[item.name] == nil, let value = item.value,
                      !value.isEmpty, value.utf8.count <= 128,
                      value.range(of: "^[a-zA-Z0-9_.:-]+$", options: .regularExpression) != nil else { return nil }
                fields[item.name] = value
            }
            guard fields["cie_product_id"] == "sonance-eq",
                  let click = fields["cie_click_id"], let campaign = fields["cie_campaign_id"] else { return nil }
            clickID = click; campaignID = campaign
        }
    }

    struct Event: Codable, Equatable {
        let id: UUID
        let subject: UUID
        let occurredAt: Date
        let kind: String
        let handoff: Handoff?
        let transaction: StorePurchaseEvidence?

        var wire: [String: Any] {
            var properties: [String: Any] = [
                "app_id": "sonance-eq", "product_id": "sonance-eq",
                "consent_basis": "explicit_opt_in", "$process_person_profile": false,
                "$geoip_disable": true,
                "native_evidence_contract": "sonance_native_journey_v1",
                "audibility_verified": false, "revenue_verified": false,
            ]
            #if DEBUG
            properties["is_test"] = true
            #else
            properties["is_test"] = false
            #endif
            if kind == "onboarding_step" { properties["step"] = "valid_audio_route_callbacks" }
            if let handoff {
                // Keep proposed URL identities out of the canonical cie_* namespace.
                // Only an authenticated owner binding can establish attribution.
                properties["proposed_click_id"] = handoff.clickID
                properties["proposed_campaign_id"] = handoff.campaignID
                properties["handoff_status"] = "requires_owner_receipt_binding"
            }
            if let transaction {
                properties["store_transaction_key"] = transaction.transactionKey
                properties["store_product_id"] = transaction.productID
                properties["store_environment"] = transaction.environment
                properties["store_verification"] = "local_storekit_verified_history"
                #if !DEBUG
                properties["is_test"] = transaction.environment != "production"
                #endif
            }
            return ["uuid": id.uuidString.lowercased(), "distinct_id": subject.uuidString.lowercased(),
                    "event": kind, "timestamp": ISO8601DateFormatter().string(from: occurredAt),
                    "properties": properties]
        }
    }

    private struct State: Codable {
        var consentedAt: Date
        var subject = UUID()
        var queue: [Event] = []
        var recordedTransactions: Set<String> = []
        var observedRoute = false
        var handoff: Handoff?
        var discardedEvents = 0
    }
    enum Delivery: String { case disabled, configurationRequired, idle, pending, accepted, failed }
    private static let key = "sonance.nativeJourney.v1"
    private let defaults: UserDefaults
    private let configuration: Configuration?
    private var state: State?
    private var revision = 0
    private var sending = false
    private var session: URLSession?
    private(set) var delivery: Delivery = .disabled
    var optedIn: Bool { state != nil }
    var configured: Bool { configuration != nil }
    var pendingCount: Int { state?.queue.count ?? 0 }
    var discardedCount: Int { state?.discardedEvents ?? 0 }

    init(defaults: UserDefaults = .standard, configuration: Configuration? = .bundled) {
        self.defaults = defaults; self.configuration = configuration
        state = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(State.self, from: $0) }
        if state != nil { delivery = configuration == nil ? .configurationRequired : .idle }
    }

    func setConsent(_ enabled: Bool) {
        guard enabled != optedIn else { return }
        revision += 1
        session?.invalidateAndCancel(); session = nil
        if enabled { state = State(consentedAt: Date()); persist(); delivery = configured ? .idle : .configurationRequired }
        else { state = nil; defaults.removeObject(forKey: Self.key); delivery = .disabled }
    }

    func observeSession() { append(kind: "return_session") }

    func observeAudioFlow(_ flowing: Bool) {
        guard flowing, state != nil, state?.observedRoute == false else { return }
        state?.observedRoute = true
        append(kind: "onboarding_step")
    }

    @discardableResult func receive(_ url: URL) -> Bool {
        guard state != nil, let proposal = Handoff(url: url) else { return false }
        guard state?.handoff != proposal else { return true }
        state?.handoff = proposal
        append(kind: "native_campaign_handoff")
        return true
    }

    /// Called only by the existing actual StoreKit reader. Entitlement callbacks,
    /// historical restores, partial reads and family sharing do not create purchases.
    func observe(_ snapshot: StorePurchaseSnapshot) {
        guard let consent = state?.consentedAt, snapshot.state == .complete else { return }
        let revoked = Set(snapshot.transactions.filter { $0.revokedAt != nil }.map(\.transactionKey))
        state?.queue.removeAll { event in event.transaction.map { revoked.contains($0.transactionKey) } ?? false }
        for purchase in snapshot.transactions where purchase.productID == LicenseConfig.proProductID
            && purchase.ownership == "purchased" && purchase.revokedAt == nil
            && purchase.originalPurchasedAt >= consent && purchase.purchasedAt >= consent
            && purchase.purchasedAt <= snapshot.observedAt
            && ["production", "sandbox", "xcode"].contains(purchase.environment) {
            guard state?.recordedTransactions.contains(purchase.transactionKey) == false else { continue }
            state?.recordedTransactions.insert(purchase.transactionKey)
            append(kind: "purchase", occurredAt: purchase.purchasedAt, transaction: purchase)
        }
        persist()
    }

    private func append(kind: String, occurredAt: Date = Date(), transaction: StorePurchaseEvidence? = nil) {
        guard let current = state else { return }
        state?.queue.append(Event(id: UUID(), subject: current.subject, occurredAt: occurredAt,
                                  kind: kind, handoff: current.handoff, transaction: transaction))
        if let count = state?.queue.count, count > 100 {
            state?.queue.removeFirst(count - 100); state?.discardedEvents += count - 100
        }
        persist(); delivery = configured ? .pending : .configurationRequired
    }

    private func persist() {
        if let state, let bytes = try? JSONEncoder().encode(state) { defaults.set(bytes, forKey: Self.key) }
    }

    /// One bounded delivery attempt. Stable UUIDs survive retries, redirects are
    /// refused, and consent revocation cancels this instance's actual URLSession.
    func flush() async {
        guard state != nil else { delivery = .disabled; return }
        guard let configuration else { delivery = .configurationRequired; return }
        await send(to: configuration.endpoint, token: configuration.projectToken)
    }

    private func send(to endpoint: URL, token: String) async {
        guard !sending, let events = state?.queue, !events.isEmpty else { return }
        let expectedRevision = revision
        guard let body = try? JSONSerialization.data(withJSONObject: ["api_key": token, "batch": events.map(\.wire)]),
              body.count <= 256 * 1024 else { delivery = .failed; return }
        sending = true
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 5; settings.timeoutIntervalForResource = 5
        settings.httpShouldSetCookies = false; settings.httpCookieStorage = nil
        settings.urlCache = nil
        let transport = URLSession(configuration: settings, delegate: RefuseJourneyRedirects(), delegateQueue: nil)
        session = transport
        defer { transport.invalidateAndCancel(); if revision == expectedRevision { session = nil }; sending = false }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (bytes, response) = try await transport.bytes(for: request)
            guard revision == expectedRevision, state != nil else { return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  response.expectedContentLength <= 64 * 1024 else { delivery = .failed; return }
            var received = 0
            for try await _ in bytes {
                received += 1
                guard received <= 64 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
            }
            guard revision == expectedRevision, state != nil else { return }
            let sent = Set(events.map(\.id))
            state?.queue.removeAll { sent.contains($0.id) }
            persist(); delivery = pendingCount == 0 ? .accepted : .pending
        } catch { if revision == expectedRevision, state != nil { delivery = .failed } }
    }

    #if DEBUG
    /// Actual loopback HTTP integration, never a substituted provider or public capture.
    func deliverToLocalAcceptanceServer(_ endpoint: URL, token: String) async {
        guard endpoint.scheme == "http", endpoint.host == "127.0.0.1",
              endpoint.user == nil, endpoint.password == nil, state != nil else { return }
        await send(to: endpoint, token: token)
    }
    #endif
}

private final class RefuseJourneyRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
