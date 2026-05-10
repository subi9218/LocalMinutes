# App Store 가격 정책

기준일: 2026-05-10

## 정책 변경 예정

- 기존 정책: 유료 다운로드 `19,000원`
- 새 권장 정책: 무료 다운로드 + `Pro Unlock` 19,000원 비소모성 In-App Purchase
- 구독: 첫 출시 버전에서는 사용하지 않음
- In-App Purchase: `Pro Unlock` 일회성 구매
- 무료 체험판: 별도 기간제 체험 대신 무료 기능 제한 제공

## 포지셔닝

적자생존은 월 구독형 클라우드 회의록 서비스가 아니라, 회의 녹음과 음성 인식, 요약을 사용자의 Mac에서 처리하는 온디바이스 회의록 앱으로 포지셔닝한다. 사용자는 무료로 로컬 처리 흐름을 확인한 뒤, 필요하면 Pro Unlock을 한 번 구매한다.

핵심 메시지:

- 무료로 시작
- Pro Unlock 19,000원 한 번 구매
- 회의 내용 외부 서버 업로드 없음
- 내 Mac에서 처리하는 AI 회의록
- Markdown/PDF/DOCX 내보내기 포함

## App Store Connect 설정

1. App Store Connect > Business 또는 Agreements 영역에서 Paid Apps Agreement를 수락한다.
2. 세금 및 은행 정보를 입력한다.
3. 앱의 Pricing and Availability에서 앱 가격을 무료로 설정한다.
4. In-App Purchase에서 Non-Consumable 상품을 만든다.
   - Reference Name: `Pro Unlock`
   - Product ID: `com.subi9218.localminutes.pro`
   - Price: Korea `19,000원`
5. IAP를 앱 버전과 함께 심사 제출한다.

## 구현 체크리스트

- [ ] `FREEMIUM_TODO.md` 기준으로 코드/문서 전환
- [ ] `EntitlementService` hardcoded Pro 제거
- [ ] `in_app_purchase` 추가
- [ ] Paywall UI 추가
- [ ] 구매/복원 QA
- [ ] App Store metadata 가격 문구 변경

## 향후 검토 후보

- Pro 구독: 고급 시리즈 분석, 고급 보고서 템플릿, 암호화 저장 등. 첫 출시에는 사용하지 않음.
- 팀용 라이선스: 여러 좌석 구매 수요가 있을 때 별도 검토
- 출시 후 정가 조정: 리뷰, 전환율, 지원 부담을 보고 결정

## 주의 사항

- 앱 설명에는 가격 자체를 과도하게 반복 노출하지 않는다. 가격은 App Store 상품/IAP 가격 표시를 따른다.
- IAP를 넣으면 구매 복원 버튼과 심사용 IAP 제출이 필수다.
- 모델 다운로드가 필요한 앱이므로 Review Notes에서 첫 실행 절차를 명확히 안내한다.
