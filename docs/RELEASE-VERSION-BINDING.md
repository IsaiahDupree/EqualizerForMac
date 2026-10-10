# Release version and build binding

Sonance's previous source declared version/build in both Xcode settings and literal
Info.plist values. AppFleet passes MARKETING_VERSION and CURRENT_PROJECT_VERSION
when it archives, but literal plist values can retain the old identity. An
incremented setting alone does not establish the identity of the resulting app.

The XcodeGen spec and generated source Info.plist now use `$(MARKETING_VERSION)`
and `$(CURRENT_PROJECT_VERSION)` for those two metadata keys. The source release
baseline is 1.0.7 (10), matching appstore.json. Apple was observed on October 10
with 1.0.6 (9) already on sale and 10 as the next build number. This is source
preparation; it does not create an Apple version or upload a build. AppFleet
rechecks the next available number when a release is authorized.

The existing purchase preflight also verifies the contained metadata source,
those two variable references, and exact manifest/resolved-setting agreement.
Frozen metadata or a conflicting manifest fails before a provider read or a
build/upload handoff. Package metadata must still match its explicit selected
build and the source marketing version. AppFleet validates signing and native
distribution identity separately.

CI compiles a real default Release-MAS app and a second app with a later version
and build. The second version/build is derived from the actual release manifest;
tests require it to differ from the source baseline and inspect the processed
native app metadata and executable. The probes use the host architecture,
disabled signing/optimization and DWARF-only debug information to bound this
metadata check. They do not establish a signed or optimized distribution release.
The normal native and local StoreKit gates remain separate and retain their
existing assertions.

The historical source plist at f18873b is retained with its SHA-256 as an unchanged
negative control under Tools/tests/evidence/version_binding. It is source
evidence, not a new provider response or native distribution artifact. Explicit
compiled-app paths enable the local integration checks; absent artifacts are
reported as skips, never as verified native coverage.

Apple describes [build-setting substitution in the information property
list](https://developer.apple.com/documentation/bundleresources/managing-your-app-s-information-property-list)
and the [version/build settings](https://developer.apple.com/documentation/xcode/build-settings-reference).
The actual processed app remains the acceptance authority.

Purchase receipt-to-Pro, restore/refund, audible hardware acceptance, review and
campaign-to-paid attribution require their own live evidence. Version metadata
does not establish those outcomes.
