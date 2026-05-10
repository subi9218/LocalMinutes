# Codex TODO — 적자생존 App Store 제출 마무리

기준일: 2026-05-10

## 현재 확인된 상태

- 프로젝트는 Git 저장소가 아니므로 변경 이력 기반 비교는 불가.
- 현재 앱 버전은 `2.1.1+26`.
- `flutter analyze` 통과: 0 issues.
- `flutter test` 통과: 90/90.
- 최근 안정 산출물은 `dist/적자생존_v2.1.1_build26.dmg`.
- 핵심 제품 기능은 대부분 완료 상태.
- 다음 우선순위는 신규 기능 추가보다 App Store 제출 리스크 제거.

## P0 — App Store 제출 차단 요소

### 1. 실제 Bundle ID 확정 및 적용

- [x] App Store Connect에 등록할 실제 Bundle ID 확정: `com.subi9218.localminutes`.
- [x] `macos/Runner/Configs/AppInfo.xcconfig`의 `PRODUCT_BUNDLE_IDENTIFIER` 교체.
- [x] `PRODUCT_COPYRIGHT`의 `com.example` 문구 교체.
- [x] `macos/Runner.xcodeproj/project.pbxproj`의 RunnerTests Bundle ID도 실제 ID 기반으로 정리.
- [x] `APP_STORE_METADATA_KO.md`의 예시 Bundle ID 문구 업데이트.

완료 조건:

- `com.example.*`가 제출용 설정에 남아 있지 않음.
- `./scripts/archive_app_store.sh`의 Bundle ID 검사 통과 가능.

### 2. Privacy Policy URL / Support URL 확정

- [ ] `PRIVACY_POLICY.md` 내용을 실제 공개 URL에 게시.
- [x] Support URL에 실제 문의 가능한 이메일 또는 연락 양식 게시.
- [x] `APP_STORE_METADATA_KO.md`의 TODO URL 교체.
- [x] `APP_STORE_SUBMISSION_NOTES.md`의 TODO URL 교체.
- [ ] App Store Connect 입력값과 문서의 URL이 일치하는지 확인.

완료 조건:

- App Store Connect에 입력 가능한 Privacy Policy URL과 Support URL이 준비됨.
- URL 접속 시 로그인 없이 내용 확인 가능.

### 3. Apple Distribution 서명 준비

- [ ] Apple Developer Team ID 확인.
- [ ] Xcode > Settings > Accounts에서 Apple Distribution 인증서 설치.
- [ ] App Store Connect에서 Bundle ID / App record 생성.
- [ ] Provisioning profile이 Xcode 자동 서명으로 잡히는지 확인.
- [ ] `security find-identity -v -p codesigning`에서 유효한 Apple Distribution identity 확인.

완료 조건:

- `security find-identity -v -p codesigning` 결과에 유효한 배포 인증서가 표시됨.
- `scripts/archive_app_store.sh`의 인증서 검사 통과 가능.

### 4. App Store Archive 생성 및 strict 검증

- [ ] 아래 환경변수로 archive 스크립트 실행.

```bash
APPLE_TEAM_ID=<팀ID> \
APP_STORE_BUNDLE_ID=<실제.bundle.id> \
./scripts/archive_app_store.sh
```

- [ ] Archive Bundle ID 검사 통과.
- [ ] `codesign --verify --strict --deep` 통과.
- [ ] `get-task-allow=false` 확인.
- [ ] Calendar/AppleEvent entitlement 미포함 확인.
- [ ] `LSMinimumSystemVersion=15.5` 확인.

완료 조건:

- `.xcarchive`가 생성되고 `scripts/archive_app_store.sh`가 성공 종료.
- Xcode Organizer 또는 Transporter 업로드 준비 완료.

### 5. 유료 앱 가격 설정

- [x] 출시 가격 정책 확정: 유료 앱 `19,000원`.
- [ ] App Store Connect에서 Paid Apps Agreement 수락.
- [ ] 세금 및 은행 정보 입력.
- [ ] Pricing and Availability에서 대한민국 기준 가격 `19,000원` 설정.
- [ ] 다른 국가/지역 가격은 Apple 자동 환산값을 우선 사용.
- [ ] 첫 출시 버전에서는 구독/IAP를 만들지 않음.

완료 조건:

- App Store Connect 앱 가격이 `19,000원`으로 저장됨.
- 앱 페이지에 In-App Purchases 없이 유료 다운로드 가격만 표시됨.

