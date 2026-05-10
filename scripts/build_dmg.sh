#!/usr/bin/env bash
# =============================================================================
#  build_dmg.sh — 온디바이스 AI 회의록 macOS DMG 빌드 스크립트
#
#  사용법:
#    chmod +x scripts/build_dmg.sh
#    ./scripts/build_dmg.sh              # build number 자동 증가
#    ./scripts/build_dmg.sh --no-bump    # 현재 pubspec 버전 그대로 빌드
#
#  출력:
#    dist/적자생존_v<version>_build<build>.dmg
#
#  필요 조건:
#    - Flutter SDK (macOS)
#    - hdiutil (macOS 내장)
#    - Xcode Command Line Tools
# =============================================================================

set -euo pipefail

# ── 설정 ─────────────────────────────────────────────────────────────────────
APP_NAME="적자생존"
APP_BUNDLE="적자생존"
DIST_DIR="dist"
STAGING_DIR=".dmg_staging"
DIRECT_ENTITLEMENTS="macos/Runner/DirectDistribution.entitlements"
BUMP_BUILD=1

for arg in "$@"; do
  case "$arg" in
    --no-bump)
      BUMP_BUILD=0
      ;;
    -h|--help)
      sed -n '1,18p' "$0"
      exit 0
      ;;
    *)
      echo "[ERROR] 알 수 없는 옵션: $arg" >&2
      exit 1
      ;;
  esac
done

if [ "${BUMP_BUILD}" -eq 1 ]; then
  VERSION_RAW="$(./scripts/version.sh bump-build)"
else
  VERSION_RAW="$(./scripts/version.sh show)"
fi
VERSION="${VERSION_RAW%%+*}"
BUILD_NUMBER="${VERSION_RAW##*+}"

RELEASE_APP="build/macos/Build/Products/Release/${APP_BUNDLE}.app"
DMG_NAME="${APP_NAME}_v${VERSION}_build${BUILD_NUMBER}"
DMG_OUTPUT="${DIST_DIR}/${DMG_NAME}.dmg"
DMG_TMP="${DIST_DIR}/${DMG_NAME}_tmp.dmg"

# ── 색상 출력 ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

sign_direct_distribution_app() {
  local app_path="$1"
  if [ ! -f "${DIRECT_ENTITLEMENTS}" ]; then
    log_error "DMG 직접 배포 entitlements를 찾을 수 없습니다: ${DIRECT_ENTITLEMENTS}"
  fi

  log_info "직접 배포용 ad-hoc 재서명 중..."
  while IFS= read -r target; do
    codesign --force --sign - "${target}" >/dev/null 2>&1 || true
  done < <(
    find "${app_path}/Contents/Frameworks" -type f \
      \( -perm -111 -o -name "*.dylib" -o -name "*.so" \) \
      -print 2>/dev/null
  )

  while IFS= read -r framework; do
    codesign --force --sign - "${framework}" >/dev/null 2>&1 || true
  done < <(find "${app_path}/Contents/Frameworks" -type d -name "*.framework" -print 2>/dev/null)

  codesign --force --deep --sign - \
    --entitlements "${DIRECT_ENTITLEMENTS}" \
    "${app_path}" >/dev/null
  codesign --verify --deep --strict "${app_path}" >/dev/null
  log_success "직접 배포용 재서명 완료"
}

# ── 프로젝트 루트 확인 ────────────────────────────────────────────────────────
if [ ! -f "pubspec.yaml" ]; then
  log_error "프로젝트 루트에서 실행하세요: ./scripts/build_dmg.sh"
fi

echo ""
echo "============================================================"
echo "  ${APP_NAME} v${VERSION} (${BUILD_NUMBER}) — DMG 빌드"
echo "============================================================"
echo ""
if [ "${BUMP_BUILD}" -eq 1 ]; then
  log_info "빌드 번호 자동 증가: ${VERSION_RAW}"
else
  log_info "현재 pubspec 버전 사용: ${VERSION_RAW}"
fi

# ── 1. Isar 코드 생성 확인 ───────────────────────────────────────────────────
log_info "Isar .g.dart 파일 확인..."
MISSING_GENERATED=0
for f in \
  "lib/domain/entities/meeting.g.dart" \
  "lib/domain/entities/transcript.g.dart" \
  "lib/domain/entities/summary.g.dart"; do
  if [ ! -f "$f" ]; then
    log_warn "미생성: $f"
    MISSING_GENERATED=1
  fi
done

if [ "$MISSING_GENERATED" -eq 1 ]; then
  log_info "build_runner 실행 중..."
  dart run build_runner build --delete-conflicting-outputs
  log_success "코드 생성 완료"
fi

# ── 2. Flutter 릴리스 빌드 ───────────────────────────────────────────────────
log_info "Flutter 릴리스 빌드 중..."
flutter build macos --release \
  --build-name="${VERSION}" \
  --build-number="${BUILD_NUMBER}"
log_success "빌드 완료: ${RELEASE_APP}"

# ── 3. .app 존재 확인 ────────────────────────────────────────────────────────
if [ ! -d "${RELEASE_APP}" ]; then
  log_error ".app 번들을 찾을 수 없습니다: ${RELEASE_APP}"
