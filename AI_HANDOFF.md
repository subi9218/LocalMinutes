# AI Handoff — 적자생존 / LocalMinutes

이 문서는 다른 AI/개발자가 현재 앱의 목적, 구현 상태, 최근 의사결정, 성능 측정, 남은 리스크를 빠르게 이어받기 위한 인수인계 문서입니다.

마지막 업데이트: 2026-05-09

## 다음 AI 빠른 시작

현재 상태:

- 앱은 macOS용 Flutter 회의록 앱 `적자생존`
- 로컬 온디바이스 STT/화자 라벨/요약 중심 제품
- 첫 실행 저장 폴더 선택 필수
- 자동 요약은 제거됨. 회의 종료 후 사용자가 직접 요약 실행
- 녹음 준비 다이얼로그에 실시간 마이크 테스트 추가 완료
- 회의 상세 요약 항목에 `근거` 버튼 UX 개선 완료
- 회의록 Markdown 저장/복사 추가 완료
- 회의록 Notion용 요약/보고서 형식/액션아이템 단독 복사 추가 완료
- 회의록 DOCX 저장 추가 완료
- 보고서 형식 PDF/DOCX 저장 추가 완료
- 회의 상세 태그 자동 추천 추가 완료
- 다국어 회의용 음성 인식 자동 감지 옵션 추가 완료
- 요약 신뢰도 v3 1차: 액션아이템 담당자/기한 미확인 표시 완료
- 정기 회의 시리즈 자동 인식 1차: 사이드바 추천/적용 UX 추가 완료
- P0 앱스토어 안전 모델 정리: 제한 모델 저장값/다운로드 경로 fallback 보강 완료
- 버전 관리 정리: 앱 표시 버전은 실제 번들 버전 기반, DMG 빌드 시 build number 자동 증가
- DMG 설치 앱 실행 실패 수정: 직접 배포용 entitlements/ad-hoc 재서명으로 `libisar.dylib` Library Validation 차단 해결
- 긴 WAV 다시 전사 예상 시간 보정: 이전 실제 STT RTF를 반영하고 빠른 모델 fallback 추정치를 현실화
- STT/요약 속도 개선: STT `빠름/표준/정밀` 디코딩 프로필, 요약 `빠른/균형/정밀` 모드 추가
- 49분 파일 벤치 결과 빠름(greedy)만으로는 개선이 작아, 긴 파일 재전사 오버랩을 5초에서 2초로 축소
- Core ML STT 가속 통합: 빠른 모델 기준 49분 25초 WAV가 Metal-only `628.387초` → Core ML encoder `203.654초`로 개선
- 2026-05-06 추가 QA: 29~38분대 긴 WAV 3개가 빠름 기준 `115~152초`, 대표 38분 파일 표준 기준 `161.747초`로 처리됨
- 2026-05-06 품질 QA: generic initial prompt `회의록 전사.` 누출 케이스를 확인해, 실제 용어/참석자 힌트가 있을 때만 prompt를 주도록 수정
- 2026-05-06 녹취록 검색 한글 입력 수정: 검색창 포커스 중 `J/K/Space` 단축키를 꺼서 두벌식 모음 입력이 먹히지 않는 문제 해결
- 2026-05-06 사용자 노출 텍스트 정리: 다이얼로그/상태/에러/다운로드 라벨에서 `LLM` → `요약 모델`, `Whisper STT` → `음성 인식`. P1 #2 처리 시간 카드 / #3 요약 템플릿 UI / #4 요약 재생성(SummaryStyleMode 5종) / #5 전사 보정 도구(전사 헤더 spellcheck 팝업 — 단어집 추가/치환/별칭 재교정) / P2 #7 요약 신뢰도 v2(LLM `*Evidence` 4종 배열, `Summary.evidenceJson`, evidence 직접 점프, ownerConfirmed/deadlineConfirmed, "확인 필요" 배지)는 코드상 이미 구현되어 있음을 확인하고 NEXT_AI_TASKS.md를 최신화
- 2026-05-06 P2 #9 시리즈 진행 분석 v1: 그룹 헤더의 `Icons.timeline` 아이콘으로 메인 영역에 진행 대시보드 표시. `MeetingSeriesProgress.analyze(groupId)`가 회의 수/평균 주기/누적 미완료 액션/최근 결정/반복 등장 미해결 이슈를 추출하고 `SeriesDashboardView`가 카드로 노출. 항목 클릭 시 회의 상세 점프. LLM 추가 호출 없이 저장된 `Summary` 활용. 단위 테스트 2개 추가, `flutter analyze` 0 issues / 19 tests pass
- 2026-05-09 P2 추가 3건 (AI 검색 보강 + 시리즈 비교 + 회의 비교):
  (1) AI 검색 keyword pre-filter — `MeetingKeywordSearch.rank(query, meetings, summaries, topN)`가 쿼리 토크나이즈(2글자 미만 제거) → title/tags/notes/agenda/transcriptPreview + summary 필드 매칭, 키워드 등장 횟수로 스코어. 상위 30개만 LLM에 전달(이전 60개 → 30개). 매칭 0개면 입력 순서 폴백. `_runAiSearch`가 사용. 테스트 9개.
  (2) 시리즈 비교 대시보드 — `SeriesOverview.analyze(groups, meetingRepo, summaryRepo)`가 모든 그룹 `MeetingSeriesProgress.analyze` 결과 수집. 사이드바 하단 `📊 시리즈 비교` 버튼(다이제스트 옆) → `MacosSheet`. 카드마다 회의 수/평균 주기/마지막 N일 전/미완료/지속 이슈/결정 표시. 카드 클릭 시 해당 시리즈 대시보드로 점프. 회의 0회 그룹 자동 제외. 마지막 회의 최신순 정렬. 테스트 5개.
  (3) 회의 비교 — `MeetingComparison.compare(earlier, later, earlierSummary, laterSummary)`가 keyDiscussions/decisions/openQuestions/actions 4개 섹션 diff 산출. `_roughlySame` 부분 일치(8자 이상 substring)로 task/string 매칭. 시리즈 대시보드 헤더 `⇄` 아이콘 → `_CompareSheet`로 picker + 결과 표시. dropdown 두 개로 회의 선택, 시간순 자동 정렬. 4개 섹션 카드 — `+`/`−`/`·` 마커, 액션은 전이 상태(`completed`/`reopened`/`stillOpen`/`stillCompleted`) + 담당자/마감 변경 표식. 테스트 8개.
  `flutter analyze` 0 issues, `flutter test` 90/90 통과 (68 → 90, 새 테스트 22개).
- 2026-05-09 P2 인사이트/업무 흐름 5건:
  (1) 회의 품질 점수 — `MeetingQuality.analyze(summary, transcripts)` decisions/actions/balance/evidence 4개 sub-score 가중 평균(30/30/15/25), 우수/양호/보통/개선 필요 등급. 개선 힌트(담당자 미지정/발화 편중/근거 미명시 등)를 행동 가능한 메시지로. LLM 추가 호출 없음. 회의 상세 `_QualityScoreCard` (처리 시간 카드 아래). 단위 테스트 10개.
  (2) 화자 발언 통계 — `SpeakerStats.analyze(transcripts)` 화자별 발화 시간/세그먼트/점유율 + 미식별 bucket. 8색 팔레트, `Meeting.speakerNamesJson` 사용자 지정 이름. 회의 상세 `_SpeakerStatsCard` (품질 카드 아래) — 누적 가로 막대 + per-speaker 행. 단위 테스트 7개.
  (3) 액션아이템 회차별 변화 추적 — `MeetingSeriesProgress`에 `TrackedAction`/`ActionAppearance`/`TrackedActionStatus`(ongoing/resolved/dropped) 추가. `_roughlySame` 부분 일치로 task 매칭, 담당자/마감 변경 배지. 시리즈 대시보드 `_ActionTimelineCard`. 테스트 2개.
  (4) 주간/월간 다이제스트 — `DigestReport.generate(period, meetingRepo, summaryRepo)` 주간(월요일 시작)/월간. 기간 내 모든 회의의 미완료 액션/결정/미해결 이슈 집계. 사이드바 하단 `📅 다이제스트` 버튼 → `MacosSheet` + `SegmentedButton` 토글. 회의 클릭 시 시트 닫고 회의 상세로 점프. 테스트 7개.
  (5) AI 검색 KV 캐시 초과 fix — `_runAiSearch`가 `loadLlm`을 `nCtx: 2048`(기본값 4096의 절반)로 다운설정해서 회의 목록 컨텍스트 2574 토큰으로 초과 발생. `nCtx: 4096`로 정상화 + `maxMeetings: 60` + `maxCharsPerMeeting: 140` + 잘림 안내. 빠른 fix이지만 회의가 매우 많은 경우엔 keyword pre-filtering 도입 검토 필요.
  `flutter analyze` 0 issues, `flutter test` 68/68 통과 (40 → 68, 새 테스트 28개).
