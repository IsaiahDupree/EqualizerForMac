# RevenueCat configuration for Sonance EQ

The Mac App Store configuration already contains a live public SDK key and the approved
one-time Pro SKU, `com.isaiahdupree.SonanceEQ.pro`. The current read-only public configuration
gate verifies that this SKU maps to `pro` and appears in the selected offering. Configuration
checks do not verify a customer payment or RevenueCat's receipt-to-entitlement processing.
See [the MAS configuration contract](../../docs/MAS-PURCHASE-CONFIGURATION.md).

The v2 setup tool requires an explicitly supplied Sonance project secret in `RC_SECRET_KEY`,
`RC_PROJECT_ID`, and `RC_APP_ID`. Supply credentials through the environment from the approved
secret store; never paste a secret into a command, report, or Git. The tool does not search
other repositories, infer a project from key visibility, select the first App Store app, or
create a missing app. `Tools/asc/env.sh` sets Apple credentials only and preserves an explicitly
supplied RevenueCat environment without replacing it.

With those three variables set:

```bash
python3 Tools/rc/api.py apps
python3 Tools/rc/api.py setup
```

`setup` is a read-only preview. It first verifies the selected app's project, store type and
exact Sonance bundle. It resolves the actual Release-MAS Xcode settings and requires that
public SDK key to appear among the selected app's production keys. It then reads the complete
bounded product, entitlement, offering and package collections. A conflicting app, SKU,
purchase type, duplicate lookup, package eligibility, a different current offering, or selected-app entitlement product
blocks the operation. Shared package products from other apps are retained.

The JSON preview lists concrete pending actions: creating the missing Pro product, `pro`
entitlement, `default` offering or `lifetime` package, and attaching the exact product. A
missing resource in a preview has no invented provider ID. After reviewing the preview, an
operator can explicitly run:

```bash
python3 Tools/rc/api.py setup --apply
```

Apply performs a fresh preflight, rechecks the selected app immediately before each write,
validates returned resource identities, then reads back the entire configuration. Already
attached products do not get attached again. This is a sequence of provider operations, not
an atomic transaction: a timeout or provider failure after a successful write can leave a
partial configuration. A fresh preview shows what remains. No app settings, customers,
attributes, purchases, receipts, prices, deletions or store records are changed by this tool.

All requests use RevenueCat's fixed HTTPS origin. Redirects, foreign-project continuations,
repeated cursors, duplicate identities, malformed or oversized JSON and incomplete collections
block the operation. Limits are 128 KiB per response, 100 rows per page, 20 pages / 2,000 rows
per collection, 12 seconds per request and 90 seconds for the configuration operation. Xcode
settings resolution has its own 30-second bound; the next provider operation also checks the
shared deadline. Provider error bodies and credentials are omitted from output.

The July project note in the old README is historical; the tool requires current explicit
selection and live proof. The available portfolio integration observed on October 9 belongs
to EverReach and is rejected for Sonance even with `--apply`. The committed test captures are
minimal identity projections of that actual foreign configuration, with provenance and
hashes. Tests serve those captures through a real local HTTP listener and label adversarial
mutations separately. No successful Sonance provider write has been exercised without its
project secret. Actual purchase, restore and refund acceptance remain separate release gates.

The dashboard helpers and `set_key.py` are legacy tools, not the canonical release authority.
Use AppFleet for register, sign, archive, upload, VALID processing and attachment; do not ship
a development-store build as a live paid unlock.

API contracts: [apps](https://www.revenuecat.com/docs/api-v2/app),
[products](https://www.revenuecat.com/docs/api-v2/product),
[entitlements](https://www.revenuecat.com/docs/api-v2/entitlement), and
[packages](https://www.revenuecat.com/docs/api-v2/package).