## P0 — 샌드박스 파일 접근 리스크

### 6. 저장 폴더 security-scoped bookmark 검토

현재 첫 실행 저장 폴더는 path 문자열만 저장한다.

관련 파일:

- `lib/presentation/screens/storage_setup_screen.dart`
- `lib/core/services/app_settings.dart`
- `macos/Runner/Release.entitlements`

할 일:

- [ ] App Store sandbox release 환경에서 앱 재실행 후 선택 폴더 쓰기 권한이 유지되는지 테스트.
- [ ] 권한이 유지되지 않으면 security-scoped bookmark 저장/복원 구현 검토.
- [ ] 구현 시 macOS native channel 또는 적절한 플러그인 방식 선택.
- [ ] 저장 폴더 변경, 앱 재실행, 녹음 저장, 내보내기 저장 시나리오 테스트.
- [ ] 실패 시 사용자에게 폴더 재선택을 요청하는 복구 UX 추가.

완료 조건:

- App Store sandbox 빌드에서 재실행 후에도 사용자 선택 저장 폴더에 녹음 저장 가능.
- 권한 만료/실패 상황에서 데이터 손실 없이 재선택 UX가 동작.

## P1 — 제출 자료 마무리

### 7. App Store Connect 메타데이터 최종화

- [ ] 앱 이름: `적자생존`.
- [ ] 부제: `내 Mac에서 처리하는 AI 회의록`.
- [ ] 키워드 100바이트 이하 재확인.
- [ ] 앱 설명 최종 교정.
- [x] 가격 정책 확정: 유료 앱 `19,000원`.
- [ ] 카테고리 Productivity / Business 확정.
- [ ] 연령 등급 4+ 입력.
- [ ] App Review Notes 복사 전 최신 기능과 불일치 없는지 확인.

완료 조건:

- `APP_STORE_METADATA_KO.md` 기준으로 App Store Connect 입력 완료.

### 8. App Privacy 입력

- [ ] `APP_STORE_PRIVACY_ANSWERS.md` 기준으로 `Data Not Collected` 입력.
- [ ] Tracking 없음으로 입력.
- [ ] Calendar/AppleEvent 미사용 설명 유지.
- [ ] 모델 다운로드 네트워크 사용 설명과 Privacy Policy 내용 일치 확인.

완료 조건:

- App Store Connect App Privacy 섹션 입력 완료.

### 9. 스크린샷 준비

권장 구성:

- [ ] 첫 실행 온보딩: 로컬 처리/외부 미전송 메시지.
- [ ] 녹음 준비 화면: 제목, 말할 사람 수, 마이크, 회의 유형.
- [ ] 녹음/처리 진행 화면: 진행률, 중지 버튼, 예상 시간.
- [ ] 회의 상세 화면: 요약, 결정사항, 액션아이템, 근거 버튼.
- [ ] 설정 화면: 저장 폴더, 모델, 라이선스와 개인정보.

완료 조건:

- App Store Connect macOS 스크린샷 규격에 맞는 이미지 준비.
- 민감한 실제 회의 내용이 노출되지 않음.

## P1 — 출시 전 품질 확인

### 10. App Store safe mode 회귀 테스트

- [ ] `APP_STORE_COMPLIANCE_MODE=true` 빌드에서 EXAONE 노출 없음 확인.
- [ ] Calendar/AppleEvent 관련 UI 노출 없음 확인.
- [ ] 과거 `selectedLlmModel=exaone35_7b` 저장값이 안전 모델로 정리되는지 확인.
- [ ] 모델 다운로드 카드/카운트/선택 다이얼로그가 안전 모드와 일치하는지 확인.

완료 조건:

- `test/app_settings_compliance_test.dart` 통과.
- 실제 앱 UI에서도 제한 모델/권한 기능이 숨겨짐.

### 11. 모델 다운로드 심사 환경 점검

- [ ] 심사자가 계정 없이 필요한 모델을 다운로드할 수 있는지 확인.
- [ ] Hugging Face/GitHub 다운로드 URL 접근성 확인.
- [ ] 모델 용량과 다운로드 시간이 Review Notes 설명과 어긋나지 않는지 확인.
- [ ] 다운로드 실패 시 사용자 메시지가 일반 사용자용 문구인지 확인.

완료 조건:

- 신규 macOS 환경에서 모델 다운로드부터 요약 실행까지 막히지 않음.

### 12. 실제 사용자 흐름 최종 QA