- 2026-05-09 P2 미세 개선 두 건: (1) 요약 카드 "근거 미명시" 배지 — `_EvidenceButton`이 evidenceTs 빈 문자열일 때 ⚠️ + "근거 미명시" 라벨 + 명확한 tooltip ("LLM이 근거 타임스탬프를 명시하지 않았습니다…"). keyDiscussions/decisions/openQuestions 세 카드 모두 동일 적용. (2) 시리즈 이슈 매칭 정밀도 — `MeetingSeriesProgress`가 정규화 키 동등 비교 → `_roughlySame` 부분 일치(8자 이상에서 한쪽이 다른 쪽을 포함하면 같은 이슈)로 변경. `SummaryParser._roughlySame`과 동일 규칙. 회귀 테스트 2개 추가, 총 42/42 통과
- 2026-05-09 옵션 C macos_ui Phase 4 완료: 다이얼로그 23개를 9개 Step에 걸쳐 `MacosAlertDialog` / `MacosSheet`로 전환. `showDialog` → `showMacosAlertDialog` / `showMacosSheet`, `AlertDialog(title, content, actions)` → `MacosAlertDialog(appIcon, title, message, primaryButton, secondaryButton)`, `Dialog(shape:)` → `MacosSheet(child:)`, action 버튼은 `PushButton(secondary: true / color:)`. 2 buttons + 단순 콘텐츠는 `MacosAlertDialog`, 3+ buttons 또는 큰 layout(IconButton 닫기 등)은 `MacosSheet`. 파괴적 액션은 `color: MacosColors.systemRedColor`. 클래스 기반 다이얼로그(`_SummaryHistoryDialog`, `_TermExtractDialog`, `_SummaryEditDialog`)는 build의 `Dialog` → `MacosSheet`로 바꾸고 호출 측 `showDialog` → `showMacosSheet`. 가장 큰 폼인 `_RecordingPrepDialog`(520×540, 회의제목/말할 사람 수/마이크/회의 유형/MicTestPanel)도 `MacosAlertDialog`로 변환. 내부 폼 위젯(`TextField`/`DropdownButtonFormField`/`SegmentedButton`/`SwitchListTile`/`RadioListTile`/`ChoiceChip`/`FilterChip`/`CheckboxListTile`)은 회귀 위험 최소화 차원에서 Material 그대로 유지. `flutter analyze` 0 issues, `flutter test` 40/40 통과
- 2026-05-09 옵션 C macos_ui Phase 3 완료: `lib/presentation/widgets/recording_view.dart`(L2347–2415, L2547–2625, L3235, L4830) + `lib/presentation/widgets/meeting_detail_view.dart`(L2057, L2147, L2260, L2386–2480, L2725, L3466, L5253, L5560, L6431) 메인 뷰 Material 위젯 23개를 macos_ui로 전환. 매핑: `FilledButton.icon` → `PushButton(color: <Color>)` + 흰 icon/text, `OutlinedButton.icon` → `PushButton(secondary: true)` + 색상은 icon/text에만, `IconButton` (ghost) → `MacosIconButton(backgroundColor: Colors.transparent)` + 명시적 `boxConstraints`, `Tooltip`/`IconButton.tooltip` → `MacosTooltip`, `TextButton.icon`(라벨 있음) → `PushButton(secondary, ControlSize.small)`. 빨강/녹색 강조는 `MacosColors.systemRedColor/systemGreenColor` 다이나믹 컬러로 라이트/다크 자동 대응. 보라/인디고/청록/앰버/오렌지 브랜드/구분 색은 그대로 유지(icon/text에). 다이얼로그 안 위젯(L4735 `_MicTestPanel`, L4964 화자 편집 등)은 Phase 4로 이연. `PopupMenuButton` 3곳(요약 헤더, 타임라인, 전사 spellcheck)과 `Slider`(오디오 재생바)는 macos_ui 직접 대응 없어 유지. `flutter analyze` 0 issues, `flutter test` 40/40 통과. 5개 Step 각각 빌드/시각 QA로 회귀 확인
- 최근 검증: Core ML 벤치/품질 QA, `flutter analyze`, `flutter test` **90/90**, `flutter build macos --debug` 통과, `./scripts/build_dmg.sh` 통과, `hdiutil verify` VALID, `codesign --verify --deep --strict` 통과
- 최근 DMG: `dist/적자생존_v2.1.1_build26.dmg` (P2 추가 3건 통합 안정 마커, 47M). pubspec 버전 `2.1.1+26`. build26 = AI 검색 keyword pre-filter + 시리즈 비교 대시보드 + 회의 비교. build25 = 회의 품질 점수 + 화자 발언 통계 + 액션 회차별 변화 추적 + 주간/월간 다이제스트 + AI 검색 KV fix. 이전 build24 = macos_ui Phase 3+4 완료. build23 = Phase 3, build22 = Phase 2c. 옵션 C macos_ui 모든 Phase 완료. 남은 macos_ui 미대응 위젯: `PopupMenuButton` 3곳, `Slider`(오디오), `ChoiceChip`/`FilterChip`/`SegmentedButton`/`RadioListTile`/`SwitchListTile`/`CheckboxListTile`/`TextField`/`DropdownButtonFormField` (모두 macos_ui 직접 대응 없음 — 필요 시 별도 작업)

다음 추천 작업:

1. App Store 제출 준비
   - Privacy Policy URL, Support URL, Bundle ID 확정
   - Apple Distribution 인증서/프로비저닝 준비
   - Xcode Archive 후 strict 검사

2. `정기 회의 시리즈 고도화`
   - 같은 시리즈의 이전 결정사항, 미해결 이슈, 액션아이템 변화를 추적
   - 그룹 상세/대시보드에서 진행 변화 요약

가장 중요한 개발 원칙:

- 오디오 원본은 기본적으로 지우지 말 것
- 사용자가 만든 DB/녹음 파일을 임의 삭제하지 말 것
- 자동 요약을 되살리지 말 것
- 저장 폴더 선택 필수 정책을 되돌리지 말 것
- STT/화자 라벨/요약 네이티브 작업은 동시에 실행하지 말 것
- 앱스토어 안전 모드에서 EXAONE, Calendar AppleEvent 등 심사 리스크 요소를 노출하지 말 것
- GPT/OpenAI STT 재시도 금지. 사용자가 중단을 요청했고 기존 API quota도 부족했음

개발 명령:

```bash
flutter analyze
flutter test
flutter build macos --debug
./scripts/version.sh show
./scripts/version.sh bump-patch
./scripts/build_dmg.sh
open "/Users/channy/LocalMinutes/build/macos/Build/Products/Debug/적자생존.app"
```

## 프로젝트 개요

- 앱 이름: `적자생존`
- 플랫폼: Flutter macOS 앱
- 목적: 맥에서 회의를 녹음하고, 온디바이스 STT/화자 분리/LLM 요약으로 회의록을 생성하는 프라이버시 중심 회의록 앱
- 핵심 포지셔닝: 클라우드 업로드 없이 로컬 모델로 한국어 회의 전사와 요약을 처리
- 저장소 경로: `/Users/channy/LocalMinutes`

## 기술 스택

- UI: Flutter + Riverpod
- 로컬 DB: Isar
- STT: whisper.cpp 커스텀 FFI 래퍼
- 화자 분리: sherpa-onnx
- LLM 요약: llama.cpp 커스텀 FFI 래퍼
- 주요 모델 파일 위치: macOS Application Support 아래 `models`
- 녹음 파일 저장 위치: 사용자가 첫 실행 때 선택한 폴더. 더 이상 기본 Application Support로 자동 저장하지 않음

## 현재 모델 구성

STT 모델:

- 빠른 모델: `ggml-large-v3-turbo-q8_0.bin`
- 빠른 모델 Core ML 가속팩: `ggml-large-v3-turbo-encoder.mlmodelc` (선택 설치, 없으면 Metal fallback)
- 정확 모델: `ggml-large-v3-q5_0.bin`
- 현재 기본 정책: 정확 모드 기본값 `true`

LLM 모델:

- `gemma4_e2b`
- `qwen25_7b`
- `exaone35_7b`는 내부 테스트 빌드 전용. 앱스토어 안전 모드에서는 숨김

화자 분리 모델:

- `sherpa-onnx-pyannote-segmentation-3-0.onnx`
- `3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx`

## 핵심 사용자 흐름

1. 앱 첫 실행
   - 저장 폴더가 비어 있으면 `StorageSetupScreen`이 먼저 뜸
   - 3단계 온보딩: 로컬 처리/외부 미전송 안내 → 음성 인식·요약 모델 준비 안내 → 저장 폴더 선택
   - "회의 내용은 내 Mac 밖으로 나가지 않습니다"와 외부 서버 미전송을 첫 단계에서 강조
   - 사용자가 녹음 저장 폴더를 반드시 선택해야 홈/모델 설정으로 진입 가능

2. 녹음 시작
   - `녹음 준비` 다이얼로그가 뜸
   - 회의 제목, 말할 사람 수, 마이크, 요약 템플릿, 발화자 라벨 사용 여부를 한 화면에서 설정
   - 선택한 마이크 기준으로 실시간 입력 레벨 테스트가 표시됨
   - 마이크 가이드가 아직 표시되지 않았다면 준비 다이얼로그 안에 체크리스트로 표시
   - 말할 사람 수는 2~6명 중 선택하며, 해당 회의의 발화자 라벨 힌트와 전역 `numSpeakersHint`에 반영됨

3. 녹음 중
   - 30초 윈도우 기반 실시간 초안 STT
   - 정확 모드에서 빠른 모델이 설치되어 있으면 녹음 중에는 빠른 모델, 요약 전에는 정확 모델로 최종 재전사

4. 녹음 종료
   - 자동 요약은 제거됨
   - 항상 `녹음 완료. 요약을 실행하세요.` 상태로 멈춤
   - 사용자가 직접 요약 버튼을 눌러야 LLM 요약 시작

5. 요약
   - 요약 실행 전에 회의 길이 기반 예상 처리 시간 다이얼로그를 표시
   - 정확 음성 인식, 발화자 라벨, 요약 생성 예상 시간을 보여주며 발화자 라벨을 끄고 빠르게 진행할 수 있음
   - STT 최종본 저장 후 발화자 라벨 선택 실행
   - 전사본, 메모, 단어집, 템플릿을 반영해 LLM 요약
   - 긴 전사본은 `ChunkedSummarizer`가 map-reduce 방식으로 구간 요약 후 통합

## 최근 주요 변경 사항

### DMG 설치 앱 실행 실패 수정

파일:

- `macos/Runner/DirectDistribution.entitlements`
- `scripts/build_dmg.sh`
- `TASKS.md`

내용:

- 설치된 DMG 앱이 Dock에 잠깐 뜬 뒤 열리지 않는 문제 확인
- 시스템 로그 원인: `Library Validation failed`, `Library not loaded: @rpath/libisar.dylib`
- App Store용 `Release.entitlements`는 그대로 두고 직접 배포 DMG용 entitlements를 별도 추가
- 직접 배포 DMG에서는 `com.apple.security.cs.disable-library-validation=true`를 적용해 포함 dylib 로드를 허용
- `scripts/build_dmg.sh`가 스테이징된 `.app`의 내부 dylib/framework와 앱 번들을 ad-hoc으로 재서명
- 새 산출물: `dist/적자생존_v2.1.1_build3.dmg`

검증:

- `/Applications/적자생존.app` 재서명 후 실행 성공
- `hdiutil verify dist/적자생존_v2.1.1_build3.dmg`: 통과
- DMG 내부 앱 `codesign --verify --deep --strict`: 통과

