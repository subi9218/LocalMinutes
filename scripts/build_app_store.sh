#!/usr/bin/env bash
# App Store safe release build.
#
# This script keeps the Dart feature gate in compliance mode and verifies that
# release entitlements do not include Calendar/AppleEvent exceptions.

set -euo pipefail

APP_BUNDLE="적자생존"
RELEASE_APP="build/macos/Build/Products/Release/${APP_BUNDLE}.app"
ENTITLEMENTS="macos/Runner/Release.entitlements"
MIN_MACOS_VERSION="15.5"

log() { echo "[app-store] $*"; }
warn() { echo "[app-store][warn] $*" >&2; }
fail() { echo "[app-store][error] $*" >&2; exit 1; }

if [ ! -f "pubspec.yaml" ]; then
  fail "프로젝트 루트에서 실행하세요: ./scripts/build_app_store.sh"
fi

log "Release entitlements 검사"
grep -q "<key>com.apple.security.app-sandbox</key>" "${ENTITLEMENTS}" ||
  fail "Release.entitlements에 app sandbox key가 없습니다"
grep -A1 "<key>com.apple.security.app-sandbox</key>" "${ENTITLEMENTS}" |
  grep -q "<true/>" ||
  fail "Release.entitlements의 app sandbox가 true가 아닙니다"

if grep -q "temporary-exception.apple-events\\|personal-information.calendars" "${ENTITLEMENTS}"; then
  fail "앱스토어 빌드에는 AppleEvent/Calendar entitlement를 포함하지 않습니다"
fi

if grep -q "NSAppleEventsUsageDescription\\|NSCalendarsUsageDescription" "macos/Runner/Info.plist"; then
  fail "앱스토어 빌드 Info.plist에는 AppleEvent/Calendar usage string을 포함하지 않습니다"
fi

log "최소 macOS 버전 검사"
grep -q "platform :osx, '${MIN_MACOS_VERSION}'" macos/Podfile ||
  fail "Podfile platform이 macOS ${MIN_MACOS_VERSION}가 아닙니다"
grep -q "MACOSX_DEPLOYMENT_TARGET = ${MIN_MACOS_VERSION};" macos/Runner.xcodeproj/project.pbxproj ||
  fail "Runner deployment target이 macOS ${MIN_MACOS_VERSION}가 아닙니다"

log "정적 분석"
flutter analyze

log "테스트"
flutter test

log "macOS release 빌드"
flutter build macos --release \
  --dart-define=APP_STORE_COMPLIANCE_MODE=true

if [ ! -d "${RELEASE_APP}" ]; then
  fail "릴리스 앱 번들을 찾을 수 없습니다: ${RELEASE_APP}"
fi

log "빌드 산출물 entitlements 검사"
ENTITLEMENTS_DUMP="$(codesign -d --entitlements :- "${RELEASE_APP}" 2>/dev/null || true)"
echo "${ENTITLEMENTS_DUMP}" | grep -q "<key>com.apple.security.app-sandbox</key>" ||
  fail "산출물에 app sandbox entitlement가 없습니다"
echo "${ENTITLEMENTS_DUMP}" | grep -A1 "<key>com.apple.security.app-sandbox</key>" |
  grep -q "<true/>" ||
  fail "산출물 app sandbox가 true가 아닙니다"
if echo "${ENTITLEMENTS_DUMP}" | grep -A1 "<key>com.apple.security.get-task-allow</key>" |
  grep -q "<true/>"; then
  if [ "${STRICT_CODESIGN_CHECK:-0}" = "1" ]; then
    fail "산출물 get-task-allow가 true입니다. App Store 배포용 서명을 확인하세요"
  fi
  warn "로컬 개발 서명 산출물에 get-task-allow=true가 주입되었습니다."
  warn "App Store Archive/Distribution 서명에서는 false여야 합니다. 엄격 검사: STRICT_CODESIGN_CHECK=1 ./scripts/build_app_store.sh"
fi
if echo "${ENTITLEMENTS_DUMP}" | grep -q "temporary-exception.apple-events\\|personal-information.calendars"; then
  fail "산출물에 AppleEvent/Calendar entitlement가 포함되어 있습니다"
fi

log "빌드 산출물 최소 macOS 버전 검사"
APP_MIN_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${RELEASE_APP}/Contents/Info.plist" 2>/dev/null || true)"
if [ "${APP_MIN_VERSION}" != "${MIN_MACOS_VERSION}" ]; then
  fail "산출물 LSMinimumSystemVersion=${APP_MIN_VERSION}, 기대값=${MIN_MACOS_VERSION}"
fi

log "완료: ${RELEASE_APP}"
log "App Store Connect 업로드 전 Xcode Archive/Signing/Notarization 설정을 별도로 확인하세요."
