# App Store Privacy Nutrition Label 답변

최종 검토일: 2026년 5월 1일

이 문서는 App Store Connect > App Privacy 입력용 체크리스트입니다. 현재 앱스토어 안전 모드 기준으로 작성했습니다.

## 결론

App Store Connect에서 다음처럼 입력합니다.

| 항목 | 답변 |
| --- | --- |
| Does this app collect data from this app? | No |
| Privacy Nutrition Label 표시 | Data Not Collected |
| Tracking | No |
| Data Linked to You | 없음 |
| Data Not Linked to You | 없음 |
| Data Used to Track You | 없음 |

근거:

- 회의 음성, 전사본, 요약본, 메모, 태그, 로그를 개발자 서버로 전송하지 않습니다.
- 음성 인식, 발화자 라벨, 요약은 사용자의 Mac에서 로컬 모델로 처리됩니다.
- 계정 로그인, 원격 분석 SDK, 광고 SDK, 자동 크래시 리포트, 클라우드 동기화가 없습니다.
- 사용자가 직접 공유/내보내기/이메일/로그 복사를 실행한 경우는 사용자의 명시적 동작입니다.

## App Store Connect 입력 순서

### 1. App Privacy 시작

질문:

> Do you or your third-party partners collect data from this app?

답변:

> No

선택 이유:

- 앱의 일반 사용 과정에서 개발자 또는 제3자가 사용자 데이터를 수집하지 않습니다.
- 로컬 저장 데이터는 사용자의 Mac 안에 남습니다.

### 2. Tracking

질문:

> Do you use this app to track users?

답변:

> No

선택 이유:

- 광고 추적을 하지 않습니다.
- 광고 ID 또는 추적 식별자를 사용하지 않습니다.
- 다른 회사의 앱/웹사이트 데이터와 결합해 사용자를 추적하지 않습니다.

### 3. Data Types

답변:

> 선택하지 않음

선택하지 않는 항목:

- Contact Info
- Health and Fitness
- Financial Info
- Location
- Sensitive Info
- Contacts
- User Content
- Browsing History
- Search History
- Identifiers
- Purchases
- Usage Data
- Diagnostics
- Other Data

이유:

- 위 데이터가 앱 내부에 로컬 저장될 수는 있어도, 개발자 또는 제3자 서버로 수집되지 않습니다.
- 로컬 진단 로그도 자동 전송되지 않으며, 사용자가 설정 화면에서 직접 복사/공유할 때만 앱 밖으로 나갑니다.

## 주의해서 설명할 항목

### 회의 녹음/전사/요약

App Privacy Label에서는 `User Content`를 선택하지 않습니다.

이유:

- 회의 녹음, 전사본, 요약본은 사용자의 Mac에 로컬 저장됩니다.
- 개발자 서버로 업로드되지 않습니다.
- 사용자가 직접 내보내거나 공유한 경우에는 사용자가 선택한 대상 앱/서비스 정책이 적용됩니다.

### 오류 로그

App Privacy Label에서는 `Diagnostics`를 선택하지 않습니다.

이유:

- 앱은 로컬 오류 로그를 저장할 수 있지만 자동 전송하지 않습니다.
- 사용자가 직접 복사/공유한 경우에만 앱 밖으로 나갑니다.

### 모델 다운로드

App Privacy Label에서는 별도 데이터 타입을 선택하지 않습니다.

이유:

- 네트워크는 모델 파일 다운로드를 위해 사용됩니다.
- 모델 다운로드 요청은 Hugging Face/GitHub 등 모델 제공 사이트로 직접 연결됩니다.
- 회의 음성, 전사, 요약이 모델 다운로드 서버로 전송되지는 않습니다.

### Hugging Face 토큰

App Privacy Label에서는 `Identifiers` 또는 `Contact Info`를 선택하지 않습니다.

이유:

- 토큰은 사용자가 모델 제공 사이트에서 받은 다운로드 권한 토큰입니다.
- 앱은 토큰을 모델 다운로드 요청에만 사용합니다.
- 앱 개발자 서버로 전송하지 않습니다.

## App Review Notes 제출 문구

아래 문구를 App Review Notes에 넣는 것을 권장합니다.

```text
적자생존은 온디바이스 회의록 앱입니다. 회의 녹음, 음성 인식, 발화자 라벨, 요약 생성은 사용자의 Mac에서 로컬 모델로 처리되며 개발자 서버로 업로드되지 않습니다.

앱은 사용자가 명시적으로 요청한 AI 모델 파일 다운로드와 외부 도움말/라이선스 링크 열기에만 네트워크를 사용합니다. 회의 음성, 전사 텍스트, 요약 내용은 모델 다운로드 서버로 전송되지 않습니다.

앱스토어 빌드에서는 Calendar/AppleEvent 자동화 기능과 라이선스 리스크가 있는 모델 선택지를 숨겼습니다. 설정 > 라이선스와 개인정보에서 사용 모델 및 라이선스 고지를 확인할 수 있습니다.

로컬 오류 로그는 자동 전송되지 않으며, 사용자가 직접 복사하거나 공유할 때만 앱 밖으로 나갈 수 있습니다.
```

## Privacy Policy URL 페이지에 포함할 핵심 문구

개인정보 처리방침 공개 페이지에는 아래 내용이 반드시 포함되어야 합니다.

- 회의 음성, 전사본, 요약본은 개발자 서버로 전송하지 않음
- AI 처리는 사용자의 Mac에서 로컬 모델로 실행
- 모델 다운로드와 외부 링크 열기에 네트워크 사용 가능
- 사용자가 직접 공유/내보내기/메일/로그 복사를 실행하면 선택한 대상 앱 또는 서비스로 데이터가 전달될 수 있음
- 로컬 오류 로그는 자동 전송되지 않음
- 앱스토어 빌드는 Calendar/AppleEvent 자동화 권한을 사용하지 않음

현재 프로젝트 문서:

- `PRIVACY_POLICY.md`

## 향후 기능 추가 시 답변 변경 조건

아래 기능 중 하나라도 추가되면 `Data Not Collected` 답변을 다시 검토해야 합니다.

- 자동 크래시 리포트 업로드
- 사용량 분석/원격 분석
- 계정 로그인
- 클라우드 백업 또는 동기화
- 서버 기반 STT/요약
- 앱 개발자 서버를 통한 모델 다운로드 프록시
- 결제/구독 계정 식별자를 앱 서버에 저장
- 사용자 피드백/문의 내용이 앱 내부에서 서버로 전송되는 기능
- 광고 SDK 또는 추적 SDK 추가

## 최종 제출 전 체크리스트

- [ ] App Store Connect > App Privacy에서 `No, data is not collected` 선택
- [ ] Tracking 질문에서 `No` 선택
- [ ] 데이터 타입을 추가 선택하지 않음
- [ ] Privacy Policy URL에 `PRIVACY_POLICY.md` 내용 게시
- [ ] App Review Notes에 온디바이스 처리/모델 다운로드 설명 추가
- [ ] 앱스토어 빌드에서 Calendar/AppleEvent 권한이 없는지 확인
- [ ] 앱스토어 빌드에서 자동 크래시 리포트/분석 SDK가 없는지 확인
- [ ] 향후 기능 변경 시 Privacy Label 재검토