### 버전 관리 및 build2 DMG

파일:

- `lib/presentation/widgets/app_version_credit.dart`
- `lib/presentation/screens/home_screen.dart`
- `lib/presentation/widgets/meeting_sidebar.dart`
- `scripts/version.sh`
- `scripts/build_dmg.sh`
- `pubspec.yaml`
- `TASKS.md`

내용:

- 홈 빈 화면과 사이드바 하단의 하드코딩 `v1.0` 제거
- `PackageInfo.fromPlatform()` 기반 공용 버전/작성자 위젯 추가
- 앱 UI가 실제 macOS 번들 버전 `CFBundleShortVersionString`을 표시
- `scripts/version.sh`로 `version: x.y.z+n`을 관리
- `scripts/build_dmg.sh`는 기본 실행 시 build number를 자동 증가시키고, `--build-name`, `--build-number`에 pubspec 버전을 명시 전달
- 새 산출물: `dist/적자생존_v2.1.1_build2.dmg`

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `scripts/build_dmg.sh`: 통과
- `hdiutil verify`: 통과
- `codesign --verify --deep --strict`: 통과

### P0 앱스토어 안전 모델 정리

파일:

- `lib/core/services/app_settings.dart`
- `lib/presentation/screens/setup_screen.dart`
- `lib/presentation/screens/settings_screen.dart`
- `test/app_settings_compliance_test.dart`
- `TASKS.md`

내용:

- 앱 시작 시 과거 `selectedLlmModel=exaone35_7b` 저장값을 안전 기본 모델로 자동 정리
- 앱스토어 안전 모드에서 Calendar 자동 추가 설정이 남아 있으면 `false`로 정리
- 초기 설정/설정 화면의 EXAONE 다운로드 함수가 직접 호출돼도 안전 모드에서는 즉시 반환
- 초기 설정 화면의 EXAONE URL 컨트롤러는 내부 빌드에서만 URL을 보유
- 앱스토어 안전 모드의 제한 모델 제외, 저장값 정리, 파일/URL fallback 회귀 테스트 추가

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 보고서 파일 저장 템플릿

파일:

- `lib/core/services/export_service.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `test/export_service_test.dart`
- `TASKS.md`

내용:

- 내보내기 메뉴에 `보고서 PDF 저장`, `보고서 Word 저장` 추가
- 전체 회의록 파일 저장과 달리 전사본을 제외하고 보고용 핵심 섹션만 출력
- 보고서 구성: 제목/일자/참석자, 핵심 논의, 결정 사항, 액션 아이템, 리스크/확인 필요
- 보고서 DOCX가 전사본을 포함하지 않는지 회귀 테스트 추가

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### DOCX 내보내기

파일:

- `lib/core/services/export_service.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `test/export_service_test.dart`
- `TASKS.md`

내용:

- 내보내기 메뉴에 `Word 문서로 저장 (.docx)` 추가
- 회의 제목, 날짜, 소요 시간, 참석자, 주요 논의, 결정 사항, 액션 아이템, 미해결 이슈, 전사본을 DOCX로 출력
- 기존 `archive` 패키지로 기본 WordprocessingML 패키지를 직접 생성
- 생성된 DOCX 구조와 주요 문서 내용 회귀 테스트 추가

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### P1 일반 사용자 UX 보강

파일:

- `lib/core/services/export_service.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `lib/presentation/screens/settings_screen.dart`
- `test/export_service_test.dart`
- `TASKS.md`

내용:

- 내보내기 메뉴에 `Notion용 요약 복사`, `보고서 형식 복사`, `액션아이템만 복사` 추가
- Notion용 요약은 전체 전사본을 제외하고 회의 핵심만 Markdown으로 복사
- 보고서 형식은 일자/참석자 표와 핵심 논의, 결정 사항, 액션아이템, 리스크 섹션으로 구성
- 액션아이템 단독 복사는 체크리스트 형태로 담당자/기한 포함
- 설정 화면의 요약 템플릿 문구에서 `LLM`, `시스템 프롬프트` 같은 개발자 용어 노출 축소

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 정기 회의 시리즈 자동 인식 1차

파일:

- `lib/core/services/meeting_series_detector.dart`
- `lib/presentation/widgets/meeting_sidebar.dart`
- `test/meeting_series_detector_test.dart`
- `TASKS.md`

내용:

- 미분류 회의의 제목, 태그, 참석자를 기반으로 정기 회의 후보를 탐지
- 제목의 날짜/시간/불러오기 표기를 정규화해 같은 반복 회의를 묶음
- 이미 그룹에 들어간 회의는 사용자의 수동 분류로 보고 자동 추천 대상에서 제외
- 사이드바 하단에 `시리즈 추천` 버튼 추가
- 추천 다이얼로그에서 후보별 회의 수, 신뢰도, 추천 이유, 포함 회의를 확인하고 선택 적용 가능
- 적용 시 기존 `MeetingGroup` 구조를 사용해 새 그룹을 만들고 회의 `groupId`를 갱신

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 녹음 준비 다이얼로그 실시간 마이크 테스트

파일:

- `lib/presentation/widgets/recording_view.dart`
- `TASKS.md`

내용:

- `_MicTestPanel` 추가
- 준비 다이얼로그에서 선택한 입력 장치로 별도 `AudioRecorder.startStream()` 실행
- PCM16 RMS 기반 입력 레벨 계산 후 진행 바로 표시
- 상태 문구:
  - `입력이 잘 들어오고 있어요`
  - `조금 작게 들립니다`
  - `너무 조용합니다`
  - `확인 필요`
- 마이크 선택 변경 시 테스트 스트림 재시작
- 새로고침 버튼으로 마이크 테스트 재시작 가능
- 실제 녹음 시작/취소 전에 테스트 스트림 정리

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 요약 근거 보기 버튼 UX 개선

파일:

- `lib/presentation/widgets/meeting_detail_view.dart`
- `TASKS.md`

내용:

- 기존 근거 기능은 작은 시간/확인 칩 형태라 사용자가 버튼으로 인지하기 어려웠음
- 주요 논의, 결정 사항, 미해결 이슈 항목 오른쪽에 명확한 `근거` 버튼 표시
- 액션 아이템 행에도 같은 `근거` 버튼 표시
- LLM이 근거 시간을 명시한 경우 `근거 02:55`처럼 버튼에 시간 표시
- 근거 시간이 있으면 해당 전사/오디오 시점으로 이동
- 근거 시간이 없으면 전사본에서 관련 후보 구간을 검색해 근거 패널 표시

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 요약 신뢰도 v3 1차

파일:

- `lib/domain/entities/summary.dart`
- `lib/core/utils/summary_parser.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `lib/core/services/export_service.dart`
- `test/action_item_confidence_test.dart`
- `TASKS.md`

내용:

- `ActionItem`에 `ownerConfirmed`, `deadlineConfirmed` 선택 필드 추가
- 기존 JSON도 빈 값, `(미언급)`, `미정`, `TBD` 등은 자동으로 미확인 처리
- 요약 프롬프트에 owner/deadline 확실성 필드 출력 규칙 추가
- 회의 상세 액션아이템 섹션에 확인 필요한 담당자/기한 개수 배너 표시
- 액션아이템 행에 `담당자 미확인`, `기한 미확인` 칩 표시
- 텍스트/PDF/Markdown 내보내기에서도 미확인 정보를 명시

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 다국어 회의 지원

파일:

- `lib/core/services/app_settings.dart`
- `lib/data/datasources/stt_service.dart`
- `lib/domain/entities/meeting_processing_report.dart`
- `lib/presentation/screens/settings_screen.dart`
- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `test/meeting_processing_report_test.dart`
- `TASKS.md`

내용:

- 음성 인식 언어에 `자동 감지` 옵션 추가
- 설정 화면/녹음 준비 다이얼로그/음성 인식 재실행 다이얼로그에서 언어 선택 가능
- `auto` 선택 시 Whisper language auto 사용
- 자동 감지일 때 initial prompt가 한국어로 치우치지 않도록 중립적인 영어 힌트 사용
- 처리 리포트 JSON에 `sttLanguage` 저장
- 회의 상세 기술 정보에서 사용한 음성 인식 언어 표시

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 태그 자동 추천

파일:

- `lib/core/services/tag_extractor.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `lib/presentation/widgets/recording_view.dart`
- `test/tag_extractor_test.dart`
- `TASKS.md`

내용:

- 회의 상세 태그 영역에 `추천` 버튼 추가
- 요약이 있는 회의에서 현재 선택된 요약 모델로 태그 후보 생성
- 추천 후보는 다이얼로그에서 선택 후 적용
- 자동 태그 추출은 기존 수동 태그를 덮어쓰지 않고 병합
- 중복 태그와 너무 일반적인 태그를 필터링
- 작업 중인 네이티브 모델이 있으면 태그 추천을 안내 후 차단

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 회의록 Markdown 내보내기 강화

파일:

- `lib/core/services/export_service.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `TASKS.md`

내용:

- `ExportService.buildMarkdown()` 추가
- `ExportService.saveAsMarkdown()`으로 `.md` 파일 저장 지원
- `ExportService.copyMarkdown()`으로 Markdown 클립보드 복사 지원
- 회의 상세 내보내기 메뉴에 `Markdown으로 저장 (.md)`, `Markdown 복사` 추가
- Markdown에는 제목, 날짜, 소요 시간, 참석자, 요약 섹션, 액션 아이템 표, 전사본 포함

### 키보드 단축키 확장 QA/보강

파일:

- `lib/main.dart`
- `lib/presentation/providers/meeting_providers.dart`
- `lib/presentation/screens/home_screen.dart`
- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `lib/presentation/widgets/meeting_sidebar.dart`
- `TASKS.md`

현재 단축키:

- `Cmd+Shift+R`: 녹음 시작/정지
- `Cmd+Shift+S`: 녹음 화면에서는 요약 실행, 회의 상세에서는 재요약 실행
- `Cmd+F`: 사이드바 검색 포커스
- `Cmd+,`: 설정 열기
- 회의 상세 전사 패널:
  - `Space`: 오디오 재생/일시정지
  - `J`: 이전 세그먼트
  - `K`: 다음 세그먼트