- [ ] 새 설치 상태에서 저장 폴더 선택.
- [ ] 모델 준비 화면 진입.
- [ ] 마이크 권한 요청 및 녹음 시작.
- [ ] 녹음 종료 후 자동 요약이 실행되지 않는지 확인.
- [ ] 사용자가 직접 요약 실행.
- [ ] 회의 상세에서 전사, 요약, 근거, 액션아이템 확인.
- [ ] Markdown/PDF/DOCX 내보내기 확인.
- [ ] 앱 재실행 후 기존 회의 접근 확인.

완료 조건:

- 첫 실행부터 회의록 내보내기까지 심사자가 막히지 않는 흐름 확인.

## P2 — 선택적 마감 품질

### 13. 보조 화면 macos_ui 정리

핵심 녹음/상세 화면은 macos_ui 전환이 많이 완료되었지만, 일부 보조 화면에는 Material dialog가 남아 있다.

대상 후보:

- `lib/presentation/widgets/meeting_sidebar.dart`
- `lib/presentation/screens/settings_screen.dart`
- `lib/presentation/screens/glossary_screen.dart`
- `lib/presentation/screens/action_items_screen.dart`
- `lib/presentation/screens/stats_screen.dart`
- `lib/main.dart`

할 일:

- [ ] 남은 `showDialog` / `AlertDialog` / `Dialog` 목록 정리.
- [ ] 단순 confirm은 `MacosAlertDialog`로 전환.
- [ ] 큰 목록/관리 화면은 `MacosSheet`로 전환.
- [ ] 회귀 위험이 큰 폼 내부 Material 위젯은 필요 시 유지.

완료 조건:

- 앱 전체의 다이얼로그 톤이 macOS 스타일에 더 가까워짐.
- `flutter analyze`, `flutter test` 통과.

### 14. README 정리

현재 `README.md`는 Flutter 기본 템플릿에 가깝다.

- [ ] 제품 소개를 `적자생존` 기준으로 갱신.
- [ ] 로컬 AI 처리와 개인정보 보호 원칙 요약.
- [ ] 개발/검증 명령 정리.
- [ ] App Store 제출 관련 문서는 별도 문서로 링크.

완료 조건:

- 저장소를 처음 보는 사람이 README만 보고 앱 목적과 개발 방법을 이해 가능.

## P3 — 출시 후 후보

### 15. 보안 옵션

- [ ] 회의 종료 후 오디오 자동 삭제 옵션.
- [ ] 오디오 암호화 옵션.
- [ ] macOS Keychain 키 저장 검토.

주의:

- 오디오 원본은 기본적으로 삭제하지 않는다.
- 사용자가 명시적으로 켠 보안 옵션으로만 제공한다.

### 16. 캘린더 연동

- [ ] App Store 권한 설명과 사용자 기대치 먼저 정리.
- [ ] AppleEvent/Calendar entitlement 정책 재검토.
- [ ] 내부 빌드와 App Store 빌드 분리 유지.

주의:

- App Store safe mode에서는 Calendar/AppleEvent 기능을 노출하지 않는다.

### 17. 장시간 회의 중간 진행 요약

- [ ] `OnDeviceModelManager`의 STT/LLM 동시 실행 제한 재검토.
- [ ] 녹음 안정성을 해치지 않는 모델 로드/언로드 전략 설계.
- [ ] 제품 스펙 확정 후 구현 여부 결정.

주의:

- 녹음 중 STT/LLM 동시 실행으로 안정성을 깨지 않는다.

## 유지해야 할 원칙

- 오디오 원본은 기본적으로 삭제하지 않는다.
- 사용자가 만든 DB/녹음 파일을 임의 삭제하지 않는다.
- 자동 요약을 되살리지 않는다.
- 첫 실행 저장 폴더 선택 필수 정책을 되돌리지 않는다.
- STT/화자 라벨/요약 네이티브 작업을 동시에 실행하지 않는다.
- App Store safe mode에서 EXAONE, Calendar AppleEvent 등 심사 리스크 기능을 노출하지 않는다.
- OpenAI/GPT STT 재시도는 하지 않는다.

## 기본 검증 명령

```bash
./scripts/version.sh show
flutter analyze
flutter test
flutter build macos --debug
./scripts/build_app_store.sh
```

릴리즈/Archive 단계:

```bash
APPLE_TEAM_ID=<팀ID> \
APP_STORE_BUNDLE_ID=<실제.bundle.id> \
./scripts/archive_app_store.sh
```
