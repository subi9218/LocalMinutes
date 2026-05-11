#!/usr/bin/env bash
# whisper.cpp macOS (Apple Metal/arm64) 빌드 스크립트
#
# 사전 요구사항:
#   brew install cmake
#   Xcode Command Line Tools: xcode-select --install
#
# 실행:
#   bash scripts/build_whisper_macos.sh
#
# 출력:
#   macos/Runner/libwhisper_wrapper.dylib
#
# 이후 Xcode 설정 (최초 1회):
#   Runner 타겟 → Build Phases → Copy Files
#   Destination: Frameworks, 파일: libwhisper_wrapper.dylib 추가

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NATIVE_DIR="$PROJECT_DIR/native"
WHISPER_DIR="$NATIVE_DIR/whisper.cpp"
BUILD_DIR="$NATIVE_DIR/whisper_build"
OUTPUT_DIR="$PROJECT_DIR/macos/Runner"
WRAPPER_CPP="$NATIVE_DIR/whisper_wrapper/whisper_wrapper.cpp"
WRAPPER_H="$NATIVE_DIR/whisper_wrapper"
OUTPUT_DYLIB="$OUTPUT_DIR/libwhisper_wrapper.dylib"

echo "=========================================="
echo "  whisper.cpp macOS/Metal 빌드"
echo "=========================================="

# ── Step 1: 소스 준비 ─────────────────────────────────────────
echo ""
echo "▶ [1/4] whisper.cpp 소스 준비"
if [ ! -d "$WHISPER_DIR" ]; then
    echo "  → git clone --depth 1 (수 분 소요)"
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp "$WHISPER_DIR"
    echo "  ✓ 클론 완료"
else
    echo "  → 이미 존재, 건너뜀"
    echo "  (업데이트하려면: rm -rf native/whisper.cpp && 재실행)"
fi

# ── Step 2: CMake 빌드 ────────────────────────────────────────
echo ""
echo "▶ [2/4] CMake 빌드 (Metal + Core ML 활성화, ~5분)"
mkdir -p "$BUILD_DIR"
cmake -S "$WHISPER_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_METAL=ON \
    -DWHISPER_METAL=ON \
    -DWHISPER_COREML=ON \
    -DWHISPER_COREML_ALLOW_FALLBACK=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0

cmake --build "$BUILD_DIR" --config Release -j "$(sysctl -n hw.logicalcpu)"
echo "  ✓ 빌드 완료"

# ── Step 3: 정적 라이브러리 수집 ─────────────────────────────
echo ""
echo "▶ [3/4] 정적 라이브러리 수집"
STATIC_LIBS=$(find "$BUILD_DIR" -name "*.a" | tr '\n' ' ')
LIB_COUNT=$(echo $STATIC_LIBS | wc -w | tr -d ' ')
echo "  → .a 파일 ${LIB_COUNT}개 발견"

if [ -z "$STATIC_LIBS" ]; then
    echo "  ✗ 오류: 정적 라이브러리를 찾을 수 없습니다"
    exit 1
fi

# ── Step 4: 래퍼 dylib 빌드 ──────────────────────────────────
echo ""
echo "▶ [4/4] libwhisper_wrapper.dylib 빌드"
mkdir -p "$OUTPUT_DIR"

clang++ -dynamiclib \
    -o "$OUTPUT_DYLIB" \
    "$WRAPPER_CPP" \
    -I "$WHISPER_DIR/include" \
    -I "$WHISPER_DIR/ggml/include" \
    -I "$WRAPPER_H" \
    $STATIC_LIBS \
    -framework CoreML \
    -framework Metal \
    -framework Foundation \
    -framework MetalKit \
    -framework Accelerate \
    -std=c++17 \
    -O3 \
    -arch arm64 \
    -mmacosx-version-min=13.0

# rpath 설정 (앱 번들 Frameworks/ 기준)
install_name_tool -id "@rpath/libwhisper_wrapper.dylib" "$OUTPUT_DYLIB"

echo "  ✓ 생성 완료: $OUTPUT_DYLIB"

# ── 완료 안내 ─────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  ✅ 빌드 성공"
echo "=========================================="
echo ""
echo "다음 단계 (최초 1회):"
echo ""
echo "  [Xcode 설정]"
echo "  open macos/Runner.xcworkspace"
echo "  Runner 타겟 → Build Phases → Copy Files"
echo "  Destination: Frameworks"
echo "  + 버튼 → Add Other → libwhisper_wrapper.dylib 선택"
echo ""
echo "  [모델 파일 배치]"
echo "  cp whisper-large-v3-turbo-q8_0.gguf \\"
echo "     ~/Library/Application\\ Support/LocalMinutes/models/"
echo ""
echo "  [테스트용 WAV 파일 준비]"
echo "  16kHz 모노 WAV 권장 (다른 샘플레이트/스테레오도 자동 변환)"
