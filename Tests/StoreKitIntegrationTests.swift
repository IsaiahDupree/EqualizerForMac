import Foundation
import RevenueCat
import StoreKit
import StoreKitTest
import Testing
@testable import SonanceEQ

/// Marker class so we can locate the test bundle (Swift Testing suites are structs, not classes).
private final class StoreKitTestBundleMarker {}

/// Gate: **opt-in**, SKIPPED by default. StoreKit Testing propagates transactions asynchronously and
/// its process-global state is sensitive to the heavy parallel load of the full unit suite — running
/// it inline makes it flaky (and a flaky pre-commit suite = random commit failures). Kept deterministic
/// by quarantining it here; the test itself polls for propagation so it's reliable when invoked.
///
/// Run it from Xcode (Edit Scheme → Test → Options → StoreKit Configuration: SonanceEQ.storekit) or:
///
///   xcodebuild test -project SonanceEQ.xcodeproj -scheme SonanceEQ-StoreKit \
///     -destination 'platform=macOS,arch=arm64' -jobs 1 -parallel-testing-enabled NO \
///     -only-testing:SonanceEQTests/StoreKitIntegrationTests
let storeKitTestsEnabled = ProcessInfo.processInfo.environment["SONANCE_STOREKIT_TESTS"] == "1"

private struct StoreKitTimeout: Error {}

/// Race an async read against a deadline so a hung StoreKit call fails fast instead of wedging the run.
private func withTimeout<T: Sendable>(_ seconds: Double,
                                      _ operation: @escaping @Sendable () async -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw StoreKitTimeout()
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw StoreKitTimeout() }
        return first
    }
}

/// **Integration test** over the real StoreKit purchase machinery (local `SKTestSession`, no Apple
/// servers): a genuine `buyProduct` transaction → `Transaction.currentEntitlements` → our gating policy.
/// Proves a real purchase unlocks Pro and that no-purchase / refund keeps it locked.
///
/// Scope boundary: in production RevenueCat maps the StoreKit transaction to the `pro` entitlement
/// server-side; that backend hop can't run hermetically. Here we apply the same mapping RevenueCat is
/// configured with (owning `…SonanceEQ.pro` ⇒ `pro`), then drive the exact `applyActiveEntitlements`
/// policy the app ships. `.serialized` because StoreKit Testing state is process-global; `.timeLimit`
/// is a backstop against environmental hangs.
@MainActor
@Suite(.serialized, .enabled(if: storeKitTestsEnabled), .timeLimit(.minutes(1)))
struct StoreKitIntegrationTests {

    /// This adapts observed, verified local Apple transactions to the public RevenueCat value
    /// types used by the app's callback policy. It does not manufacture purchases or make a backend
    /// request, and does not claim to verify RevenueCat's server receipt-to-entitlement mapping.
    private func localCustomerInfo(userID: String, firstSeen: Date) async throws -> CustomerInfo {
        let entitlements: [String: EntitlementInfo] = try await withTimeout(20) {
            var entitlements: [String: EntitlementInfo] = [:]
            for await result in Transaction.currentEntitlements {
                if case .verified(let txn) = result,
                   txn.productID == LicenseConfig.proProductID, txn.revocationDate == nil {
                    entitlements[LicenseConfig.proEntitlementID] = EntitlementInfo(
                        identifier: LicenseConfig.proEntitlementID, isActive: true,
                        willRenew: false, periodType: .normal,
                        latestPurchaseDate: txn.purchaseDate, originalPurchaseDate: txn.originalPurchaseDate,
                        expirationDate: txn.expirationDate, store: .appStore,
                        productIdentifier: txn.productID, isSandbox: txn.environment != .production,
                        ownershipType: txn.ownershipType == .familyShared ? .familyShared : .purchased)
                }
            }
            return entitlements
        }
        return CustomerInfo(entitlements: EntitlementInfos(entitlements: entitlements),
                            requestDate: Date(), firstSeen: firstSeen, originalAppUserId: userID)
    }