- 녹음 화면:
  - `Cmd+B`: 북마크 추가

이번 보강:

- AI/STT/요약 등 네이티브 작업 중 `Cmd+Shift+R`로 녹음을 시작하려 하면 안내 표시
- 시작 화면의 `새 녹음 시작` 버튼도 네이티브 작업 중이면 차단
- 녹음 중 `Cmd+Shift+S`를 누르면 녹음 중지 후 요약 가능 안내
- 이미 요약 중이면 중복 요약 안내
- 전사 내용이 없는 상세 화면에서 `Cmd+Shift+S`를 누르면 음성 인식 먼저 실행 안내

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 빈 세션 감지 고도화

파일:

- `lib/domain/entities/meeting_processing_report.dart`
- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `lib/presentation/widgets/meeting_sidebar.dart`
- `TASKS.md`

내용:

- 녹음 시간, 마이크 입력 바이트, 전사 세그먼트 수, 인식 글자 수, 최대 입력 레벨을 함께 평가
- 입력 품질 상태:
  - `empty`: 거의 빈 녹음
  - `low`: 요약 품질 낮을 수 있음
  - `ok`: 정상
- 요약 전 품질 경고 다이얼로그 개선
  - `보관만 하기`
  - `삭제`
  - `그래도 요약하기`
- 전사 세그먼트가 없는 녹음은 요약을 막고 삭제/보관만 제공
- `MeetingProcessingReport`에 입력 품질 필드 추가:
  - `inputQualityStatus`
  - `inputQualityReason`
  - `inputRecognizedChars`
  - `inputSegmentCount`
  - `inputMaxLevel`
- 사이드바 회의 목록에 `마이크 입력 낮음`, `전사 부족` 경고 표시
- 회의 상세 `작업 시간` 카드에 `녹음 품질` 항목 표시
- 고급 정보에서 품질 사유, 전사 글자/세그먼트, 최대 입력 레벨 표시
- 품질 문제는 `CrashLogService.info()`로 로컬 로그 기록
- 추가된 로그 context:
  - `emptyRecordingAfterStop`
  - `summaryBlockedEmptyRecording`
  - `summaryLowQualityPrompt`
  - `persistMeetingInputQuality`

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 진단 로그 내보내기 UX 고도화

파일:

- `lib/presentation/screens/settings_screen.dart`
- `TASKS.md`

내용:

- 설정 화면의 `디버그·진단` 섹션명을 일반 사용자용 `문제 해결`로 변경
- 섹션 상단에 프라이버시 안내 고정 표시:
  - 원본 녹음 파일 미포함
  - 전체 전사 텍스트 미포함
  - 회의 요약 전문 미포함
  - 회의 제목 원문 미포함
- 최근 충돌·예외 로그 크기를 설정 화면에 표시
- 진단 ZIP 내보내기 전 확인 다이얼로그 추가
- 저장 완료 후 파일 경로를 클립보드에 복사하고 SnackBar에서 `Finder 열기` 액션 제공
- 로그 파일 위치 버튼도 Finder에서 폴더를 열도록 변경
- 진단 ZIP 생성 실패와 Finder 열기 실패는 `friendlyErrorText()`로 사용자용 안내 표시
- 실제 예외는 `CrashLogService.recordCaught()`로 로컬 로그 기록
- 추가된 로그 context:
  - `exportDiagnostics`
  - `openPathInFinder`

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 에러 처리 강화

파일:

- `lib/core/services/user_error_message.dart`
- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `lib/presentation/screens/setup_screen.dart`
- `lib/presentation/screens/settings_screen.dart`
- `TASKS.md`

내용:

- `UserErrorMessage` / `friendlyErrorMessage()` / `friendlyErrorText()` 추가
- 디스크 부족, 권한 문제, 네트워크 문제, 모델 로드 실패, 메모리 부족, 오디오 파일 문제를 사용자용 문구로 변환
- 녹음 시작, 전사 저장, 정확 전사, 요약, 재요약, STT 다시 돌리기, 용어 추출, 모델 다운로드 일반 예외에 적용
- 사용자는 원인과 다음 행동을 보고, 실제 raw exception은 `CrashLogService.recordCaught()` 로컬 로그에 기록
- 추가된 로그 context:
  - `startRecording`
  - `persistMeetingAndTranscripts`
  - `runSummary`
  - `refreshFinalTranscript`
  - `resummarize`
  - `rerunStt`
  - `extractTerms`
  - `setupModelDownload`
  - `settingsModelDownload`

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 화자 라벨 실패 안내 정리

파일:

- `lib/data/datasources/diarization_service.dart`
- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `lib/data/datasources/pipeline_service.dart`
- `TASKS.md`

내용:

- `friendlyDiarizationFailureMessage(nextStep:)` 추가
- 화자 라벨 실패 시 UI에는 기술 오류 대신 사용자용 안내 표시
- 요약 전 실패: 라벨 없이 요약 계속
- STT 다시 돌리기 중 실패: 라벨 없이 전사본 저장
- 실제 예외는 `CrashLogService.recordCaught()`로 로컬 로그 기록
- pipeline path도 diarization 실패를 로그에 기록하고 계속 진행

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 앱 종료/창 닫기 중 작업 안내

파일:

- `lib/main.dart`
- `TASKS.md`

내용:

- `MeetingAssistantApp` state가 `WindowListener`를 mixin
- macOS에서 `windowManager.setPreventClose(true)` 설정
- 녹음/일시정지 녹음/STT/화자 라벨/요약/모델 로드 중 종료 시 확인 다이얼로그 표시
- 종료 경로 통합:
  - Cmd+Q / 시스템 종료 요청: `AppLifecycleListener.onExitRequested`
  - 창 닫기: `WindowListener.onWindowClose`
  - 트레이 종료: `MenuBarService.onQuit`
- 사용자가 종료를 확정하면 기존 `_gracefulShutdown()` 유지:
  - 녹음 정지
  - LLM 취소 요청
  - LLM/STT 언로드
  - 트레이 dispose
- `_exitPromptShowing`, `_isExiting`으로 중복 다이얼로그/중복 종료 방지

사용자 문구:

- `현재 <작업명> 작업 중입니다.`
- `종료하면 진행 중인 작업이 중단되거나 결과가 저장되지 않을 수 있습니다.`
- 버튼: `취소`, `종료`

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 트레이 빠른 녹음 AI 작업 중 차단

파일:

- `lib/main.dart`
- `TASKS.md`

내용:

- 앱 루트에서 `OnDeviceModelManager.nativeTaskStream`을 구독해 트레이 시작 상태를 자동 갱신
- 네이티브 작업 중이면 트레이 시작 메뉴가 `TrayStartState.busy`가 되고 `⏳ <작업명> 중...`으로 표시됨
- `_handleTrayStartRecord()`에서도 현재 네이티브 작업을 재확인
- 작업 중 빠른 녹음 요청이 들어오면 앱 창을 앞으로 가져오고 `AI 작업이 진행 중입니다` 다이얼로그 표시
- 빠른 녹음 pending signal을 보내지 않아 작업 종료 후 뒤늦게 녹음이 시작되는 일을 방지

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 버튼 비활성화/중복 요청 UX 정리

파일:

- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `TASKS.md`

내용:

- 녹음 화면:
  - `요약`, `요약 다시 시도`, `녹음 시작` 버튼이 네이티브 작업 진행 중이면 비활성화
  - tooltip으로 `현재 ... 작업 중입니다. 완료 후 ...을(를) 다시 시도해주세요.` 표시
  - `_runSummary()` 시작 시에도 네이티브 작업 진행 중이면 SnackBar 안내 후 반환
- 회의 상세:
  - `다시 요약`, `요약 생성`, `음성 인식 다시` 버튼이 STT/요약/화자 라벨/모델 로드 중이면 비활성화
  - tooltip으로 비활성화 이유 표시
  - `_runResummarize()`, `_rerunStt()` 시작 시에도 네이티브 작업 진행 중이면 SnackBar 안내 후 반환
- 버튼 영역도 `OnDeviceModelManager.nativeTaskStream`을 구독해 상태가 자동 갱신됨

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 진행 중 네이티브 작업 안내

파일:

- `lib/core/ffi/on_device_model_manager.dart`
- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `TASKS.md`

내용:

- `NativeModelTaskSnapshot` 추가
  - `activeLabel`
  - `queuedLabel`
  - `queuedCount`
- `OnDeviceModelManager.nativeTaskStream` 추가
- 네이티브 작업이 큐에 들어갈 때 `native task queued` 로그 기록
- 요약 진행 카드에 현재 실행 중/대기 중 네이티브 작업 표시
- `STT 다시 돌리기`, `다시 요약` 진행 인디케이터에도 같은 안내 표시

사용자 노출 예:

- `현재 작업: 요약 생성`
- `현재 작업: 발화자 라벨 생성 · 다음 작업 대기: LLM 모델 로드`
- `대기 중: 음성 인식 전사 외 1개`

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 네이티브 모델 작업 직렬화

파일:

- `lib/core/ffi/on_device_model_manager.dart`
- `lib/data/datasources/stt_service.dart`
- `lib/data/datasources/diarization_service.dart`
- `lib/data/datasources/llm_service.dart`
- `TASKS.md`

배경:

- 이전 crash report에서 화자 분리 중 `libsherpa-onnx` worker가 abort되었고, 같은 리포트 main thread에는 `libllama_wrapper.dylib` 모델 로딩 stack이 보였음
- callback-free 화자 분리로 직접 원인은 완화했지만, whisper/sherpa/llama 네이티브 작업이 겹치지 않게 하는 2차 방어막이 필요했음

내용:

- `OnDeviceModelManager.acquireNativeTask(label)` 추가
- `OnDeviceModelManager.runExclusiveNativeTask(label, action)` 추가
- STT 모델 로드/전사/실시간 전사/해제, 화자 분리, LLM 모델 로드/생성/해제를 단일 네이티브 작업 큐로 직렬화
- LLM 생성은 스트림 전체 기간 동안 `NativeModelTaskLease`를 유지해 요약 생성 중 STT/화자 분리가 끼어들지 않음
- `CrashLogService.info()`로 `native task start/end`와 소요 시간을 로컬 로그에 기록

