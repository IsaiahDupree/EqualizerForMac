fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac test

```sh
[bundle exec] fastlane mac test
```

Run the test suite (1,000+ Swift Testing cases)

### mac certificates

```sh
[bundle exec] fastlane mac certificates
```

Create/fetch the Developer ID Application certificate (interactive Apple-ID 2FA the first time; Account Holder only)

### mac build_app

```sh
[bundle exec] fastlane mac build_app
```

Build a Developer ID-signed .app (Release, hardened runtime)

### mac release

```sh
[bundle exec] fastlane mac release
```

Direct distribution: build → notarize → DMG (one command)

### mac appstore

```sh
[bundle exec] fastlane mac appstore
```

Mac App Store: build sandboxed .pkg and upload via the API key

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
