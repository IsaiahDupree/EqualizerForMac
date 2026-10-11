# Sonance purchase measurement

The Purchase Analytics screen previously called successful unlock callbacks divided
by paywall impressions a conversion rate. Two callbacks for the same CustomerInfo
could produce two completions for one purchase. A restore or historical entitlement
does not establish another sale, and a local development unlock establishes none.

The screen now reads verified StoreKit transaction history for the exact Sonance
bundle and non-consumable Pro SKU. Production and local/sandbox transactions remain
separate. The original transaction identity is hashed with its product and environment
before local persistence. Repeated reads and restores retain the same identity;
the newest signed version supplies its current revocation state. Family-shared
ownership does not increase purchase counts. Refunds are shown separately and are
excluded from the owned-purchase headline.

The existing callback log, event names and licensing policy remain available for
diagnosis. Its `conversionRate` property is a legacy callback ratio and is no longer
the UI headline. No historical callback is transformed into purchase evidence.

## Read and persistence contract

`PurchaseEventTracker.refreshStorePurchases()` reads Apple's `Transaction.all`,
with at most 500 processed records plus one truncation probe. It checks cancellation
and a ten-second processing budget between elements. This budget is not a hard
deadline on an individual StoreKit iterator await. Concurrent calls on one tracker
share the read. Partial, cancelled, unverified or conflicting reads return unknown
counts; a partial prefix cannot report a zero or a complete total.

Only a complete read replaces the bounded local projection under
`sonance.storePurchaseEvidence.v1`. The projection contains the transaction hash,
SKU, original/current purchase dates, signing date, revocation date, environment
and ownership. Cached projections do not supply a fresh count after relaunch.
Clear log removes both local projections and callbacks; it does not delete Apple's
transaction history, which a later refresh can read again.

The screen reads history on opening in the live licensing configuration and offers
a refresh action. Development-store unlock callbacks cannot populate the App Store
purchase headline. No purchase, transaction finish, account sync, remote analytics,
receipt/JWS export or licensing write is performed by this reader.

## Evidence limits

These are observations of verified transaction history available to this app on
this Mac and Apple account. They are not distinct customers, account-wide reporting,
content-attributed purchases, new-purchase conversion, settled proceeds or operating
profit. A production purchase may have promotional terms; no amount is inferred.
The retained summary is a diagnostic projection, not independently verifiable
payment proof for another service.

The connected Foundry RevenueCat credential was independently read on October 10
UTC and exposes only the EverReach project. It cannot certify Sonance licensing or
server-side transactions. Sonance still needs its scoped provider access, actual
provider acceptance and campaign/activation/transaction joins. Existing App Store
releases do not acquire this change until a separate native release is built,
validated and distributed.

## Verification

Run the existing serial opt-in gate; new measurement cases use actual local Apple
StoreKit transactions and verified history, with no new provider stand-ins:

```sh
xcodegen generate
xcodebuild test -project SonanceEQ.xcodeproj -scheme SonanceEQ-StoreKit \
  -destination 'platform=macOS,arch=arm64' -jobs 1 -parallel-testing-enabled NO \
  -only-testing:SonanceEQTests/StoreKitIntegrationTests
```

The cases cover empty history, repeated successful callbacks over one purchase,
restore/read/relaunch identity, hashed persistence, refund updates, actual truncated
history, cancellation and clear-log behavior. They supplement the retained purchase,
restore, refund, gating and regional price cases. Local Xcode transactions do not
prove RevenueCat's live receipt mapping or an actual customer payment.

Apple's [transaction history](https://developer.apple.com/documentation/storekit/transaction/all)
and RevenueCat's [CustomerInfo](https://www.revenuecat.com/docs/customers/customer-info)
describe their respective evidence sources. The exact source, commands, results and
release limitations are retained in the owner's private revenue verification report.
