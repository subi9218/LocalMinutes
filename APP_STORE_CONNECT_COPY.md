# App Store Connect Copy — 적자생존

기준일: 2026-05-10

App Store Connect에 그대로 복사하기 위한 입력값 모음입니다.

## 앱 정보

```text
앱 이름: 적자생존
부제: 내 Mac에서 처리하는 AI 회의록
기본 언어: Korean
기본 카테고리: Productivity
보조 카테고리: Business
연령 등급: 4+
SKU: localminutes-macos-001
가격: 유료 앱 19,000원
구독/IAP: 없음
최소 macOS: macOS 15.5 이상
Bundle ID: com.subi9218.localminutes
```

## URL

```text
Privacy Policy URL:
https://subi9218.github.io/LocalMinutes/privacy.html

Support URL:
https://subi9218.github.io/LocalMinutes/support.html

Marketing URL:
비워도 됨
```

## 홍보 문구

```text
회의 녹음부터 전사, 요약, 액션아이템까지 내 Mac에서 처리하세요. 외부 서버 업로드 없이 중요한 회의를 정리합니다.
```

## 키워드

```text
회의록,녹음,음성인식,AI요약,전사,회의요약,액션,메모,업무회의,로컬AI
```

## 앱 설명

```text
적자생존은 회의를 녹음하고, 음성 인식으로 전사한 뒤, 핵심 논의·결정사항·액션아이템을 정리해 주는 macOS 회의록 앱입니다.

회의 내용은 사용자의 Mac에서 처리됩니다. 음성 인식과 요약은 로컬 모델로 실행되며, 회의 음성이나 전사본을 개발자 서버로 업로드하지 않습니다.

주요 기능
- 회의 녹음 및 재생
- 한국어 음성 인식과 전사
- 회의 요약, 주요 논의, 결정사항, 미해결 이슈 정리
- 액션아이템 관리
- 발화자 라벨 보조
- 메모와 어젠다 반영
- 전사 구간 근거 확인
- Markdown/PDF/DOCX 회의록 내보내기
- 로컬 오류 로그 확인 및 삭제

이런 분께 좋습니다
- 회의 후 정리 시간을 줄이고 싶은 분
- 민감한 회의 내용을 외부 서비스에 올리고 싶지 않은 팀
- 결정사항과 후속 업무를 놓치지 않고 관리하고 싶은 분

안내
- 첫 사용 시 음성 인식/요약 모델 다운로드가 필요합니다.
- 모델 파일은 용량이 클 수 있습니다.
- AI 결과는 회의 음질, 마이크 위치, 발화 겹침에 따라 달라질 수 있습니다. 중요한 회의록은 제출 전 직접 확인하세요.
- 앱스토어 빌드는 macOS 15.5 이상을 대상으로 합니다.
```

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

## App Privacy 입력

```text
Do you or your third-party partners collect data from this app?
No

Do you use this app to track users?
No

Privacy Nutrition Label:
Data Not Collected
```

## 검증 메모

```text
Privacy Policy URL: HTTP 200 확인
Support URL: HTTP 200 확인
Support email: subi9218@gmail.com
Privacy manifest: macos/Runner/PrivacyInfo.xcprivacy 포함
```
