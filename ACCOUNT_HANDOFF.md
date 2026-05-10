# Account Handoff — LocalMinutes / 적자생존

Last updated: 2026-05-10

This document is for continuing App Store submission work from another Apple/GitHub account or another AI assistant.

## Current Repository

- Local path: `/Users/channy/LocalMinutes`
- GitHub repo: `https://github.com/subi9218/LocalMinutes`
- Branch: `main`
- Current git state at handoff: local App Store risk-reduction changes are pending commit
- Important: a GitHub PAT was pasted in chat during setup. If still active, revoke it when no longer needed.

## Completed So Far

### Git / GitHub

- Initialized Git in `/Users/channy/LocalMinutes`.
- Added remote:
  - `origin https://github.com/subi9218/LocalMinutes.git`
- Created initial import commit with source, docs, scripts, macOS project, tests, and native wrapper dylibs.
- Excluded large/generated artifacts via `.gitignore`:
  - `build/`
  - `.dart_tool/`
  - `dist/`
  - `exports/`
  - root `*.dmg`
  - native third-party checkouts/build folders (`native/llama.cpp`, `native/whisper.cpp`, `native/build*`, `native/whisper_build`)
- Pushed all work to GitHub.

Recent pushed commits:

```text
1b7cdbb Document Apple Developer enrollment blocker
b742823 Mark public support pages ready
99d1945 Prepare App Store metadata
1b3a93a Merge remote initial commit
fc1a6a7 Initial import
```

### GitHub Pages

GitHub Pages is enabled from:

- Branch: `main`
- Folder: `/docs`

Public URLs verified with HTTP 200:

- Privacy Policy: `https://subi9218.github.io/LocalMinutes/privacy.html`
- Support: `https://subi9218.github.io/LocalMinutes/support.html`

### Bundle ID / App Store Metadata

Chosen App Store Bundle ID:

```text
com.subi9218.localminutes
```

Updated:

- `macos/Runner/Configs/AppInfo.xcconfig`
  - `PRODUCT_BUNDLE_IDENTIFIER = com.subi9218.localminutes`
  - `PRODUCT_COPYRIGHT = Copyright © 2026 subi9218. All rights reserved.`
- `macos/Runner.xcodeproj/project.pbxproj`
  - RunnerTests bundle IDs changed to `com.subi9218.localminutes.RunnerTests`
- `APP_STORE_METADATA_KO.md`
  - Privacy/Support URLs updated
- `APP_STORE_SUBMISSION_NOTES.md`
  - Privacy URL updated
- `CODEX_TODO.md`
  - Bundle ID and public URL tasks marked/annotated
- `test/diagnostic_export_test.dart`
  - Mock package name changed to `com.subi9218.localminutes`

### Local Verification

Commands run successfully after moving the project to `/Users/channy/LocalMinutes` and after the latest App Store risk-reduction changes:

```bash
flutter analyze
flutter test
flutter build macos --debug
```

Results:

- `flutter analyze`: no issues
- `flutter test`: all tests passed (`90/90`)
- `flutter build macos --debug`: succeeded
  - Built app: `build/macos/Build/Products/Debug/적자생존.app`
- `macos/Runner/PrivacyInfo.xcprivacy`: included in built app resources

Note: the first debug build after folder migration failed because stale Flutter/Xcode files still referenced `/Users/channy/meeting_assistant2`. Running `flutter clean` fixed it.

## Apple Developer Status

At the time this handoff was written:

- The user said Apple Developer registration was done or in progress.
- Earlier access to Certificates/Identifiers/Profiles showed:

```text
Access Unavailable
```

- Local machine still had no valid signing identities:

```bash
security find-identity -v -p codesigning
```

returned:

```text
0 valid identities found
```

If using another Apple account, repeat the certificate setup under that account.

## Next Required Apple Account Steps

### 1. Confirm Apple Developer Program Enrollment

Check:

- `https://developer.apple.com/account`
- `https://developer.apple.com/account#MembershipDetailsCard`

Ready when:

- Certificates, Identifiers & Profiles is accessible
- Team ID is visible
- Xcode Accounts shows the Team

### 2. Register Bundle ID

In Apple Developer > Certificates, Identifiers & Profiles:

- Type: App ID
- Platform: macOS
- Bundle ID type: Explicit
- Bundle ID:

```text
com.subi9218.localminutes
```

If using a different developer account/brand, choose a new stable Bundle ID and update the repo accordingly.

### 3. Create App Store Connect App

