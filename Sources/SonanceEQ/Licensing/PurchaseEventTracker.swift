import Foundation
import OSLog

/// A single point in the purchase / paywall conversion funnel worth recording.
///
/// The funnel is: `paywallShown` → `purchaseStarted` → (`purchaseCompleted` |
/// `purchaseCancelled` | `purchaseFailed`). Restores have their own short funnel:
/// `restoreStarted` → (`restoreCompleted` | `restoreNoEntitlement` | `restoreFailed`).
public enum PurchaseEvent: String, Codable, CaseIterable, Sendable {
    case paywallShown
    case purchaseStarted
    case purchaseCompleted
    case purchaseCancelled
    case purchaseFailed
    case restoreStarted
    case restoreCompleted        // restore found an active entitlement
    case restoreNoEntitlement    // restore succeeded, but there was nothing to restore
    case restoreFailed

    // Apple / RevenueCat-originated lifecycle (pushed via `Purchases.customerInfoStream`, so they
    // capture changes that happen *outside* an app-initiated buy: renewals, refunds, Ask-to-Buy
    // approvals, purchases made on another device, and RevenueCat dashboard grants).
    case configured              // the live RevenueCat SDK finished configuring at launch
    case customerInfoUpdated     // RevenueCat pushed a fresh CustomerInfo
    case entitlementGranted      // Pro flipped inactive → active (unlock from any source)
    case entitlementRevoked      // Pro flipped active → inactive (refund / expiry / revoke)

    /// Terminal outcomes of a purchase attempt (everything after `purchaseStarted`).
    public static let purchaseOutcomes: [PurchaseEvent] = [.purchaseCompleted, .purchaseCancelled, .purchaseFailed]
    /// Terminal outcomes of a restore attempt.
    public static let restoreOutcomes: [PurchaseEvent] = [.restoreCompleted, .restoreNoEntitlement, .restoreFailed]
}

/// One recorded event: what happened, on which store, an optional detail (product id or error
/// message), and when. `Codable` so the whole log round-trips through `UserDefaults`.
public struct TrackedEvent: Codable, Equatable, Sendable {
    public let event: PurchaseEvent
    public let store: String       // "mock" | "revenueCat"
    public let detail: String?     // product id on success, error message on failure
    /// Locale active when the event occurred. Optional so existing v1 event logs decode unchanged.
    public let locale: String?
    public let date: Date

    public init(event: PurchaseEvent, store: String, detail: String? = nil,
                locale: String? = nil, date: Date) {
        self.event = event
        self.store = store
        self.detail = detail
        self.locale = locale
        self.date = date
    }
}

/// Records the purchase/paywall funnel locally so we can reason about conversion **without** any
/// third-party analytics SDK. Events persist to `UserDefaults` (a bounded ring buffer), survive
/// relaunch, and are fully injectable (`UserDefaults` + `clock`) for deterministic tests.
///
/// This is real, shipping behaviour — not a stub. The live RevenueCat dashboard tracks the *server*
/// side of purchases; this tracks the *client* funnel (including paywall impressions and cancels,
/// which RevenueCat can't see) so the two together explain conversion.
@MainActor
final class PurchaseEventTracker {
    /// Versioned storage key — bump the suffix if `TrackedEvent`'s shape ever changes incompatibly.
    static let storageKey = "sonance.purchaseEvents.v1"
    static let storeEvidenceKey = "sonance.storePurchaseEvidence.v1"

    /// Newest-kept cap. Older events roll off the front once the log exceeds this.
    let maxEvents: Int

    private let defaults: UserDefaults
    private let clock: () -> Date
    private let localeIdentifier: () -> String
    private let log = Logger(subsystem: kSubsystem, category: "PurchaseTracking")

    /// The full event log, oldest → newest.
    private(set) var events: [TrackedEvent]
    /// Cached projections are retained for diagnostics; only a fresh complete StoreKit read
    /// supplies purchase counts. Historical callback logs are never promoted to transactions.
    private(set) var cachedStorePurchases: [StorePurchaseEvidence]
    private(set) var storePurchaseSnapshot: StorePurchaseSnapshot?
    private var storeReadTask: Task<StorePurchaseSnapshot, Never>?
    private var evidenceRevision = 0
    /// A complete actual StoreKit read can feed consented product observations;
    /// legacy callback events never supply this observer.
    var onStorePurchaseSnapshot: ((StorePurchaseSnapshot) -> Void)?
    var onRecordedEvent: ((TrackedEvent) -> Void)?

