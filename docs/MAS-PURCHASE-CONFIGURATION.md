# Sonance App Store purchase configuration

`Tools/submit_appstore.sh` previously archived `Release`. That configuration has
an empty RevenueCat key and selects the existing development store. The script
now archives `Release-MAS`, preserving its live public key, sandbox, hardened
runtime and public audio-permission configuration. Both shell builders and the
fastlane App Store lane stop on a failed configuration check. Xcode generation
errors also stop fastlane instead of silently building a stale project.

The shared read-only check resolves the actual SonanceEQ target through Xcode,
requires `Release-MAS`, the exact bundle, a live app-specific public SDK key,
the MAS entitlements with sandbox/network access, and no `ENABLE_TCC_SPI` flag.
It reads RevenueCat's product-entitlement mapping and offerings using that
resolved public key. Only the configured Pro SKU granting `pro` and an
unambiguous current or named-default package are accepted. Requests use fixed
HTTPS endpoints, no redirects or retries, a 128 KiB body limit and a 12-second
total deadline per read; Xcode settings have a 30-second subprocess deadline.
No secret key or unrelated project's credential is searched or loaded.

```bash
xcodegen generate
python3 Tools/verify_mas_purchase_config.py
python3 Tools/verify_mas_purchase_config.py \
  --app build/SonanceEQ-MAS.xcarchive/Products/Applications/SonanceEQ.app --metadata-only
```

The post-archive check compares the app's bundle, executable name, version,
build and embedded public key against the resolved MAS settings before shell
export or fastlane upload. It does not assert the archive's signature,
provisioning, compiled permission behavior or package identity. AppFleet's
distribution checks and current-build device acceptance remain independent.
These builders perform no upload during the check; invoking a build/upload
script still requires the owner's existing release authorization.

The offerings read uses a fresh, explicitly named configuration-probe identifier.
It does not read customer information, purchase, restore, upload a receipt,
change offerings or entitlements, or set attributes. Its selected offering is
configuration evidence for that probe, not acceptance of customer-specific
targeting or experiments. RevenueCat documents that an identifier need not
already exist for an offerings read.

An October 9 Eastern live read returned `default` / `lifetime` /
`com.isaiahdupree.SonanceEQ.pro`, with that exact product attached to `pro`.
The two non-identifying response bodies in `Tools/tests/evidence` are actual
captures; their dated provenance and hashes are retained alongside them.
Tests apply explicitly adversarial mutations to those captures, serve the
retained bytes through real loopback HTTP, and read actual Xcode settings.
They do not invent provider/customer/transaction data.

```bash
python3 -m unittest discover -s Tools/tests -p test_mas_purchase_config.py -v
# Include the actual compiled-app metadata checks when available:
SONANCE_PURCHASE_GATE_TEST_APP=/absolute/path/to/SonanceEQ.app \
  python3 -m unittest discover -s Tools/tests -p test_mas_purchase_config.py -v
```

The test-only aiohttp dependency runs a bounded loopback server; the production
checker uses the Python standard library. CI creates an isolated environment.
Missing Xcode or an unsupplied compiled app is an explicit test skip. Live
distribution checks never substitute the retained capture for a provider read.

Configuration success is not a verified payment, current StoreKit price,
RevenueCat receipt-to-entitlement acceptance, installed App Store build,
campaign conversion or operating profit. Those fields stay unverified in the
machine-readable result. Local StoreKit purchase/restore/refund tests remain
required and independent; no new native purchase was made in this repair.

Primary sources: [RevenueCat offerings API](https://www.revenuecat.com/docs/api-v1/offerings),
[app-specific SDK configuration](https://www.revenuecat.com/docs/getting-started/configuring-sdk),
and RevenueCat's installed 5.91.0 `GetProductEntitlementMappingOperation` /
`ProductEntitlementMappingResponse` sources for the mapping endpoint and schema.
