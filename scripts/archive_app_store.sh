#!/usr/bin/env bash
# Create and verify an App Store-signed macOS archive.
#
# Required environment:
#   APPLE_TEAM_ID        Apple Developer Team ID, e.g. ABCDE12345
#   APP_STORE_BUNDLE_ID  App Store Connect bundle id, e.g. com.company.app
#
# Optional:
#   ARCHIVE_PATH         Output .xcarchive path
#   SKIP_TESTS=1         Skip analyze/test preflight
#   CODE_SIGN_STYLE      Automatic or Manual. Defaults to Manual for distribution.
#   CODE_SIGN_IDENTITY   Optional manual signing identity SHA-1 or name.
#                        Defaults to the first non-revoked Apple Distribution identity.
#   CODE_SIGN_TIMEOUT_SECONDS
#                        Private-key signing smoke-test timeout. Defaults to 20.

set -euo pipefail

APP_NAME="Local Minutes"
WORKSPACE="macos/Runner.xcworkspace"
SCHEME="Runner"
CONFIGURATION="Release"
MIN_MACOS_VERSION="15.5"
ARCHIVE_PATH="${ARCHIVE_PATH:-build/macos/archive/${APP_NAME}.xcarchive}"
ARCHIVED_APP="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
ARCHIVE_DSYMS="${ARCHIVE_PATH}/dSYMs"
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Manual}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
CODE_SIGN_TIMEOUT_SECONDS="${CODE_SIGN_TIMEOUT_SECONDS:-20}"

log() { echo "[archive] $*"; }
fail() { echo "[archive][error] $*" >&2; exit 1; }

if [ ! -f "pubspec.yaml" ]; then
  fail "프로젝트 루트에서 실행하세요: ./scripts/archive_app_store.sh"
fi

if [ -z "${APPLE_TEAM_ID:-}" ]; then
  fail "APPLE_TEAM_ID가 필요합니다. 예: APPLE_TEAM_ID=ABCDE12345 APP_STORE_BUNDLE_ID=com.company.app ./scripts/archive_app_store.sh"
fi

if [ -z "${APP_STORE_BUNDLE_ID:-}" ]; then
  fail "APP_STORE_BUNDLE_ID가 필요합니다. App Store Connect에 등록한 Bundle ID를 넣어주세요."
fi

if [[ "${APP_STORE_BUNDLE_ID}" == com.example.* ]]; then
  fail "com.example.* Bundle ID는 App Store 제출용으로 사용할 수 없습니다: ${APP_STORE_BUNDLE_ID}"
fi

log "Apple Distribution 인증서 확인"
SIGNING_IDENTITIES="$(security find-identity -v -p codesigning)"
if ! echo "${SIGNING_IDENTITIES}" | grep -E "Apple Distribution|3rd Party Mac Developer Application" | grep -vq "CSSMERR"; then
  fail "유효한 Apple Distribution 인증서를 찾지 못했습니다. Xcode > Settings > Accounts에서 인증서를 먼저 준비하세요."
fi
if [ -z "${CODE_SIGN_IDENTITY}" ]; then
  CODE_SIGN_IDENTITY="$(echo "${SIGNING_IDENTITIES}" | awk '/Apple Distribution|3rd Party Mac Developer Application/ && $0 !~ /CSSMERR/ { print $2; exit }')"
fi
[ -n "${CODE_SIGN_IDENTITY}" ] || fail "사용할 Apple Distribution signing identity를 결정하지 못했습니다."

log "Apple Distribution 개인키 접근 확인: ${CODE_SIGN_IDENTITY}"
SIGN_TEST_DIR="$(mktemp -d)"
SIGN_TEST_BIN="${SIGN_TEST_DIR}/echo"
cp /bin/echo "${SIGN_TEST_BIN}"
SIGN_TEST_ERR="${SIGN_TEST_DIR}/codesign.err"
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY}" --timestamp=none "${SIGN_TEST_BIN}" 2>"${SIGN_TEST_ERR}" &
SIGN_TEST_PID=$!
SIGN_TEST_DONE=0
for _ in $(seq 1 "${CODE_SIGN_TIMEOUT_SECONDS}"); do
  if ! kill -0 "${SIGN_TEST_PID}" 2>/dev/null; then
    SIGN_TEST_DONE=1
    break
  fi
  sleep 1
