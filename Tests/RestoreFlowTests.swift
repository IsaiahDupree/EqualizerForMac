import Foundation
import Testing
@testable import SonanceEQ

/// Restore flow: with nothing bought, with an existing entitlement, and across repeated attempts.
@MainActor
@Suite struct RestoreFlowTests {

    // 1...20 = 20 — restoring with nothing purchased never unlocks and records `restoreNoEntitlement`.
    @Test(arguments: 1...20)
    func restoreWithoutPurchaseStaysLocked(_ attempts: Int) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        for _ in 0..<attempts { await pm.restore() }
        #expect(!pm.isPro)
        #expect(pm.tracker.count(of: .restoreStarted) == attempts)
        #expect(pm.tracker.count(of: .restoreNoEntitlement) == attempts)
        #expect(pm.tracker.count(of: .restoreCompleted) == 0)
    }

    // 1...15 = 15 — after a purchase, every restore confirms the entitlement.
    @Test(arguments: 1...15)
    func restoreAfterPurchaseCompletes(_ attempts: Int) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        await pm.purchasePro()
        for _ in 0..<attempts { await pm.restore() }
        #expect(pm.isPro)
        #expect(pm.tracker.count(of: .restoreCompleted) == attempts)
        #expect(pm.tracker.count(of: .restoreNoEntitlement) == 0)
    }

    // 0...20 = 21 — restoreStarted counts every attempt.
    @Test(arguments: 0...20)
    func restoreStartedCountsAttempts(_ attempts: Int) async {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        for _ in 0..<attempts { await pm.restore() }
        #expect(pm.tracker.count(of: .restoreStarted) == attempts)
    }

    @Test func restorePersistsAcrossManagerInstances() async {
        let suite = "test.purchases.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { LicensingTestKit.dispose(suite) }
        let tracker1 = PurchaseEventTracker(defaults: defaults, clock: LicensingTestKit.fixedClock())
        let pm1 = PurchaseManager(defaults: defaults, tracker: tracker1)
        pm1.start()
        await pm1.purchasePro()
        #expect(pm1.isPro)
        // A fresh manager on the same store restores the unlock on restore().
        let tracker2 = PurchaseEventTracker(defaults: defaults, clock: LicensingTestKit.fixedClock())
        let pm2 = PurchaseManager(defaults: defaults, tracker: tracker2)
        pm2.start()
        #expect(pm2.isPro)               // start() already reads the persisted flag
        await pm2.restore()
        #expect(pm2.isPro)
        #expect(tracker2.count(of: .restoreCompleted) == 1)
    }
}