In App Store Connect:

- Platform: macOS
- App name: `적자생존`
- Bundle ID: `com.subi9218.localminutes`
- SKU suggestion:

```text
localminutes-macos-001
```

- Primary language: Korean
- Price plan: paid app, Korea price `19,000원`

Paid app setup also requires:

- Paid Apps Agreement
- Tax information
- Banking information

### 4. Create Apple Distribution Certificate

In Xcode:

1. Xcode > Settings > Accounts
2. Add/sign in with the Apple Developer account
3. Select Team
4. Manage Certificates
5. `+`
6. Create `Apple Distribution`

Verify:

```bash
security find-identity -v -p codesigning
```

Expected: at least one `Apple Distribution` identity.

### 5. Run App Store Archive Script

After Team ID and Apple Distribution certificate are ready:

```bash
cd /Users/channy/LocalMinutes

APPLE_TEAM_ID=<TEAM_ID> \
APP_STORE_BUNDLE_ID=com.subi9218.localminutes \
./scripts/archive_app_store.sh
```

This script checks:

- `flutter analyze`
- `flutter test`
- macOS deployment target `15.5`
- Release entitlements
- App sandbox enabled
- `get-task-allow=false`
- no Calendar/AppleEvent entitlement
- archive Bundle ID

## App Store Review Risk Notes

The latest review pass found no obvious fatal App Store blocker in release entitlements. The two main code risks previously identified were addressed locally and still need App Store-signed QA once certificates are ready.

### Model Download Flow

Previous risk:

- The setup screen could show Hugging Face token UI with copy implying a token was required for the summary model.

Current state:

- `lib/presentation/screens/setup_screen.dart`
- `lib/core/services/model_download_service.dart`

- App Store compliance mode hides the token input and custom download URL UI by default.
- The "token required" wording was removed.
- Public Hugging Face/GitHub model URLs were checked with unauthenticated range requests.
- Still test the in-app download flow before upload.

### Sandbox Persistent Folder Access

Previous risk:

- Storage selection stored only the folder path, so sandbox access could be lost after relaunch.

Current state:

- `lib/presentation/screens/storage_setup_screen.dart`
- `lib/core/services/app_settings.dart`
- `lib/core/services/security_scoped_bookmark_service.dart`
- `macos/Runner/MainFlutterWindow.swift`

Release entitlements include app-scope bookmarks:

- `macos/Runner/Release.entitlements`

- The app now stores/restores a security-scoped bookmark for the selected recording folder.
- If restore fails, recording start asks the user to reselect the save folder.
- Still test with an App Store-signed/sandboxed build:
  - choose save folder
  - record
  - quit app
  - reopen
  - record again to the same folder

### Privacy Manifest

- Added `macos/Runner/PrivacyInfo.xcprivacy`.
- It declares no tracking and no collected data.
- It includes the UserDefaults required reason entry used by `shared_preferences`.
- The manifest was verified as included in the built app resources.

### Calendar / AppleEvent

Calendar AppleScript code exists:

- `lib/core/services/calendar_service.dart`

But it is gated by:

- `AppBuildConfig.enableCalendarIntegration == false` in App Store mode

Release entitlements do not include Calendar/AppleEvent permissions.

Keep archive builds using:

```text
APP_STORE_COMPLIANCE_MODE=true
```

### EXAONE Restricted Model

EXAONE references remain in code for internal builds, but App Store mode hides/blocks them:

- `AppBuildConfig.allowRestrictedModels`
- `AppSettings.availableLlmModelIds`
- setup/settings UI conditionals
- compliance tests

Do not enable `ALLOW_RESTRICTED_MODELS=true` for App Store builds.

## Useful Commands

```bash
cd /Users/channy/LocalMinutes

git status --short --branch
flutter analyze
flutter test
flutter build macos --debug

security find-identity -v -p codesigning

APPLE_TEAM_ID=<TEAM_ID> \
APP_STORE_BUNDLE_ID=com.subi9218.localminutes \
./scripts/archive_app_store.sh
```

## Files To Read First

- `CODEX_TODO.md`
- `APP_STORE_METADATA_KO.md`
- `APP_STORE_PRIVACY_ANSWERS.md`
- `APP_STORE_SUBMISSION_NOTES.md`
- `APP_STORE_COMPLIANCE.md`
- `APP_STORE_PREP_CHECKLIST.md`
- `AI_HANDOFF.md`
- `NEXT_AI_TASKS.md`
