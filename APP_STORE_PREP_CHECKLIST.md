# App Store Prep Checklist — 적자생존

기준일: 2026-05-10

인증서 준비 전까지 완료할 수 있는 제출 준비와, 인증서 준비 직후 실행할 검증 절차를 한곳에 모은 체크리스트입니다.

## 1. App Store Connect 입력값

`APP_STORE_METADATA_KO.md`를 기준으로 입력합니다.

- 앱 이름: `적자생존`
- 부제: `내 Mac에서 처리하는 AI 회의록`
- 기본 언어: Korean
- 기본 카테고리: Productivity
- 보조 카테고리: Business
- 연령 등급: 4+
- 가격: 유료 앱 `19,000원`
- SKU: `localminutes-macos-001`
- Privacy Policy URL: `https://subi9218.github.io/LocalMinutes/privacy.html`
- Support URL: `https://subi9218.github.io/LocalMinutes/support.html`

체크:

- [ ] 앱 이름/부제 입력
- [ ] 설명/홍보 문구/키워드 입력
- [ ] 카테고리 Productivity / Business 선택
- [ ] 연령 등급 4+ 입력
- [ ] Privacy Policy URL 입력
- [ ] Support URL 입력
- [ ] Paid Apps Agreement 수락
- [ ] 세금/은행 정보 입력
- [ ] Pricing and Availability에서 한국 가격 `19,000원` 설정
- [ ] 구독/IAP 없음 확인

## 2. App Privacy

`APP_STORE_PRIVACY_ANSWERS.md`를 기준으로 입력합니다.

- Data Collection: No
- Tracking: No
- Privacy Label: Data Not Collected

체크:

- [ ] `No, data is not collected` 선택
- [ ] Tracking 질문에 `No` 선택
- [ ] 데이터 타입 추가 선택 없음 확인
- [ ] Privacy Policy 페이지와 설명 불일치 없음 확인
- [ ] `macos/Runner/PrivacyInfo.xcprivacy` 포함 확인

## 3. App Review Notes

`APP_STORE_SUBMISSION_NOTES.md`의 App Review Notes를 복사합니다.

복사 전 확인:

- [ ] “로그인이나 계정 생성은 필요하지 않습니다” 문구와 실제 App Store 빌드 UI가 일치
- [ ] Hugging Face 토큰 입력 UI가 App Store 제출 빌드에서 기본 노출되지 않음
- [ ] Calendar/AppleEvent 기능이 App Store 제출 빌드에서 노출되지 않음
- [ ] 지원 모델 목록이 Gemma/Qwen 기준으로 표시됨
- [ ] 테스트 방법 1~5단계가 실제 앱 흐름과 일치

## 4. 스크린샷 촬영 구성

실제 고객/회사 회의 내용은 사용하지 않습니다. 아래 데모 문구로 새 회의를 만들어 촬영합니다.

상세 촬영 대본:

- `DEMO_SCREENSHOT_SCRIPT.md`

데모 회의 제목:

```text
제품 주간 회의
```

데모 어젠다:

```text
- 6월 출시 준비
- QA 일정
- 고객 피드백 반영
```

데모 메모:

```text
- 이번 주는 앱스토어 제출 준비를 우선 확인
- QA 체크리스트와 스크린샷 준비 필요
- 모델 다운로드와 로컬 처리 안내를 명확히 보여주기
```

권장 5장:

1. 첫 실행 온보딩
   - 화면: `회의 내용은 내 Mac 밖으로 나가지 않습니다`
   - 보여줄 포인트: 로컬 처리, 외부 서버 미전송

2. 모델 준비 화면
   - 화면: 음성 인식 모델/요약 모델 준비
   - 보여줄 포인트: 설치 상태, 모델 다운로드, 설치 경로
   - 주의: App Store mode에서 토큰/URL 편집 UI가 보이지 않는 상태

3. 녹음 준비/녹음 중 화면
   - 화면: 회의 제목, 말할 사람 수, 마이크, 회의 유형
   - 보여줄 포인트: 사용자가 직접 녹음 시작, 실시간 상태