fi

# ── 4. dist 디렉토리 준비 ────────────────────────────────────────────────────
mkdir -p "${DIST_DIR}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

# ── 5. 스테이징 폴더 구성 ─────────────────────────────────────────────────────
log_info "DMG 스테이징 폴더 구성..."
cp -R "${RELEASE_APP}" "${STAGING_DIR}/${APP_BUNDLE}.app"
sign_direct_distribution_app "${STAGING_DIR}/${APP_BUNDLE}.app"
# Applications 심볼릭 링크 (드래그 설치용)
ln -s /Applications "${STAGING_DIR}/Applications"

# ── 5-1. 설치 도우미 앱 생성 (Gatekeeper 격리 해제) ────────────────────────
log_info "설치 도우미 앱 생성 중..."
HELPER_SRC="${STAGING_DIR}/설치_도우미_소스.applescript"
HELPER_APP="${STAGING_DIR}/⚡ 처음 여기를 먼저 실행하세요.app"

cat > "${HELPER_SRC}" << 'APPLESCRIPT'
set appName to "적자생존"
set appPath to "/Applications/" & appName & ".app"

-- 앱이 설치되어 있는지 확인
if not (do shell script "test -d " & quoted form of appPath & " && echo yes || echo no") is equal to "yes" then
  display dialog "먼저 '" & appName & "' 앱을 왼쪽 Applications 폴더로 드래그해서 설치해주세요." & return & return & "설치 후 이 도우미를 다시 실행하세요." buttons {"확인"} default button "확인" with icon caution with title "설치 도우미"
  return
end if

-- 이미 실행 가능한지 확인
set alreadyOk to (do shell script "xattr " & quoted form of appPath & " 2>/dev/null | grep -c com.apple.quarantine || true")
if alreadyOk is equal to "0" then
  display dialog "'" & appName & "' 앱이 이미 정상적으로 설정되어 있습니다." & return & return & "Launchpad 또는 Applications 폴더에서 앱을 실행하세요!" buttons {"확인"} default button "확인" with icon note with title "설치 도우미"
  return
end if

-- 격리 속성 해제 (관리자 권한 요청)
display dialog "'" & appName & "' 앱을 처음 실행하기 위한 준비를 합니다." & return & return & "다음 화면에서 Mac 로그인 비밀번호를 입력해주세요." buttons {"계속"} default button "계속" with icon note with title "설치 도우미"

try
  do shell script "xattr -cr " & quoted form of appPath with administrator privileges
  display dialog "준비 완료! 🎉" & return & return & "이제 Launchpad 또는 Applications 폴더에서 '" & appName & "' 앱을 실행하세요." buttons {"앱 실행하기"} default button "앱 실행하기" with icon note with title "설치 도우미"
  do shell script "open " & quoted form of appPath
on error errMsg
  display dialog "오류가 발생했습니다: " & errMsg & return & return & "Mac 시스템 설정 > 개인 정보 보호 및 보안에서 앱을 허용해주세요." buttons {"확인"} default button "확인" with icon stop with title "설치 도우미"
end try
APPLESCRIPT

osacompile -o "${HELPER_APP}" "${HELPER_SRC}"
rm -f "${HELPER_SRC}"
log_success "설치 도우미 앱 생성 완료"
log_success "스테이징 완료"

# ── 6. DMG 생성 ──────────────────────────────────────────────────────────────
log_info "DMG 생성 중 (압축: UDZO)..."

# 기존 파일 제거
rm -f "${DMG_TMP}" "${DMG_OUTPUT}"

# 임시 읽기/쓰기 DMG 생성
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDRW \
  "${DMG_TMP}" \
  > /dev/null

# 읽기 전용 압축 DMG 변환
hdiutil convert "${DMG_TMP}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "${DMG_OUTPUT}" \
  > /dev/null

rm -f "${DMG_TMP}"
log_success "DMG 생성 완료"

# ── 7. 스테이징 폴더 정리 ────────────────────────────────────────────────────
rm -rf "${STAGING_DIR}"

# ── 8. 결과 출력 ─────────────────────────────────────────────────────────────
DMG_SIZE=$(du -sh "${DMG_OUTPUT}" | cut -f1)
echo ""
echo "============================================================"
log_success "DMG 빌드 성공!"
echo ""
echo "  출력 파일 : ${DMG_OUTPUT}"
echo "  앱 버전   : ${VERSION}"
echo "  빌드 번호 : ${BUILD_NUMBER}"
echo "  파일 크기 : ${DMG_SIZE}"
echo ""
echo "  수신자 설치 방법 (터미널 불필요!):"
echo "    1. DMG 파일 열기"
echo "    2. '${APP_BUNDLE}.app' → Applications 폴더로 드래그"
echo "    3. '⚡ 처음 여기를 먼저 실행하세요' 더블클릭"
echo "    4. Mac 비밀번호 입력 → 앱 자동 실행!"
echo "    5. 모델 파일(Whisper + Gemma)을 별도로 전달"
echo "============================================================"
echo ""
