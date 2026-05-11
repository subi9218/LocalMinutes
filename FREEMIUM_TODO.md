# Freemium Conversion TODO — 출시 후 검토용

기준일: 2026-05-11

## 현재 상태

이 문서는 1차 App Store 출시 범위가 아닙니다.

현재 첫 출시 정책은 아래 기준으로 고정합니다.

```text
앱 다운로드: 유료
대한민국 가격: 19,000원
구독/IAP: 없음
```

무료 앱 + Pro Unlock 전환은 출시 후 사용자 반응과 지원 부담을 확인한 뒤 별도 작업으로 검토합니다.

## 향후 검토안

```text
앱 다운로드: 무료
수익 모델: 비소모성 In-App Purchase
상품명: Pro Unlock
가격: 19,000원 일회성 구매
권장 Product ID: com.subi9218.localminutes.pro
```

아래 작업 목록은 향후 freemium 전환을 실제로 결정했을 때만 사용합니다.

## 왜 검토할 수 있는가

- 이 앱은 첫 사용 전에 모델 다운로드, 저장 폴더 선택, 마이크 권한, 온디바이스 처리 시간을 사용자가 직접 체감해야 한다.
- 처음부터 유료 앱이면 “내 Mac에서 잘 작동할지” 확인하기 전에 결제해야 해서 진입 장벽이 높을 수 있다.
- 무료로 짧게 테스트한 뒤 Pro를 구매하는 흐름이 제품 신뢰와 전환율에 더 자연스러울 수 있다.

## 권장 무료/Pro 정책

1차 구현은 단순해야 한다. 아래 정책을 우선 추천한다.

### Free

- 저장 폴더 선택
- 모델 다운로드
- 회의 3개까지 생성/녹음/요약
- Markdown 내보내기
- 기본 검색/회의 상세 보기

### Pro Unlock

- 회의/요약 무제한
- PDF/DOCX 내보내기
- 긴 회의 처리 제한 해제
- 시리즈 대시보드
- 주간/월간 다이제스트
- 회의 비교
- 고급 검색/분석
- 단어집 제한 해제

주의:

- 무료 제한을 너무 복잡하게 시작하지 말 것.
- 첫 출시에서는 `무료 회의 3개 + Pro 무제한`만으로도 충분하다.
- PDF/DOCX, 시리즈/다이제스트/회의 비교는 Pro 가치 설명에 좋다.

## App Store Connect 작업

- [ ] 앱 가격을 무료로 설정
- [ ] In-App Purchase 생성
  - Type: Non-Consumable
  - Reference Name: `Pro Unlock`
  - Product ID: `com.subi9218.localminutes.pro`
  - Price: Korea `19,000원`
  - Family Sharing: 가능하면 활성화 검토
- [ ] IAP 현지화
  - Display Name: `Pro Unlock`
  - Description: `회의 수 제한 없이 녹음, 요약, 내보내기와 고급 분석 기능을 사용합니다.`
- [ ] IAP 심사용 스크린샷 준비
- [ ] App Store app price가 무료인지 확인
- [ ] Paid Apps Agreement / Tax / Banking 완료
- [ ] IAP를 앱 버전과 함께 심사 제출

## 코드 작업

### 1. 의존성 추가

- [ ] `pubspec.yaml`에 `in_app_purchase` 추가
- [ ] macOS 빌드/Pod install 확인

### 2. 결제 서비스 추가

권장 파일:

- `lib/core/services/purchase_service.dart`

필수 기능:

- [ ] StoreKit 사용 가능 여부 확인
- [ ] Product ID `com.subi9218.localminutes.pro` 조회
- [ ] 가격 표시 문자열 로드
- [ ] 구매 시작
- [ ] 구매 완료 처리
- [ ] 구매 복원
- [ ] 구매 취소/실패 메시지 처리
- [ ] purchase stream lifecycle 관리
- [ ] 앱 시작 시 구매 상태 복원 또는 로컬 상태 확인

주의:

- 비소모성 IAP는 반드시 `구매 복원`을 제공해야 한다.
- 외부 결제 링크/문구를 넣지 말 것.
- 가격은 App Store 상품에서 받은 localized price를 UI에 표시할 것.

### 3. EntitlementService 실제화

현재 파일:

- `lib/core/services/entitlement_service.dart`

현재 상태:

- `currentTier`가 항상 `EntitlementTier.pro`를 반환한다.
- 무료/Pro 게이트 인터페이스와 테스트 기반은 이미 어느 정도 준비되어 있다.

할 일:

- [ ] `currentTier`를 SharedPreferences + 구매 상태 기반으로 변경
- [ ] `isUnlocked`가 Pro 구매 상태를 반영하게 변경
- [ ] 무료 회의 카운터 정책 확정
- [ ] 무료 회의 3개 초과 시 `PaywallTrigger.monthlyMeetingLimit` 반환
- [ ] Pro 구매 후 제한 없음 확인
- [ ] 테스트에서 hardcoded pro 기대값 수정

권장 키:

```text
entitlement.proUnlocked = true/false
_meetingCount.month = YYYY-MM
_meetingCount.count = N
```

### 4. Paywall UI 추가

권장 위치:

- `lib/presentation/widgets/paywall_dialog.dart`

필수 UI:

- [ ] Pro 혜택 3~5개 표시
- [ ] 가격 표시: StoreKit에서 받은 localized price
- [ ] `Pro 잠금해제` 버튼
- [ ] `구매 복원` 버튼
- [ ] 취소/닫기 버튼
- [ ] 구매 진행/성공/실패 상태
- [ ] App Store 결제라는 점 명확히 표시

권장 문구:

```text
Pro Unlock
19,000원 한 번 구매로 제한 없이 사용하세요.

- 회의와 요약 무제한
- PDF/DOCX 내보내기
- 시리즈/다이제스트/회의 비교
- 긴 회의 처리
```

### 5. 제한 지점 연결

최소 구현:

- [ ] 새 녹음 시작 전 `EntitlementService.canStartMeeting()`
- [ ] 녹음 시작 성공 시 `incrementMonthMeetingCount()`
- [ ] 무료 한도 초과 시 Paywall 표시

추가 Pro 게이트 후보:

- [ ] PDF/DOCX 내보내기 전
- [ ] 시리즈 대시보드 진입 전
- [ ] 주간/월간 다이제스트 진입 전
- [ ] 회의 비교 진입 전
- [ ] 단어집 10개 초과 추가 전

관련 파일 후보:

- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `lib/presentation/widgets/series_dashboard_view.dart`
- `lib/presentation/widgets/meeting_sidebar.dart`
- `lib/presentation/screens/glossary_screen.dart`

### 6. 설정 화면 추가

현재 파일:

- `lib/presentation/screens/settings_screen.dart`

할 일:

- [ ] `Pro Unlock` 섹션 추가
- [ ] 현재 상태 표시: Free / Pro
- [ ] Free 잔여 회의 수 표시
- [ ] `Pro 잠금해제` 버튼
- [ ] `구매 복원` 버튼
- [ ] 구매 성공 후 즉시 UI 갱신

### 7. 문서/메타데이터 변경

수정 대상:

- `APP_STORE_PRICING.md`
- `APP_STORE_METADATA_KO.md`
- `APP_STORE_CONNECT_COPY.md`
- `APP_STORE_SUBMISSION_NOTES.md`
- `APP_STORE_PREP_CHECKLIST.md`
- `CODEX_TODO.md`
- `ACCOUNT_HANDOFF.md`
- `README.md`

변경 방향:

- `유료 앱 19,000원` 제거
- `무료 다운로드 + Pro Unlock 19,000원 일회성 구매`로 교체
- 구독 없음 유지
- IAP 심사 설명 추가
- App Review Notes에 무료 한도/Pro 잠금해제 테스트 방법 추가

### 8. 테스트

필수 테스트:

- [ ] 기본 상태가 Free인지
- [ ] Pro unlock 저장 상태면 `isUnlocked == true`
- [ ] 무료 회의 3개까지 허용
- [ ] 4번째 회의 시작 시 PaywallTrigger 반환
- [ ] Pro 상태에서는 회의 제한 없음
- [ ] 월이 바뀌면 무료 회의 카운트 reset
- [ ] 구매 복원 실패/상품 조회 실패 시 사용자 메시지
- [ ] App Store 제출 빌드에서 Calendar/AppleEvent 기능 미포함 유지

기존 테스트 수정 후보:

- `test/entitlement_service_test.dart`
- `test/app_settings_compliance_test.dart`

## QA 체크리스트

Sandbox StoreKit 테스트:

- [ ] 상품 조회 성공
- [ ] 구매 성공
- [ ] 구매 취소
- [ ] 구매 복원
- [ ] 앱 재실행 후 Pro 상태 유지
- [ ] 무료 상태에서 3회 이후 Paywall 표시
- [ ] Pro 상태에서 제한 없이 녹음/요약 가능

앱 흐름:

- [ ] 새 설치 상태에서 Free로 시작
- [ ] 모델 다운로드 가능
- [ ] 무료 회의 생성/요약 가능
- [ ] 제한 도달 시 Paywall 문구 자연스러움
- [ ] Pro 구매 후 Paywall 사라짐
- [ ] PDF/DOCX/고급 분석 기능이 Pro 상태에서 가능

심사:

- [ ] App Store Connect의 앱 가격 무료
- [ ] IAP 가격 19,000원
- [ ] Review Notes에 IAP 테스트 방법 포함
- [ ] 앱 안에 외부 결제 유도 없음
- [ ] 구매 복원 버튼 있음

## 권장 구현 순서

1. `EntitlementService`를 Free 기본값으로 바꾸고 테스트 수정
2. Paywall UI 추가
3. 새 녹음 시작 전 무료 3회 제한 연결
4. `in_app_purchase` 기반 `PurchaseService` 추가
5. 설정 화면에 Pro 상태/구매/복원 추가
6. PDF/DOCX/고급 기능 Pro 게이트 연결
7. App Store 문서/메타데이터 가격 정책 변경
8. StoreKit sandbox QA
9. QA DMG build 생성
10. Apple Distribution 인증서 준비 후 archive

## 임시 주의

이 전환을 시작하면 기존 `19,000원 유료 앱` 문서와 코드가 섞이지 않게 한 번에 정리해야 한다.

특히 아래 문구는 모두 바뀌어야 한다.

```text
유료 앱 19,000원
구독/IAP 없음
첫 출시 버전에서는 IAP를 만들지 않음
```

새 기준 문구:

```text
무료 다운로드
Pro Unlock 19,000원 일회성 구매
구독 없음
```
