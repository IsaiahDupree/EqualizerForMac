import Foundation
import Testing
@testable import SonanceEQ

/// `applyAndTrack` is the single funnel every RevenueCat/Apple-originated entitlement change passes
/// through (the `customerInfoStream` listener calls it). These tests prove it both updates gating and
/// records the right lifecycle events — `customerInfoUpdated` every time, plus `entitlementGranted` /
/// `entitlementRevoked` exactly on the Pro transitions — so the in-app analytics see unlocks/revokes
/// no matter where they originate (renewal, refund, Ask-to-Buy, another device, dashboard grant).
@MainActor
@Suite struct EntitlementEventTrackingTests {

    @Test func grantRecordsUpdatedAndGranted() {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.applyAndTrack(["pro"])
        #expect(pm.isPro)
        #expect(pm.tracker.count(of: .customerInfoUpdated) == 1)
        #expect(pm.tracker.count(of: .entitlementGranted) == 1)
        #expect(pm.tracker.count(of: .entitlementRevoked) == 0)
    }

    @Test func revokeRecordsUpdatedAndRevoked() {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.applyAndTrack(["pro"])
        pm.applyAndTrack([])                 // entitlement lost (refund / expiry)
        #expect(!pm.isPro)
        #expect(pm.tracker.count(of: .customerInfoUpdated) == 2)
        #expect(pm.tracker.count(of: .entitlementGranted) == 1)
        #expect(pm.tracker.count(of: .entitlementRevoked) == 1)
    }

    @Test func repeatedActiveStateDoesNotReGrant() {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.applyAndTrack(["pro"])
        pm.applyAndTrack(["pro"])            // unchanged — no second grant
        pm.applyAndTrack(["pro", "premium"]) // still active — still no grant
        #expect(pm.tracker.count(of: .customerInfoUpdated) == 3)
        #expect(pm.tracker.count(of: .entitlementGranted) == 1)
        #expect(pm.tracker.count(of: .entitlementRevoked) == 0)
    }

    @Test func emptyUpdatesNeverGrantOrRevoke() {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.applyAndTrack([])
        pm.applyAndTrack(["premium"])        // a non-pro entitlement: no grant
        #expect(!pm.isPro)
        #expect(pm.tracker.count(of: .customerInfoUpdated) == 2)
        #expect(pm.tracker.count(of: .entitlementGranted) == 0)
        #expect(pm.tracker.count(of: .entitlementRevoked) == 0)
    }

    // Every call records exactly one customerInfoUpdated. 16 subsets.
    @Test(arguments: entitlementSubsets)
    func everyApplyRecordsOneUpdate(_ subset: [String]) {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.applyAndTrack(Set(subset))
        #expect(pm.tracker.count(of: .customerInfoUpdated) == 1)
        #expect(pm.canUse(.parametricEQ) == subset.contains("pro"))
    }

    // Full 16×16 transition matrix — grant/revoke fire exactly on the Pro edges, modelled independently.
    @Test(arguments: entitlementSubsets, entitlementSubsets)
    func transitionMatrix(_ from: [String], _ to: [String]) {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        let fromPro = from.contains("pro")
        let toPro = to.contains("pro")

        pm.applyAndTrack(Set(from))          // baseline: false → fromPro
        pm.applyAndTrack(Set(to))            // fromPro → toPro

        let expectedGrants = (fromPro ? 1 : 0) + ((toPro && !fromPro) ? 1 : 0)
        let expectedRevokes = (fromPro && !toPro) ? 1 : 0
        #expect(pm.tracker.count(of: .customerInfoUpdated) == 2)
        #expect(pm.tracker.count(of: .entitlementGranted) == expectedGrants)
        #expect(pm.tracker.count(of: .entitlementRevoked) == expectedRevokes)
        #expect(pm.isPro == toPro)
    }
}
