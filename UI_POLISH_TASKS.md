# UI Polish Tasks — Local Minutes

기준일: 2026-05-14

목표: Local Minutes의 주요 화면을 macOS 네이티브 앱처럼 차분하고 전문적으로 다듬는다. 한 번에 큰 리디자인을 하지 않고, 작은 단위로 수정하고 매 단계마다 `flutter analyze`와 실제 빌드로 회귀를 확인한다.

## 작업 원칙

- 기존 `macos_ui` 패턴과 현재 앱 구조를 우선 사용한다.
- 사용자 흐름이 바뀌는 기능 변경은 하지 않는다. 이번 작업은 시각적 정리와 상태 표현 개선에 한정한다.
- 한 단계가 끝날 때마다 `flutter analyze`를 실행한다.
- 사이드바, 홈, 설정, 녹음 준비 모달처럼 사용자가 자주 보는 화면부터 다룬다.
- 과한 블러, 과한 그림자, 큰 카드형 레이아웃, 완전히 둥근 알약 버튼 남발은 피한다.
- radius는 대부분 6~10px 안에서 정리한다.
- primary color는 macOS system blue 계열을 사용하되, 경고/성공/비활성 색은 기존 의미를 유지한다.
- 텍스트는 줄이고, 상태는 아이콘/색/간결한 라벨로 표현한다.
- App Store 제출 문서나 브랜드명 변경과 무관한 기록성 문서는 건드리지 않는다.

## 완료 기준

- `flutter analyze` 통과.
- `./scripts/build_dmg.sh --no-bump` 통과.
- `hdiutil verify dist/LocalMinutes_v2.1.1_build28.dmg` 통과.
- 앱 표시명은 `Local Minutes`, 제출/문서명은 `Local Minutes - 로컬 회의록`, DMG명은 `LocalMinutes_v...dmg` 규칙을 유지한다.
- 설정/모델 관리 화면에서 필수/선택/상태가 한눈에 보인다.
- 초기 설정에서 여러 모델을 동시에 다운로드하려는 흐름이 계속 막힌다.
- 기존 회의 녹음, 전사, 요약, 모델 다운로드 동작이 깨지지 않는다.

## P0 — 안전장치와 기준선

- [x] 현재 워킹트리 상태를 확인한다.
  - 명령: `git status --short --branch`
- [x] 변경 전 기준 분석을 확인한다.
  - 명령: `flutter analyze`
- [x] 현재 DMG 빌드가 통과하는지 확인한다.
  - 명령: `./scripts/build_dmg.sh --no-bump`
- [x] DMG 검증을 확인한다.
  - 명령: `hdiutil verify dist/LocalMinutes_v2.1.1_build28.dmg`
- [ ] UI 관련 변경 전후 비교를 위해 주요 파일만 추적한다.
  - 예상 파일:
    - `lib/presentation/screens/home_screen.dart`
    - `lib/presentation/screens/setup_screen.dart`
    - `lib/presentation/screens/settings_screen.dart`
    - `lib/presentation/widgets/meeting_sidebar.dart`
    - `lib/presentation/widgets/recording_view.dart`

완료 조건:

- 분석/빌드/DMG 검증이 모두 통과한다.
- 실패가 있으면 UI 변경 전에 원인을 따로 기록한다.

## P1 — 글로벌 스타일 정리

- [x] 앱 전체 primary color가 macOS system blue 계열로 일관적인지 확인한다.
- [x] `ThemeData` 또는 현재 테마 설정에서 불필요하게 Flutter Material 느낌이 강한 색/라운딩이 있는지 확인한다.
- [x] 공통적으로 반복되는 radius, border, muted text color를 정리할 수 있는지 검토한다.
- [x] 버튼, 카드, 모달의 radius를 6~10px 범위로 맞춘다.
- [x] 큰 그림자, 진한 단색 배경, 과한 gradient를 줄인다.
- [x] 앱 기본 폰트는 Flutter/macOS 시스템 폰트 흐름을 유지한다.

주요 확인 파일:

- `lib/main.dart`
- `lib/presentation/screens/home_screen.dart`
- `lib/presentation/screens/setup_screen.dart`
- `lib/presentation/screens/settings_screen.dart`

완료 조건:

- 특정 화면만 튀는 색감이 줄어든다.
- 텍스트 크기와 여백이 MacBook 화면에서 답답하지 않다.
- `flutter analyze` 통과.

## P2 — 사이드바와 메인 레이아웃

- [x] 좌측 회의 목록 사이드바 배경을 macOS 사이드바처럼 옅고 차분하게 정리한다.
- [x] 사이드바와 메인 화면 사이에 1px 수준의 얇은 구분선을 유지하거나 추가한다.
- [x] 선택된 회의 항목은 macOS list selection처럼 system blue 배경과 흰색 텍스트로 정리한다.
- [x] hover/selected/inactive 상태가 서로 구분되는지 확인한다.
- [x] 빈 목록, 검색 결과 없음, 선택된 회의 없음 상태가 과하게 설명적이지 않게 정리한다.
- [x] 메인 상단 액션 영역은 툴바처럼 가볍게 정리한다.

주요 확인 파일:

- `lib/presentation/widgets/meeting_sidebar.dart`
- `lib/presentation/screens/home_screen.dart`

완료 조건:

- 사이드바가 웹 대시보드 카드처럼 보이지 않는다.
- 선택 상태와 기본 상태가 명확하다.
- 긴 회의 제목에서도 레이아웃이 깨지지 않는다.
- `flutter analyze` 통과.

