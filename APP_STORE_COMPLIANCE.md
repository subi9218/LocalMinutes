# App Store Compliance Notes

Last updated: 2026-05-10

## Build Mode

Default Dart build mode is App Store safe:

```bash
flutter build macos --release --dart-define=APP_STORE_COMPLIANCE_MODE=true
```

Convenience script:

```bash
./scripts/build_app_store.sh
```

The Flutter local release build may be signed with a development identity and
show `com.apple.security.get-task-allow=true` in the generated `.app`. The
source release entitlement explicitly sets it to false. For the final upload,
archive/sign with an Apple Distribution profile in Xcode and run the strict
check:

```bash
STRICT_CODESIGN_CHECK=1 ./scripts/build_app_store.sh
```

## Xcode Archive Verification

Use this script after creating an Apple Developer account, App Store Connect
Bundle ID, and Apple Distribution certificate:

```bash
APPLE_TEAM_ID=ABCDE12345 \
APP_STORE_BUNDLE_ID=com.company.app \
./scripts/archive_app_store.sh
```

What it checks:

- Apple Distribution or Mac App Store signing identity exists locally
- Bundle ID is not `com.example.*`
- Release entitlements file is used
- App Sandbox is enabled
- `get-task-allow` is not true
- Calendar/AppleEvent entitlements are absent
- `LSMinimumSystemVersion` is `15.5`
- Xcode archive app passes `codesign --verify --strict --deep`

Current local machine status:

- `security find-identity -v -p codesigning` returns `0 valid identities found`
- Actual Apple Distribution Archive cannot be completed until the signing
  certificate/team/profile are installed through Xcode.

Internal testing only:

```bash
flutter run -d macos \
  --dart-define=APP_STORE_COMPLIANCE_MODE=false \
  --dart-define=ENABLE_CALENDAR_INTEGRATION=true
```

Internal Calendar testing also requires matching Info.plist usage strings and
AppleEvent/Calendar entitlements. The App Store release files intentionally do
not include them.

## Release Entitlements

`macos/Runner/Release.entitlements` is configured for App Store review:

- App Sandbox: enabled
- Network client: enabled for model downloads and links
- Microphone: enabled for recording
- User-selected read/write files: enabled for user-chosen storage/export paths
- App-scope security bookmarks: enabled for persistent recording folder access
- Calendar entitlement: removed
- AppleEvent temporary exception: removed

Persistent recording folder access is implemented through a Flutter method
channel:

- Dart service: `lib/core/services/security_scoped_bookmark_service.dart`
- Native channel: `app/security_scoped_bookmark`
- macOS host code: `macos/Runner/MainFlutterWindow.swift`

The app stores a security-scoped bookmark when the user selects the recording
folder and attempts to restore it on app startup and before recording starts.
If access cannot be restored, recording start asks the user to reselect the
folder.

## Minimum macOS Version

The app uses `sherpa_onnx_macos 1.12.40`, which bundles
`libonnxruntime.1.24.4.dylib`. That dylib is built with macOS `minos 15.5`, so
the App Store release target is intentionally set to macOS 15.5:

- `macos/Podfile`: `platform :osx, '15.5'`
- `macos/Runner.xcodeproj`: `MACOSX_DEPLOYMENT_TARGET = 15.5`
- `Info.plist`: `LSMinimumSystemVersion` inherits the same build setting

Do not lower the deployment target unless sherpa-onnx/onnxruntime is replaced
with binaries built for the lower target.

## Supported Summary Models

The App Store build supports public distribution summary models only:

- Gemma 4 E2B
- Qwen 2.5 7B Instruct

Unsupported saved `selectedLlmModel` values fall back to Gemma.

## User-Facing License Notice

Settings now includes:

- `라이선스와 개인정보`
- `사용 모델 및 라이선스`

The notice lists local engines/models and their source/license summary:

- whisper.cpp / Whisper models
- llama.cpp
- Gemma
- Qwen 2.5 7B Instruct
- sherpa-onnx

## Privacy Documents

Prepared App Store privacy materials:

- `PRIVACY_POLICY.md`: user-facing privacy policy draft
- `APP_STORE_PRIVACY_ANSWERS.md`: App Store Connect privacy label and review
  notes draft
- `APP_STORE_SUBMISSION_NOTES.md`: copy/paste App Review Notes draft
- `macos/Runner/PrivacyInfo.xcprivacy`: app privacy manifest included in the
  built app resources

Core privacy position:

- Meeting audio, transcripts, summaries, notes, tags, and logs are not uploaded
  to the developer's server.
- AI processing runs on the user's Mac.
- Network is used for user-requested model downloads and external links.
- User-initiated export/share/email actions may pass selected content to the
  destination app or service.

## Remaining Pre-Submission Check

The release build is now safer, but final App Store submission still needs:

- Apple Developer team signing profile
- App Store Connect privacy nutrition labels
- Full legal review of model redistribution/download flow
- App Store-signed QA of persistent custom save folders
- Screenshot capture with non-sensitive demo data