4. 회의 상세 화면
   - 화면: 요약, 주요 논의, 결정사항, 액션아이템, 근거 버튼
   - 보여줄 포인트: 회의록 결과와 근거 점프

5. 설정/라이선스와 개인정보 화면
   - 화면: 저장 폴더, 모델, 라이선스/개인정보
   - 보여줄 포인트: 저장 위치, 로컬 처리 고지, 라이선스 고지

체크:

- [ ] 민감한 실제 회의명/참석자/음성/회사 정보 없음
- [ ] 화면에 개발용 경로, 토큰, 내부 모델명이 불필요하게 노출되지 않음
- [ ] macOS App Store Connect 규격에 맞는 해상도로 촬영
- [ ] 다크/라이트 중 더 읽기 좋은 테마로 통일

## 5. 인증서 준비 후 실행할 명령

먼저 인증서를 확인합니다.

```bash
security find-identity -v -p codesigning
```

기대:

```text
Apple Distribution
```

App Store archive:

```bash
cd /Users/channy/LocalMinutes

APPLE_TEAM_ID=<TEAM_ID> \
APP_STORE_BUNDLE_ID=com.subi9218.localminutes \
./scripts/archive_app_store.sh
```

성공 시 확인:

- [ ] `flutter analyze` 통과
- [ ] `flutter test` 통과
- [ ] Archive Bundle ID가 `com.subi9218.localminutes`
- [ ] `codesign --verify --strict --deep` 통과
- [ ] `get-task-allow=false`
- [ ] Calendar/AppleEvent entitlement 없음
- [ ] `LSMinimumSystemVersion=15.5`
- [ ] Xcode Organizer 또는 Transporter 업로드 가능

## 6. App Store-Signed QA

인증서 준비 후 archive 또는 TestFlight/설치 빌드에서 확인합니다.

첫 실행:

- [ ] 새 사용자 상태로 앱 실행
- [ ] 저장 폴더 선택
- [ ] 앱 종료 후 재실행
- [ ] 같은 저장 폴더로 녹음 시작 가능
- [ ] 저장 폴더 권한 실패 시 재선택 안내가 뜸

모델:

- [ ] STT 모델 다운로드 가능
- [ ] 요약 모델 다운로드 가능
- [ ] 계정/토큰 없이 기본 모델 다운로드 가능
- [ ] App Store 제출 빌드에서 지원 모델 목록이 Gemma/Qwen 기준으로 표시됨
- [ ] App Store 제출 빌드에서 Hugging Face 토큰 입력/URL 편집 기본 노출 없음

회의 흐름:

- [ ] 마이크 권한 요청 문구 정상
- [ ] 녹음 시작/일시정지/중지 정상
- [ ] 녹음 종료 후 자동 요약이 실행되지 않음
- [ ] 사용자가 직접 요약 실행
- [ ] 회의 상세에서 요약/결정사항/액션아이템/근거 확인
- [ ] Markdown 내보내기 정상
- [ ] PDF 내보내기 정상
- [ ] DOCX 내보내기 정상
- [ ] 앱 재실행 후 기존 회의 접근 가능

개인정보/심사:

- [ ] 네트워크 사용은 모델 다운로드/외부 링크로만 설명 가능
- [ ] 회의 음성/전사/요약이 개발자 서버로 전송되지 않음
- [ ] 자동 크래시 리포트/분석 SDK 없음
- [ ] Privacy Policy, App Privacy, Review Notes 설명이 서로 일치

## 7. 제출 직전 금지 사항

- App Store archive에 `ENABLE_CALENDAR_INTEGRATION=true`를 넣지 않음
- App Store archive에 `APP_STORE_COMPLIANCE_MODE=false`를 넣지 않음
- `com.example.*` Bundle ID 사용 금지
- 실제 회의 데이터가 포함된 스크린샷 업로드 금지
- 개발자 토큰, GitHub PAT, Hugging Face 토큰 노출 금지