done
if [ "${SIGN_TEST_DONE}" != "1" ]; then
  kill -TERM "${SIGN_TEST_PID}" 2>/dev/null || true
  for _ in 1 2 3; do
    if ! kill -0 "${SIGN_TEST_PID}" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  if kill -0 "${SIGN_TEST_PID}" 2>/dev/null; then
    kill -KILL "${SIGN_TEST_PID}" 2>/dev/null || true
  fi
  wait "${SIGN_TEST_PID}" >/dev/null 2>&1 || true
  rm -rf "${SIGN_TEST_DIR}"
  fail "Apple Distribution 개인키 접근이 ${CODE_SIGN_TIMEOUT_SECONDS}초 안에 완료되지 않았습니다. Keychain Access에서 Apple Distribution 개인키 접근 권한에 codesign/Xcode를 허용한 뒤 다시 실행하세요."
fi
if ! wait "${SIGN_TEST_PID}"; then
  SIGN_TEST_OUTPUT="$(cat "${SIGN_TEST_ERR}" 2>/dev/null || true)"
  rm -rf "${SIGN_TEST_DIR}"
  fail "Apple Distribution 개인키 서명 테스트 실패: ${SIGN_TEST_OUTPUT}"
fi
rm -rf "${SIGN_TEST_DIR}"

log "Release 설정 확인"
grep -q "platform :osx, '${MIN_MACOS_VERSION}'" macos/Podfile ||
  fail "Podfile platform이 macOS ${MIN_MACOS_VERSION}가 아닙니다"
grep -q "MACOSX_DEPLOYMENT_TARGET = ${MIN_MACOS_VERSION};" macos/Runner.xcodeproj/project.pbxproj ||
  fail "Runner deployment target이 macOS ${MIN_MACOS_VERSION}가 아닙니다"
grep -q "CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;" macos/Runner.xcodeproj/project.pbxproj ||
  fail "Release entitlements 설정을 찾지 못했습니다"

if [ "${SKIP_TESTS:-0}" != "1" ]; then
  log "정적 분석"
  flutter analyze

  log "테스트"
  flutter test
fi

log "기존 archive 제거: ${ARCHIVE_PATH}"
rm -rf "${ARCHIVE_PATH}"
mkdir -p "$(dirname "${ARCHIVE_PATH}")"

DART_DEFINE_APP_STORE="$(printf 'APP_STORE_COMPLIANCE_MODE=true' | base64 | tr -d '\n')"

log "Xcode archive 생성"
XCODEBUILD_ARGS=(
  archive
  -workspace "${WORKSPACE}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination "generic/platform=macOS"
  -archivePath "${ARCHIVE_PATH}"
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID}"
  PRODUCT_BUNDLE_IDENTIFIER="${APP_STORE_BUNDLE_ID}"
  CODE_SIGN_STYLE="${CODE_SIGN_STYLE}"
  DART_DEFINES="${DART_DEFINE_APP_STORE}"
)
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
  XCODEBUILD_ARGS+=(CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}")
fi
xcodebuild "${XCODEBUILD_ARGS[@]}"

if [ ! -d "${ARCHIVED_APP}" ]; then
  fail "archive 안에서 앱을 찾지 못했습니다: ${ARCHIVED_APP}"
fi

