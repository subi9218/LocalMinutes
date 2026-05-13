# Account Handoff — LocalMinutes / Local Minutes

Last updated: 2026-05-12

This document is for continuing App Store submission work from another Apple/GitHub account or another AI assistant.

## Current Repository

- Local path: `/Users/channy/LocalMinutes`
- GitHub repo: `https://github.com/subi9218/LocalMinutes`
- Branch: `main`
- Latest local commit: `9d41be9 Prepare App Store submission build`
- Bundle ID for App Store: `com.subi9218.localminutes`
- Current app version: `2.1.1+28`
- Important: a GitHub PAT was pasted in chat during earlier setup. If still active, revoke it.

## Current Working Tree

Current status:

- `git status --short`: clean
- Latest changes are committed in `9d41be9`.
- Push is still needed if the other account will continue from GitHub.

Major changes included in `9d41be9`:

- Removed all EXAONE-related source/test references and App Store submission wording.
- Removed `ALLOW_RESTRICTED_MODELS` / `allowRestrictedModels`.
- Simplified supported summary models to Gemma 4 E2B and Qwen 2.5 7B Instruct.
- Updated setup/settings/recording/detail/model selection flows and compliance tests.
- Renamed the internal Dart package to `local_minutes`.
- Renamed the macOS bundle executable to `LocalMinutes`; user-facing app name is now `Local Minutes`.
- Improved recording-related UI:
  - “회의 유형 / 재생성 스타일” dialog is wider/two-column.
  - “녹음 진행 중” sidebar banner returns to the recording screen.
  - “녹음 준비” dialog keeps the start/cancel buttons visible in small windows.
- Cleaned App Store submission docs for paid-app first release.
- Changed model download 401/403 wording so App Store users are not told to enter a Hugging Face token.

Verification run after these changes:

```bash
flutter analyze
flutter test
flutter build macos
```

Results:

- `flutter analyze`: no issues
- `flutter test`: all tests passed (`89/89`)
- `flutter build macos`: success, output `build/macos/Build/Products/Release/Local Minutes.app`

Code/doc search after removal:

```bash
rg -n "exaone|EXAONE|ALLOW_RESTRICTED|allowRestrictedModels|restrictedModel|llmExaone|summaryRestricted" lib test macos scripts pubspec.yaml APP_STORE_*.md PRIVACY_POLICY.md docs/privacy.html
```

Expected: no matches.

## Product / Pricing Direction

Use the paid-app path for the first App Store submission:

```text
App download: paid
Korea price: 19,000원
IAP/subscriptions: none for first release
```

The code currently matches this better than freemium:

- `EntitlementService.currentTier` still returns `EntitlementTier.pro`.
- There is no StoreKit / `in_app_purchase` implementation.
- There is no restore purchases UI.

Do not submit as “Free + Pro Unlock” unless the freemium implementation is completed first.

## Completed App Store Prep

### Public URLs

GitHub Pages is enabled from branch `main`, folder `/docs`.

Public URLs previously verified:

- Privacy Policy: `https://subi9218.github.io/LocalMinutes/privacy.html`
- Support: `https://subi9218.github.io/LocalMinutes/support.html`

### Bundle ID / Metadata

Chosen Bundle ID:

```text
com.subi9218.localminutes
```

Relevant files:

- `macos/Runner/Configs/AppInfo.xcconfig`
- `macos/Runner.xcodeproj/project.pbxproj`
- `APP_STORE_CONNECT_COPY.md`
- `APP_STORE_METADATA_KO.md`
- `APP_STORE_SUBMISSION_NOTES.md`

### Release Entitlements

`macos/Runner/Release.entitlements` is configured for App Store review:

- App sandbox: enabled
- Network client: enabled, for model downloads
- Audio input: enabled, for recording
- User-selected file read/write: enabled
- App-scope bookmarks: enabled, for persistent selected recording folder
- Calendar/AppleEvent entitlements: absent

Archive script checks these again.

## Apple Developer Account Steps

### 1. Confirm Apple Developer Program Enrollment

Check:

- `https://developer.apple.com/account`
- `https://developer.apple.com/account#MembershipDetailsCard`

Ready when:

- Certificates, Identifiers & Profiles is accessible
- Team ID is visible
- Xcode Accounts shows the Team

### 2. Register Bundle ID

Apple Developer > Certificates, Identifiers & Profiles:

- Type: App ID
- Platform: macOS
- Bundle ID type: Explicit
- Bundle ID:

```text
com.subi9218.localminutes
```

### 3. Create App Store Connect App

In App Store Connect:

- Platform: macOS
- App name: `Local Minutes`
- Bundle ID: `com.subi9218.localminutes`
- SKU suggestion: `localminutes-macos-001`
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

## Remaining App Review / Submission Risks

### 1. Submission Docs Cleaned

App Store submission docs no longer use removed model / restricted model / NC license-risk wording. Keep App Review Notes simple:

```text
App Store build supports public distribution models only: Whisper, Gemma, Qwen, and sherpa-onnx.
Calendar/AppleEvent automation is not included in the App Store build.
```

Do not add removed model, restricted model, or NC license-risk wording back into App Review Notes.

### 2. Model Download 401/403 Wording Cleaned

`lib/core/services/model_download_service.dart` no longer tells App Store users to enter a Hugging Face token on 401/403. It now asks users to check the model provider page and access conditions.

### 3. Main Remaining Blocker: Apple Developer Account / Signing

The codebase is ready for the next signing step, but App Store upload is blocked until the new Apple Developer account is ready:

- Apple Developer Program enrollment approved
- Team ID available
- Paid Apps Agreement accepted
- Tax and banking information completed
- Apple Distribution certificate installed in Xcode
- App Store Connect app record created for `com.subi9218.localminutes`

Run:

```bash
security find-identity -v -p codesigning
```

Expected before archive work: at least one valid `Apple Distribution` identity.

### 4. Sandbox Folder Access Needs App Store-Signed QA

Relevant files:

- `lib/presentation/screens/storage_setup_screen.dart`
- `lib/core/services/app_settings.dart`
- `lib/core/services/security_scoped_bookmark_service.dart`
- `macos/Runner/MainFlutterWindow.swift`
- `macos/Runner/Release.entitlements`

Test with an App Store-signed/sandboxed build:

1. Choose recording save folder.
2. Record one meeting.
3. Quit app.
4. Reopen app.
5. Record again to the same folder.
6. Export Markdown/PDF/DOCX.

### 5. Privacy / Diagnostics Explanation

Privacy manifest says no tracking and no collected data.

This is consistent with local-only processing if:

- Meeting audio/transcripts/summaries are not automatically uploaded.
- Diagnostic ZIP export remains user-initiated.

In Review Notes, say:

```text
The app does not upload meeting audio, transcripts, summaries, or diagnostics to developer servers.
Diagnostic export is manual and user-initiated only.
```

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

## Suggested Next Steps For Another Account

1. Push `main` so the other account can pull commit `9d41be9`.
2. Confirm Apple Developer Program enrollment and Team ID.
3. Create the explicit macOS Bundle ID `com.subi9218.localminutes`.
4. Create the App Store Connect app record:
   - Name: `Local Minutes`
   - SKU: `localminutes-macos-001`
   - Price: paid app, Korea `19,000원`
   - IAP/subscription: none
5. Install/create Apple Distribution certificate in Xcode.
6. Run `./scripts/archive_app_store.sh` with `APPLE_TEAM_ID` and `APP_STORE_BUNDLE_ID`.
7. Perform App Store-signed QA, especially folder bookmark persistence and model downloads.

## Files To Read First

- `ACCOUNT_HANDOFF.md`
- `CODEX_TODO.md`
- `APP_STORE_CONNECT_COPY.md`
- `APP_STORE_METADATA_KO.md`
- `APP_STORE_PRIVACY_ANSWERS.md`
- `APP_STORE_SUBMISSION_NOTES.md`
- `APP_STORE_PREP_CHECKLIST.md`
- `APP_STORE_COMPLIANCE.md`
