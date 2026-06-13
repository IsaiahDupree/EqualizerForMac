# fastlane — Sonance EQ automation

One-command build / sign / notarize / release for the native macOS app. Complements the plain-shell
scripts in `Tools/` (use whichever you prefer). Full context: [`docs/RELEASE.md`](../docs/RELEASE.md).

## Setup
```bash
brew install fastlane            # already installed here
# Reused account-level App Store Connect API key (the one EverReach uses):
export ASC_API_KEY_ID=<your key id>
export ASC_API_ISSUER_ID=<your issuer id>
export ASC_API_KEY_PATH="$HOME/private_keys/AuthKey_<your key id>.p8"
# Optional (kept out of this public repo):
export FASTLANE_APPLE_ID=<your apple id>
export FASTLANE_TEAM_ID=<your team id>
```

## Lanes
| Command | What it does |
|---------|--------------|
| `fastlane mac test` | regenerate project + run the full Swift Testing suite |
| `fastlane mac certificates` | create/fetch the **Developer ID Application** cert (interactive Apple-ID 2FA the first time; Account Holder only — Apple's rule). If it fails, make it in Xcode and skip this. |
| `fastlane mac build_app` | Developer ID-signed Release `.app` |
| `fastlane mac release` | **build → notarize → DMG** → `build/Sonance-EQ.dmg` (signed, notarized, stapled) |
| `fastlane mac appstore` | sandboxed App Store `.pkg` → upload to App Store Connect via the API key |

## Notes
- **Notarization & App Store upload are fully automated** via the reused API key — no passwords.
- **Developer ID cert creation is the one step Apple keeps interactive** (Account-Holder Apple-ID + 2FA).
  Everything after it is one command.
- The Mac App Store path (`appstore`) builds the sandboxed / public-permission variant; per
  `docs/RESEARCH.md` it's the #1 rejection risk (system capture under sandbox is unproven) — lead with
  `release` (Direct).