주의:

- 긴 STT 또는 요약 중에는 다른 네이티브 작업이 큐에서 기다릴 수 있음
- UX에서 이미 녹음/요약/재전사 중 중복 버튼을 대부분 막고 있으나, 내부적으로도 겹침을 방지함

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 화자 분리 진행 UX 보완

파일:

- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `lib/data/datasources/pipeline_service.dart`
- `TASKS.md`

내용:

- 요약 실행 중 화자 라벨 단계에서 카드 제목을 `발화자를 구분하고 있습니다`로 표시
- 긴 녹음은 몇 분 걸릴 수 있다는 설명 추가
- 요약 카드 안에 실제 상태 문구 표시
- 단계 표시를 `전사 확인 → 발화자 라벨 → 요약 생성 → 결과 저장`으로 변경
- STT 다시 돌리기 중 화자 라벨 단계에서는 기존 STT 진행률/시간 표시를 초기화하고 indeterminate progress로 표시
- 화자 라벨 단계는 callback-free 안정화로 인해 세밀한 중간 진행률이 없으므로 `진행률이 자주 갱신되지 않을 수 있습니다` 안내 추가
- 파이프라인 단계 문구를 일반 사용자용으로 변경

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 화자 분리 크래시 완화

파일:

- `lib/data/datasources/diarization_service.dart`
- `TASKS.md`

배경:

- 사용자 crash report에서 `Thread 24 DartWorker`가 `DLRT_GetFfiCallbackMetadata` → `libsherpa-onnx-c-api.dylib` → `OfflineSpeakerDiarizationPyannoteImpl::Process` 경로로 `SIGABRT` 발생
- 이는 sherpa-onnx `processWithCallback()`이 네이티브 worker thread에서 Dart FFI callback을 호출하는 경로와 일치
- 같은 crash report의 main thread에는 `libllama_wrapper.dylib` 모델 로딩 stack도 보여 네이티브 모델 작업이 겹친 정황이 있음

조치:

- `DiarizationService`에서 `sd.processWithCallback(...)` 사용 중단
- callback-free `sd.process(samples: wav)`로 변경
- 화자 분리 진행률은 5% 시작, 100% 완료만 보내도록 단순화
- timeout 시 `worker.kill(priority: Isolate.immediate)` 제거
- isolate가 결과 없이 종료되거나 error port로 오류를 보내면 명확한 실패로 처리

효과:

- Dart FFI callback metadata abort 위험 제거
- 네이티브 FFI 실행 중 isolate 강제 종료로 인한 런타임 abort 위험 감소
- 단점: 화자 분리 중간 진행률이 세밀하게 표시되지 않음

검증:

- `flutter analyze`: 통과
- `flutter test`: 통과
- `flutter build macos --debug`: 통과

### 문제 진단 자료 내보내기 UX

파일:

- `lib/core/services/diagnostic_export_service.dart`
- `lib/presentation/screens/settings_screen.dart`
- `test/diagnostic_export_test.dart`
- `pubspec.yaml`
- `pubspec.lock`
- `macos/Flutter/GeneratedPluginRegistrant.swift`
- macOS Pods 관련 생성 파일

내용:

- `archive`, `package_info_plus` 의존성 추가
- `DiagnosticExportService.exportWithSavePanel()` 추가
- 설정 화면 `디버그·진단` 섹션에 `문제 진단 자료 내보내기` 버튼 추가
- 저장 패널로 ZIP 저장
- 저장 완료 시 경로를 클립보드에 복사
- 생성 실패 시 `CrashLogService.recordCaught(..., context: 'exportDiagnostics')`로 기록

ZIP 구성:

- `README.txt`
- `diagnostics.json`
- `logs/crash.log`
- `logs/crash.log.old`가 있으면 포함

개인정보 정책:

- 원본 녹음 파일 미포함
- 전체 전사 텍스트 미포함
- 요약 전문 미포함
- 회의 제목 원문 미포함
- 최근 회의는 id, 상태, 생성/종료 시각, 길이, titleLength, notesLength, transcriptSegmentCount, transcriptTotalChars, summary item count, processingReport 등 메타데이터만 포함
- 사용자 홈 경로는 `~`로 축약

검증:

- `flutter test test/diagnostic_export_test.dart`: 통과
- `flutter test`: 통과
- `flutter analyze`: 통과
- `flutter build macos --debug`: 통과

테스트 상세:

- 테스트에서 임시 Application Support/녹음 폴더를 mock 처리
- 테스트용 회의/전사/요약에 `SECRET_DIAGNOSTIC_*` 문자열을 넣고 ZIP 생성
- ZIP 파일 목록에 `README.txt`, `diagnostics.json`, `logs/crash.log`가 있는지 확인
- ZIP 전체 텍스트에 테스트용 회의 제목/전사/요약 비밀 문자열이 들어가지 않는지 확인
- `flutter test` VM에서 Isar가 루트의 `libisar.dylib`를 찾기 때문에 테스트 시작 시 pub cache의 `isar_flutter_libs` dylib를 임시 복사하고 종료 시 삭제함

### 트레이 메뉴 상태 개선

파일:

- `lib/core/services/menu_bar_service.dart`
- `lib/main.dart`
- `lib/presentation/widgets/recording_view.dart`

내용:

- `TrayStartState` 추가:
  - `ready`
  - `storageRequired`
  - `modelsRequired`
  - `busy`
- `MenuBarService.setStartState()` 추가
- idle 상태 트레이 메뉴가 앱 준비 상태에 따라 다르게 표시됨:
  - 준비 완료: `빠른 녹음 시작`
  - 저장 폴더 없음: `저장 폴더 설정 필요`
  - 모델 준비 전: `AI 모델 준비 필요`
  - 처리 중: `모델 확인 중...`, `녹음 준비 중...`, `녹음 정리 중...`, `요약 중...`
- 준비되지 않은 상태의 시작 메뉴는 disabled
- tooltip도 상태별로 변경
- 앱 루트는 첫 실행/저장 폴더 선택/모델 준비 완료 상태를 트레이에 동기화
- `RecordingView`는 현재 phase를 기준으로 busy/ready/model required 상태를 트레이에 동기화

검증:

- `flutter test`: 통과
- `flutter analyze`: 통과
- `flutter build macos --debug`: 통과

### 트레이 녹음 시작 실패 안내

파일:

- `lib/presentation/providers/meeting_providers.dart`
- `lib/main.dart`
- `lib/presentation/screens/home_screen.dart`
- `lib/presentation/widgets/recording_view.dart`

내용:

- `pendingTrayQuickStartFromTrayProvider` 추가
- 트레이 메뉴에서 시작한 빠른 녹음과 키보드 단축키 시작을 구분
- 트레이 시작 시 `_handleTrayStartRecord()`가 먼저 `_showAppWindow()` 호출
- 저장 폴더가 준비되지 않았거나 모델 설정 화면 단계라면 녹음 신호를 보내지 않고 안내 다이얼로그 표시
- `RecordingView._startRecording({showTrayFailureNotice})`로 확장
- 트레이 시작 실패 시 다음 케이스를 다이얼로그로 안내:
  - 음성 인식 모델 없음
  - 저장 폴더 미설정
  - 저장 폴더 접근 실패
  - 마이크 권한 없음
  - 기타 녹음 시작 오류
- 사용자 화면에 새로 추가한 문구는 `Whisper` 대신 `음성 인식 모델` 중심으로 표현

검증:

- `flutter test`: 통과
- `flutter analyze`: 통과
- `flutter build macos --debug`: 통과

### 트레이 앱 창 열기 포커스 보강

파일:

- `pubspec.yaml`
- `pubspec.lock`
- `lib/main.dart`
- `macos/Flutter/GeneratedPluginRegistrant.swift`
- macOS Pods 관련 생성 파일

내용:

- `window_manager: ^0.5.1` 추가
- 앱 시작 시 macOS에서 `windowManager.ensureInitialized()` 실행
- `MenuBarService.onShowWindow`가 `_showAppWindow()`를 호출하도록 변경
- `_showAppWindow()` 흐름:
  - 최소화 상태면 `windowManager.restore()`
  - `windowManager.show()`
  - `windowManager.focus()`
- `window_manager` macOS 구현 확인 결과:
  - `show()`는 `makeKeyAndOrderFront`와 `NSApp.activate(ignoringOtherApps: true)` 호출
  - `focus()`는 `makeKeyAndOrderFront` 호출

검증:

- `flutter test`: 통과
- `flutter analyze`: 통과
- `flutter build macos --debug`: 통과

### 트레이 빠른 녹음 QA

결과:

- 코드 경로 기준으로 빠른 녹음 시작/북마크/녹음 정지 흐름 점검 완료
- `RecordingView`가 마운트된 상태와, 다른 회의 상세 화면 때문에 언마운트된 상태 모두 pending provider로 복구되는 구조 확인
- Debug 앱 실행 및 프로세스 확인 완료
- 최근 macOS 로그에서 앱 크래시 징후 없음

검증:

- `flutter test`: 통과
- `flutter analyze`: 통과
- `flutter build macos --debug`: 통과

제한:

- 현재 Codex 실행 환경에는 macOS 보조 접근 권한이 없어 `osascript`로 트레이 메뉴를 직접 클릭하지 못함
- 실제 릴리즈 전 사람이 직접 트레이 메뉴에서 `빠른 녹음 시작` → `북마크 추가` → `녹음 정지`를 눌러 최종 확인 필요

### 트레이 북마크 추가 동작 보강

파일:

- `lib/presentation/providers/meeting_providers.dart`
- `lib/main.dart`
- `lib/presentation/widgets/recording_view.dart`

내용:

- `pendingTrayBookmarkCountProvider` 추가
- 트레이 bookmark 메뉴 액션 시 녹음 화면으로 복귀하도록 `isRecordingActiveProvider=true`, `selectedMeetingIdProvider=null` 처리
- `RecordingView`가 없는 상태에서도 북마크 요청을 count로 보존
- `RecordingView`가 마운트되면 `_consumePendingTrayBookmarks()`가 pending count를 읽어 `_addBookmark(showFeedback:false)`로 저장
- 이미 `RecordingView`가 마운트된 상태에서는 `trayBookmarkSignalProvider` listener가 즉시 저장
- pending 여러 개는 한 번의 SnackBar로 요약 표시

