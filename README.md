# LocalMinutes / 적자생존

적자생존은 macOS용 온디바이스 AI 회의록 앱입니다. 회의 녹음, 음성 인식, 발화자 라벨, 요약 생성을 사용자의 Mac에서 처리하고, 회의 음성이나 전사본을 개발자 서버로 업로드하지 않는 것을 기본 원칙으로 합니다.

## 주요 기능

- 회의 녹음과 WAV 저장
- 로컬 Whisper 기반 음성 인식
- 로컬 LLM 기반 회의 요약
- 주요 논의, 결정사항, 미해결 이슈, 액션아이템 정리
- 발화자 라벨 보조
- 전사 근거 확인과 회의록 검색
- Markdown, PDF, DOCX 내보내기
- 정기 회의 시리즈/다이제스트/회의 비교 보조 기능
- App Store 제출용 sandbox, privacy, 안전 모델 모드

## 기술 스택

- Flutter macOS
- Riverpod
- Isar
- whisper.cpp FFI wrapper
- llama.cpp FFI wrapper
- sherpa-onnx
- macos_ui

## 개발

```bash
flutter pub get
flutter analyze
flutter test
flutter build macos --debug
```

앱 실행:

```bash
open "build/macos/Build/Products/Debug/적자생존.app"
```

## 배포

직접 배포용 DMG:

```bash
./scripts/build_dmg.sh
```

App Store archive는 Apple Developer Team ID와 Apple Distribution 인증서가 준비된 뒤 실행합니다.

```bash
APPLE_TEAM_ID=<TEAM_ID> \
APP_STORE_BUNDLE_ID=com.subi9218.localminutes \
./scripts/archive_app_store.sh
```

## 제출 문서

- `APP_STORE_PREP_CHECKLIST.md`: 제출 전/후 체크리스트
- `APP_STORE_CONNECT_COPY.md`: App Store Connect 복사용 입력값
- `APP_STORE_METADATA_KO.md`: App Store Connect 입력 문구
- `APP_STORE_PRIVACY_ANSWERS.md`: App Privacy 답변
- `APP_STORE_SUBMISSION_NOTES.md`: App Review Notes
- `DEMO_SCREENSHOT_SCRIPT.md`: 스크린샷/QA용 데모 회의 대본
- `FREEMIUM_TODO.md`: 무료 앱 + Pro Unlock 전환 작업 목록
- `ACCOUNT_HANDOFF.md`: 계정/서명 인수인계
- `CODEX_TODO.md`: 남은 작업 우선순위

## 주의

- App Store 빌드에는 `APP_STORE_COMPLIANCE_MODE=true`를 유지합니다.
- 제한 모델, Calendar AppleEvent 연동, 개발용 다운로드 옵션은 App Store 제출 빌드에서 켜지 않습니다.
- 실제 회의 데이터, 토큰, 개인 키, 인증 정보는 커밋하거나 스크린샷에 노출하지 않습니다.