    init(defaults: UserDefaults = .standard,
         maxEvents: Int = 500,
         clock: @escaping () -> Date = { Date() },
         localeIdentifier: @escaping () -> String = { Locale.current.identifier }) {
        self.defaults = defaults
        self.maxEvents = max(1, maxEvents)
        self.clock = clock
        self.localeIdentifier = localeIdentifier
        self.events = Self.load(from: defaults)
        self.cachedStorePurchases = defaults.data(forKey: Self.storeEvidenceKey)
            .flatMap { try? JSONDecoder().decode([StorePurchaseEvidence].self, from: $0) } ?? []
    }

    // MARK: Recording

    /// Append an event and persist. Trims the oldest events past `maxEvents`.
    @discardableResult
    func record(_ event: PurchaseEvent, store: String, detail: String? = nil) -> TrackedEvent {
        let entry = TrackedEvent(event: event, store: store, detail: detail,
                                 locale: localeIdentifier(), date: clock())
        events.append(entry)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        persist()
        log.notice("\(event.rawValue, privacy: .public) store=\(store, privacy: .public)")
        onRecordedEvent?(entry)
        return entry
    }

    /// Forget everything (used by tests and a future "reset analytics" affordance).
    func clear() {
        events.removeAll()
        evidenceRevision += 1
        storeReadTask?.cancel()
        storeReadTask = nil
        cachedStorePurchases.removeAll()
        storePurchaseSnapshot = nil
        defaults.removeObject(forKey: Self.storeEvidenceKey)
        persist()
    }

    /// Coalesce reads of the actual Apple history. No remote analytics or licensing write occurs.
    @discardableResult
    func refreshStorePurchases(limit: Int = 500) async -> StorePurchaseSnapshot {
        let revision = evidenceRevision
        if let pending = storeReadTask {
            let snapshot = await pending.value
            guard revision == evidenceRevision else {
                return StorePurchaseSnapshot(state: .cancelled, observedAt: Date(),
                                             transactions: [], recordsRead: 0, unverifiedRecords: 0)
            }
            return snapshot
        }
        let task = Task { await StorePurchaseEvidenceReader.read(limit: limit) }
        storeReadTask = task
        let snapshot = await task.value
        guard revision == evidenceRevision else {
            return StorePurchaseSnapshot(state: .cancelled, observedAt: Date(),
                                         transactions: [], recordsRead: 0, unverifiedRecords: 0)
        }
        storeReadTask = nil
        storePurchaseSnapshot = snapshot
        if snapshot.state == .complete {
            cachedStorePurchases = snapshot.transactions
            if let data = try? JSONEncoder().encode(cachedStorePurchases) {
                defaults.set(data, forKey: Self.storeEvidenceKey)
            }
        }
        onStorePurchaseSnapshot?(snapshot)
        return snapshot
    }

    // MARK: Queries

    /// Most recent event, if any.
    var lastEvent: TrackedEvent? { events.last }

    /// How many times `event` was recorded.
    func count(of event: PurchaseEvent) -> Int {
        events.reduce(0) { $0 + ($1.event == event ? 1 : 0) }
    }

    /// All recorded events of a given kind, oldest → newest.
    func events(of event: PurchaseEvent) -> [TrackedEvent] {
        events.filter { $0.event == event }
    }

    /// Legacy callback diagnostic: successful unlock callbacks ÷ paywall impressions.
    /// Repeated callbacks can repeat the numerator; this is not transaction conversion and is
    /// no longer used as the Purchase Analytics headline. `nil` when the paywall was never shown
    /// (division-by-zero guard — "no impressions" is not "0% conversion").
    var conversionRate: Double? {
        let shown = count(of: .paywallShown)
        guard shown > 0 else { return nil }
        return Double(count(of: .purchaseCompleted)) / Double(shown)
    }

    /// Successful restores ÷ restore attempts. `nil` when restore was never attempted.
    var restoreSuccessRate: Double? {
        let started = count(of: .restoreStarted)
        guard started > 0 else { return nil }
        return Double(count(of: .restoreCompleted)) / Double(started)
    }

    /// Failed purchases ÷ started purchases (cancels are not failures). `nil` when none started.
    var purchaseFailureRate: Double? {
        let started = count(of: .purchaseStarted)
        guard started > 0 else { return nil }
        return Double(count(of: .purchaseFailed)) / Double(started)
    }

    // MARK: Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> [TrackedEvent] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TrackedEvent].self, from: data) else {
            return []
        }
        return decoded
    }
}