검증:

- `flutter analyze`: 통과
- `flutter build macos --debug`: 통과

### 트레이 녹음 중 상태 표시 보강

파일:

- `lib/core/services/menu_bar_service.dart`

내용:

- `MenuBarService`가 자체 `_recordingTicker`를 갖도록 변경
- 녹음 상태로 전환되면 1초마다 `_elapsed`를 증가시키고 `_rebuildMenu()` 실행
- 녹음 화면이 현재 보이지 않아도 트레이 메뉴의 `녹음 중 · 00:00` 및 tooltip 시간이 계속 갱신됨
- 녹음 종료 또는 서비스 dispose 시 ticker cancel
- 기존 아이콘 전환 유지:
  - idle: `assets/tray/mic_idle.png`, template icon
  - recording: `assets/tray/mic_recording.png`, non-template icon

검증:

- `flutter analyze`: 통과
- `flutter build macos --debug`: 통과

### 트레이 녹음 시작/정지 경로 보강

파일:

- `lib/presentation/providers/meeting_providers.dart`
- `lib/main.dart`
- `lib/presentation/screens/home_screen.dart`
- `lib/presentation/widgets/recording_view.dart`

내용:

- 트레이 start/stop 메뉴 액션의 Riverpod signal 경로를 점검
- `pendingTrayStopProvider` 추가
- 트레이 정지 또는 `Cmd+Shift+R` 정지 시:
  - `isRecordingActiveProvider=true`
  - `selectedMeetingIdProvider=null`
  - `pendingTrayStopProvider=true`
  - `trayStopRecordingSignalProvider++`
- 이로써 녹음 중 사용자가 기존 회의 상세 화면을 보고 있어서 `RecordingView`가 없는 상태여도, 녹음 화면을 다시 마운트한 뒤 `_stopRecording()`을 실행할 수 있음
- `RecordingView`가 이미 마운트되어 signal을 직접 처리하는 경우 pending start/stop flag를 즉시 해제

검증:

- `flutter analyze`: 통과
- `flutter build macos --debug`: 통과

### 빈 녹음 감지 강화

파일:

- `lib/presentation/widgets/recording_view.dart`

내용:

- 녹음 중 낮은 입력을 감지하는 상태값 추가:
  - `_lastAudibleInputAt`
  - `_lowInputBannerDismissed`
  - `_maxInputLevelDuringRecording`
  - `_emptyRecordingPromptShown`
- `MicrophoneService.onLevel` 콜백에서 입력 레벨이 0.08 이상이면 유의미한 음성으로 기록
- 녹음 시작 시 빈 녹음 감지 상태를 초기화
- 녹음 중 20초 이상 경과했고 최근 18초 동안 유의미한 입력이 없으면 `_LowInputWarningBanner` 표시
- 녹음 종료 직후 `_maybeWarnEmptyRecordingAfterStop()` 실행
- 빈 세션 판정:
  - 5초 미만 녹음
  - 마이크 오디오 데이터 0 byte
  - 12초 이상 녹음했지만 전사 세그먼트 없음
  - 20초 이상 녹음, 인식 글자 20자 미만, 최대 입력 레벨 0.10 미만
- 빈 녹음 경고 다이얼로그는 “그냥 유지 / 삭제”만 제공
- 삭제는 사용자가 명시적으로 선택한 경우에만 실행하며, 오디오 파일과 DB 레코드를 함께 정리

검증:

- `flutter analyze`: 통과
- `flutter build macos --debug`: 통과

### 모델 다운로드 오류 안내 개선

파일:

- `lib/core/services/model_download_service.dart`
- `lib/core/constants/app_constants.dart`
- `lib/presentation/screens/setup_screen.dart`
- `lib/presentation/screens/settings_screen.dart`

내용:

- 다운로드 오류를 인증 필요, HTTP/URL 문제, 서버 일시 장애, 네트워크/SSL, 디스크 부족, 권한/파일 저장 실패, URL 형식 오류로 분류
- 401/403은 Hugging Face 토큰/모델 사용 동의 안내
- 404는 URL 변경 가능성 안내
- 429/5xx는 잠시 후 재시도 안내
- `SocketException`/`HandshakeException`은 인터넷 연결, VPN, 프록시, 회사 보안 프로그램 확인 안내
- `FileSystemException`의 macOS error code 28은 저장 공간 부족, 13/1은 권한 문제로 안내
- 모델별 예상 크기를 `AppConstants.expectedModelBytes()`로 제공하고, 모델 크기 + 200MB 여유 공간을 다운로드 시작 전에 확인
- 첫 설정 화면과 설정 화면 모두 `expectedBytes`를 전달
- 인증 실패 시 토큰 입력란을 열고, 카드에도 오류 메시지를 남김

검증:

- `flutter analyze`: 통과
- `flutter build macos --debug`: 통과

### 안정성 개선 — 요약 중지/종료 보강

파일:

- `lib/data/datasources/llm_service.dart`
- `lib/core/services/chunked_summarizer.dart`
- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `lib/main.dart`

내용:

- `LlmService.requestCancelActiveGeneration()` 추가
- LLM 생성 worker isolate가 control port를 통해 취소 신호를 받도록 개선
- worker loop가 토큰 4개마다 event loop에 양보해 취소 메시지를 처리
- 녹음 직후 요약과 회의 상세 재요약의 중지 버튼에서 LLM worker에 즉시 취소 요청
- 앱 graceful shutdown에서 `unloadLlm()` 전에 진행 중 생성 작업을 먼저 취소 요청
- `ChunkedSummarizer._runLlm()`은 취소 후 부분 생성 결과를 정상 요약으로 반환하지 않고 `SummaryCancelledException`을 던짐

주의:

- 취소는 native decode 한 호출 중간을 강제로 끊지 않고 토큰 경계에서 멈춘다
- 안정성을 위해 worker isolate를 즉시 kill하지 않고 자연 종료를 기다린 뒤 llama/Metal context를 free한다
- `flutter analyze`와 `flutter build macos --debug` 통과

### App Store 설명/키워드/심사 메모 작성

파일:

- `APP_STORE_METADATA_KO.md`
- `APP_STORE_SUBMISSION_NOTES.md`

내용:

- App Store Connect에 복사해 넣을 한국어 메타데이터 초안 작성
- 앱 이름: `적자생존`
- 부제: `내 Mac에서 처리하는 AI 회의록`
- 홍보 문구: `회의 녹음부터 전사, 요약, 액션아이템까지 내 Mac에서 처리하세요. 외부 서버 업로드 없이 중요한 회의를 정리합니다.`
- 키워드: `회의록,녹음,음성인식,AI요약,전사,회의요약,액션,메모,업무회의,로컬AI`
- 설명에는 로컬 처리, 외부 서버 미업로드, 녹음/전사/요약/액션아이템/근거 확인/내보내기를 일반 사용자 언어로 정리
- App Review Notes에는 로그인 불필요, 첫 실행 저장 폴더 선택, 모델 다운로드, 녹음 후 수동 요약 테스트 흐름을 포함

주의:

- 실제 제출 전 Privacy Policy URL, Support URL을 공개 웹페이지로 만들어 App Store Connect에 입력해야 함
- Bundle ID는 아직 `com.example.meetingAssistant2`이므로 실제 도메인 기반 ID로 변경 필요
- 키워드는 Apple의 100바이트 제한 기준으로 94바이트

### 개인정보 처리방침 / App Store Privacy 답변 작성

파일:

- `PRIVACY_POLICY.md`
- `APP_STORE_PRIVACY_ANSWERS.md`
- `APP_STORE_SUBMISSION_NOTES.md`
- `APP_STORE_COMPLIANCE.md`

핵심 포지션:

- 회의 음성, 전사본, 요약본은 개발자 서버로 전송하지 않음
- AI 처리는 사용자의 Mac에서 로컬 모델로 실행
- 네트워크는 사용자가 요청한 모델 다운로드와 외부 링크 열기에 사용
- 사용자가 직접 내보내기/공유/메일/로그 복사를 실행한 경우에는 선택한 대상 앱 또는 서비스로 데이터가 전달될 수 있음
- App Store Privacy Label 초안은 `Data Not Collected`, Tracking 없음, 데이터 타입 미선택 기준
- `APP_STORE_PRIVACY_ANSWERS.md`에 User Content/Diagnostics/모델 다운로드/Hugging Face 토큰을 label에 포함하지 않는 이유를 정리
- `APP_STORE_SUBMISSION_NOTES.md`에 App Review Notes 복붙 문구와 Privacy Policy URL placeholder 정리

주의:

- 향후 원격 분석, 자동 크래시 리포트, 클라우드 동기화, 계정 기능, 서버 기반 STT/요약을 추가하면 privacy 답변을 즉시 변경해야 함
- 실제 앱스토어 제출 전 개발자명/문의 이메일/개인정보 처리방침 공개 URL을 확정해야 함

### Xcode Archive + Apple Distribution 검증 준비

파일:

- `scripts/archive_app_store.sh`
- `macos/Runner.xcodeproj/project.pbxproj`
- `APP_STORE_COMPLIANCE.md`

내용:

- App Store Connect에 등록한 Bundle ID와 Apple Developer Team ID를 환경변수로 받아 Xcode archive를 생성하는 스크립트 추가
- 사용법:

```bash
APPLE_TEAM_ID=ABCDE12345 \
APP_STORE_BUNDLE_ID=com.company.app \
./scripts/archive_app_store.sh
```

- archive 후 검사:
  - Bundle ID 일치
  - `LSMinimumSystemVersion=15.5`
  - `codesign --verify --strict --deep`
  - sandbox entitlement true
  - `get-task-allow` true 금지
  - Calendar/AppleEvent entitlement 부재
- Runner Release 설정:
  - `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`
  - `ENABLE_HARDENED_RUNTIME = YES`

현재 로컬 상태:

- `security find-identity -v -p codesigning` 결과가 `0 valid identities found`
- Apple Distribution 인증서가 없어서 실제 archive 완료는 아직 불가
- 다음 작업자는 Xcode > Settings > Accounts에서 Apple Developer 계정을 추가하고, App Store Connect Bundle ID를 만든 뒤 위 스크립트를 실행하면 됨

