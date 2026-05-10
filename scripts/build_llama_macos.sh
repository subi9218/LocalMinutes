#!/usr/bin/env bash
# llama.cpp macOS (Apple Metal/arm64) 빌드 스크립트
#
# 사전 요구사항:
#   brew install cmake
#   Xcode Command Line Tools: xcode-select --install
#
# 실행:
#   bash scripts/build_llama_macos.sh
#
# 출력:
#   macos/Runner/libllama_wrapper.dylib
#
# 이후 Xcode 설정 (최초 1회):
#   Runner 타겟 → Build Phases → Copy Files
#   Destination: Frameworks, 파일: libllama_wrapper.dylib 추가

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NATIVE_DIR="$PROJECT_DIR/native"
LLAMA_DIR="$NATIVE_DIR/llama.cpp"
BUILD_DIR="$NATIVE_DIR/build"
OUTPUT_DIR="$PROJECT_DIR/macos/Runner"
WRAPPER_CPP="$NATIVE_DIR/llama_wrapper/llama_wrapper.cpp"
WRAPPER_H="$NATIVE_DIR/llama_wrapper"
OUTPUT_DYLIB="$OUTPUT_DIR/libllama_wrapper.dylib"

echo "=========================================="
echo "  llama.cpp macOS/Metal 빌드"
echo "=========================================="

# ── Step 1: 소스 준비 ─────────────────────────────────────────
echo ""
echo "▶ [1/4] llama.cpp 소스 준비"
if [ ! -d "$LLAMA_DIR" ]; then
    echo "  → git clone --depth 1 (수 분 소요)"
    git clone --depth 1 https://github.com/ggerganov/llama.cpp "$LLAMA_DIR"
    echo "  ✓ 클론 완료"
else
    echo "  → 이미 존재, 건너뜀"
    echo "  (업데이트하려면: rm -rf native/llama.cpp && 재실행)"
fi

# ── Step 2: CMake 빌드 ────────────────────────────────────────
echo ""
echo "▶ [2/4] CMake 빌드 (Metal 활성화, ~10분)"
mkdir -p "$BUILD_DIR"
cmake -S "$LLAMA_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_METAL=ON \
    -DLLAMA_METAL=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
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
echo "▶ [4/4] libllama_wrapper.dylib 빌드"
mkdir -p "$OUTPUT_DIR"

clang++ -dynamiclib \
    -o "$OUTPUT_DYLIB" \
    "$WRAPPER_CPP" \
    -I "$LLAMA_DIR/include" \
    -I "$LLAMA_DIR/ggml/include" \
    -I "$LLAMA_DIR/src" \
    -I "$WRAPPER_H" \
    $STATIC_LIBS \
    -framework Metal \
    -framework Foundation \
    -framework MetalKit \
    -framework Accelerate \
    -std=c++17 \
    -O3 \
    -arch arm64 \
    -mmacosx-version-min=13.0

# rpath 설정 (앱 번들 Frameworks/ 기준)
install_name_tool -id "@rpath/libllama_wrapper.dylib" "$OUTPUT_DYLIB"

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
echo "  + 버튼 → Add Other → libllama_wrapper.dylib 선택"
echo ""
echo "  [모델 파일 배치]"
echo "  mkdir -p ~/Library/Application\\ Support/meeting_assistant2/models/"
echo "  cp /path/to/gemma-4-e2b-it-q8_0.gguf \\"
echo "     ~/Library/Application\\ Support/meeting_assistant2/models/"
echo ""
echo "  [실행]"
echo "  flutter pub get"
echo "  flutter run -d macos"
