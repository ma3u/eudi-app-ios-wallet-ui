# Hackathon — Build, Debug & TestFlight Runbook

Working notes for getting `ma3u/eudi-app-ios-wallet-ui` building on **Xcode 26.5**, debuggable on
device, and onto **TestFlight** for internal testers. Companion to the EUDI hackathon plan in the
[health-dataspace repo](https://github.com/ma3u/MinimumViableHealthDataspacev2/blob/main/docs/planning/eudi-wallet-hackathon-2026.md).

## What was fixed on this branch

| # | File | Problem | Fix |
| - | ---- | ------- | --- |
| 1 | `EudiReferenceWallet.xcodeproj/project.pbxproj` | The **"Swift Lint" build phase** ran `swiftlint --fix && swiftlint`; SwiftLint 0.63.3 (vs the project's pinned 0.48.0) returns non-zero → **build fails** and leaves the `.app` incomplete. | Neutralised the phase (echo a note; no `--fix`, no failure). Re-enable + pin for production. |
| 2 | `Modules/logic-ui/.../Input/PinTextFieldView.swift` | Empty PIN positions rendered `Image(systemName: "")` → SwiftUI **`No symbol named '' found`** fault spamming ~2×/sec on the PIN screen. | Render a `Color.clear` placeholder for empty positions. |
| 3 | `Modules/logic-storage/Sources/Service/SwiftDataService.swift` | The `actor` created its `ModelContext` in `init` (caller/main thread) and used it on the actor's executor → SwiftData **"instantiated on the main queue but is being used off it … not Sendable"** (crash risk on Swift 6 / iOS 26). | Create a fresh per-call `ModelContext(container)` inside each actor method, bound to the actor. |
| 4 | `fastlane/Fastfile` | `build_app(include_bitcode: true)` — **bitcode was removed** in modern Xcode; this fails the TestFlight build/upload. | `include_bitcode: false`. |

**Verified:** builds clean on Xcode 26.5, runs on the iPhone 17 simulator (Debug Demo), and both
runtime faults are gone (0 occurrences post-launch; app no longer crashes/spams).

## 1. Build for the simulator (no signing)

```bash
xcodebuild -project EudiReferenceWallet.xcodeproj \
  -scheme "EUDI Wallet Demo" -configuration "Debug Demo" \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath .build-dd -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO build
```

Install/launch on a booted sim:

```bash
xcrun simctl install booted ".build-dd/Build/Products/Debug Demo-iphonesimulator/EudiWallet.app"
xcrun simctl launch booted eu.europa.ec.euidi
```

## 2. Debug on a physical iPhone (full lldb)

1. Open `EudiReferenceWallet.xcodeproj` in Xcode.
2. Target **EudiWallet → Signing & Capabilities**: set **Team = your Apple Developer account** and a
   **unique Bundle Identifier you own** (e.g. `red.mabu.ehds.wallet`). You **cannot** ship under
   `eu.europa.ec.euidi` — that's the EU's id and won't sign/upload to your account.
3. Scheme **"EUDI Wallet Demo" (Debug Demo)** → select your connected iPhone → **Run (⌘R)**: full
   breakpoints / lldb.
4. If the **Document Provider** extension complains about app groups / keychain groups, see
   `wiki/CONFIGURATION.md` (`SHARED_APP_GROUP_IDENTIFIER`). Automatic signing manages these per team.

## 3. TestFlight (internal testers) — you run the upload

**Prerequisites (your Apple account):**
- A unique **bundle id** registered to your team + an **App Store Connect app record** for it.
- An **App Store Connect API key** (`.p8`) → Key ID, Issuer ID, key-file path.
- A **distribution provisioning profile** for that bundle id (or Xcode-managed signing).
- `bundle install` (installs fastlane from the repo `Gemfile`).

**Run the `deploy` lane:**

```bash
export APP_PROJECT="EudiReferenceWallet.xcodeproj"
export APP_SCHEME="EUDI Wallet Demo"
export APP_BUILD_TYPE="DEMO"
export APP_TARGETS="EudiWallet"
export APP_VERSION_CONFIG="Wallet/Config/WalletDemoRelease.xcconfig"
export APP_BUNDLE_ID="red.mabu.ehds.wallet"          # your bundle id
export APP_PROVISION_PROFILE="<your distribution profile name>"
export APP_IPA_PATH="EudiWallet.ipa"
export TESTFLIGHT_GROUPS="Internal Testers"          # an existing TestFlight group
export CONNECT_KEY_ID="<ASC key id>"
export CONNECT_ISSUER_ID="<ASC issuer id>"
export CONNECT_KEY_PATH="$PWD/AuthKey_<keyid>.p8"

bundle exec fastlane ios deploy
```

The lane builds (`export_method: app-store`), uploads to TestFlight via `pilot`
(`skip_submission: false` → distributed to the internal group), bumps the build number and tags.
**dSYMs are produced** (Release = `dwarf-with-dsym`) and uploaded, so crash reports symbolicate in
App Store Connect / Xcode Organizer.

**No-fastlane fallback:** Xcode → **Product → Archive** (scheme *EUDI Wallet Demo*, *Release Demo*)
→ **Organizer → Distribute App → TestFlight Internal Only**.

## 4. Debuggability of TestFlight builds

TestFlight builds are **Release** (optimized): you get **symbolicated crash reports** (dSYMs uploaded),
not live stepping. For step-through debugging use the Xcode device Run (§2). Add `OSLog` /
`os_signpost` for field diagnostics if needed.

## Caveats / re-enable for production

- SwiftLint is disabled in the build phase for the hackathon — re-enable and pin a version
  (`brew install swiftlint`, set `swiftlint_version` in `.swiftlint.yml`) before production.
- The fixes target **Demo** (stable `issuer.eudiw.dev`). Point at the **SPRIND sandbox** / your
  Keycloak per the hackathon plan when ready.
- Bundle id + signing must be **yours**.