### macOS 최소 버전 정책 정리

배경:

- release 빌드에서 `libonnxruntime.1.24.4.dylib`가 macOS 15.5용으로 빌드되어 있는데 앱 target은 10.15/11.0이라는 링커 경고가 있었음
- `otool -l`로 해당 dylib의 `LC_BUILD_VERSION minos 15.5`를 확인

수정:

- App Store 릴리스 최소 macOS 버전을 15.5로 명시
- `macos/Podfile`: `platform :osx, '15.5'`
- `macos/Runner.xcodeproj`: `MACOSX_DEPLOYMENT_TARGET = 15.5`
- Pod post_install에서 모든 Pod target의 `MACOSX_DEPLOYMENT_TARGET`을 15.5로 정렬
- `scripts/build_app_store.sh`가 원본 설정과 산출물 `LSMinimumSystemVersion`을 검사

주의:

- macOS 15.5 미만 지원이 필요하면 현재 sherpa-onnx/onnxruntime 바이너리를 그대로 쓰면 안 됨
- 낮은 OS를 지원하려면 화자 라벨 기능을 빌드 플래그로 빼거나, 더 낮은 deployment target으로 빌드된 onnxruntime/sherpa-onnx 바이너리를 별도 준비해야 함

### App Store 빌드 모드 정리

파일:

- `lib/core/constants/app_build_config.dart`
- `lib/core/constants/legal_notices.dart`
- `macos/Runner/Release.entitlements`
- `macos/Runner/Info.plist`
- `scripts/build_app_store.sh`
- `APP_STORE_COMPLIANCE.md`

정책:

- 기본 빌드는 `APP_STORE_COMPLIANCE_MODE=true`
- EXAONE 3.5는 공식 라이선스가 NC 성격이라 앱스토어 빌드에서 다운로드/선택/기본 설정 노출을 숨김
- 내부 테스트에서만 `APP_STORE_COMPLIANCE_MODE=false`, `ALLOW_RESTRICTED_MODELS=true`로 다시 노출 가능
- Calendar.app AppleEvent 연동은 앱스토어 빌드에서 숨김

Release entitlement:

- App Sandbox `true`
- `get-task-allow=false`를 원본 Release entitlement에 명시
- network client, microphone, user-selected read/write, app-scope bookmark만 유지
- Calendar entitlement와 AppleEvent temporary exception 제거
- 로컬 Flutter release 빌드는 개발 서명 때문에 산출물에 `get-task-allow=true`가 주입될 수 있음. 최종 업로드는 Xcode Archive + Apple Distribution 서명 후 `STRICT_CODESIGN_CHECK=1 ./scripts/build_app_store.sh` 기준으로 검사

설정 UI:

- `라이선스와 개인정보` 섹션 추가
- `사용 모델 및 라이선스` 다이얼로그에서 whisper.cpp, Whisper, llama.cpp, Gemma, Qwen, sherpa-onnx 고지
- `앱스토어 안전 모드` 상태 표시
- 앱 시작 시 제한 모델 저장값과 비활성 Calendar 자동화 설정을 현재 빌드 정책에 맞게 정리

### 요약 중 네이티브 종료 안정화

파일:

- `lib/core/ffi/on_device_model_manager.dart`
- `lib/data/datasources/llm_service.dart`
- `lib/core/services/chunked_summarizer.dart`

배경:

- macOS DiagnosticReports에서 요약 중 종료 원인이 `DartWorker`의 `llama_decode`/`ggml_metal_get_tensor_async`와 메인 스레드의 `llama_free`/`ggml_backend_metal_free`가 겹친 `SIGABRT`로 확인됨
- 관련 리포트: `/Users/channy/Library/Logs/DiagnosticReports/LocalMinutes-2026-04-30-162946.ips`

수정:

- `OnDeviceModelManager`가 LLM 생성 중인지 카운트하고, `unloadLlm()`은 decode가 끝날 때까지 기다린 뒤 context/model/backend를 해제
- `LlmService`는 같은 llama context를 동시에 쓰지 않도록 동시 생성 요청을 즉시 차단
- 스트림 취소/요약 중지 시 worker isolate를 즉시 kill하지 않고 자연 종료를 기다려 native free와 decode 충돌을 피함
- `ChunkedSummarizer`는 중지 요청 후 토큰을 버리며 스트림을 drain하고, 종료 뒤 취소 예외를 던짐

주의:

- 현재 중지 버튼은 안정성을 위해 "즉시 강제 종료"가 아니라 "현재 native 생성 루프가 정리된 뒤 중지"에 가깝다
- 진짜 즉시 중지를 원하면 llama.cpp wrapper 레벨에 atomic cancel flag를 추가해 decode loop 내부에서 안전하게 빠져나오도록 구현해야 함

### 첫 실행 저장 폴더 필수화

파일:

- `lib/presentation/screens/storage_setup_screen.dart`
- `lib/main.dart`
- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/screens/settings_screen.dart`
- `lib/core/services/app_settings.dart`

내용:

- `recordingsSavePath`가 비어 있으면 저장 폴더 선택 화면을 먼저 표시
- 첫 화면에서 녹음/STT/화자 분리/요약이 모두 Mac 안에서 실행되며 외부 서버로 전송하지 않는다는 점을 강조
- 녹음 시작 시 기본 Application Support 폴더 fallback 제거
- 설정 화면에서 저장 폴더 `초기화` 버튼 제거
- 녹음 저장 폴더는 설정에서 변경만 가능

### 녹음 중지 후 자동 요약 제거

파일:

- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/screens/settings_screen.dart`
- `lib/core/services/app_settings.dart`

내용:

- `autoSummarize` 설정 UI 삭제
- 녹음 종료 후 자동으로 `_runSummary()`를 호출하지 않음
- 사용자가 직접 요약 버튼을 누르는 흐름으로 고정

### 화자 인원수 필수 입력

파일:

- `lib/presentation/widgets/recording_view.dart`

내용:

- 녹음 시작 전 `_showSpeakerCountDialog()` 표시
- 2~6명 중 하나를 선택해야 녹음 가능
- 선택값은 `_meetingSpeakerCount`와 `AppSettings.numSpeakersHint`에 저장
- 화자 분리 시 `numSpeakersHint`로 사용
- 목적: 자동 클러스터링이 `화자 A~Q`처럼 과분리되는 문제 완화

### LLM의 사람 이름 자동 생성 방지

파일:

- `lib/core/utils/summary_parser.dart`
- `lib/presentation/widgets/recording_view.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`

내용:

- 프롬프트에 "사용자가 직접 입력한 참석자만 participants에 사용" 규칙 추가
- 직접 입력 참석자가 없으면 `participants: []`
- `actionItems.owner`는 직접 입력된 참석자명 또는 `화자 A` 같은 라벨만 허용
- 파싱 단계에서도 LLM이 만든 `participants`를 버리고 `forcedParticipants`만 저장
- 다시 요약 시 기존 요약의 participants를 강제로 유지

### 요약 프리셋 품질 강화

파일:

- `lib/core/services/summary_templates.dart`
- `lib/core/services/chunked_summarizer.dart`
- `lib/presentation/screens/settings_screen.dart`

내용:

- 일반 회의/회고/인터뷰 프리셋 instruction을 긴 실무형 프롬프트로 재설계
- 일반 회의는 실무 공유용 회의록, 결정사항, 액션아이템, 미해결 이슈 누락 방지에 집중
- 회고는 Keep / Problem / Try 구조와 실행 가능한 개선 조치에 집중
- 인터뷰/1:1은 Q/A, 인사이트, 후속 확인에 집중
- 각 프리셋에 좋은 항목 예시를 포함
- `ChunkedSummarizer` map 단계에도 프리셋 instruction을 전달해 긴 회의 구간 요약에서 의도 손실을 줄임
- 구간 요약은 [결정]/[액션]/[질문] 태그를 유지하도록 변경
- 설정 화면에서 "JSON 스키마" 같은 개발자 표현을 제거하고 일반 사용자용 설명으로 변경

### 긴 WAV STT 개선

파일:

- `lib/data/datasources/stt_service.dart`
- `lib/core/utils/transcript_corrector.dart`
- `lib/core/utils/transcript_text_cleaner.dart`

내용:

- 긴 파일은 30초 청크 + 5초 오버랩으로 STT
- 90초 초과 파일은 청크 모드
- 오버랩 중복 세그먼트 제거
- 최근 8개 세그먼트까지 비교해 오버랩 중복 제거를 강화함
- 숫자가 다른 문장(`10월` vs `1월`)은 중복으로 보지 않음
- 청크 완료마다 진행률 갱신
- STT 취소 콜백 지원
- 단어집 alias 교정에 보수적 기본 치환을 추가함
  - 예: `GQ팀→지표팀`, `로고 설계→로그 설계`, `S로고→S로그`, `Q&A 1차→QA 1차`
- 요약 입력에는 `TranscriptTextCleaner.cleanForSummary()`를 적용
  - 저장 전사본은 보존
  - LLM 프롬프트에서만 근접 중복 라인을 제거해 요약 과대표현을 완화
  - 적용 경로: 녹음 직후 요약, 회의 상세 다시 요약, `PipelineService`

### 화자 분리 멈춤 방지

파일:

- `lib/data/datasources/diarization_service.dart`

내용:

- sherpa-onnx diarization을 UI isolate 밖으로 분리
- timeout과 실패 fallback 추가
- 실패해도 전사/요약 계속 진행

### 처리 리포트

파일:

- `lib/domain/entities/meeting_processing_report.dart`
- `lib/domain/entities/meeting.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`
- `lib/presentation/widgets/recording_view.dart`

내용:

- 회의별 STT 모델, STT 소요 시간, 오디오 길이, RTF, 화자 분리 상태/시간, LLM 모델, 요약 시간 저장
- 회의 상세에 `처리 리포트` 카드 표시

### 설정 화면 일반 사용자화

파일:

- `lib/presentation/screens/settings_screen.dart`

내용:

