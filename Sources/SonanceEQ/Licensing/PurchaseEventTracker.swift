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
    public let date: Date

    public init(event: PurchaseEvent, store: String, detail: String? = nil, date: Date) {
        self.event = event
        self.store = store
        self.detail = detail
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

    /// Newest-kept cap. Older events roll off the front once the log exceeds this.
    let maxEvents: Int

    private let defaults: UserDefaults
    private let clock: () -> Date
    private let log = Logger(subsystem: kSubsystem, category: "PurchaseTracking")

    /// The full event log, oldest → newest.
    private(set) var events: [TrackedEvent]

    init(defaults: UserDefaults = .standard,
         maxEvents: Int = 500,
         clock: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.maxEvents = max(1, maxEvents)
        self.clock = clock
        self.events = Self.load(from: defaults)
    }

    // MARK: Recording

    /// Append an event and persist. Trims the oldest events past `maxEvents`.
    @discardableResult
    func record(_ event: PurchaseEvent, store: String, detail: String? = nil) -> TrackedEvent {
        let entry = TrackedEvent(event: event, store: store, detail: detail, date: clock())
        events.append(entry)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        persist()
        log.notice("\(event.rawValue, privacy: .public) store=\(store, privacy: .public)")
        return entry
    }

    /// Forget everything (used by tests and a future "reset analytics" affordance).
    func clear() {
        events.removeAll()
        persist()
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

    /// Completed purchases ÷ paywall impressions. `nil` when the paywall was never shown
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