    private func freshManager() -> (PurchaseManager, String) {
        let suite = "test.storekit.callbacks.\(UUID().uuidString)"
        return (PurchaseManager(defaults: UserDefaults(suiteName: suite)!), suite)
    }

    private func newSession() throws -> SKTestSession {
        let url = try #require(Bundle(for: StoreKitTestBundleMarker.self)
            .url(forResource: "SonanceEQ", withExtension: "storekit"),
            "SonanceEQ.storekit must be bundled into the test target")
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.resetToDefaultState()
        session.clearTransactions()
        return session
    }

    /// The product→entitlement mapping RevenueCat performs server-side: owning the non-consumable
    /// `…SonanceEQ.pro` (a non-revoked current entitlement) grants the `pro` entitlement.
    private func activeEntitlementIDs() async throws -> Set<String> {
        try await withTimeout(20) {
            var owned = false
            for await result in Transaction.currentEntitlements {
                if case .verified(let txn) = result,
                   txn.productID == LicenseConfig.proProductID,
                   txn.revocationDate == nil {
                    owned = true
                }
            }
            return owned ? [LicenseConfig.proEntitlementID] : []
        }
    }

    /// Poll the entitlement set until it satisfies `predicate` (StoreKit Testing propagates buy/clear/
    /// refund asynchronously — a single read right after can race). Returns the last read either way so
    /// the caller's `#expect` reports a real mismatch if it never converges.
    private func awaitEntitlements(_ predicate: (Set<String>) -> Bool) async throws -> Set<String> {
        var ids: Set<String> = []
        for _ in 0..<100 {                        // up to ~10s
            ids = try await activeEntitlementIDs()
            if predicate(ids) { return ids }
            try await Task.sleep(nanoseconds: 100_000_000)   // 100 ms
        }
        return ids
    }

    @Test func noPurchaseLeavesEveryFeatureLocked() async throws {
        let session = try newSession()
        _ = session
        let active = try await awaitEntitlements { $0.isEmpty }
        #expect(active.isEmpty)

        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.applyActiveEntitlements(active)
        #expect(!pm.isPro)
        for feature in ProFeature.allCases {
            #expect(!pm.canUse(feature))
            #expect(pm.shouldShowPaywall(for: feature))
        }
    }

    @Test func realPurchaseUnlocksEveryFeature() async throws {
        let session = try newSession()

        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }

        // Pre-purchase: locked.
        pm.applyActiveEntitlements(try await awaitEntitlements { $0.isEmpty })
        #expect(!pm.isPro)

        // A real StoreKit transaction (no Product.products lookup needed).
        let txn = try await session.buyProduct(identifier: LicenseConfig.proProductID)
        #expect(txn.productID == LicenseConfig.proProductID)

        // The transaction maps to the `pro` entitlement → policy unlocks every feature.
        let active = try await awaitEntitlements { $0.contains(LicenseConfig.proEntitlementID) }
        #expect(active.contains(LicenseConfig.proEntitlementID))
        pm.applyActiveEntitlements(active)
        #expect(pm.isPro)
        for feature in ProFeature.allCases {
            #expect(pm.canUse(feature))
            #expect(!pm.shouldShowPaywall(for: feature))
        }
    }

    @Test func refundReLocksEveryFeature() async throws {
        let session = try newSession()

        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }

        let txn = try await session.buyProduct(identifier: LicenseConfig.proProductID)
        let bought = try await awaitEntitlements { $0.contains(LicenseConfig.proEntitlementID) }
        pm.applyActiveEntitlements(bought)
        #expect(pm.isPro)

        // Refund/revoke — RevenueCat would drop it from `.active`; so does StoreKit.
        try session.refundTransaction(identifier: UInt(txn.id))

        let active = try await awaitEntitlements { !$0.contains(LicenseConfig.proEntitlementID) }
        #expect(!active.contains(LicenseConfig.proEntitlementID))
        pm.applyActiveEntitlements(active)
        #expect(!pm.isPro)
        for feature in ProFeature.allCases { #expect(!pm.canUse(feature)) }
    }

    @Test func clearingTransactionsReturnsToLocked() async throws {
        let session = try newSession()
        _ = try await session.buyProduct(identifier: LicenseConfig.proProductID)
        #expect(try await awaitEntitlements { $0.contains(LicenseConfig.proEntitlementID) }
                == [LicenseConfig.proEntitlementID])

        session.clearTransactions()
        #expect(try await awaitEntitlements { $0.isEmpty }.isEmpty)
    }

    @Test(arguments: [
        ("USA", "en_US"), ("POL", "pl_PL"), ("VNM", "vi_VN"), ("CZE", "cs_CZ"),
        ("ITA", "it_IT"), ("PRT", "pt_PT"), ("GRC", "el_GR"), ("HUN", "hu_HU"),
        ("TWN", "zh_TW"), ("HKG", "zh_HK"), ("FRA", "fr_FR"),
    ])
    func approvedPackagePreservesRealStoreKitPrice(storefront: String, locale: String) async throws {
        let session = try newSession()
        session.storefront = storefront
        session.locale = Locale(identifier: locale)
        let product = try #require(try await Product.products(for: [LicenseConfig.proProductID]).first)
        #expect(product.id == LicenseConfig.proProductID)
        #expect(product.type == .nonConsumable)
        #expect(!product.displayPrice.isEmpty)
        let package = Package(identifier: product.id, packageType: .lifetime,
                              storeProduct: StoreProduct(sk2Product: product),
                              offeringIdentifier: LicenseConfig.offeringID, webCheckoutUrl: nil)
        let offering = Offering(identifier: LicenseConfig.offeringID, serverDescription: product.displayName,
                                availablePackages: [package], webCheckoutUrl: nil)
        let selected = try #require(PurchaseManager.proPackage(in: offering))
        #expect(selected === package)
        #expect(selected.storeProduct.localizedPriceString == product.displayPrice)
        #expect(PurchaseManager.isAuthorizedProPackage(selected))
        #expect(PurchaseManager.proPackage(in: nil) == nil)
        #expect(PurchaseManager.proPackage(in: Offering(identifier: LicenseConfig.offeringID,
            serverDescription: product.displayName, availablePackages: [], webCheckoutUrl: nil)) == nil)
    }

    @Test func emptyRestoreReportsNoEntitlementAndKeepsEveryFeatureLocked() async throws {
        let session = try newSession()
        _ = session
        #expect(try await awaitEntitlements { $0.isEmpty }.isEmpty)
        let (pm, suite) = freshManager()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let info = try await localCustomerInfo(userID: suite, firstSeen: Date())
        #expect(!pm.completeRestore(info))
        #expect(!pm.isPro)
        #expect(pm.tracker.lastEvent?.event == .restoreNoEntitlement)
        #expect(pm.lastError == EQText.string("No active Pro purchase was found for this Apple Account."))
        for feature in ProFeature.allCases { #expect(!pm.canUse(feature)) }
    }

    @Test func purchaseRestoreAndRefundCallbacksUseVerifiedTransactionSnapshots() async throws {
        let session = try newSession()
        #expect(try await awaitEntitlements { $0.isEmpty }.isEmpty)
        let (pm, suite) = freshManager()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let firstSeen = Date()
        let emptyBeforePurchase = try await localCustomerInfo(userID: suite, firstSeen: firstSeen)

        let transaction = try await session.buyProduct(identifier: LicenseConfig.proProductID)
        #expect(try await awaitEntitlements { $0.contains(LicenseConfig.proEntitlementID) }
            == [LicenseConfig.proEntitlementID])
        let purchased = try await localCustomerInfo(userID: suite, firstSeen: firstSeen)
        #expect(pm.completePurchase(purchased))
        #expect(pm.isPro)
        #expect(pm.tracker.lastEvent?.event == .purchaseCompleted)
        #expect(pm.lastError == nil)
        #expect(pm.completeRestore(purchased))
        #expect(pm.tracker.lastEvent?.event == .restoreCompleted)

        // A delayed empty restore cannot claim success merely because a newer purchase unlocked Pro.
        #expect(!pm.completeRestore(emptyBeforePurchase))
        #expect(pm.isPro)
        #expect(pm.tracker.lastEvent?.event == .restoreNoEntitlement)
        #expect(!pm.completePurchase(emptyBeforePurchase))
        #expect(pm.isPro)
        #expect(pm.tracker.lastEvent?.event == .purchaseFailed)

        try session.refundTransaction(identifier: UInt(transaction.id))
        #expect(try await awaitEntitlements { $0.isEmpty }.isEmpty)
        let refunded = try await localCustomerInfo(userID: suite, firstSeen: firstSeen)
        #expect(!pm.completeRestore(refunded))
        #expect(!pm.isPro)
        #expect(pm.tracker.lastEvent?.event == .restoreNoEntitlement)
        // A delayed purchase callback cannot re-unlock access after the newer refund snapshot.
        #expect(!pm.completePurchase(purchased))
        #expect(!pm.isPro)
        #expect(pm.tracker.lastEvent?.event == .purchaseFailed)
        for feature in ProFeature.allCases { #expect(!pm.canUse(feature)) }
    }

    @Test func actualEmptyHistoryHasNoTransactionEvidenceUntilRead() async throws {
        let session = try newSession()
        _ = session
        #expect(try await awaitEntitlements { $0.isEmpty }.isEmpty)
        let suite = "test.storekit.evidence.empty.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let tracker = PurchaseEventTracker(defaults: defaults)
        #expect(tracker.storePurchaseSnapshot == nil)
        let read = await tracker.refreshStorePurchases()
        #expect(read.state == .complete)
        #expect(read.productionPurchaseCount == 0)
        #expect(read.testPurchaseCount == 0)
        #expect(read.revokedPurchaseCount == 0)
        #expect(read.transactions.isEmpty)
    }

    @Test func nativeJourneyUsesVerifiedLocalTransactionsAndKeepsTestEnvironment() async throws {
        let suite = "test.storekit.nativeJourney.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let journey = ProductJourneyTracker(defaults: defaults, configuration: nil)
        journey.setConsent(true)
        let session = try newSession()
        let transaction = try await session.buyProduct(identifier: LicenseConfig.proProductID)
        _ = try await awaitEntitlements { $0.contains(LicenseConfig.proEntitlementID) }
        let tracker = PurchaseEventTracker(defaults: defaults)
        tracker.onStorePurchaseSnapshot = { journey.observe($0) }
        let snapshot = await tracker.refreshStorePurchases()
        #expect(snapshot.state == .complete)
        #expect(snapshot.testPurchaseCount == 1)
        #expect(snapshot.productionPurchaseCount == 0)
        let evidence = try #require(snapshot.transactions.first)
        #expect(evidence.environment == "xcode")
        #expect(evidence.productID == transaction.productID)
        #expect(journey.pendingCount == 1)
        journey.observe(snapshot)
        #expect(journey.pendingCount == 1)

        // A new opt-in cannot relabel an already-owned transaction as a fresh sale.
        journey.setConsent(false); journey.setConsent(true)
        journey.observe(snapshot)
        #expect(journey.pendingCount == 0)
    }

    @Test func verifiedHistoryDeduplicatesCallbacksAndSurvivesRelaunch() async throws {
        let session = try newSession()
        let transaction = try await session.buyProduct(identifier: LicenseConfig.proProductID)
        #expect(try await awaitEntitlements { $0.contains(LicenseConfig.proEntitlementID) }
                == [LicenseConfig.proEntitlementID])
        let (pm, suite) = freshManager()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let info = try await localCustomerInfo(userID: suite, firstSeen: Date())
        pm.tracker.record(.paywallShown, store: "revenueCat")
        #expect(pm.completePurchase(info))
        #expect(pm.completePurchase(info))
        #expect(pm.completeRestore(info))
        // Reproduce the old inflated callback ratio over one actual Apple transaction.
        #expect(pm.tracker.count(of: .purchaseCompleted) == 2)
        #expect(pm.tracker.conversionRate == 2)
        let read = await pm.tracker.refreshStorePurchases()
        #expect(read.state == .complete)
        #expect(read.productionPurchaseCount == 0)
        #expect(read.testPurchaseCount == 1)
        #expect(read.revokedPurchaseCount == 0)
        let evidence = try #require(read.transactions.first)
        #expect(read.transactions.count == 1)
        #expect(evidence.productID == transaction.productID)
        #expect(evidence.originalPurchasedAt == transaction.originalPurchaseDate)
        #expect(evidence.environment == "xcode")
        #expect(evidence.ownership == "purchased")
        #expect(evidence.transactionKey.count == 64)
        #expect(evidence.transactionKey != String(transaction.originalID))

        let defaults = try #require(UserDefaults(suiteName: suite))
        let data = try #require(defaults.data(forKey: PurchaseEventTracker.storeEvidenceKey))
        let objects = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(objects.count == 1)
        #expect(Set(try #require(objects.first).keys) == ["transactionKey", "productID", "purchasedAt",
            "originalPurchasedAt", "signedAt", "environment", "ownership"])
        #expect(objects.first?["transactionID"] == nil)
        #expect(objects.first?["originalID"] == nil)
        #expect(objects.first?["jws"] == nil)
        #expect(objects.first?["customerID"] == nil)
        let relaunched = PurchaseEventTracker(defaults: defaults)
        #expect(relaunched.cachedStorePurchases == read.transactions)
        #expect(relaunched.storePurchaseSnapshot == nil) // a persisted projection is not a fresh read
        let repeated = await relaunched.refreshStorePurchases()
        #expect(repeated.transactions == read.transactions)
        #expect(repeated.testPurchaseCount == 1)
        #expect(repeated.productionPurchaseCount == 0)
        relaunched.clear()
        #expect(defaults.data(forKey: PurchaseEventTracker.storeEvidenceKey) == nil)
        #expect(relaunched.storePurchaseSnapshot == nil)
        #expect(relaunched.cachedStorePurchases.isEmpty)
        #expect(relaunched.events.isEmpty)
    }

    @Test func refundedVerifiedHistoryDoesNotCountAsAnOwnedPurchase() async throws {
        let session = try newSession()
        let transaction = try await session.buyProduct(identifier: LicenseConfig.proProductID)
        #expect(try await awaitEntitlements { $0.contains(LicenseConfig.proEntitlementID) }
                == [LicenseConfig.proEntitlementID])
        let suite = "test.storekit.evidence.refund.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let tracker = PurchaseEventTracker(defaults: defaults)
        let bought = await tracker.refreshStorePurchases()
        #expect(bought.testPurchaseCount == 1)
        try session.refundTransaction(identifier: UInt(transaction.id))
        #expect(try await awaitEntitlements { $0.isEmpty }.isEmpty)
        let refunded = await tracker.refreshStorePurchases()
        #expect(refunded.state == .complete)
        #expect(refunded.testPurchaseCount == 0)
        #expect(refunded.productionPurchaseCount == 0)
        #expect(refunded.revokedPurchaseCount == 1)
        #expect(refunded.transactions.count == 1)
        #expect(refunded.transactions.first?.transactionKey == bought.transactions.first?.transactionKey)
        #expect(refunded.transactions.first?.revokedAt != nil)
        #expect(tracker.cachedStorePurchases == refunded.transactions)
    }

    @Test func truncatedActualHistoryStaysUnknownAndPreservesCompleteCache() async throws {
        let session = try newSession()
        let first = try await session.buyProduct(identifier: LicenseConfig.proProductID)
        #expect(try await awaitEntitlements { $0.contains(LicenseConfig.proEntitlementID) }
                == [LicenseConfig.proEntitlementID])
        try session.refundTransaction(identifier: UInt(first.id))
        #expect(try await awaitEntitlements { $0.isEmpty }.isEmpty)
        _ = try await session.buyProduct(identifier: LicenseConfig.proProductID)
        #expect(try await awaitEntitlements { $0.contains(LicenseConfig.proEntitlementID) }
                == [LicenseConfig.proEntitlementID])
        let suite = "test.storekit.evidence.partial.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let tracker = PurchaseEventTracker(defaults: defaults)
        let complete = await tracker.refreshStorePurchases()
        #expect(complete.state == .complete)
        #expect(complete.recordsRead >= 2)
        let saved = try #require(defaults.data(forKey: PurchaseEventTracker.storeEvidenceKey))
        let partial = await tracker.refreshStorePurchases(limit: 1)
        #expect(partial.state == .partial)
        #expect(partial.recordsRead == 1)
        #expect(partial.productionPurchaseCount == nil)
        #expect(partial.testPurchaseCount == nil)
        #expect(partial.revokedPurchaseCount == nil)
        #expect(tracker.cachedStorePurchases == complete.transactions)
        #expect(defaults.data(forKey: PurchaseEventTracker.storeEvidenceKey) == saved)
    }

    @Test func cancelledActualReadCannotReportZeroPurchases() async throws {
        let session = try newSession()
        _ = session
        let task = Task { await StorePurchaseEvidenceReader.read() }
        task.cancel()
        let read = await task.value
        #expect(read.state == .cancelled)
        #expect(read.productionPurchaseCount == nil)
        #expect(read.testPurchaseCount == nil)
        #expect(read.revokedPurchaseCount == nil)
    }

    @Test func concurrentActualReadsShareOneSnapshot() async throws {
        let session = try newSession()
        _ = try await session.buyProduct(identifier: LicenseConfig.proProductID)
        #expect(try await awaitEntitlements { $0.contains(LicenseConfig.proEntitlementID) }
                == [LicenseConfig.proEntitlementID])
        let suite = "test.storekit.evidence.concurrent.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let tracker = PurchaseEventTracker(defaults: defaults)
        async let first = tracker.refreshStorePurchases()
        async let second = tracker.refreshStorePurchases()
        let (a, b) = await (first, second)
        #expect(a.state == .complete)
        #expect(b.state == .complete)
        #expect(a.observedAt == b.observedAt)
        #expect(a.transactions == b.transactions)
        #expect(a.testPurchaseCount == 1)
        #expect(tracker.cachedStorePurchases == a.transactions)
    }

    @Test func clearCannotBeUndoneByAnInFlightHistoryRead() async throws {
        let session = try newSession()
        _ = try await session.buyProduct(identifier: LicenseConfig.proProductID)
        #expect(try await awaitEntitlements { $0.contains(LicenseConfig.proEntitlementID) }
                == [LicenseConfig.proEntitlementID])
        let suite = "test.storekit.evidence.clear.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let tracker = PurchaseEventTracker(defaults: defaults)
        let read = Task { await tracker.refreshStorePurchases() }
        await Task.yield()
        tracker.clear()
        _ = await read.value
        #expect(tracker.cachedStorePurchases.isEmpty)
        #expect(tracker.storePurchaseSnapshot == nil)
        #expect(defaults.data(forKey: PurchaseEventTracker.storeEvidenceKey) == nil)
    }
}
