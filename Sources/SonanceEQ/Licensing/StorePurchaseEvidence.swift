import CryptoKit
import Foundation
import StoreKit

/// A small local projection of a StoreKit-verified non-consumable transaction.
/// The original store identifier is hashed before persistence; no receipt, JWS, account,
/// customer price or provider identity is retained or transmitted.
struct StorePurchaseEvidence: Codable, Equatable, Sendable {
    let transactionKey: String
    let productID: String
    let purchasedAt: Date
    let originalPurchasedAt: Date
    let signedAt: Date
    let revokedAt: Date?
    let environment: String
    let ownership: String
}

struct StorePurchaseSnapshot: Sendable {
    enum State: String, Sendable { case complete, partial, cancelled }

    let state: State
    let observedAt: Date
    let transactions: [StorePurchaseEvidence]
    let recordsRead: Int
    let unverifiedRecords: Int

    /// These are device/account history counts, never a distinct-customer or campaign metric.
    /// Unknown/truncated reads remain nil. Family sharing does not create another purchase.
    var productionPurchaseCount: Int? {
        count { $0.environment == "production" && $0.ownership == "purchased" && $0.revokedAt == nil }
    }

    var testPurchaseCount: Int? {
        count { ["sandbox", "xcode"].contains($0.environment) && $0.ownership == "purchased" && $0.revokedAt == nil }
    }

    var revokedPurchaseCount: Int? { count { $0.ownership == "purchased" && $0.revokedAt != nil } }

    private func count(_ predicate: (StorePurchaseEvidence) -> Bool) -> Int? {
        state == .complete ? transactions.filter(predicate).count : nil
    }
}

enum StorePurchaseEvidenceReader {
    /// StoreKit's local history is the evidence source, independent of unlock callbacks.
    /// One extra item detects truncation; even a verified prefix cannot claim a complete count.
    /// This does not finish transactions, change licensing, sync the account, or initiate purchases.
    static func read(limit: Int = 500) async -> StorePurchaseSnapshot {
        let limit = max(1, min(limit, 500))
        var records: [String: StorePurchaseEvidence] = [:]
        var read = 0
        var unverified = 0
        var state = StorePurchaseSnapshot.State.complete
        let start = ContinuousClock.now
        for await result in Transaction.all {
            if Task.isCancelled {
                state = .cancelled
                break
            }
            if read == limit || start.duration(to: .now) >= .seconds(10) {
                state = .partial
                break
            }
            read += 1
            guard case .verified(let transaction) = result else {
                unverified += 1
                state = .partial
                continue
            }
            guard transaction.productID == LicenseConfig.proProductID,
                  transaction.productType == .nonConsumable,
                  transaction.appBundleID == "com.isaiahdupree.SonanceEQ" else { continue }
            let environment: String
            switch transaction.environment {
            case .production: environment = "production"
            case .sandbox: environment = "sandbox"
            case .xcode: environment = "xcode"
            default:
                state = .partial
                continue
            }
            let ownership: String
            switch transaction.ownershipType {
            case .purchased: ownership = "purchased"
            case .familyShared: ownership = "family_shared"
            default:
                state = .partial
                continue
            }
            let material = "sonance-storekit-v1|\(environment)|\(transaction.productID)|\(transaction.originalID)"
            let key = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
            let evidence = StorePurchaseEvidence(
                transactionKey: key, productID: transaction.productID,
                purchasedAt: transaction.purchaseDate, originalPurchasedAt: transaction.originalPurchaseDate,
                signedAt: transaction.signedDate, revokedAt: transaction.revocationDate,
                environment: environment, ownership: ownership)
            if let existing = records[key] {
                if evidence.signedAt > existing.signedAt { records[key] = evidence }
                else if evidence.signedAt == existing.signedAt && evidence != existing { state = .partial }
            } else { records[key] = evidence }
        }
        if Task.isCancelled { state = .cancelled }
        return StorePurchaseSnapshot(state: state, observedAt: Date(),
            transactions: records.values.sorted { $0.transactionKey < $1.transactionKey },
            recordsRead: read, unverifiedRecords: unverified)
    }
}
