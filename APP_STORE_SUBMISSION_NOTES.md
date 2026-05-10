# App Store 제출 메모 초안

관련 문서:

- `APP_STORE_METADATA_KO.md`: 앱 설명, 부제, 키워드, 홍보 문구, 심사 메모 전체 초안
- `APP_STORE_PRIVACY_ANSWERS.md`: App Store Privacy Nutrition Label 입력값
- `PRIVACY_POLICY.md`: 개인정보 처리방침 게시용 본문

## App Review Notes

```text
적자생존은 온디바이스 회의록 앱입니다. 회의 녹음, 음성 인식, 발화자 라벨, 요약 생성은 사용자의 Mac에서 로컬 모델로 처리되며 개발자 서버로 업로드되지 않습니다.

로그인이나 계정 생성은 필요하지 않습니다. 첫 실행 시 사용자가 회의 녹음 저장 폴더를 선택해야 하며, 이후 앱을 사용할 수 있습니다.

앱은 사용자가 명시적으로 요청한 AI 모델 파일 다운로드와 외부 도움말/라이선스 링크 열기에만 네트워크를 사용합니다. 회의 음성, 전사 텍스트, 요약 내용은 모델 다운로드 서버로 전송되지 않습니다.

테스트 방법:
1. 앱 실행 후 저장 폴더를 선택합니다.
2. 설정 또는 모델 준비 화면에서 음성 인식 모델과 요약 모델을 다운로드합니다.
3. 새 녹음을 시작하고, 회의 제목과 말할 사람 수를 입력합니다.
4. 녹음을 종료한 뒤 사용자가 직접 요약 버튼을 눌러 전사/요약을 실행합니다.
5. 회의 상세 화면에서 요약, 주요 논의, 결정사항, 액션아이템, 전사 근거, 내보내기 기능을 확인할 수 있습니다.

앱스토어 빌드에서는 Calendar/AppleEvent 자동화 기능과 라이선스 리스크가 있는 모델 선택지를 숨겼습니다. 설정 > 라이선스와 개인정보에서 사용 모델 및 라이선스 고지를 확인할 수 있습니다.

로컬 오류 로그는 자동 전송되지 않으며, 사용자가 직접 복사하거나 공유할 때만 앱 밖으로 나갈 수 있습니다.
```

## 가격 정책

```text
유료 앱: 19,000원
구독/IAP: 첫 출시 버전에서는 사용하지 않음
```

App Store Connect에서 Paid Apps Agreement, 세금, 은행 정보 입력을 완료한 뒤 Pricing and Availability에서 대한민국 기준 가격을 19,000원으로 설정합니다.

## Privacy Policy URL 안내 문구

개인정보 처리방침 URL에는 `PRIVACY_POLICY.md`의 내용을 게시합니다.

게시 후 App Store Connect에 입력할 URL:

```text
TODO: https://example.com/privacy
```

## App Privacy 입력값

```text
Data Collection: No
Tracking: No
Privacy Label: Data Not Collected
```