- 설정 기본 화면에서 `STT`, `Whisper`, `LLM`, 모델 파일명 같은 개발자 용어 노출을 줄임
- 음성 인식 설정은 `음성 인식 언어`, `음성 인식 방식`, `빠름`, `정확도 높음` 중심으로 표시
- 모델 관리 섹션은 `음성/요약 모델`로 변경
- 모델 목록은 `빠른 음성 인식 모델`, `정확도 높은 음성 인식 모델`, `기본 요약 모델`, `고품질 요약 모델`, `한국어 특화 요약 모델`로 표시
- 기본 요약 모델 선택 칩은 모델명 대신 `기본`, `고품질`, `한국어 특화`로 표시
- 실제 모델 파일명은 `고급 정보` 접기 안에서만 확인 가능
- 발화자 라벨 모델도 `발화 구간 찾기 모델`, `목소리 구분 모델`로 일반 사용자화

### 사이드바 접기와 회의 상세 폭 조절

파일:

- `lib/presentation/screens/home_screen.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`

내용:

- 홈 화면 왼쪽 사이드바에 접기/펼치기 기능 추가
- 펼친 상태에서는 기존처럼 사이드바 폭 드래그 조절 가능
- 접힌 상태에서는 좁은 레일에 `사이드바 펼치기`, `새 녹음 시작` 버튼만 표시
- 회의 상세 화면의 요약 영역과 전사본 영역 사이에 드래그 가능한 분할선 추가
- 요약/전사 영역은 최소 폭을 유지하면서 사용자가 비율을 조절할 수 있음

### 음성 인식 재실행 예상 시간 안내

파일:

- `lib/presentation/widgets/meeting_detail_view.dart`

내용:

- 기존 회의 상세의 `STT 다시 돌리기`는 사용자 표시상 `음성 인식 다시`로 정리됨
- 실행 전 다이얼로그에서 오디오 길이, 빠른/정확 음성 인식 예상 시간, 발화자 라벨 예상 시간, 총 예상 시간을 표시
- 빠른/정확 모델 선택과 발화자 라벨 사용 여부를 한 화면에서 고름
- 발화자 라벨을 끄면 실제 재전사 실행에서도 diarization을 건너뛰고 처리 리포트에도 `disabled`로 저장됨

### 요약 근거 보기 v1

파일:

- `lib/presentation/widgets/meeting_detail_view.dart`

내용:

- 주요 논의, 결정 사항, 미해결 이슈, 액션 아이템에 `근거` 버튼 추가
- 클릭 시 관련 전사 구간 후보를 팝업으로 표시
- 후보에는 타임스탬프, 발화자 라벨, 전사 텍스트, 유사도 표시
- 매칭 방식은 LLM 호출 없이 키워드 교집합 + 문자 bigram 유사도 기반
- 후보가 없거나 최고 점수가 낮으면 `확인 필요` 배지를 표시
- v1은 전사 패널로 실제 스크롤 이동하지 않고 근거 팝업을 표시하는 방식

### 전체 할 일 보드

파일:

- `lib/presentation/screens/action_items_screen.dart`
- 사이드바 관련 파일

내용:

- 모든 회의의 액션아이템을 통합 조회
- 미완료/완료/담당자/검색 필터
- 원본 회의 이동

## 성능 기준 측정

테스트 파일:

- `/Users/channy/Library/Containers/com.example.meetingAssistant2/Data/Library/Application Support/com.example.meetingAssistant2/recordings/meeting_1776920772703.wav`
- 길이: `45분 36초`

로컬 기준 추출 결과:

- 결과 폴더: `/Users/channy/LocalMinutes/exports/meeting_1776920772703_reference_2026-04-25T230632_575896`
- STT 모델: `ggml-large-v3-q5_0.bin`
- STT 소요: `16분 16초`
- STT RTF: `0.357x`
- STT 세그먼트: `596개`
- 화자 분리: `success`
- 화자 분리 소요: `16분 22초`
- 화자 분리 세그먼트: `630개`
- 요약 모델: `EXAONE-3.5-7.8B-Instruct-Q4_K_M.gguf`
- 요약 소요: `6분 45초`
- 전체 처리 합계: 약 `39분 23초`

중요 관찰:

- STT 자체는 온디바이스 기준 속도가 양호함
- 화자 분리가 STT만큼 오래 걸림
- 기존 자동 화자 수 추정은 과분리 위험이 있었음
- 그래서 녹음 시작 전 화자 수 필수 입력으로 UX를 변경함

## GPT/OpenAI 비교 작업 상태

사용자 요청으로 OpenAI/GPT API 기반 비교 스크립트를 만들었지만, OpenAI API quota 부족으로 실제 STT는 수행하지 못함.

파일:

- `tool/openai_gpt_extract_compare.py`

역할:

- WAV를 25MB 이하 청크로 분할
- `gpt-4o-transcribe-diarize`로 STT+화자 분리
- `gpt-5.2`로 요약
- 로컬 결과와 비교해 `comparison.md` 생성

현재 상태:

- API 키 인식은 성공
- 청크 분할 성공
- 첫 청크 업로드 시 `insufficient_quota` 에러로 중단
- 사용자가 "너가 stt하는건 그만둬"라고 요청했으므로 더 이상 GPT STT 재시도하지 말 것

## 품질 평가 메모

STT:

- 정확 모델 기준 한국어 회의 전사 품질은 출시 가능 수준에 가까움
- 단어집/initial prompt/후처리로 고유명사 보정 가능
- 긴 파일 처리 속도는 개선됨

요약:

- 주요 논의, 결정사항, 액션아이템, 미해결 이슈 구조는 실용적
- 주요 논의, 결정사항, 액션아이템, 미해결 이슈에 `근거` 버튼이 표시되어 관련 전사 구간 확인 가능
- 다음 개선 여지는 근거 신뢰도 점수와 근거 출처 저장 구조 고도화
- LLM이 참석자 이름을 추측하는 문제를 방지하도록 최근 수정됨

화자 분리:

- 가장 큰 리스크
- 자동 화자 수 추정은 과분리 위험이 큼
- 현재는 녹음 시작 전 화자 수 입력 필수로 완화
- 앱스토어용으로는 화자 분리를 "정확한 사람 식별"이 아니라 "화자 라벨 보조"로 안내하는 것이 안전

## 앱스토어 출시 관점

추천 포지셔닝:

- "프라이버시 중심 온디바이스 한국어 회의록 앱"
- "빠른 클라우드 회의록 앱"으로 홍보하면 속도 기대치 때문에 불만 가능성

확정 가격:

- 첫 출시 가격: 유료 앱 `19,000원`
- 구독/IAP: 첫 출시 버전에서는 사용하지 않음
- App Store Connect에서 Paid Apps Agreement, 세금, 은행 정보 완료 후 Pricing and Availability에 반영

출시 전 특히 중요한 UX:

- 긴 작업 예상 시간 표시
- 화자 분리 시간이 오래 걸릴 수 있음을 명확히 안내
- 요약 근거 버튼은 적용됨. 다음은 근거 신뢰도/출처 저장 고도화
- 내보내기 기능 강화

## 남은 추천 작업

2026-05-05 정리 기준:

- 첫 실행 온보딩, 녹음 준비 패널, 긴 작업 예상 시간, 발화자 라벨 기대치 정리, 설정 화면 기술 용어 정리는 이미 상당 부분 반영됨
- 메뉴바 트레이, 단축키, 에러 처리, 진단 ZIP, 빈 녹음 감지, 네이티브 작업 잠금, 작업 중 종료 안내도 Completed에 기록됨
- 앱스토어 안전 모드의 제한 모델 숨김/저장값 정리/다운로드 방어도 Completed에 기록됨
- P0 출시 전 수동 QA 3개도 사용자 확인 완료:
  - 녹음 준비 다이얼로그 마이크 테스트
  - 트레이 빠른 녹음
  - 45분 이상 실제 회의 파일 안정성 재검증
- 아래 목록은 실제 남은 제품 개선 중심

P0 App Store 제출 준비:

- Privacy Policy URL, Support URL, Bundle ID 확정
- Apple Distribution 인증서/프로비저닝 준비
- Xcode Archive 후 `scripts/build_app_store.sh` strict 검사

P1 회의록 신뢰도/출력 품질:

완료:

- `.txt` 저장, `.pdf` 저장, 이메일 열기, macOS 공유 시트
- Markdown 파일 저장
- Markdown 클립보드 복사
- Notion용 요약 복사, 보고서 형식 복사, 액션아이템 단독 복사
- DOCX 업무 문서 저장
- 보고서 형식 PDF/DOCX 저장

남은 확장 후보:

- 전사본 선택 단어 기반 보정 UX 고도화

P2 전사/요약 보정:

- 요약 신뢰도 v3
  - 근거 유무, 담당자/기한 확실성, 전사 출처 함께 저장

완료:

- 태그 자동 추천
- 다국어 회의 지원

P2 업무 흐름/인사이트:

- 정기 회의 시리즈 자동 인식
- 주간/월간 다이제스트
- 회의 비교
- 회의 품질 점수
- 화자 통계

P3 보안/연동/보류:

- 회의 종료 후 오디오 자동 삭제 옵션
  - 오디오 원본은 기본적으로 지우지 않는다는 사용자 요구 유지
  - 보안 회의용 선택 옵션으로만 제공
- 오디오 암호화 옵션
- macOS 캘린더 연동
- 장시간 회의 중간 진행 요약
  - 보류 사유: `OnDeviceModelManager`가 STT/LLM 동시 로드를 금지
  - 녹음 중 요약은 모델 언로드/로드 반복이 필요해 녹음 안정성을 해칠 수 있음

## 검증 상태

최근 변경 후 아래 명령 통과:

```bash
flutter analyze
flutter test
flutter build macos --debug
```

빌드 산출물:

- `/Users/channy/LocalMinutes/build/macos/Build/Products/Debug/적자생존.app`

## 주의 사항

- 사용자가 만든 변경을 되돌리지 말 것
- `apply_patch`로 수동 편집할 것
- 로컬 DB/녹음 파일은 사용자 데이터이므로 임의 삭제 금지
- `OPENAI_API_KEY`는 현재 quota 부족이며, 사용자가 GPT STT 중단을 요청했으므로 재시도하지 말 것
- 저장 폴더 선택은 이제 필수 UX이므로 기본 폴더 fallback을 되살리지 말 것
- 자동 요약은 제거된 의도적 결정이므로 다시 켜지 말 것
