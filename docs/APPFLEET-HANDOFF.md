# Sonance's AppFleet handoff

The former `Tools/asc/pipeline.py` built `build/mas/SonanceEQ.pkg` and then uploaded
`build/appstore/SonanceEQ.pkg`. It also built from a hardcoded primary checkout.
`Tools/ship.sh upload` used the same inconsistent package path. A missing file could stop the
release, and a stale file at the other path could be selected. These are observed source defects;
they do not establish that a past store release uploaded the wrong binary.

Both entry points now use `Tools/asc/pipeline.py` as a thin adapter to the canonical
`AppFleet/appstore_pipeline.py`. The app repository is the checkout containing the adapter.
The adapter never implements Apple registration, signing, building, upload, processing or
attachment. Those remain in AppFleet. The canonical path defaults to the owner's Software
workspace; `APPFLEET_PIPELINE` may explicitly select an absolute installed AppFleet path.

```bash
Tools/ship.sh                         # read-only AppFleet doctor
Tools/ship.sh status --json           # read-only live Apple state
Tools/ship.sh ship                    # inspect a source-release command
Tools/ship.sh all                     # same preview; compatibility name
Tools/ship.sh ship --yes              # canonical full native release

Tools/ship.sh upload --artifact /absolute/path/to/SonanceEQ.pkg --build-number 9
Tools/ship.sh upload --artifact /absolute/path/to/SonanceEQ.pkg --build-number 9 --yes
```

The source command pins Sonance's scheme, bundle, Mac platform and Release-MAS configuration.
`ship` and `all` preview by default. `upload` requires an explicit existing `.pkg` and exact
positive numeric build; it never falls back to a package in another directory. Read-only
doctor/status reject write or artifact options. The shell entry works outside a Git checkout.
The adapter does not offer dirty-source or skip-attachment overrides.

Release previews resolve the real Xcode settings and require the live public SDK key, sandbox,
hardened runtime and public permission configuration. Existing-package previews expand the
actual Apple package without installing it, require one main app and contained metadata,
and compare its bundle, version, explicit build and embedded SDK key to those settings. The
package size limit is 256 MiB; package extraction has a 60-second bound. Digests are checked
before and after inspection. Preview deliberately reports distribution signing as unverified.
It is a plan and metadata check, not proof of a signed release or a customer payment.

For an authorized source release, AppFleet's existing generation helper prepares the selected
Xcode project before the purchase preflight. Dirty source fails that canonical generation gate.
Before delegation with `--yes`, the adapter also checks current RevenueCat public configuration
for the exact Pro product, `pro` entitlement and eligible offering. The configuration probe
does not read customers or receipts. AppFleet then revalidates the repository and actual
artifact signatures/team/profiles/version/build before Apple writes. It owns the single upload
lock, duplicate-VALID detection, processing wait and exact-version attachment. That sequence
does not submit the app for review or establish public distribution.

The old `provision`, `app`, `build`, `meta`, `web`, `finalize`, `audit` and `submit` stages are
no longer supported by this entry point. Their purpose-specific source files remain available;
listing, IAP, pricing, privacy and review work require their own exact-app evidence and scope.
In particular, the adapter does not automatically set a free price or declare no data collection.
The older `Tools/build_mas.sh` still exports into `build/mas`; when reusing such a package, name
that exact file explicitly. AppFleet is the preferred complete native-release path.

Local acceptance used a genuine unsigned `productbuild` package made from the retained
Sonance 1.0.6 (9) compile candidate, plus an actual retained foreign-app Apple package. The
Sonance package passes purchase-metadata comparison and fails AppFleet's actual signature
check. This tests the boundary without uploading, installing, charging or fabricating a provider
response. The package integration tests require the real AppFleet checkout and explicit local
artifact paths; CI skips those when the prerequisites are absent. The command-plan tests remain
active in CI. No successful signed Sonance upload or purchase acceptance is claimed here.