log "누락되기 쉬운 native dSYM 보강"
mkdir -p "${ARCHIVE_DSYMS}"
FRAMEWORKS_DIR="${ARCHIVED_APP}/Contents/Frameworks"
NATIVE_SYMBOL_TARGETS=(
  "${FRAMEWORKS_DIR}/libisar.dylib"
  "${FRAMEWORKS_DIR}/libllama_wrapper.dylib"
  "${FRAMEWORKS_DIR}/libonnxruntime.1.24.4.dylib"
  "${FRAMEWORKS_DIR}/libsherpa-onnx-c-api.dylib"
  "${FRAMEWORKS_DIR}/libsherpa-onnx-cxx-api.dylib"
  "${FRAMEWORKS_DIR}/libwhisper_wrapper.dylib"
  "${FRAMEWORKS_DIR}/objective_c.framework/Versions/A/objective_c"
)
for symbol_target in "${NATIVE_SYMBOL_TARGETS[@]}"; do
  if [ ! -f "${symbol_target}" ]; then
    continue
  fi
  symbol_name="$(basename "${symbol_target}")"
  dsym_path="${ARCHIVE_DSYMS}/${symbol_name}.dSYM"
  rm -rf "${dsym_path}"
  dsymutil "${symbol_target}" -o "${dsym_path}" >/dev/null
done

log "Archive Info.plist 검사"
ARCHIVE_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "${ARCHIVE_PATH}/Info.plist" 2>/dev/null || true)"
if [ "${ARCHIVE_BUNDLE_ID}" != "${APP_STORE_BUNDLE_ID}" ]; then
  fail "Archive Bundle ID=${ARCHIVE_BUNDLE_ID}, 기대값=${APP_STORE_BUNDLE_ID}"
fi

APP_MIN_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${ARCHIVED_APP}/Contents/Info.plist" 2>/dev/null || true)"
if [ "${APP_MIN_VERSION}" != "${MIN_MACOS_VERSION}" ]; then
  fail "LSMinimumSystemVersion=${APP_MIN_VERSION}, 기대값=${MIN_MACOS_VERSION}"
fi

log "서명/entitlements 검사"
codesign --verify --strict --deep --verbose=2 "${ARCHIVED_APP}"
SIGNATURE_INFO="$(codesign -dv --verbose=4 "${ARCHIVED_APP}" 2>&1 || true)"
if echo "${SIGNATURE_INFO}" | grep -q "Signature=adhoc"; then
  fail "Archive가 ad-hoc 서명입니다. App Store 제출용 Apple Distribution 서명이 필요합니다."
fi
TEAM_IDENTIFIER="$(echo "${SIGNATURE_INFO}" | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
if [ "${TEAM_IDENTIFIER}" != "${APPLE_TEAM_ID}" ]; then
  fail "TeamIdentifier=${TEAM_IDENTIFIER:-없음}, 기대값=${APPLE_TEAM_ID}"
fi
ENTITLEMENTS_DUMP="$(codesign -d --entitlements :- "${ARCHIVED_APP}" 2>/dev/null || true)"
ENTITLEMENTS_PLIST="$(mktemp)"
printf "%s\n" "${ENTITLEMENTS_DUMP}" > "${ENTITLEMENTS_PLIST}"
APP_SANDBOX="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "${ENTITLEMENTS_PLIST}" 2>/dev/null || true)"
GET_TASK_ALLOW="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "${ENTITLEMENTS_PLIST}" 2>/dev/null || true)"

[ -n "${APP_SANDBOX}" ] ||
  fail "sandbox entitlement가 없습니다"
[ "${APP_SANDBOX}" = "true" ] ||
  fail "sandbox entitlement가 true가 아닙니다"

if [ "${GET_TASK_ALLOW}" = "true" ]; then
  fail "get-task-allow가 true입니다. Apple Distribution 서명/프로비저닝을 확인하세요"
fi

if echo "${ENTITLEMENTS_DUMP}" | grep -q "temporary-exception.apple-events\\|personal-information.calendars"; then
  fail "App Store archive에 AppleEvent/Calendar entitlement가 포함되어 있습니다"
fi
rm -f "${ENTITLEMENTS_PLIST}"

log "성공: ${ARCHIVE_PATH}"
log "다음 단계: Xcode Organizer 또는 Transporter로 App Store Connect에 업로드하세요."