## P3 — 설정 화면과 모델 관리

- [x] 모델 관리 섹션을 `필수`, `선택`, `필요한 모델` 그룹으로 나눈다.
- [x] 모델 설명 문구를 줄이고 상태를 더 명확하게 표시한다.
- [x] 모델 다운로드 중 다른 모델 다운로드가 동시에 시작되지 않도록 유지한다.
- [x] 설정 화면 전체에서 정보량이 많은 섹션을 한 번 더 줄인다.
- [x] 드롭다운, 스위치, 체크박스가 macOS 설정 화면처럼 차분하게 보이는지 확인한다.
- [x] 경고/오류 문구는 연한 배경 + 진한 텍스트/아이콘 조합으로 정리한다.
- [x] 고급 설정은 기본 화면에서 너무 강하게 보이지 않도록 접거나 시각적 우선순위를 낮춘다.

주요 확인 파일:

- `lib/presentation/screens/settings_screen.dart`
- `lib/presentation/screens/setup_screen.dart`

완료 조건:

- 모델 상태, 설치 필요 여부, 다운로드 액션이 한눈에 보인다.
- 설정 화면이 Flutter 샘플 앱처럼 보이지 않는다.
- `flutter analyze` 통과.

## P4 — 녹음 준비 모달과 입력 컨트롤

- [x] 녹음 준비 모달의 여백, radius, 그림자를 macOS sheet/dialog 느낌으로 정리한다.
- [x] 마이크 선택, 언어 선택 등 드롭다운을 더 작고 차분한 macOS 컨트롤처럼 정리한다.
- [x] 주요 버튼은 primary/secondary 구분이 명확하게 보이도록 한다.
- [x] 위험하거나 되돌리기 어려운 액션은 빨간색을 쓰되 배경을 과하게 강하게 만들지 않는다.
- [x] 체크박스와 토글은 가능한 경우 macOS 스타일 스위치로 통일한다.

주요 확인 파일:

- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/screens/settings_screen.dart`

완료 조건:

- 모달이 브라우저 alert나 Bootstrap dialog처럼 보이지 않는다.
- 키보드 포커스, disabled 상태, 긴 텍스트가 깨지지 않는다.
- `flutter analyze` 통과.

## P5 — 녹음/전사/요약 상태 표현

- [x] 녹음 중 파형이 너무 날카롭거나 튀지 않는지 확인한다.
- [x] 녹음 상태 색상을 system blue 중심으로 차분하게 정리한다.
- [x] 전사/요약 로딩은 얇은 progress indicator 또는 spinner 중심으로 정리한다.
- [x] 로딩 문구는 짧고 회색 톤으로 줄인다.
- [x] 오류/중단/완료 상태가 서로 명확히 구분되는지 확인한다.

주요 확인 파일:

- `lib/presentation/widgets/recording_view.dart`
- `lib/core/services/menu_bar_service.dart`

완료 조건:

- 녹음 중, 전사 중, 요약 중 상태가 전문적인 데스크톱 앱처럼 보인다.
- 상태 변화로 레이아웃이 흔들리지 않는다.
- `flutter analyze` 통과.

## P6 — 브랜드명 최종 점검

- [x] 앱 표시명은 `Local Minutes`로 유지한다.
- [x] App Store 및 문서 타이틀은 `Local Minutes - 로컬 회의록`로 유지한다.
- [x] DMG 파일명은 `LocalMinutes_v<version>_build<build>.dmg` 규칙을 유지한다.
- [x] 사용자-facing 문서에 예전 `적자생존` 또는 예전 DMG명이 남아 있지 않은지 확인한다.
- [x] 과거 작업 로그의 역사 기록은 무리하게 수정하지 않는다.

확인 명령:

```bash
rg -n "적자생존|LocalMinutes_v1|LocalMinutes 허용" README.md INSTALL.md USER_MANUAL.md PRIVACY_POLICY.md APP_STORE_CONNECT_COPY.md APP_STORE_METADATA_KO.md APP_STORE_PREP_CHECKLIST.md APP_STORE_PRIVACY_ANSWERS.md APP_STORE_SUBMISSION_NOTES.md APP_STORE_PRICING.md CODEX_TODO.md docs scripts macos lib test tool
```

완료 조건:

- 사용자-facing 경로에서 예전 이름이 검출되지 않는다.
- 히스토리성 작업 로그에 남은 예전 이름은 의도적으로 유지한 것으로 구분한다.

## 최종 검증

- [x] `dart format` 실행이 필요한 파일만 포맷한다.
- [x] `flutter analyze` 통과.
- [x] 가능하면 주요 테스트를 실행한다.
  - 명령: `flutter test`
- [x] DMG 빌드.
  - 명령: `./scripts/build_dmg.sh --no-bump`
- [x] DMG 검증.
  - 명령: `hdiutil verify dist/LocalMinutes_v2.1.1_build28.dmg`
- [x] 변경 요약 확인.
  - 명령: `git diff --stat`
- [ ] 커밋 전 사용자에게 변경 범위와 검증 결과를 공유한다.

## 커밋 기준

- UI 변경과 문서 변경이 너무 커지면 커밋을 나눈다.
- 권장 커밋 1: `Polish macOS settings and setup UI`
- 권장 커밋 2: `Align Local Minutes branding docs`
- 커밋 전 반드시 `flutter analyze`와 DMG 빌드 결과를 확인한다.
