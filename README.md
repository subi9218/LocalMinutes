# LocalMinutes

LocalMinutes는 macOS용 온디바이스 AI 회의록 앱입니다.

## 개요

- 회의 녹음, 음성 인식, 발화자 라벨, 요약을 로컬 Mac에서 처리합니다.
- Flutter macOS 앱이며 Riverpod, Isar, whisper.cpp, llama.cpp, sherpa-onnx를 사용합니다.
- App Store 제출 준비와 직접 배포용 DMG 빌드 스크립트를 포함합니다.

## 개발

```bash
flutter pub get
flutter analyze
flutter test
flutter build macos --debug
```

배포용 DMG:

```bash
./scripts/build_dmg.sh
```
