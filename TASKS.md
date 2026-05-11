# 적자생존 (LocalMinutes) 작업 로그

> 토큰 한계로 세션이 끊겨도 이어서 작업할 수 있도록 유지하는 파일.
> 새 작업 시작 → **In Progress** 이동, 끝나면 **Completed** 최상단에 날짜와 함께 기록.

---

## In Progress

_(없음)_

---

## Backlog (실제 남은 일 기준)

> 2026-05-05 정리 기준: 메뉴바 트레이, 단축키, 에러 처리, 진단 ZIP, 빈 녹음 감지, 네이티브 작업 잠금, 종료 안내, 앱스토어 안전 모델 정리는 이미 Completed에 기록됨.

### P0 — App Store 제출 준비

- [ ] **제출용 서명/Archive 최종 검증**
  - Privacy Policy URL, Support URL, Bundle ID 확정
  - Apple Distribution 인증서/프로비저닝 준비
  - Xcode Archive 후 `scripts/build_app_store.sh` strict 검사 통과 확인

### P1 — 회의록 신뢰도/출력 품질

_(현재 P1 제품 개선 항목은 완료. 다음은 P2 후보 중 선택)_

### P2 — 전사/요약 보정 도구

_(태그 자동 추천/다국어 회의 지원/요약 신뢰도 v3 1차 완료. 다음은 업무 흐름 확장 후보)_

### P2 — 업무 흐름 확장

- [x] ~~**주간/월간 다이제스트**~~ — 2026-05-09 완료 (사이드바 `📅 다이제스트` → MacosSheet)
- [x] ~~**회의 비교**~~ — 2026-05-09 완료 (시리즈 대시보드 헤더 `⇄` → MacosSheet, 4개 섹션 diff)
- [x] ~~**시리즈 비교 대시보드**~~ — 2026-05-09 완료 (사이드바 `📊 시리즈 비교` → MacosSheet, 카드 클릭 시 해당 시리즈로 점프)

### P2 — 인사이트

- [x] ~~**회의 품질 점수**~~ — 2026-05-09 완료 (회의 상세 카드, decisions/actions/balance/evidence 가중 평균 + 개선 힌트)

- [x] ~~**화자 통계**~~ — 2026-05-09 완료 (회의 상세 발언 통계 카드 — 누적 가로 막대 + per-speaker 행)

### P3 — 보안/연동/보류

- [ ] **회의 종료 후 오디오 자동 삭제 옵션**
  - 오디오 원본은 기본적으로 지우지 않는다는 사용자 요구 유지
  - 보안 회의용 선택 옵션으로만 제공

- [ ] **오디오 암호화 옵션**
  - AES + macOS Keychain 키 저장 검토
  - 앱스토어 심사/데이터 복구 UX까지 함께 설계 필요

- [ ] **macOS 캘린더 연동**
  - 앱스토어 권한 설명과 사용자 기대치를 먼저 정리한 뒤 진행
  - 자동 회의 제목/참석자 매칭은 편하지만 권한 부담이 큼

- [ ] **장시간 회의 중간 진행 요약**
  - 보류 사유: `OnDeviceModelManager`가 STT/LLM 동시 로드를 금지
  - 녹음 중 요약하려면 모델 언로드/로드 반복이 필요해 녹음 안정성을 해칠 수 있음
  - 제품 스펙 확정 후 재검토

---

## Completed

### 2026-05-09 (P2 추가 — AI 검색 keyword pre-filter + 시리즈 비교 대시보드 + 회의 비교)

- ✅ **AI 검색 keyword pre-filter** ([meeting_keyword_search.dart](lib/core/services/meeting_keyword_search.dart))
  - 회의가 매우 많아도 토큰 압박 없이 검색 가능
  - 쿼리를 공백 토크나이즈(2글자 미만 제거) → 회의의 title/tags/notes/agenda/transcriptPreview + summary 필드와 매칭
  - 키워드 등장 횟수로 스코어 → 상위 30개만 LLM에 전달 (기존 60개 → 30개)
  - 매칭 0개면 입력 순서 폴백 (대화형 질문 대응)
  - `_runAiSearch`가 `MeetingKeywordSearch.rank()` 사용
  - 단위 테스트 9개
- ✅ **시리즈 비교 대시보드** ([series_overview.dart](lib/core/services/series_overview.dart))
  - 모든 그룹 한눈에 비교 (회의 수, 평균 주기, 마지막 회의, 누적 미완료, 지속 이슈, 결정)
  - 사이드바 하단 `📊 시리즈 비교` 버튼 (다이제스트 옆) → `MacosSheet`
  - 카드 클릭 시 해당 시리즈 대시보드로 점프
  - 마지막 회의 최신순 정렬, 회의 0회 그룹 제외
  - 단위 테스트 5개
- ✅ **회의 비교** ([meeting_comparison.dart](lib/core/services/meeting_comparison.dart))
  - 같은 시리즈 두 회의의 결정/이슈/액션/논의 변화 비교
  - 시리즈 대시보드 헤더 `⇄` 아이콘 → `MacosSheet`로 picker + 결과
  - 기본값: 가장 최근 두 회의 자동 선택
  - 4개 섹션 카드 — 결정/미해결 이슈/액션/논의 (+/−/· 마커)
  - 액션 상태 전이 (`✓` 완료, `↺` 재오픈, `·` 진행 중) + 담당자/마감 변경 표식
  - `_roughlySame` 부분 일치로 task 매칭 (시리즈 진행/타임라인과 동일 규칙)
  - 단위 테스트 8개
- ✅ **검증/빌드**
  - `flutter analyze`: 0 issues
  - `flutter test`: **90/90 통과** (68 → 90, 새 테스트 22개 추가)
  - `flutter build macos --debug`: 통과
  - DMG 생성: `dist/적자생존_v2.1.1_build26.dmg` (47M, pubspec `2.1.1+26`)
  - `hdiutil verify` VALID, `codesign --verify --deep --strict` 통과

### 2026-05-09 (P2 인사이트/업무 흐름 — 품질 점수 + 발언 통계 + 액션 타임라인 + 다이제스트 + AI 검색 fix)

- ✅ **회의 품질 점수** ([meeting_quality.dart](lib/core/services/meeting_quality.dart))
  - 4개 sub-score 가중 평균: decisions 30% + actions 30% + balance 15% + evidence 25%
  - 등급: 우수(≥85)/양호(≥70)/보통(≥50)/개선 필요
  - LLM 추가 호출 없음 (Summary + Transcript만 사용)
  - 개선 힌트 (담당자 미지정, 발화 편중, 근거 미명시 등)를 행동 가능한 메시지로 노출
  - 회의 상세 처리 시간 카드 아래에 `_QualityScoreCard` 표시
  - 단위 테스트 10개
- ✅ **화자 발언 통계** ([speaker_stats.dart](lib/core/services/speaker_stats.dart))
  - `Transcript.speakerLabel` + start/end만 사용
  - 화자별 발화 시간/세그먼트 수/점유율 (8색 팔레트)
  - 라벨 없는 세그먼트는 "미식별" bucket
  - `Meeting.speakerNamesJson`의 사용자 지정 이름 표시
  - 회의 상세 품질 카드 아래에 `_SpeakerStatsCard` 표시 (누적 가로 막대 + per-speaker 행)
  - 단위 테스트 7개
- ✅ **액션아이템 회차별 변화 추적** ([meeting_series_progress.dart](lib/core/services/meeting_series_progress.dart) 확장)
  - `TrackedAction` / `ActionAppearance` / `TrackedActionStatus` 추가
  - 같은 task가 시리즈 회의들을 가로질러 어떻게 변하는지 추적
  - 상태: ongoing / resolved / dropped
  - 변경 표식: 담당자 변경 / 마감 변경
  - `_roughlySame` 부분 일치로 task 매칭 (기존 시리즈 이슈 매칭과 동일 규칙)
  - 시리즈 대시보드의 "누적 미완료 액션" 카드 아래 `_ActionTimelineCard` 추가
  - 단위 테스트 2개
- ✅ **주간/월간 다이제스트** ([digest_report.dart](lib/core/services/digest_report.dart))
  - 주간(월요일 시작) / 월간 토글
  - 기간 내 모든 회의의 미완료 액션 / 결정 / 미해결 이슈 집계
  - 사이드바 하단 `📅 다이제스트` 버튼 → `MacosSheet` 표시
  - 회의 클릭 시 시트 닫고 회의 상세로 점프
  - 단위 테스트 7개
- ✅ **AI 검색 KV 캐시 초과 fix** ([meeting_sidebar.dart](lib/presentation/widgets/meeting_sidebar.dart) `_runAiSearch`)
  - 원인: AI 검색이 LLM을 `nCtx: 2048`로 다운설정 (기본값 4096의 절반) → 회의 목록 컨텍스트 2574 토큰으로 초과 발생
  - 수정: `nCtx: 2048` → `4096` (기본값 일치) + 회의 60개 상한 + 회의당 140자 상한 + 잘림 안내 문구 추가
- ✅ **검증/빌드**
  - `flutter analyze`: 0 issues
  - `flutter test`: **68/68 통과** (40 → 68, 새 테스트 28개 추가)
  - `flutter build macos --debug`: 통과
  - DMG 생성: `dist/적자생존_v2.1.1_build25.dmg` (47M, pubspec `2.1.1+25`)
  - `hdiutil verify` VALID, `codesign --verify --deep --strict` 통과

### 2026-05-09 (P2 미세 개선 — 근거 미명시 배지 + 시리즈 이슈 매칭 정밀도)

- ✅ **요약 카드 "근거 미명시" 배지** ([meeting_detail_view.dart `_EvidenceButton`](lib/presentation/widgets/meeting_detail_view.dart))
  - LLM이 evidenceTs를 명시하지 않은 항목에 ⚠️ 아이콘 + "근거 미명시" 라벨로 표시
  - 사용자가 클릭 전에 신뢰도 즉시 파악 가능
  - keyDiscussions/decisions/openQuestions 카드에 동일 적용 (단일 위젯 공유)
  - tooltip 문구도 "LLM이 근거 타임스탬프를 명시하지 않았습니다. 키워드 검색으로 후보 구간을 찾아보세요."로 명확화
- ✅ **시리즈 이슈 매칭 정밀도 강화** ([meeting_series_progress.dart](lib/core/services/meeting_series_progress.dart))
  - `Map<normKey, bucket>` 동등 비교 → `List<_IssueBucket>` + `_roughlySame` 부분 일치
  - 8자 이상 정규화 키에서 한쪽이 다른 쪽을 포함하면 같은 이슈로 묶음 (`SummaryParser._roughlySame`과 동일 규칙)
  - 짧은 텍스트(8자 미만)는 부분 일치 비활성 → 노이즈 방지
  - 가장 긴 표현이 대표 텍스트로 보존
  - 회귀 테스트 2개 추가 (`partial match merges`, `짧은 텍스트 노이즈 방지`) — 총 42/42 통과
- ✅ **검증/빌드**
  - `flutter analyze`: 0 issues
  - `flutter test`: 42/42 통과 (40 → 42, 새 테스트 2개 추가)
  - `flutter build macos --debug`: 통과

### 2026-05-09 (옵션 C macos_ui Phase 4 — 다이얼로그 → MacosSheet/MacosAlertDialog 전환)

- ✅ **다이얼로그 23개 macos_ui 전환 완료** — 9개 Step에 걸쳐 진행
  - Step 1 (정보/confirm 4개): `_showTrayRecordingStartFailureDialog`, `_showMicPermissionDialog`, 녹음 삭제 confirm, 액션 아이템 삭제 → `MacosAlertDialog`
  - Step 2 (input textfield 2개): `_showTitleEditDialog`, 태그 추가 → `MacosAlertDialog`
  - Step 3 (picker 2개): `_pickLlmDialog` × 2 → `MacosAlertDialog`
  - Step 4 (3-button 2개): `_showLowQualityRecordingDialog`, 어젠다 편집 → `MacosSheet`
  - Step 5 (Switch/Checkbox 폼 3개): 예상 처리 시간, 단어집 추가, 전사본 단어 치환 → `MacosAlertDialog`
  - Step 6 (큰 폼 2개): `_pickTemplateDialog`, rerun STT options → `MacosAlertDialog`
  - Step 7 (클래스 다이얼로그 4개): 추천 태그 picker, `_SummaryHistoryDialog`, `_TermExtractDialog`, `_SummaryEditDialog` → `MacosSheet`
  - Step 8 (ListView + 폼 2개): evidence picker, `_ActionItemEditDialog` → `MacosAlertDialog`
  - Step 9 (가장 큰 폼 2개): `_SpeakerEditDialog`, `_RecordingPrepDialog` (520×540) → `MacosAlertDialog`
- ✅ **API 매핑 패턴 정립**
  - `showDialog` → `showMacosAlertDialog` 또는 `showMacosSheet`
  - `AlertDialog(title, content, actions)` → `MacosAlertDialog(appIcon, title, message, primaryButton, secondaryButton)`
  - `Dialog(shape:)` → `MacosSheet(child:)`
  - `TextButton`/`FilledButton` (action) → `PushButton(secondary: true)` / `PushButton(color:)`
  - `Tooltip` → `MacosTooltip`
  - 클래스 기반 다이얼로그(`StatefulWidget`이 `Dialog(...)` 반환)는 build의 `Dialog` → `MacosSheet`로, 호출 측 `showDialog` → `showMacosSheet`
- ✅ **디자인 결정**
  - 2 buttons + 단순 콘텐츠 → `MacosAlertDialog`
  - 3+ buttons 또는 큰 layout/IconButton 닫기 → `MacosSheet` 직접 빌드
  - 파괴적 액션 → `color: MacosColors.systemRedColor` + 흰 텍스트
  - 내부 위젯(`TextField`, `DropdownButtonFormField`, `SegmentedButton`, `SwitchListTile`, `RadioListTile`, `ChoiceChip`, `FilterChip`, `CheckboxListTile`, `Wrap`, `ListView`)은 Material 그대로 유지 — 회귀 위험 최소화 우선
- ✅ **검증/빌드**
  - `flutter analyze`: 0 issues
  - `flutter test`: 40/40 통과
  - `flutter build macos --debug`: 통과
  - 각 Step마다 사용자 시각 QA로 회귀 확인
  - DMG 생성: `dist/적자생존_v2.1.1_build24.dmg` (47M, pubspec `2.1.1+24`)
  - `hdiutil verify` VALID, `codesign --verify --deep --strict` 통과

### 2026-05-09 (옵션 C macos_ui Phase 3 — RecordingView/MeetingDetailView 전환)

- ✅ **메인 뷰 Material → macos_ui 위젯 전환 완료**
  - 5개 Step에 걸쳐 총 23개 버튼 변환
  - Step 1 (`recording_view.dart` L2347–2415): 컨트롤 버튼 5개 (일시정지/북마크/녹음중지/계속하기/녹음중지-paused)
  - Step 2 (`recording_view.dart` L2547–2625): 완료 후 액션 4개 (요약 다시 시도/회의록 열기/녹음 시작/요약)
  - Step 3 (`meeting_detail_view.dart` L2057, L2147, L2386–2480): 진행 인디케이터 중지 2개 + 헤더 액션 4개 (용어 추출/편집/이력/다시 요약)
  - Step 4 (`meeting_detail_view.dart` L2260, L2725, L3466, L5253, L5560, L6431): 카드/인라인 IconButton 5개 + TextButton.icon 1개 (제목/액션 추가/어젠다/오디오 재생/음성 인식 다시/메모 수정)
  - Step 5 (`recording_view.dart` L3235, L4830): IconButton 2개 (마이크 새로고침/배너 닫기)
- ✅ **위젯 매핑 패턴 정립**
  - `FilledButton.icon` (배경색 강조) → `PushButton(color: <Color>)` + 흰 icon/text
  - `OutlinedButton.icon` → `PushButton(secondary: true)` + 색상은 icon/text에만 (macOS HIG)
  - `IconButton` (ghost) → `MacosIconButton(backgroundColor: Colors.transparent)` + 명시적 `boxConstraints`
  - `IconButton.tooltip` / `Tooltip` → `MacosTooltip` 래핑
  - `TextButton.icon` (라벨 있음) → `PushButton(secondary, ControlSize.small)` + 색상은 icon/text
- ✅ **디자인 결정**
  - 빨강/녹색 강조 → `MacosColors.systemRedColor/systemGreenColor` 다이나믹 컬러로 라이트/다크 자동 대응
  - 보라/인디고/청록 등 브랜드 색은 그대로 유지 (`Colors.deepPurple` 등)
  - 다이얼로그 안 위젯은 변환 제외 (Phase 4 대상): `_RecordingPrepDialog`의 `_MicTestPanel`(L4735), 화자 편집 다이얼로그(L4964) 등
  - `PopupMenuButton` 3곳(요약 헤더, 타임라인, 전사 spellcheck)은 macos_ui 직접 대응 없어 유지
  - `Slider`(오디오 재생바)도 macos_ui 대응 없어 유지
- ✅ **검증/빌드**
  - `flutter analyze`: 0 issues
  - `flutter test`: 40/40 통과
  - `flutter build macos --debug`: 통과
  - 각 Step마다 빌드 후 사용자 시각 QA로 회귀 확인
  - DMG 생성: `dist/적자생존_v2.1.1_build23.dmg` (47M, pubspec `2.1.1+23`)
  - `hdiutil verify` VALID, `codesign --verify --deep --strict` 통과

### 2026-05-05 (Core ML STT 가속 통합)

- ✅ **whisper.cpp Core ML encoder 벤치마크**
  - 빠른/표준 모델용 Core ML sidecar `ggml-large-v3-turbo-encoder.mlmodelc` 다운로드 및 검증
  - 같은 49분 25초 WAV, 같은 빠름(greedy), 같은 2초 overlap 기준:
    - 기존 Metal-only: `628.387초`, RTF `0.211885`
    - Core ML encoder: `203.654초`, RTF `0.0686698`
    - 약 `3.1배` 속도 개선 확인
- ✅ **앱 통합**
  - `libwhisper_wrapper.dylib`를 Core ML fallback 빌드로 교체
  - `scripts/build_whisper_macos.sh`가 `WHISPER_COREML=ON`, `WHISPER_COREML_ALLOW_FALLBACK=ON`으로 빌드하도록 수정
  - Core ML sidecar가 없으면 기존 Metal 경로로 fallback 유지
  - 설정/첫 실행 모델 화면에 `빠른 음성 인식 가속팩` 다운로드 및 압축 해제 추가
  - 진단 ZIP 모델 상태에 Core ML 가속팩 포함
- ✅ **검증/빌드**
  - `flutter analyze` 통과
  - `flutter test` 통과
  - `flutter build macos --debug` 통과
  - DMG 생성: `dist/적자생존_v2.1.1_build9.dmg`
  - DMG 내부 앱 `codesign --verify --deep --strict` 통과
  - `hdiutil verify` VALID

### 2026-05-06 (긴 회의 Core ML 재전사 추가 QA)

- ✅ **긴 WAV 3개 추가 속도 확인**
  - `meeting_1776747762956.wav` — 38분 28초
    - 빠름: `152.237초`, RTF `0.065952`
    - 표준: `161.747초`, RTF `0.0700719`
  - `meeting_1777011772576.wav` — 35분 57초
    - 빠름: `142.307초`, RTF `0.0659745`
  - `meeting_1776754895133.wav` — 29분 29초
    - 빠름: `115.336초`, RTF `0.065191`
- ✅ **확인 결과**
  - 세 파일 모두 Core ML encoder 로드 확인
  - 긴 회의 재전사 속도는 약 `오디오 길이 × 0.065~0.070`
  - 30~40분대 회의도 2~3분대 처리로 확인
  - QA 로그: `build/qa/stt_coreml_long_meetings_20260506.tsv`, `build/qa/stt_coreml_long_meetings_20260506.log`

### 2026-05-06 (긴 회의 전사 품질 QA)

- ✅ **전사 품질 샘플 추출**
  - `scripts/qa_stt_transcript_dump.cpp` 추가
  - 긴 회의 3개 빠름 모드, 대표 38분 파일 빠름/표준 비교 TSV 추출
  - QA 리포트: `build/qa/stt_quality_report_20260506.md`
- ✅ **발견 및 수정**
  - generic initial prompt `회의록 전사.`가 저신뢰 구간에서 본문처럼 새어 나오는 케이스 확인
  - `SttService._buildInitialPrompt()`가 실제 용어/참석자 힌트가 있을 때만 prompt를 넣도록 변경
  - 빈 단어집/참석자 상태에서는 Whisper initial prompt를 비워 환각 리스크 감소
  - 38분 파일 no-prompt 재검증에서 `회의록/위의록 전사` 누출 제거 확인
- ✅ **검증/빌드**
  - `flutter analyze` 통과
  - `flutter test` 통과
  - `flutter build macos --debug` 통과
  - DMG 생성: `dist/적자생존_v2.1.1_build10.dmg`
  - `hdiutil verify` VALID
  - DMG 내부 앱 `codesign --verify --deep --strict` 통과

### 2026-05-06 (녹취록 검색 한글 입력 수정)

- ✅ **원인**
  - 녹취록 패널의 단일 키 단축키 `J/K/Space`가 검색창 포커스 중에도 활성화됨
  - 두벌식 한글 모음 키 `j=ㅓ`, `k=ㅏ` 등이 단축키에 먹혀 한글 검색 시 자음만 입력되는 문제 발생
- ✅ **수정**
  - `EditableText`에 포커스가 있을 때 녹취록 패널의 `J/K/Space` 단축키 바인딩을 비활성화
  - 검색창/인라인 편집 중 한글 IME 조합 입력 보존
- ✅ **검증/빌드**
  - `flutter analyze` 통과
  - `flutter test` 통과
  - `flutter build macos --debug` 통과
  - DMG 생성: `dist/적자생존_v2.1.1_build11.dmg`
  - `hdiutil verify` VALID
  - DMG 내부 앱 `codesign --verify --deep --strict` 통과

### 2026-05-05 (STT/요약 속도 프로필 추가)

- ✅ **음성 인식 3단계 처리 방식 추가**
  - 설정: `빠름 / 표준 / 정밀` 선택 UI로 변경
  - 네이티브 whisper 래퍼에 `decode_mode` 추가
    - `빠름`: greedy 디코딩
    - `표준`: beam search `beam_size=2`
    - `정밀`: beam search `beam_size=5`
  - 기존 `sttAccurateMode` 저장값은 새 `sttProcessingMode`로 자동 승계
  - 회의 상세의 "음성 인식 다시" 다이얼로그도 3단계 선택으로 변경
- ✅ **요약 속도/품질 모드 추가**
  - 설정: `빠른 / 균형 / 정밀` 선택 UI 추가
  - 빠른 모드는 더 큰 청크, 더 적은 구간 bullet, 낮은 출력 토큰으로 요약 시간 단축
  - 빠른 요약 모드에서는 태그 자동 추출용 추가 LLM 호출을 생략
- ✅ **검증/빌드**
  - `bash scripts/build_whisper_macos.sh`로 `libwhisper_wrapper.dylib` 재빌드
  - `meeting_1776841360361.wav` 49분 파일 벤치: 빠름(greedy)도 537초(8분 57초)로 큰 개선 없음 확인
  - 무음 분석: 2초 이상 긴 무음은 약 70초(2.4%)라 VAD 스킵만으로는 개선폭 제한적
  - 긴 파일 재전사 청크 오버랩 `5초 → 2초`로 축소해 처리 청크 수를 줄임
  - 벤치 도구 추가: `scripts/benchmark_stt_modes.cpp`
  - `flutter analyze` 통과
  - `flutter test` 통과
  - `flutter build macos --debug` 통과
  - DMG 생성: `dist/적자생존_v2.1.1_build7.dmg`
  - `hdiutil verify` VALID, `codesign --verify --deep --strict` 통과
- ✅ **라벨 정리**
  - 실제 벤치 결과를 반영해 사용자 노출 STT 라벨을 `초고속/균형/정확` → `빠름/표준/정밀`로 변경
  - 최종 라벨 반영 DMG: `dist/적자생존_v2.1.1_build8.dmg`

### 2026-05-05 (긴 WAV 다시 전사 예상 시간 보정)

- ✅ **음성 인식 다시 돌리기 예상 시간 개선** (`lib/presentation/widgets/meeting_detail_view.dart`)
  - 원인: 빠른 STT 모델 예상 시간이 고정 `오디오 길이 × 0.08`로 계산되어 49분 25초 파일이 3분 57초로 과소 표시됨
  - 이전 실제 STT 기록(`sttRtf`, 모델명, 오디오 길이)이 같은 회의/같은 모델에 남아 있으면 해당 RTF에 12% 여유를 더해 예상 시간으로 사용
  - 이전 기록이 없을 때도 빠른 모델 기본 추정치를 `0.08` → `0.16`으로 보수화
  - 예: `meeting_1776841360361.wav` 49분대 파일은 기본 추정만으로도 약 7분 54초 수준으로 표시
  - 다이얼로그에 "이 회의의 이전 음성 인식 시간을 반영했습니다." 보조 문구 추가
- ✅ **검증/빌드**
  - `flutter analyze` 통과
  - `flutter test` 통과
  - DMG 생성: `dist/적자생존_v2.1.1_build4.dmg`
  - `hdiutil verify` VALID, `codesign --verify --deep --strict` 통과

### 2026-05-05 (DMG 설치 앱 실행 실패 수정)

- ✅ **원인 확인**
  - `/Applications/적자생존.app` 실행 직후 `dyld`가 `libisar.dylib` 로드를 거부
  - 시스템 로그 원인: Hardened Runtime Library Validation에서 메인 앱과 내부 dylib Team ID 불일치로 차단
  - `codesign --verify --deep --strict`는 통과했지만, 설치 실행 시 `Library Validation failed`로 종료됨
- ✅ **직접 배포용 서명 경로 분리**
  - App Store용 `Release.entitlements`는 유지
  - DMG 직접 배포용 `macos/Runner/DirectDistribution.entitlements` 추가
  - 직접 배포 DMG에서는 sandbox를 끄고 `com.apple.security.cs.disable-library-validation=true` 적용
- ✅ **DMG 빌드 스크립트 수정**
  - `scripts/build_dmg.sh`가 스테이징된 `.app`을 직접 배포용 ad-hoc 서명으로 재서명
  - 내부 dylib/framework 재서명 후 앱 번들 재서명 및 `codesign --verify --deep --strict` 검사
- ✅ **새 DMG 생성**
  - 산출물: `dist/적자생존_v2.1.1_build3.dmg`
  - `hdiutil verify`: VALID
  - SHA-256: `8d0cfcbc8e616b798bbaa3890658ec02ab3cac6d5bdcceacf5774ccd47b42618`
- ✅ **설치 앱 임시 복구 확인**
  - 기존 `/Applications/적자생존.app`도 직접 배포용 entitlements로 재서명
  - `open -n /Applications/적자생존.app` 실행 후 프로세스 정상 기동 확인

### 2026-05-05 (버전 관리 및 build2 DMG)

- ✅ **앱 표시 버전 동기화**
  - 홈 빈 화면/사이드바 하단의 하드코딩 `v1.0` 제거
  - `PackageInfo.fromPlatform()` 기반 공용 `AppVersionCredit` 위젯 추가
  - 앱 UI가 실제 macOS 번들 버전 `CFBundleShortVersionString`을 표시하도록 변경
- ✅ **빌드 번호 관리 스크립트 추가**
  - `scripts/version.sh` 추가
  - `show`, `bump-build`, `bump-patch`, `bump-minor`, `bump-major`, `set` 지원
  - App Store 업로드에 필요한 build number 증가를 `pubspec.yaml`의 `version: x.y.z+n`으로 관리
- ✅ **DMG 빌드 스크립트 버전 연동**
  - `scripts/build_dmg.sh`가 `pubspec.yaml` 버전을 읽어 `--build-name`, `--build-number`에 전달
  - 기본 실행 시 build number 자동 증가
  - 산출물 파일명에 build number 포함: `적자생존_v2.1.1_build2.dmg`
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `scripts/build_dmg.sh`: 성공
  - `hdiutil verify dist/적자생존_v2.1.1_build2.dmg`: VALID
  - `codesign --verify --deep --strict`: 통과

### 2026-05-05 (P0 출시 전 수동 QA 완료)

- ✅ **녹음 준비 다이얼로그 마이크 테스트 확인**
  - 자동 검증: `flutter analyze`, `flutter test`, `flutter build macos --debug` 통과
  - 앱 실행/종료 확인: 프로세스 정상 기동, 새 녹음 파일 생성 없음, 새 DiagnosticReports 크래시 없음
  - 확인 입력 장치: `MacBook Air 마이크`, `Channy_iPhone17 마이크`
  - 사용자 수동 QA로 마이크 레벨 바, 마이크 변경/새로고침, 녹음 시작/취소 충돌 없음 확인
- ✅ **트레이 빠른 녹음 확인**
  - 사용자 수동 QA로 메뉴바 `빠른 녹음 시작` → `북마크 추가` → `녹음 정지` 확인
- ✅ **장시간 회의 안정성 확인**
  - 사용자 수동 QA로 45분 이상 실제 회의 파일 안정성 재검증 완료

### 2026-05-05 (P0 앱스토어 안전 모델 정리)

- ✅ **제한 모델 저장값 정리**
  - 앱 시작 시 과거 `selectedLlmModel=exaone35_7b` 저장값을 안전 기본 모델로 자동 정리
  - 앱스토어 안전 모드에서 Calendar 자동 추가 설정이 남아 있으면 `false`로 정리
- ✅ **제한 모델 다운로드 방어**
  - 초기 설정/설정 화면의 EXAONE 다운로드 함수가 직접 호출돼도 안전 모드에서는 즉시 반환
  - 초기 설정 화면의 EXAONE URL 컨트롤러는 내부 빌드에서만 URL을 보유
- ✅ **회귀 테스트 추가**
  - 앱스토어 안전 모드에서 `exaone35_7b`가 선택지에서 제외되는지 검증
  - 과거 제한 모델 저장값이 `gemma4_e2b`로 정리되는지 검증
  - 제한 모델 파일/URL helper가 안전 기본 모델로 fallback 하는지 검증
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-05 (보고서 파일 저장 템플릿)

- ✅ **보고서 형식 PDF/DOCX 저장 추가**
  - 내보내기 메뉴에 `보고서 PDF 저장`, `보고서 Word 저장` 추가
  - 기존 전체 회의록 저장과 달리 전사본을 제외하고 보고용 핵심 섹션만 출력
  - 보고서 구성: 제목/일자/참석자, 핵심 논의, 결정 사항, 액션 아이템, 리스크/확인 필요
- ✅ **보고서 DOCX 회귀 테스트 추가**
  - 전체 DOCX에는 전사본이 포함되고, 보고서 DOCX에는 전사본이 빠지는지 검증
  - 보고서 DOCX에 `핵심 논의`, `리스크 / 확인 필요` 섹션이 포함되는지 검증
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-05 (DOCX 내보내기)

- ✅ **Word 문서 저장 추가**
  - 회의 상세 내보내기 메뉴에 `Word 문서로 저장 (.docx)` 추가
  - 회의 제목, 날짜, 소요 시간, 참석자, 주요 논의, 결정 사항, 액션 아이템, 미해결 이슈, 전사본을 DOCX로 생성
  - 별도 패키지 추가 없이 기존 `archive` 패키지로 WordprocessingML 기반 `.docx` 패키지 생성
- ✅ **회귀 테스트 추가**
  - 생성된 DOCX zip 안에 `[Content_Types].xml`, `_rels/.rels`, `word/document.xml`이 포함되는지 검증
  - 문서 XML에 회의 제목, 결정 사항, 액션 아이템이 포함되는지 검증
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-05 (P1 일반 사용자 UX 보강)

- ✅ **내보내기 복사 옵션 강화**
  - `Notion용 요약 복사` 추가: 전사본 없이 참석자, 주요 논의, 결정, 액션아이템, 미해결 이슈만 Markdown으로 복사
  - `보고서 형식 복사` 추가: 업무 보고서에 붙여넣기 쉬운 요약형 Markdown 생성
  - `액션아이템만 복사` 추가: 체크리스트 형태로 후속 조치만 빠르게 공유 가능
- ✅ **요약 템플릿 문구 일반 사용자화**
  - 설정 화면의 `LLM`, `시스템 프롬프트` 표현을 줄이고 `세부 정리 방식`, `요약에서 강조할 기준`으로 정리
  - 긴 분석 지침은 계속 고급 설정 접기 안에 유지
- ✅ **회귀 테스트 추가**
  - Notion용 요약이 전사본을 제외하는지 검증
  - 액션아이템 단독 복사 Markdown 검증
  - 보고서 형식 Markdown 섹션 검증
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-05 (정기 회의 시리즈 자동 인식 1차)

- ✅ **시리즈 후보 탐지 로직 추가**
  - 미분류 회의의 제목, 태그, 참석자 유사도를 계산해 정기 회의 후보를 추천
  - 제목 날짜/시간/불러오기 표기를 정규화해 `제품 주간 회의 2026-05-01`과 `제품 주간 회의 2026-05-08`을 같은 시리즈로 인식
  - 이미 사용자가 수동 그룹에 넣은 회의는 자동 추천 대상에서 제외
- ✅ **사이드바 적용 UX 추가**
  - 사이드바 하단에 `시리즈 추천` 버튼 추가
  - 추천 다이얼로그에서 후보별 회의 수, 신뢰도, 추천 근거, 포함 회의를 확인 후 선택 적용 가능
  - 적용 시 기존 `MeetingGroup`을 사용해 새 그룹을 만들고 관련 회의를 이동
- ✅ **회귀 테스트 추가**
  - 반복 제목/참석자 기반 추천
  - 기존 그룹 회의 제외
  - `회의` 같은 일반 제목만으로 오탐하지 않는 케이스 검증
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-03 (요약 신뢰도 v3 1차)

- ✅ **액션아이템 담당자/기한 확실성 표시**
  - 액션아이템 JSON에 `ownerConfirmed`, `deadlineConfirmed` 선택 필드 지원
  - 기존 데이터도 빈 값, `(미언급)`, `미정`, `TBD` 등은 자동으로 미확인 처리
  - 회의 상세 액션아이템 행에 `담당자 미확인`, `기한 미확인` 칩 표시
- ✅ **확인 필요 요약 배너**
  - 액션아이템 섹션 상단에 확인 필요한 담당자/기한 개수 표시
  - 사용자가 실수 비용이 큰 항목을 먼저 검토할 수 있게 개선
- ✅ **내보내기 반영**
  - 텍스트/PDF/Markdown 내보내기에서도 미확인 담당자/기한을 명시
  - `ActionItem` 확실성 판정 회귀 테스트 추가

### 2026-05-03 (다국어 회의 지원)

- ✅ **자동 감지 언어 옵션 추가**
  - 음성 인식 언어에 `자동 감지` 옵션 추가
  - 한국어+영어처럼 언어가 섞인 회의에서 Whisper language auto 사용 가능
- ✅ **녹음/재전사 UX 연결**
  - 녹음 준비 다이얼로그에서 회의별 음성 인식 언어 선택 가능
  - `음성 인식 다시` 다이얼로그에서도 언어를 선택해 재전사 가능
  - 선택한 언어는 설정값으로 저장되어 실시간 전사/최종 전사에 적용
- ✅ **처리 리포트 기록**
  - 회의 처리 리포트에 사용한 음성 인식 언어 저장
  - 상세 기술 정보에서 음성 인식 언어 표시

### 2026-05-03 (태그 자동 추천)

- ✅ **회의 상세 태그 추천 버튼 추가**
  - 회의 상세 태그 영역에 `추천` 버튼 추가
  - 요약이 있는 회의에서 선택한 요약 모델로 태그 후보를 생성
  - 추천 후보는 다이얼로그에서 선택 후 적용
- ✅ **수동 태그 보존**
  - 녹음 완료/재요약 후 자동 태그 추출 시 기존 수동 태그를 덮어쓰지 않고 병합
  - 중복 태그와 너무 일반적인 태그를 필터링
- ✅ **회귀 테스트 추가**
  - `TagExtractor.mergeTags()`가 수동 태그를 보존하고 중복 추천을 제거하는지 검증

### 2026-05-03 (회의록 Markdown 내보내기 강화)

- ✅ **Markdown 생성 추가**
  - `ExportService.buildMarkdown()` 추가
  - 회의 제목, 날짜, 소요 시간, 참석자, 주요 논의, 결정 사항, 액션 아이템, 미해결 이슈, 전사본을 Markdown 구조로 변환
  - 액션 아이템은 Markdown 표로 출력하고 완료 상태를 체크박스 형태로 표시
- ✅ **Markdown 저장/복사 추가**
  - `ExportService.saveAsMarkdown()`으로 `.md` 파일 저장 지원
  - `ExportService.copyMarkdown()`으로 Notion/Slack/문서툴에 붙여넣기 쉬운 Markdown 클립보드 복사 지원
- ✅ **회의 상세 내보내기 메뉴 연결**
  - 내보내기 메뉴에 `Markdown으로 저장 (.md)` 추가
  - 내보내기 메뉴에 `Markdown 복사` 추가

### 2026-05-03 (다른 AI 계정용 문서 최신화)

- ✅ **AI 인수인계 상단 요약 추가**
  - `AI_HANDOFF.md`에 `다음 AI 빠른 시작` 섹션 추가
  - 현재 앱 상태, 다음 추천 작업, 개발 명령, 금지/주의 정책을 한 화면에서 파악 가능하게 정리
- ✅ **남은 작업 범위 보정**
  - 내보내기 기능이 이미 `.txt`, `.pdf`, 이메일, 공유 시트를 지원한다는 점을 문서화
  - 다음 내보내기 작업은 Markdown 저장/복사 중심으로 좁혀 정리
- ✅ **리스크 문구 최신화**
  - 요약 근거 버튼이 적용된 상태에 맞춰 오래된 `근거 표시 없음` 리스크 표현 제거
  - 다음 개선은 근거 신뢰도/출처 저장 고도화로 정리

### 2026-05-03 (요약 근거 보기 버튼 UX 개선)

- ✅ **근거 버튼 노출 강화**
  - 주요 논의, 결정 사항, 미해결 이슈 항목 오른쪽에 명확한 `근거` 버튼 표시
  - 액션 아이템 행에도 같은 `근거` 버튼 표시
  - LLM이 근거 시간을 명시한 경우 `근거 02:55`처럼 시간까지 버튼에 표시
- ✅ **근거 탐색 흐름 유지**
  - 근거 시간이 있으면 해당 전사/오디오 시점으로 이동
  - 근거 시간이 없으면 전사본에서 관련 후보 구간을 검색해 근거 패널 표시
  - 버튼이 작은 `확인` 배지처럼 보이던 문제를 일반 사용자에게 명확한 버튼 형태로 개선
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-03 (녹음 준비 다이얼로그 실사용 QA — 자동 가능 범위)

- ✅ **정적 검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공
- ✅ **앱 실행 확인**
  - Debug 앱 실행: `/Users/channy/LocalMinutes/build/macos/Build/Products/Debug/적자생존.app`
  - 프로세스 확인: `LocalMinutes` 실행 중
- ✅ **실행 직후 로그 확인**
  - 앱 내부 crash log 수정 시각이 2026-04-30으로, 이번 실행에서 새 crash log 기록 없음
  - macOS `DiagnosticReports`에 이번 실행 직후 새 `LocalMinutes` 크래시 없음
- ⚠️ **남은 수동 QA**
  - 현재 환경에서 `osascript` 보조 접근 권한이 없어 녹음 준비 버튼 클릭과 마이크 레벨 움직임 자동 검증은 불가
  - 사용자가 실제 화면에서 마이크 레벨 바, 마이크 변경, 새로고침, 시작/취소 충돌 여부를 최종 확인해야 함

### 2026-05-03 (작업 목록 정리)

- ✅ **Backlog 정합성 정리**
  - 이미 완료된 메뉴바 트레이, 단축키, 에러 처리, 진단 ZIP, 빈 녹음 감지 항목을 상단 Backlog에서 제거
  - 실제 남은 일을 P0/P1/P2/P3 우선순위로 재분류
  - 출시 전 수동 QA, 요약 근거, 요약 재생성, 내보내기, 전사 보정, 업무 흐름 확장을 다음 개발 후보로 정리
- ✅ **다른 AI 인수인계 기준 맞춤**
  - `AI_HANDOFF.md`의 남은 추천 작업과 `TASKS.md` Backlog가 같은 방향을 가리키도록 정리

### 2026-05-03 (녹음 준비 다이얼로그 실시간 마이크 테스트)

- ✅ **실시간 마이크 테스트 추가**
  - 녹음 준비 다이얼로그에서 선택한 마이크 입력 레벨을 실시간 표시
  - `입력이 잘 들어오고 있어요`, `조금 작게 들립니다`, `너무 조용합니다`, `확인 필요` 상태 표시
  - 진행 바 색상으로 입력 상태를 즉시 확인 가능
- ✅ **선택 마이크 기준 테스트**
  - 시스템 기본 마이크 또는 사용자가 선택한 입력 장치 기준으로 테스트
  - 마이크 선택을 바꾸면 테스트 스트림을 재시작
  - 새로고침 버튼으로 마이크 테스트 재시작 가능
- ✅ **녹음 시작 충돌 방지**
  - 실제 녹음 시작/취소 전에 테스트용 `AudioRecorder` 스트림을 먼저 정리
  - 실제 STT 녹음 파이프라인과 테스트 스트림이 겹치지 않도록 처리
- ✅ **권한/입력 실패 안내**
  - 마이크 권한이 꺼져 있거나 입력 장치를 열 수 없으면 준비 화면에서 `확인 필요` 안내 표시
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-03 (키보드 단축키 확장 QA/보강)

- ✅ **전역 단축키 확인**
  - `Cmd+Shift+R`: 녹음 시작/정지
  - `Cmd+Shift+S`: 녹음 화면에서는 요약 실행, 회의 상세에서는 재요약 실행
  - `Cmd+F`: 사이드바 검색 포커스
  - `Cmd+,`: 설정 열기
  - 회의 상세 전사 패널: `Space` 재생/일시정지, `J/K` 이전/다음 세그먼트 이동
- ✅ **단축키 실패 안내 보강**
  - AI/STT/요약 등 네이티브 작업 중 `Cmd+Shift+R`로 녹음을 시작하려 하면 안내 표시
  - 녹음 중 `Cmd+Shift+S`를 누르면 `녹음을 중지한 뒤 요약을 실행할 수 있습니다.` 안내
  - 이미 요약 중이면 중복 요약 안내
  - 전사 내용이 없는 상세 화면에서 `Cmd+Shift+S`를 누르면 음성 인식 먼저 실행 안내
- ✅ **일반 버튼과 단축키 정책 일치**
  - 시작 화면의 `새 녹음 시작` 버튼도 네이티브 작업 중이면 녹음 시작을 차단
  - 트레이 빠른 녹음 차단 정책과 같은 사용자 안내 흐름 유지
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-03 (빈 세션 감지 고도화)

- ✅ **녹음 품질 판정 강화**
  - 녹음 시간, 오디오 입력 바이트, 전사 세그먼트 수, 인식 글자 수, 최대 입력 레벨을 함께 평가
  - `empty`: 5초 미만, 마이크 입력 없음, 12초 이상 전사 없음, 낮은 음량+매우 적은 글자 수
  - `low`: 30초 이상 녹음 대비 전사 글자/세그먼트가 적거나 입력 레벨이 낮은 경우
- ✅ **요약 전 경고 UX 개선**
  - 품질이 낮은 녹음은 요약 전 다이얼로그로 경고
  - 선택지: `보관만 하기`, `삭제`, `그래도 요약하기`
  - 전사 세그먼트가 없는 경우에는 요약을 막고 `보관만 하기`/`삭제`만 제공
- ✅ **회의 기록에 품질 상태 저장**
  - `MeetingProcessingReport`에 입력 품질 필드 추가
  - 저장 항목: `inputQualityStatus`, `inputQualityReason`, `inputRecognizedChars`, `inputSegmentCount`, `inputMaxLevel`
  - 기존 JSON 리포트와 하위 호환 유지
- ✅ **목록/상세 화면 표시**
  - 사이드바 회의 목록에 `마이크 입력 낮음`, `전사 부족` 경고 표시
  - 회의 상세 `작업 시간` 카드에 `녹음 품질` 항목 표시
  - 고급 정보에서 품질 사유, 전사 글자/세그먼트, 최대 입력 레벨 확인 가능
- ✅ **진단 로그 기록**
  - 품질 문제가 감지되면 `CrashLogService.info()`로 로컬 로그 기록
  - `emptyRecordingAfterStop`, `summaryBlockedEmptyRecording`, `summaryLowQualityPrompt`, `persistMeetingInputQuality` context 추가
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-03 (진단 로그 내보내기 UX 고도화)

- ✅ **설정 화면 진단 섹션 개선**
  - `디버그·진단` 섹션명을 일반 사용자용 `문제 해결`로 변경
  - 원본 녹음, 전체 전사, 회의 요약 전문이 진단 ZIP에 포함되지 않는다는 프라이버시 안내를 섹션 상단에 고정 표시
  - 최근 충돌·예외 로그 크기를 설정 화면에 표시
- ✅ **진단 ZIP 내보내기 확인 다이얼로그 추가**
  - 내보내기 전 포함 정보/미포함 정보를 명확히 안내
  - 포함: 앱/OS/설정/모델 설치 상태, 최근 처리 메타데이터, 충돌·예외 로그
  - 미포함: 원본 녹음, 전체 전사, 회의 요약 전문, 회의 제목 원문
- ✅ **내보내기 완료 UX 개선**
  - 저장 완료 후 파일 경로를 클립보드에 복사
  - SnackBar에서 `Finder 열기` 액션 제공
  - 로그 파일 위치 버튼도 Finder에서 폴더를 열도록 변경
- ✅ **오류 안내 개선**
  - 진단 ZIP 생성 실패와 Finder 열기 실패 시 `friendlyErrorText()`로 사용자용 문구 표시
  - 실제 예외는 `CrashLogService.recordCaught()`로 로컬 로그에 기록
  - `exportDiagnostics`, `openPathInFinder` context 추가
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-03 (에러 처리 강화)

- ✅ **공통 사용자 오류 문구 변환기 추가**
  - `UserErrorMessage` / `friendlyErrorMessage()` / `friendlyErrorText()` 추가
  - 디스크 부족, 권한 문제, 네트워크 문제, 모델 로드 실패, 메모리 부족, 오디오 파일 문제를 사용자용 문구로 변환
  - UI에는 기술 오류 대신 원인과 다음 행동을 안내
- ✅ **녹음/요약/STT 오류 안내 개선**
  - 녹음 시작 실패 시 마이크, 저장 폴더, 모델 설치 상태 확인 안내
  - 전사 저장 실패 시 저장 폴더와 디스크 여유 공간 확인 안내
  - 요약/재요약 실패 시 전사는 보존되며 다시 요약 또는 회의록 열기가 가능하다는 안내
  - 정확 전사 실패 시 실시간 전사본으로 계속 진행한다는 안내
  - STT 다시 돌리기 실패 시 오디오 파일과 모델 설치 상태 확인 안내
  - 용어 추출 실패 시 회의록 내용은 유지된다는 안내
- ✅ **모델 설치 오류 안내 개선**
  - 첫 실행 모델 설치 화면과 설정 화면의 일반 다운로드 예외를 사용자용 문구로 변환
  - 네트워크, 저장 공간, 모델 폴더 권한 확인 안내 추가
- ✅ **로그 기록**
  - 사용자 화면에는 친절한 안내만 표시
  - 실제 예외는 `CrashLogService.recordCaught()`로 로컬 로그에 기록
  - `startRecording`, `persistMeetingAndTranscripts`, `runSummary`, `refreshFinalTranscript`, `resummarize`, `rerunStt`, `extractTerms`, `setupModelDownload`, `settingsModelDownload` context 추가
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-03 (화자 라벨 실패 안내 정리)

- ✅ **사용자 안내 문구 개선**
  - 발화자 라벨 실패 시 기술 오류를 그대로 노출하지 않고 `발화자 구분에 실패했습니다.` 문구로 안내
  - 요약 흐름에서는 `회의 요약은 계속 진행합니다.`
  - STT 다시 돌리기 흐름에서는 `전사본은 발화자 라벨 없이 저장합니다.`
  - `나중에 음성 인식을 다시 실행하면 발화자 라벨도 다시 만들 수 있습니다.` 후속 안내 추가
- ✅ **상태 문구 개선**
  - 요약 전 화자 라벨 실패 시 `발화자 구분에 실패했습니다. 라벨 없이 요약을 계속합니다.` 표시
  - STT 다시 돌리기 중 실패 시 `발화자 구분에 실패했습니다. 라벨 없이 전사본을 저장합니다.` 표시
- ✅ **로그 기록**
  - 사용자 화면에는 친절한 안내만 표시
  - 실제 예외는 `CrashLogService.recordCaught()`로 로컬 로그에 기록
  - `runDiarizationBeforeSummary`, `rerunSttDiarization`, `pipelineDiarization` context 추가
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-03 (앱 종료/창 닫기 중 작업 안내)

- ✅ **작업 중 종료 확인 다이얼로그 추가**
  - 녹음, 일시 정지된 녹음, STT/화자 라벨/요약/모델 로드 등 네이티브 작업 중 앱 종료 시 확인 다이얼로그 표시
  - 문구: `현재 <작업명> 작업 중입니다. 종료하면 진행 중인 작업이 중단되거나 결과가 저장되지 않을 수 있습니다.`
  - `취소` / `종료` 선택 제공
- ✅ **종료 경로 통합**
  - Cmd+Q / 시스템 종료 요청: `AppLifecycleListener.onExitRequested`에서 확인
  - 창 닫기: `WindowListener.onWindowClose` + `windowManager.setPreventClose(true)`로 확인
  - 트레이 `종료`: 같은 확인 로직을 거친 뒤 종료
- ✅ **안전 종료 유지**
  - 사용자가 종료를 확정한 경우 `_gracefulShutdown()`으로 녹음 정지, LLM 취소 요청, STT/LLM 언로드, 트레이 dispose 수행
  - 중복 종료 다이얼로그 방지를 위해 `_exitPromptShowing`, `_isExiting` 상태 추가
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-03 (트레이 빠른 녹음 AI 작업 중 차단)

- ✅ **트레이 시작 상태에 네이티브 작업 반영**
  - `OnDeviceModelManager.nativeTaskStream`을 앱 루트에서 구독
  - STT/화자 라벨/요약/모델 로드 등 네이티브 작업 중이면 트레이 시작 메뉴를 `busy` 상태로 갱신
  - 트레이 메뉴에 `⏳ <작업명> 중...`으로 표시되어 빠른 녹음 시작이 비활성화됨
- ✅ **트레이 시작 요청 이중 방어**
  - 상태 반영이 늦은 상황에서도 `_handleTrayStartRecord()`에서 현재 네이티브 작업을 다시 확인
  - 작업 중이면 앱 창을 앞으로 가져오고 `AI 작업이 진행 중입니다` 다이얼로그 표시
  - 빠른 녹음 신호를 보내지 않아 RecordingView가 뒤늦게 녹음을 시작하지 않도록 처리
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-02 (버튼 비활성화/중복 요청 UX 정리)

- ✅ **요약/녹음 버튼 비활성화 기준 보강**
  - 녹음 화면의 `요약`, `요약 다시 시도`, `녹음 시작` 버튼이 네이티브 작업 진행 중이면 비활성화
  - 버튼 tooltip에 `현재 ... 작업 중입니다. 완료 후 다시 시도해주세요.` 안내 표시
  - `_runSummary()` 진입 시에도 네이티브 작업 진행 중이면 SnackBar로 안내하고 즉시 반환
- ✅ **회의 상세 버튼 비활성화 기준 보강**
  - `다시 요약`, `요약 생성`, `음성 인식 다시` 버튼이 STT/요약/화자 라벨/모델 로드 중이면 비활성화
  - 버튼 tooltip에 비활성화 이유 표시
  - `_runResummarize()`, `_rerunStt()` 진입 시에도 네이티브 작업 진행 중이면 SnackBar로 안내하고 즉시 반환
- ✅ **상태 반영**
  - `OnDeviceModelManager.nativeTaskStream`을 버튼 영역에서도 구독해 작업 시작/종료에 따라 버튼 상태가 자동 갱신되도록 처리
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-01 (진행 중 네이티브 작업 안내)

- ✅ **네이티브 작업 상태 스트림 추가**
  - `OnDeviceModelManager.nativeTaskStream` 추가
  - 현재 실행 중인 작업 `activeLabel`, 대기 중인 작업 `queuedLabel`, 대기 개수 `queuedCount`를 `NativeModelTaskSnapshot`으로 제공
  - 작업이 큐에 들어갈 때도 `CrashLogService.info()`에 `native task queued` 로그 기록
- ✅ **요약 실행 화면 안내**
  - 요약 진행 카드에 현재 실행 중인 네이티브 작업 표시
  - 대기 작업이 있으면 `다음 작업 대기: ...` 또는 `대기 중: ... 외 N개`로 표시
- ✅ **회의 상세 처리 화면 안내**
  - `STT 다시 돌리기` 진행 인디케이터에 현재/대기 네이티브 작업 안내 추가
  - `다시 요약` 진행 인디케이터에도 같은 안내 추가
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-01 (네이티브 모델 작업 직렬화)

- ✅ **공통 네이티브 작업 잠금 추가**
  - `OnDeviceModelManager.acquireNativeTask()` / `runExclusiveNativeTask()` 추가
  - STT, 화자 분리, LLM 로드/추론/해제 작업이 동시에 실행되지 않도록 단일 큐로 직렬화
  - 현재 실행 중인 네이티브 작업 라벨을 `activeNativeTaskLabel`로 확인 가능
- ✅ **STT 작업 보호**
  - 음성 파일 전사 `transcribeFile()` 전체를 네이티브 잠금으로 감쌈
  - 녹음 중 실시간 윈도우 전사 `transcribeFromSamples()`도 잠금으로 감쌈
  - STT 모델 로드/해제도 같은 잠금 사용
- ✅ **화자 분리 작업 보호**
  - `DiarizationService.diarizeWav()` 전체를 네이티브 잠금으로 감쌈
  - LLM 로드/생성 또는 STT decode와 겹치지 않도록 처리
- ✅ **LLM 작업 보호**
  - LLM 모델 로드/해제에 잠금 적용
  - LLM 생성 스트림 전체에 lease를 잡아 요약 생성 중 STT/화자 분리가 끼어들지 않도록 처리
  - 기존 LLM generation idle 대기 로직은 유지
- ✅ **진단 로그**
  - `CrashLogService.info()`로 네이티브 작업 시작/종료와 소요 시간을 로컬 로그에 기록
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-01 (화자 분리 진행 UX 보완)

- ✅ **요약 실행 중 화자 분리 안내 개선**
  - 화자 라벨 단계에서 요약 카드 제목을 `발화자를 구분하고 있습니다`로 변경
  - 긴 녹음은 몇 분 걸릴 수 있다는 설명 표시
  - 실제 상태 문구를 요약 카드 안에 표시해 사용자가 현재 단계를 확인할 수 있게 개선
  - 진행 단계 표시를 `전사 확인 → 발화자 라벨 → 요약 생성 → 결과 저장`으로 정리
- ✅ **STT 다시 돌리기 중 화자 분리 안내 개선**
  - 화자 라벨 단계 진입 시 기존 STT 진행률/시간 표시를 초기화
  - 세밀한 진행률 대신 indeterminate progress로 표시
  - `진행률이 자주 갱신되지 않을 수 있습니다` 안내 추가
- ✅ **파이프라인 단계 문구 개선**
  - `화자 분리 중...`을 일반 사용자용 `발화자 라벨 생성 중... 긴 녹음은 몇 분 걸릴 수 있습니다.`로 변경
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-01 (화자 분리 크래시 완화)

- ✅ **크래시 리포트 분석**
  - macOS crash report에서 `Thread 24 DartWorker`가 `DLRT_GetFfiCallbackMetadata` → `libsherpa-onnx-c-api.dylib` → `OfflineSpeakerDiarizationPyannoteImpl::Process` 경로에서 `SIGABRT` 발생
  - 같은 시점 main thread에는 `libllama_wrapper.dylib` 모델 로딩 stack도 보여 네이티브 모델 작업 겹침 가능성 확인
  - 직접 원인은 sherpa-onnx 화자 분리의 Dart FFI progress callback 경로로 판단
- ✅ **화자 분리 안정화**
  - `DiarizationService`에서 `processWithCallback()` 사용 중단
  - callback-free `process()` 경로로 변경해 네이티브 worker thread가 Dart callback metadata를 호출하지 않도록 수정
  - 진행률은 시작 5%, 완료 100%만 전달하도록 단순화
- ✅ **isolate 종료 처리 안정화**
  - 화자 분리 timeout 시 `Isolate.immediate` kill 제거
  - 네이티브 FFI 실행 중인 isolate를 강제 종료하지 않고 자연 정리되도록 변경
  - isolate가 결과 없이 종료되거나 error port로 오류를 보내는 경우 명확한 실패로 처리
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공

### 2026-05-01 (진단 자료 ZIP 실제 생성 테스트)

- ✅ **자동 테스트 추가**
  - `test/diagnostic_export_test.dart` 추가
  - 임시 Application Support/녹음 폴더를 mock 처리
  - 테스트용 회의/전사/요약에 비밀 문자열을 넣은 뒤 진단 ZIP 생성
- ✅ **ZIP 구조 검증**
  - `README.txt` 포함 확인
  - `diagnostics.json` 포함 확인
  - `logs/crash.log` 포함 확인
- ✅ **개인정보 제외 검증**
  - `containsOriginalAudio=false`
  - `containsFullTranscript=false`
  - `containsSummaryBody=false`
  - `containsMeetingTitles=false`
  - ZIP 전체 텍스트에 테스트용 회의 제목/전사/요약 비밀 문자열이 들어가지 않는 것 확인
- ✅ **검증**
  - `flutter test test/diagnostic_export_test.dart`: 통과
  - `flutter test`: 통과
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공

### 2026-05-01 (문제 진단 자료 내보내기 UX)

- ✅ **진단 ZIP 생성 서비스 추가**
  - `DiagnosticExportService` 추가
  - `archive` 패키지로 ZIP 생성
  - `package_info_plus`로 앱 버전/빌드 번호 수집
  - 저장 패널에서 `jeokjasaengjon_diagnostics_YYYYMMDD_HHMMSS.zip` 저장
- ✅ **진단 자료 구성**
  - `README.txt`: 포함/제외 항목과 개인정보 안내
  - `diagnostics.json`: 앱 버전, macOS 정보, 설정, 모델 설치 상태, 저장 폴더 상태, 최근 회의 처리 메타데이터
  - `logs/crash.log`: 앱 내부 충돌·예외 로그
  - `logs/crash.log.old`: 로그 회전 백업이 있을 때만 포함
- ✅ **개인정보 보호 기준**
  - 원본 녹음 파일 미포함
  - 전체 전사 텍스트 미포함
  - 요약 전문 미포함
  - 회의 제목 원문 미포함
  - 최근 회의는 상태, 시간, 세그먼트 수, 처리 리포트 등 진단용 메타데이터만 포함
- ✅ **설정 화면 UX**
  - `디버그·진단` 섹션에 `문제 진단 자료 내보내기` 추가
  - 생성 중 로딩 표시
  - 저장 완료 시 경로를 클립보드에 복사하고 SnackBar 표시
  - 생성 실패 시 `CrashLogService`에 기록하고 사용자에게 오류 안내
- ✅ **검증**
  - `flutter test`: 통과
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공

### 2026-05-01 (트레이 메뉴 상태 개선)

- ✅ **트레이 시작 가능 상태 추가**
  - `TrayStartState` 추가: `ready`, `storageRequired`, `modelsRequired`, `busy`
  - `MenuBarService.setStartState()`로 idle 상태 메뉴와 tooltip 갱신
- ✅ **상태별 메뉴 문구**
  - 녹음 가능: `빠른 녹음 시작`
  - 저장 폴더 미설정: `저장 폴더 설정 필요`
  - 모델 준비 전: `AI 모델 준비 필요`
  - 처리 중: `모델 확인 중...`, `녹음 준비 중...`, `녹음 정리 중...`, `요약 중...`
  - 준비되지 않은 상태의 시작 메뉴는 비활성화
- ✅ **앱 상태 연동**
  - 앱 첫 실행/저장 폴더 선택/모델 준비 완료 시 트레이 상태 동기화
  - 녹음 화면의 phase에 따라 busy/ready/model required 상태 동기화
  - 녹음 중 메뉴는 기존처럼 `녹음 중`, `북마크 추가`, `녹음 정지` 유지
- ✅ **검증**
  - `flutter test`: 통과
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공

### 2026-05-01 (트레이 녹음 시작 실패 안내)

- ✅ **트레이 시작 요청 분리**
  - `pendingTrayQuickStartFromTrayProvider` 추가
  - 트레이 메뉴에서 시작한 요청과 키보드 단축키 시작 요청을 구분
  - 트레이 시작 시 앱 창을 먼저 앞으로 가져오도록 처리
- ✅ **트레이 시작 전 차단 안내**
  - 첫 실행 저장 폴더가 아직 선택되지 않은 경우: 저장 폴더 선택 필요 안내
  - 모델 설정 화면 단계인 경우: 음성 인식/요약 모델 준비 필요 안내
  - 실패 시 조용히 pending 상태로 남지 않도록 트레이 시작 신호를 보내지 않음
- ✅ **녹음 화면 내 실패 안내**
  - 음성 인식 모델 없음: 사용자용 문구로 안내
  - 저장 폴더 미설정: 저장 폴더 선택 필요 안내
  - 저장 폴더 접근 실패: 다른 저장 폴더 선택 안내와 현재 경로 표시
  - 마이크 권한 없음: 기존 시스템 설정 이동 다이얼로그 유지
  - 기타 시작 실패: 상세 오류를 포함한 다이얼로그 표시
- ✅ **검증**
  - `flutter test`: 통과
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공

### 2026-05-01 (트레이 앱 창 열기 포커스 보강)

- ✅ **창 제어 패키지 도입**
  - `window_manager: ^0.5.1` 추가
  - macOS 플러그인 등록 확인: `window_manager`, `screen_retriever_macos`
- ✅ **트레이 앱 창 열기 동작 보강**
  - 앱 시작 시 `windowManager.ensureInitialized()` 실행
  - 트레이 `앱 창 열기` 및 녹음 중 트레이 아이콘 좌클릭 시 `_showAppWindow()` 실행
  - 창이 최소화되어 있으면 `restore()`
  - 창이 숨겨져 있거나 뒤에 있으면 `show()` 후 `focus()`
  - `window_manager` macOS 구현이 `makeKeyAndOrderFront`와 `NSApp.activate`를 호출하는 것 확인
- ✅ **검증**
  - `flutter test`: 통과
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공

### 2026-05-01 (트레이 빠른 녹음 QA)

- ✅ **코드 경로 QA**
  - idle 상태 트레이 메뉴: `빠른 녹음 시작` → `onStartRecord` → `pendingTrayQuickStartProvider` → `RecordingView._startRecording()`
  - 녹음 중 트레이 메뉴: `북마크 추가` → `pendingTrayBookmarkCountProvider` → `RecordingView._addBookmark()`
  - 녹음 중 트레이 메뉴: `녹음 정지` → `pendingTrayStopProvider` → `RecordingView._stopRecording()`
  - 다른 회의 상세 화면을 보고 있어 `RecordingView`가 언마운트된 경우에도 start/stop/bookmark가 녹음 화면 복귀 후 처리되는 흐름 확인
- ✅ **실행/검증**
  - `flutter test`: 통과
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공
  - Debug 앱 실행 확인: `/Users/channy/LocalMinutes/build/macos/Build/Products/Debug/적자생존.app`
  - 프로세스 확인: `LocalMinutes` 실행 중
  - 최근 시스템 로그 확인: 앱 크래시 로그 없음
- ⚠️ **자동 클릭 QA 제한**
  - macOS가 `osascript` 보조 접근 권한을 허용하지 않아 트레이 아이콘/메뉴 항목을 스크립트로 직접 클릭하는 검증은 수행하지 못함
  - 실제 배포 전 수동 체크 필요: 트레이에서 시작 → 북마크 → 정지 → 생성된 회의에 북마크 저장 여부 확인

### 2026-05-01 (트레이 북마크 추가 동작 보강)

- ✅ **트레이 북마크 신호 경로 확인**
  - `MenuBarService`의 bookmark 메뉴 액션이 `trayBookmarkSignalProvider`로 전달되는 흐름 점검
  - 녹음 화면이 마운트된 상태에서는 `RecordingView._addBookmark()`로 즉시 저장
- ✅ **화면 전환 중 북마크 누락 방지**
  - `pendingTrayBookmarkCountProvider` 추가
  - 녹음 중 다른 회의 상세 화면을 보고 있어 `RecordingView`가 언마운트된 상태에서도 트레이 북마크 요청을 카운트로 보존
  - 녹음 화면이 다시 마운트되면 pending 북마크를 한 번에 저장
- ✅ **피드백 정리**
  - pending 북마크 여러 개는 개별 SnackBar 대신 한 번의 안내로 표시
  - 녹음 시작 기준 경과 시간으로 북마크 저장
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공

### 2026-05-01 (트레이 녹음 중 상태 표시 보강)

- ✅ **트레이 자체 녹음 타이머 추가**
  - `MenuBarService`에 `_recordingTicker` 추가
  - 녹음 상태로 전환되면 1초마다 트레이 메뉴와 tooltip을 갱신
  - 녹음 화면이 언마운트되어도 `녹음 중 · 00:00` 시간이 계속 증가하도록 보강
- ✅ **아이콘/메뉴 상태 확인**
  - 녹음 시작 시 `mic_recording.png` + 비-template 아이콘 사용
  - 녹음 종료 시 `mic_idle.png` + template 아이콘으로 복귀
  - 녹음 중 메뉴는 `북마크 추가`, `녹음 정지`, `앱 창 열기`, `종료` 중심으로 유지
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공

### 2026-05-01 (트레이 녹음 시작/정지 경로 보강)

- ✅ **트레이 시작/정지 신호 경로 확인**
  - `MenuBarService`의 start/stop 메뉴 액션이 Riverpod signal로 전달되는 흐름 점검
  - start: `onStartRecord` → `isRecordingActiveProvider=true` → `RecordingView` → `_startRecording()`
  - stop: `onStopRecord` → `trayStopRecordingSignalProvider` → `_stopRecording()`
- ✅ **화면 전환 중 정지 누락 방지**
  - `pendingTrayStopProvider` 추가
  - 녹음 중 사용자가 다른 회의 상세 화면을 보고 있어 `RecordingView`가 언마운트된 상태에서도 트레이 정지가 녹음 화면으로 복귀 후 처리되도록 보강
  - 전역 단축키 `Cmd+Shift+R` 정지 경로도 같은 pending stop 흐름 사용
- ✅ **중복 pending 신호 정리**
  - `RecordingView`가 이미 마운트된 상태에서 start/stop signal을 직접 처리하면 pending flag를 즉시 해제
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공

### 2026-05-01 (빈 녹음 감지 강화)

- ✅ **녹음 중 낮은 입력 안내**
  - `recording_view.dart`
  - 20초 이상 녹음 중이고, 최근 18초 동안 유의미한 마이크 입력이 없으면 노란 안내 배너 표시
  - 마이크 데이터 자체가 없을 때와 음량이 너무 낮을 때를 구분해 안내
  - 사용자가 닫을 수 있고, 다시 음성이 감지되면 다음 경고가 가능하도록 상태 초기화
- ✅ **녹음 종료 직후 빈 세션 경고**
  - 5초 미만 녹음, 마이크 데이터 없음, 12초 이상 녹음했지만 전사 세그먼트 없음, 낮은 음량+20자 미만 전사 케이스 감지
  - 녹음 종료 직후 “그냥 유지 / 삭제” 선택 다이얼로그 표시
  - 삭제는 사용자가 명시적으로 선택한 경우에만 실행하며, 오디오/회의/전사/요약 레코드를 함께 정리
- ✅ **요약 전 빈 세션 확인과 통합**
  - 기존 요약 직전 sparse 체크가 새 공용 녹음 시간 계산을 사용하도록 정리
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공

### 2026-05-01 (모델 다운로드 오류 안내 개선)

- ✅ **다운로드 실패 원인 분류**
  - `ModelDownloadErrorCode`에 serverUnavailable, diskSpace, permission, fileSystem, invalidUrl 추가
  - 401/403 인증, 404 URL 변경, 429 제한, 5xx 서버 장애, 네트워크/SSL, 디스크 부족, 파일 권한 오류별 문구 분리
- ✅ **디스크 공간 사전 검사 강화**
  - `AppConstants.expectedModelBytes()` 추가
  - 첫 설정 화면과 설정 화면의 모델 다운로드 모두 예상 모델 크기를 전달
  - 모델 크기 + 200MB 여유 공간이 부족하면 다운로드 시작 전에 안내
- ✅ **다운로드 무결성/정리 보강**
  - content-length가 있는 경우 받은 크기가 부족하면 “중간에 끊김” 오류로 처리
  - 기존 파일 덮어쓰기 전 삭제 처리
  - 실패/취소 시 `.tmp` 임시 파일 정리 유지
- ✅ **사용자 안내 개선**
  - 인증 실패 시 토큰 입력란을 열고 오류 카드에도 메시지를 유지
  - 재시도 가능한 실패는 카드의 재시도 버튼으로 바로 다시 시도 가능
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공

### 2026-05-01 (안정성 개선 — 요약 중지/종료 보강)

- ✅ **LLM 워커 안전 취소 신호 추가**
  - `LlmService.requestCancelActiveGeneration()` 추가
  - LLM 생성 워커 isolate에 control port를 전달해 토큰 경계에서 취소 가능하게 개선
  - 워커 루프가 주기적으로 event loop에 양보해 취소 메시지를 실제로 처리하도록 보강
- ✅ **요약 중지 버튼 반응성 개선**
  - 녹음 직후 요약 화면과 회의 상세 재요약 화면의 중지 버튼이 LLM 워커에 직접 취소 신호를 보냄
  - 취소 후 부분 생성 결과가 정상 요약처럼 저장되지 않도록 `SummaryCancelledException` 처리 보강
- ✅ **앱 종료 안정성 보강**
  - graceful shutdown에서 LLM unload 전에 진행 중 생성 작업에 취소 신호를 먼저 보냄
  - 기존처럼 native decode와 llama/Metal free가 겹치지 않도록 worker 종료를 기다린 뒤 unload
- ✅ **검증**
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공

### 2026-05-01 (App Store 설명/키워드/심사 메모 작성)

- ✅ **App Store 메타데이터 초안 추가**
  - `APP_STORE_METADATA_KO.md`
  - 앱 이름, 부제, 홍보 문구, 키워드, 설명, What's New, App Review Notes 정리
  - Apple 제한 기준에 맞춰 부제 19자, 홍보 문구 66자, 키워드 94바이트, 설명 582자로 작성
- ✅ **심사 메모 보강**
  - `APP_STORE_SUBMISSION_NOTES.md`
  - 로그인 불필요, 첫 실행 저장 폴더 선택, 모델 다운로드, 녹음 후 수동 요약 테스트 흐름 추가
- ✅ **제출 전 체크리스트 추가**
  - Bundle ID 변경, Privacy/Support URL, Apple Distribution Archive, 모델 다운로드 심사 환경 확인 항목 정리

### 2026-05-01 (개인정보 처리방침 작성)

- ✅ **개인정보 처리방침 초안 추가**
  - `PRIVACY_POLICY.md`
  - 로컬 처리, 외부 서버 미전송, 모델 다운로드 네트워크 사용, 사용자 직접 공유, 로그/삭제 정책 명시
- ✅ **App Store Privacy 답변 초안 추가**
  - `APP_STORE_PRIVACY_ANSWERS.md`
  - App Store Connect 입력 순서 기준으로 `Data Not Collected`, Tracking 없음, 데이터 타입 미선택 정리
  - User Content/Diagnostics/모델 다운로드/Hugging Face 토큰을 왜 label에 포함하지 않는지 설명
- ✅ **App Review Notes 초안 추가**
  - `APP_STORE_SUBMISSION_NOTES.md`
  - 심사 메모와 개인정보 처리방침 URL placeholder 정리
- ✅ **컴플라이언스 문서 연결**
  - `APP_STORE_COMPLIANCE.md`에 privacy 문서 위치와 핵심 포지션 추가

### 2026-05-01 (Xcode Archive + Apple Distribution 검증 준비)

- ✅ **Archive 검증 스크립트 추가**
  - `scripts/archive_app_store.sh`
  - `APPLE_TEAM_ID`, `APP_STORE_BUNDLE_ID`를 받아 Xcode archive 생성
  - Apple Distribution/3rd Party Mac Developer Application 인증서 존재 여부 사전 검사
  - archive 산출물의 Bundle ID, `LSMinimumSystemVersion`, sandbox, `get-task-allow`, Calendar/AppleEvent entitlement 검사
  - `codesign --verify --strict --deep` 실행
- ✅ **Release 코드서명 설정 보강**
  - Runner Release 설정에 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`
  - Runner Release 설정에 `ENABLE_HARDENED_RUNTIME = YES`
- ⚠️ **로컬 상태**
  - 현재 머신에는 유효한 코드서명 identity가 없음 (`security find-identity -v -p codesigning` → `0 valid identities found`)
  - 실제 Archive 완료는 Xcode 계정/Apple Distribution 인증서/App Store Connect Bundle ID 준비 후 가능

### 2026-05-01 (macOS 최소 버전 정책 정리)

- ✅ **libonnxruntime deployment target 경고 정리**
  - `sherpa_onnx_macos 1.12.40`에 포함된 `libonnxruntime.1.24.4.dylib`가 `minos 15.5`로 빌드되어 있음 확인
  - App Store 릴리스 최소 macOS 버전을 15.5로 명시
  - `macos/Podfile`: `platform :osx, '15.5'`
  - `macos/Runner.xcodeproj`: `MACOSX_DEPLOYMENT_TARGET = 15.5`
  - Pod post_install에서 모든 Pod target deployment target을 15.5로 정렬
  - `scripts/build_app_store.sh`가 최소 macOS 버전과 산출물 `LSMinimumSystemVersion`까지 검사
- ✅ **AppIcon asset catalog 경고 정리**
  - `AppIcon.appiconset` 내부의 미배정 백업 이미지를 `macos/Runner/AppIconBackup/`로 이동
  - Xcode asset catalog의 "unassigned child" 경고 제거

### 2026-04-30 (App Store 빌드 모드 정리)

- ✅ **앱스토어 안전 모드 도입**
  - `AppBuildConfig`: 기본값을 `APP_STORE_COMPLIANCE_MODE=true`로 설정
  - 내부 테스트 전용 플래그: `ALLOW_RESTRICTED_MODELS`, `ENABLE_CALENDAR_INTEGRATION`
- ✅ **EXAONE 제거/숨김**
  - 앱스토어 모드에서 EXAONE 다운로드 카드, 요약 모델 선택, 설치 모델 카운트 제외
  - 기존 저장값 `selectedLlmModel=exaone35_7b`는 안전한 기본 모델로 fallback
- ✅ **샌드박스/권한 정리**
  - `Release.entitlements`: App Sandbox `true`
  - `get-task-allow=false` 원본 entitlement 명시
  - Calendar entitlement와 AppleEvent temporary exception 제거
  - microphone, network client, user-selected read/write, app-scope bookmark entitlement만 유지
  - `Info.plist`: Calendar/AppleEvent usage string 제거
- ✅ **라이선스 고지**
  - 설정에 `라이선스와 개인정보` 섹션 추가
  - 사용 모델 및 라이선스 요약 다이얼로그 추가
  - `APP_STORE_COMPLIANCE.md`와 `scripts/build_app_store.sh` 추가
  - 주의: 로컬 `flutter build macos --release`는 개발 서명으로 `get-task-allow=true`가 주입될 수 있음. 최종 업로드는 Xcode Archive + Apple Distribution 서명에서 strict 검사 필요

### 2026-04-30 (요약 중 네이티브 종료 안정화)

- ✅ **LLM/Metal SIGABRT race condition 완화**
  - 확인 로그: `/Users/channy/Library/Logs/DiagnosticReports/LocalMinutes-2026-04-30-162946.ips`
  - 원인: `DartWorker`가 `llama_decode`/`ggml_metal_get_tensor_async` 실행 중인데 메인 스레드가 `llama_free`/`ggml_backend_metal_free`를 호출해 abort
  - `OnDeviceModelManager`: LLM 생성 카운터 추가, `unloadLlm()`이 진행 중 decode 종료까지 대기
  - `LlmService`: 같은 llama context를 동시에 쓰지 않도록 동시 생성 요청을 즉시 차단
  - `LlmService`: 스트림 취소 시 worker isolate를 즉시 kill하지 않고 자연 종료를 기다린 뒤 free
  - `ChunkedSummarizer`: 요약 중지 요청 시 토큰을 버리며 스트림을 끝까지 drain 후 `SummaryCancelledException` 처리
  - 트레이드오프: 요약 중지는 즉시 네이티브 연산을 끊지 않고 현재 생성 루프가 끝난 뒤 반영된다. 안정성을 우선한 임시 해법이며, 진짜 즉시 중지는 llama 래퍼에 native cancel flag가 필요

### 2026-04-28 (v2.0 DMG 배포 + 안정화)

- ✅ **버전 2.0.0 표기 + DMG 빌드** (`pubspec.yaml`, `scripts/build_dmg.sh`)
  - `pubspec.yaml: version: 2.0.0+1`
  - `scripts/build_dmg.sh: VERSION="2.0"`
  - 출력: `dist/적자생존_v2.0.dmg` (46MB)
- ✅ **녹음 크래시 복구 시스템**
  - `lib/core/services/recovery_service.dart` 신규
    - `findRecoverable()`: status가 done/error 아니고 transcript 또는 audio가 실재하는 회의만 복구 후보
    - 빈 깡통 회의는 자동 정리 + debugPrint
    - `markAsRecovered()`: status=done, endedAt 추정 채움
    - `discardMeeting()`: 회의 + 전사 + 오디오 파일 일괄 삭제
  - `recording_view.dart`
    - `_recoveryMeetingId` + `_checkpointTimer` (30초 주기)
    - `_saveRecoveryCheckpoint()`: 시작 즉시 Meeting(status=recording) 저장 + segments 일괄 교체
    - `_persistMeetingAndTranscripts()`: 기존 Meeting을 update (새로 만들지 않음)
  - `home_screen.dart`: 시작 시 검사 → 비차단 노란 배너 (모달 다이얼로그 사고 방지)
  - 배너 "복구하기" 버튼 → 즉시 일괄 복구 + 녹색 SnackBar (모달 사용 안 함)
- ✅ **macOS 종료 시 ggml/Metal abort 방지** (`lib/main.dart`)
  - `AppLifecycleListener`로 `onExitRequested` + `onDetach` 훅 등록
  - graceful shutdown: 녹음 정지 → LLM unload → STT unload
  - Metal 백엔드 destructor 시점에 `ggml_metal_device`가 살아있지 않게 보장

### 2026-04-28 (어젠다 + 북마크 + Cmd+B 단축키)

- ✅ **회의 어젠다 기능**
  - `Meeting.agenda: String` 필드 추가 (Isar 재생성)
  - 녹음 준비 다이얼로그에 4줄 멀티라인 입력
  - `_RecordingPrepResult.agenda` 전파 → 모든 저장 경로(checkpoint + 정상)
  - `SummaryParser.buildPrompt(... String agenda)` + `ChunkedSummarizer.summarize(... String agenda)`
  - 프롬프트에 `[회의 어젠다 — 사용자가 회의 시작 전 미리 정한 항목]` 섹션
    - 어젠다 순서 유지, "어젠다명 — 핵심 논점" 형태, 미진행 항목은 openQuestions에 (확인 필요)
  - 회의 상세에 `_AgendaCard` (참석자 카드 다음) — 편집 다이얼로그 + 항목 점 리스트
- ✅ **핵심 순간 북마크 (Cmd+B)**
  - `Meeting.bookmarksJson` + `Bookmark` 헬퍼 클래스 (sec, label, timeStr)
  - 녹음 화면 노란 "북마크 N" 버튼 (`_addBookmark()`)
  - **Cmd+B 단축키** (`CallbackShortcuts` + `Focus(autofocus: true)` 래퍼)
  - 인디고 SnackBar 즉시 피드백 ("북마크 저장됨 — MM:SS")
  - 모든 저장 경로에 `_bookmarksToJson()` 반영
  - 프롬프트에 `[사용자 핵심 마킹 — 우선 분석 필수]` 섹션 + 시점 앞뒤 30초 우선 반영 지시
  - 회의 상세 `_BookmarksCard` — 노란 알약 칩 + 클릭 점프 (시간 + 라벨)
  - 녹취록 세그먼트 옆 🔖 아이콘 (북마크 시점 포함된 세그먼트)

### 2026-04-28 (마이크 인디케이터 + 화자 라벨 편집 + 검색 점프)

- ✅ **음성 펄스 카드 (`_VoicePulseCard`)** — 개발자 스타일 → 일반 사용자 디자인
  - 마이크 아이콘 칩 + RMS 비례 후광(halo) — `AnimationController` ripple 2개
  - 5단계 상태 라벨 (잘 들리고 있어요 / 작아요 / 너무 큼 / 신호 없음 등)
  - 8초 미니 파형 (32 막대, 240ms 샘플링, 자동 정규화)
  - 기존 `_InputLevelMeter` (20 세그먼트 VU) 제거
- ✅ **발화자 라벨 편집 (이름/통합)**
  - `Meeting.speakerNamesJson` 필드 (Isar 재생성)
  - 화자 배지 클릭 → 편집 다이얼로그 (이름 입력 + 다른 화자로 통합)
  - 통합 시 모든 세그먼트 `speakerLabel` 일괄 업데이트
- ✅ **회의 검색 결과 → 전사 점프**
  - `transcriptJumpRequestProvider` 신규
  - 사이드바 검색의 전사 스니펫 → 우측 화살표 + 클릭 가능
  - `MeetingDetailView.ref.listen` → `_jumpToSnippet()` (토큰 매칭 + 자동 스크롤 + 황색 글로우)

### 2026-04-27 (요약 신뢰도 v2 + 점프 UX)

- ✅ **요약 신뢰도 표시 v2** — LLM이 명시한 시점으로 즉시 점프
  - `Summary.evidenceJson` 필드 (Isar 재생성) + `SummaryEvidence.parseStartSec()`
  - 프롬프트에 `[근거 타임스탬프 — 신뢰도 표시 v2]` 섹션 + 4개 evidence 배열 출력 지시
  - `SummaryParser.parse()`에 `evList()` 헬퍼 (길이 정렬, nested actionItem.evidence 병합)
  - UI: LLM 명시 시점 → 인디고 알약 `[02:55]` / 명시 없음 → 주황 "확인" 배지
  - `_handleEvidenceTap()`: 시점 있으면 즉시 점프, 없으면 v1 후보 다이얼로그 폴백
- ✅ **근거 다이얼로그 → 전사 점프 + 오디오 재생**
  - 후보 클릭 → `_TranscriptWithAudioState.jumpToSegmentDetailed()` (스크롤 700ms + 황색 글로우 2.5s + 오디오)
  - 상단 인디고 "⬇ 01:32 시점으로 이동" 배너 1.4초
  - lazy player init + 상세 실패 사유 (`_playerInitError`)

### 2026-04-27 (요약 재생성 옵션 + 전사 보정 도구)

- ✅ **요약 재생성 5가지 스타일**
  - `SummaryStyleMode` enum: standard / detailed / concise / actionFocused / executive
  - `SummaryStyleModeX` extension (id, displayName, description, modifier)
  - `resolveInstruction(... styleMode)` — 회의 유형 instruction 끝에 modifier 누적
  - `_pickTemplateDialog`에 ChoiceChip 5개 + 설명 박스
- ✅ **전사본 품질 보정 도구**
  - 녹취록 헤더에 ✏️ PopupMenuButton (`_TranscriptWithAudio`)
  - 단어집에 추가 / 전사본 단어 치환 (옵션: 단어집 자동 등록) / 단어집 별칭 재교정
  - `_addToGlossary()` / `_replaceAcrossTranscript()` / `_applyGlossaryAliases()`
  - 변경 후 `onTranscriptChanged` 콜백 → 부모가 transcript provider invalidate
- ✅ **요약 템플릿 UI 단순화**
  - 설정 화면: "회의 유형" 섹션 (한 줄 설명 + ▸ "고급 설정 — 분석 지침 미리보기" ExpansionTile)
  - 커스텀 모드: 🔧 "전문가용" 안내 + 에디터 기본 노출
  - 녹음 준비/재요약 다이얼로그: "회의 유형" 라벨, "커스텀 (전문가용)" 표기 통일

### 2026-04-27 (처리 리포트 일반 사용자화)

- ✅ **회의 상세 처리 리포트 카드 정리** (`meeting_detail_view.dart`)
  - 기본 카드 metric subLabel(모델 브랜드명) 제거 → `음성 인식 / 발화자 라벨 / 요약 생성` 단계 + 소요 시간만 표시
  - `_AdvancedReportInfo` ExpansionTile 추가 — `고급 정보` 클릭 시 펼쳐짐
    - 음성 인식 모드 (빠른 모드 / 정확 모드)
    - 음성 인식 모델 파일 (raw 파일명, SelectableText)
    - 오디오 길이
    - 처리 속도(RTF) — 0.35x 형식
    - 발화자 라벨 상태 (성공/실패/건너뜀/비활성)
    - 요약 모델 (Gemma 4 E2B / Qwen 2.5 7B / EXAONE 3.5 7.8B)
    - 요약 모델 ID (raw id, SelectableText)
  - State 클래스의 미사용 `_sttModelLabel`, `_llmModelLabel` 헬퍼 제거 (`_AdvancedReportInfo` 내부로 이전)
  - `flutter analyze`: No issues found
  - `flutter build macos --debug`: 성공

### 2026-04-27 (사이드바 접기 + 상세 화면 폭 조절)

- ✅ **왼쪽 사이드바 접기/펼치기**
  - 홈 화면 좌측 사이드바를 접을 수 있는 버튼 추가
  - 접힌 상태에서는 좁은 레일에 `사이드바 펼치기`, `새 녹음 시작` 버튼 표시
  - 기존 사이드바 폭 드래그 조절은 펼친 상태에서 유지
- ✅ **회의 상세 요약/전사 영역 폭 조절**
  - 회의 상세 화면의 요약 영역과 전사본 영역 사이에 가로 드래그 핸들 추가
  - 사용자가 가운데/오른쪽 패널 비율을 직접 조절 가능
  - 너무 좁아지지 않도록 최소 폭 제한 적용

### 2026-04-27 (설정 화면 기술 용어 줄이기)

- ✅ **설정 화면 일반 사용자화**
  - 설정 기본 화면의 `STT`, `Whisper`, `LLM`, 모델 파일명 노출을 제거
  - `음성 인식 언어`, `음성 인식 방식`, `빠른 음성 인식 모델`, `정확도 높은 음성 인식 모델`, `기본/고품질/한국어 특화 요약 모델`처럼 일반 사용자용 표현으로 변경
  - 요약 모델 선택 칩도 모델명 대신 `기본`, `고품질`, `한국어 특화`로 표시
  - 모델 파일명은 `고급 정보` 접기 안에서만 확인할 수 있게 이동
  - 발화자 라벨 보조 모델도 `발화 구간 찾기 모델`, `목소리 구분 모델`로 변경

### 2026-04-26 (요약 근거 보기 v1)

- ✅ **요약 항목별 근거 후보 표시**
  - 주요 논의, 결정 사항, 미해결 이슈 항목 오른쪽에 `근거` 버튼 추가
  - 액션 아이템 행에도 `근거` 버튼 추가
  - 클릭 시 관련 전사 구간 후보를 팝업으로 표시
- ✅ **키워드/문장 유사도 기반 v1 매칭**
  - LLM 근거 추출 없이 전사본의 키워드 교집합과 문자 유사도로 후보 구간 탐색
  - 상위 5개 후보와 타임스탬프, 발화자 라벨, 유사도 표시
  - 매칭 신뢰도가 낮거나 후보가 없으면 `확인 필요` 배지 표시

### 2026-04-26 (전사/요약 품질 후처리 개선)

- ✅ **청크 오버랩 중복 제거 강화**
  - 긴 WAV 전사에서 최근 8개 세그먼트까지 비교해 겹친 구간 중복을 더 잘 제거
  - 숫자가 다른 문장(`10월` vs `1월`)은 중복으로 보지 않는 안전장치 추가
- ✅ **기본 도메인 용어 보정 추가**
  - 단어집 기반 교정기에 `GQ팀→지표팀`, `로고 설계→로그 설계`, `Q&A 1차→QA 1차` 등 보수적 기본 치환 추가
  - 기존 사용자 단어집 alias 교정과 함께 동작
- ✅ **요약용 클린 전사본 적용**
  - 저장 전사본은 보존하고, LLM 요약 입력에만 중복 제거된 전사 텍스트 사용
  - 녹음 직후 요약, 회의 상세 다시 요약, 파이프라인 요약 경로에 동일 적용

### 2026-04-26 (음성 인식 재실행 예상 시간 안내)

- ✅ **STT 다시 돌리기 전 예상 시간 표시**
  - 회의 상세의 `STT 다시 돌리기`를 `음성 인식 다시` 흐름으로 일반 사용자화
  - 실행 전 오디오 길이, 빠른/정확 음성 인식 예상 시간, 발화자 라벨 추가 예상 시간, 총 예상 시간 표시
  - 발화자 라벨을 끄고 더 빠르게 진행하는 선택지를 제공
  - 선택한 발화자 라벨 사용 여부를 실제 재전사 실행 조건과 처리 리포트에 반영

### 2026-04-26 (앱스토어 일반 유저 UX P0 적용)

- ✅ **첫 실행 온보딩 3단계화**
  - 저장 폴더 선택 단일 화면을 로컬 처리 안내 → 모델 준비 안내 → 저장 폴더 선택 흐름으로 개편
  - "회의 내용은 내 Mac 밖으로 나가지 않습니다" 메시지와 외부 서버 미전송을 첫 단계에서 강조
  - 발화자 라벨은 사람 이름 자동 식별이 아니라 A/B/C 흐름 보조라는 기대치 안내 추가
- ✅ **녹음 시작 전 준비 패널 통합**
  - 녹음 시작 시 회의 제목, 말할 사람 수, 마이크, 요약 템플릿, 발화자 라벨 사용 여부를 한 화면에서 설정
  - 기존 1회성 마이크 품질 가이드를 준비 패널의 체크리스트로 흡수
  - 말할 사람 수 선택값을 회의별 힌트와 전역 설정에 반영
- ✅ **요약 전 예상 처리 시간 안내**
  - 요약 실행 전 회의 길이를 기준으로 정확 음성 인식, 발화자 라벨, 요약 생성 예상 시간을 표시
  - 발화자 라벨을 끄면 더 빠르게 진행된다는 선택지를 제공
- ✅ **일반 유저용 용어 정리 1차**
  - 주요 UI의 `화자 분리` 표현을 `발화자 라벨`로 변경
  - 처리 리포트 카드를 `작업 시간`으로 변경하고 `STT`는 `음성 인식`, `요약`은 `요약 생성`으로 표시

### 2026-04-26 (요약 프리셋 품질 강화)

- ✅ **프리셋 템플릿 재설계**
  - 일반 회의: 실무 공유용 회의록 기준으로 논의·결정·액션·미해결 이슈 우선순위 강화
  - 회고: Keep / Problem / Try 구조를 실행 가능한 개선 조치 중심으로 상세화
  - 인터뷰/1:1: Q/A, 인사이트, 후속 확인 중심으로 상세화
  - 각 프리셋에 좋은 출력 예시를 포함해 로컬 LLM의 결과 안정성 개선
- ✅ **긴 회의 구간 요약에도 프리셋 지침 반영**
  - `ChunkedSummarizer`의 map 단계에도 프리셋 instruction 전달
  - 구간 요약에서 [결정]/[액션]/[질문] 태그를 유지해 최종 통합 시 정보 손실 완화
  - 담당자/기한이 없어도 후속 조치면 액션으로 남기고 "(미언급)" 처리
- ✅ **일반 사용자용 UI 문구 정리**
  - 설정 화면의 "출력 JSON 스키마" 표현 제거
  - "회의 성격에 맞춰 중요한 내용의 우선순위를 바꿉니다"로 설명 단순화

### 2026-04-26 (첫 실행 저장 폴더 필수화 + 자동 요약 제거)

- ✅ **첫 실행 저장 폴더 선택 필수화**
  - `recordingsSavePath`가 비어 있으면 홈/모델 설정 진입 전 저장 폴더 선택 화면 표시
  - 녹음 시작 시 기본 Application Support 폴더 fallback 제거
  - 설정 화면에서는 저장 폴더 변경만 제공하고 초기화 버튼 제거
- ✅ **녹음 종료 후 자동 요약 제거**
  - 설정 화면의 `녹음 중지 후 자동 요약` 스위치 삭제
  - 녹음 중지 후 항상 `녹음 완료. 요약을 실행하세요.` 상태로 멈춤
  - 유저가 직접 요약 버튼을 눌러야 LLM 요약 시작

### 2026-04-26 (화자 수 필수 입력 + 참석자 이름 추측 방지)

- ✅ **녹음 시작 전 화자 인원수 필수 입력**
  - `녹음 시작` 시 2~6명 중 화자 수를 반드시 선택하는 다이얼로그 추가
  - 선택값을 해당 녹음의 화자 분리 힌트로 사용
  - 전역 `numSpeakersHint`에도 반영해 화자 과분리(A~Q 등) 가능성 완화
- ✅ **요약에서 사람 이름 자동 생성 방지**
  - LLM 프롬프트에 "사용자가 직접 입력한 참석자만 participants에 사용" 규칙 추가
  - 입력된 참석자가 없으면 participants는 빈 배열로 출력하도록 지시
  - actionItems owner는 직접 입력한 참석자명 또는 `화자 A` 같은 라벨만 허용
  - 파싱 단계에서도 LLM이 만든 participants를 버리고 직접 입력된 참석자만 저장

### 2026-04-25 (회의 품질 리포트 v1)

- ✅ **회의별 처리 리포트 저장**
  - Meeting에 `processingReportJson` 필드 추가
  - STT 모델, LLM 모델, STT 소요 시간, 오디오 길이, RTF, 요약 소요 시간 저장
  - 화자 분리 사용 여부, 성공/실패/스킵 상태, 소요 시간 저장
- ✅ **회의 상세 화면 리포트 표시**
  - 회의 요약 상단에 `처리 리포트` 카드 추가
  - STT/화자 분리/요약 병목을 한눈에 볼 수 있도록 모델명·소요 시간·RTF 표시
  - 기존 회의처럼 리포트 데이터가 없는 경우 카드를 표시하지 않음
- ✅ **녹음 직후 요약 / STT 다시 돌리기 / 다시 요약 경로 반영**
  - 새 녹음의 최종 정확 STT, 화자 분리, 요약 단계별 시간 기록
  - 회의 상세의 `STT 다시 돌리기`와 `다시 요약`에서도 최신 처리 리포트로 갱신
  - 긴 파일에서 “어느 단계가 느렸는지” 추적 가능

### 2026-04-25 (화자 분리 멈춤 방지)

- ✅ **Diarization을 UI isolate 밖으로 분리**
  - 기존: sherpa-onnx `process()`가 UI isolate에서 동기 실행되어 긴 WAV에서 앱이 멈춘 것처럼 보임
  - 변경: `DiarizationService.diarizeWav()`가 별도 isolate에서 WAV 로드 + sherpa 처리
  - 진행률 이벤트만 메인 isolate로 전달
- ✅ **화자 분리 실패/장기 실행 fallback**
  - 기본 8분 timeout 추가
  - 실패/timeout 시 화자 라벨 없이 STT 저장 또는 요약 계속 진행
  - STT 다시 돌리기 경로에서는 화자 분리 전 STT 모델을 먼저 unload해 메모리 압박 완화
  - 화자 분리 진행률을 STT 재실행/요약 UI에 표시

### 2026-04-25 (Action Items v2 — 전체 회의 할 일 보드)

- ✅ **전체 할 일 다이얼로그 추가**
  - 사이드바 상단에 `전체 할 일` 체크리스트 버튼 추가
  - 모든 회의 Summary의 `actionItemsJson`을 모아 미완료/전체/완료로 필터링
  - 담당자 필터, 텍스트 검색(할 일/회의 제목/마감) 지원
  - 미완료/완료 개수 요약 표시
- ✅ **할 일 상태 관리**
  - 전체 할 일 화면에서 체크박스로 완료 상태 토글
  - 기존 `Summary.actionItemsJson` 저장 구조와 호환
  - 원본 회의 상세의 요약 Provider도 함께 invalidate
- ✅ **원본 회의 이동**
  - 할 일 항목의 `회의 열기` 버튼으로 해당 회의 상세 화면 이동

### 2026-04-25 (STT/요약 중지 기능)

- ✅ **진행 중 작업 중지 버튼 추가**
  - 회의 상세 화면 `STT 다시 돌리기` 진행 인디케이터에 `중지` 버튼 추가
  - 회의 상세 화면 `다시 요약` 진행 인디케이터에 `중지` 버튼 추가
  - 녹음 직후 요약 카드에도 `중지` 버튼 추가
- ✅ **서비스 레벨 취소 처리**
  - 긴 WAV STT 청크 처리 경로에 cancel callback 추가
  - STT 중지 시 현재 30초 청크 완료 후 다음 청크/저장/화자분리 단계로 넘어가지 않음
  - 요약 중지 시 `ChunkedSummarizer`가 토큰 스트리밍 루프를 끊고 저장을 중단
  - `LlmService.generate()` 취소 시 워커 isolate를 즉시 kill하도록 보강

### 2026-04-25 (긴 WAV STT 재실행 병목 개선)

- ✅ **45분 이상 긴 파일 STT 재실행을 청크 기반으로 변경**
  - 기존: 전체 WAV를 `whisper_full()` 1회 호출로 처리해 긴 파일에서 100분 이상 블로킹 가능
  - 변경: 90초 초과 파일은 30초 청크 + 5초 오버랩으로 순차 전사
  - 각 청크 완료 시 진행률을 강제 갱신해 `오디오 분석 중...` 장기 정체를 방지
  - 오버랩 구간 중복 세그먼트 제거 로직 추가
  - STT 콜백 포인터를 예외 상황에서도 정리하도록 보강

### 2026-04-25 (작업 소요 시간 표시)

- ✅ **STT 다시 돌리기 / 요약 총 소요 시간 표기**
  - 회의 상세 화면 STT 재실행 완료·오류 SnackBar 문구를 `총 소요` 기준으로 통일
  - 회의 상세 화면 재요약 완료·오류 SnackBar에도 총 소요 시간 표시
  - 녹음 직후 요약 화면에 실시간 경과 시간 표시 (`% · 경과 m:ss`)
  - 녹음 직후 요약 완료·오류 상태/SnackBar에 총 소요 시간 표시

### 2026-04-25 (LLM 모델 변경 대응 품질 개선)

- ✅ **모델별 프롬프트 템플릿 적용**
  - `LlmService.buildPromptForModel()` 추가
  - Gemma 계열은 기존 `<start_of_turn>` 템플릿 유지
  - Qwen 2.5 / EXAONE 3.5 계열은 ChatML(`<|im_start|>system/user/assistant`) 형식으로 전환
  - 공통 system 지침 추가: 전사본에 없는 내용 생성 금지, 수치·고유명사 보존, 요청 형식만 출력
- ✅ **요약·검색·용어추출 sampling 보수화**
  - `LlmService.generate()`에 `temperature` / `topP` 인자 추가
  - 회의록 단일 요약: `temperature 0.25`
  - 긴 회의 map 요약: `temperature 0.30`, 최종 reduce: `temperature 0.20`
  - AI 검색 JSON / 용어 JSON 추출은 더 낮은 temperature로 호출해 형식 이탈과 환각 감소

### 2026-04-25 (STT 성능/품질 흐름 개선)

- ✅ **녹음 종료 tail 전사 누락 방지** (`microphone_service.dart`)
  - `stopRecording()` 시 진행 중인 Whisper 윈도우 완료를 기다린 뒤, 남은 마지막 버퍼를 종료 전용 flush로 한 번 더 전사
  - 순수 5초 오버랩만 남은 경우는 스킵해 불필요한 중복 전사를 방지
  - 회의 마지막 10~20초의 결정/액션이 30초 윈도우를 못 채워 누락되는 문제 완화
- ✅ **실시간 초안 + 최종 정확 전사 분리** (`recording_view.dart`, `main.dart`)
  - STT 모델 체크를 "Fast/Accurate 중 하나 이상"으로 수정해 SetupScreen 정책과 일치
  - 정확 모드에서 Fast 모델이 있으면 녹음 중에는 Fast로 실시간 초안 전사
  - 요약 실행 직전 Accurate 모델이 있으면 저장된 WAV 전체를 Accurate로 재전사한 뒤 그 결과로 DB 저장/요약
  - Accurate 재전사 실패 시 실시간 전사본으로 계속 진행하도록 fallback 처리
  - 사용자가 전사본을 직접 편집한 경우는 수동 수정 보호를 위해 Accurate 재전사를 건너뜀
- ✅ **STT 성능 로그 추가** (`stt_service.dart`)
  - 파일 전사와 윈도우 전사 모두 `[STT PERF] audio / elapsed / RTF` 로그 출력
  - 기기·모델별 real-time factor 측정 가능
- ✅ **녹음 플로우에도 화자 분리 적용** (`recording_view.dart`)
  - 요약 실행 직전 diarization을 돌려 STT 세그먼트에 화자 라벨(A/B/C…)을 붙여 요약 프롬프트에 반영
  - Transcript DB 저장에도 `speakerLabel`을 함께 저장 (회의 상세 전사에도 동일 라벨 표시)
  - diarization 실패/모델 미설치 시에는 라벨 없이 계속 진행 (품질 개선 옵션)
- ✅ **정적 분석 잡음 정리**
  - FFI typedef 이름을 공개 API에 맞게 정리해 `library_private_types_in_public_api` 제거
  - Isar 생성 파일을 analyzer 대상에서 제외
  - `record_linux` 패치 패키지와 `tool/vad_sanity.dart` import lint 정리
  - `flutter analyze`: No issues found
  - `flutter test`: 통과
  - `flutter build macos --debug`: 성공 (`libonnxruntime` macOS deployment target warning 1건은 외부 dylib 경고)

### 2026-04-25 (오후)

- ✅ **코드 품질 정리 — flutter analyze 117 → 23 (FFI/Isar 생성 코드 제외 0)**
  - `withOpacity(...)` 44건을 `withValues(alpha: ...)`로 스크립트 일괄 치환
  - `${identifier}` brace 중복, `+` 문자열 concat → 보간 변환 (stats/setup/glossary/recording/meeting_detail)
  - 단일 문 `for`/`while` 바디에 중괄호 추가 (stt_service, silence_gate, vad_filter, pipeline_service, meeting_detail)
  - `(_, __)` 매개변수 → `(_, _)` (recording/glossary/meeting_detail)
  - `BuildContext` async gap — `settings_screen._checkModels` 이후 `mounted` 재확인, `meeting_detail` 다이얼로그 직전 `mounted` 가드
  - `if (child != null) child!` → `?child` (null-aware element)
  - `RadioListTile` + `groupValue`/`onChanged` deprecation → `RadioGroup<T>` wrapping (meeting_detail 템플릿 picker)
- ✅ **자동 삭제 로직 검증 + 중복 제거**
  - 새 헬퍼 `AutoDeleteService.run(days)` (`lib/core/services/auto_delete_service.dart`)
    - `AutoDeleteResult { deleted, missing }` 반환
    - 파일 `exists()` 선검사로 불필요한 예외 비용 제거, 실패 시 DB는 그대로 두고 다음 실행에 재시도
    - debugPrint 로 실행 결과 로깅
  - `main.dart` 시작 시 자동 삭제, `settings_screen` "지금 삭제" 버튼 모두 동일 헬퍼 사용 → 중복 코드 삭제
  - settings 결과 메시지를 "삭제 N개 · DB 참조 정리 M개" 케이스별로 분기
- ✅ **요약 실패 복구 UX**
  - `_runSummary()`를 두 단계로 분리: 1) Meeting + Transcript 저장 (`_persistMeetingAndTranscripts`) → 2) LLM 요약
  - LLM 실패 시 이미 저장된 meetingId를 `_failedSummaryMeetingId`에 보관해 전사·녹음 소실 방지
  - 에러 phase UI에 **[요약 다시 시도]** + **[회의록 열기]** 복구 Row 추가
    - 재시도: 같은 meetingId로 다시 LLM 호출, 기존 Summary가 있으면 `deleteSummaryByMeetingId`로 정리 후 새로 저장
    - 회의록 열기: `selectedMeetingIdProvider`에 id 주입 → MeetingDetailView로 이동 (거기서 재요약/편집 가능)
  - 에러 메시지도 "전사는 이미 저장되었습니다. 재시도 또는 회의록 열기를 선택하세요."로 안내 강화

- ✅ **Tier 3 — 요약 템플릿 프리셋 단순화** (`summary_templates.dart`, `meeting.dart`)
  - 5개 → 3개 + custom: standup / planning 제거 (일반 + custom 으로 대체 가능)
  - 남은 프리셋: 일반 회의 · 회고 · 인터뷰/1:1
  - 저장된 standup/planning id는 `SummaryTemplates.byId` fallback으로 general에 자동 매핑 → 마이그레이션 불필요
- ✅ **Tier 3 — 마이크 위치/거리 가이드 (1회성)** (`recording_view.dart`, `settings_screen.dart`, `app_settings.dart`)
  - `AppSettings.micGuideShown` 플래그 추가 (기본 false)
  - 첫 녹음 시작 시 `_showMicGuideDialog()` 표시 — 마이크 거리(30~60cm), 소음, 발화 중첩, 입력 볼륨, 단어집 5개 팁 + `_GuideRow` 위젯
  - 사용자 확인 → 플래그 `true` 저장, 다음부터는 스킵
  - 설정 → "녹음 품질" 섹션에 "마이크 가이드 다시 보기 (리셋)" 버튼 + SnackBar 확인
- ⏸ **Tier 3 — 장시간 중간 진행 요약: 보류** (설계 제약 명시, TASKS.md 참고)
- ✅ **코드 정리** (`recording_view.dart`)
  - `_summaryPreview` 미사용 필드 + `onPreview` 콜백 제거 (이전 세션 UX 결정 반영 마무리)
  - 사용하지 않던 `llmLabel` 로컬 변수 제거

- ✅ **Tier 2 — 윈도우 경계 누적 세그먼트 클린업** (`microphone_service.dart`)
  - 30초 윈도우 + 5초 오버랩 구조에서 같은 문장이 두 윈도우에 걸쳐 중복 기록되는 문제 해결
  - `_normText` (공백/문장부호/따옴표 제거) + `_isDuplicateOfRecent` 추가
  - 오버랩(5s)+1s 여유 범위 내 이전 세그먼트와 정규화 텍스트가 일치하거나 한쪽이 다른 쪽을 포함(최소 6자)하면 신규 세그먼트 드롭
  - `_processWindow` 카운터에 중복 제거 집계(`dup`) 추가해 로깅
- ✅ **Tier 2 — VAD / 무음 게이트 강화**
  - `MicrophoneService._processWindow` VAD: threshold `0.0001 → 0.002` (≈-54 dBFS), speechRatio `0.01 → 0.03`
    → 완전 무음 외에 생활 소음·짧은 burst 노이즈도 whisper 호출 전 스킵
  - `SttService.transcribeFromSamples`의 `SilenceGate.apply(minSilenceSec: 1.2 → 1.0)`
    → 문장 사이 쉼에서 "네"/"음" 류 환각 더 적극 차단, 1초 미만 자연스러운 쉼은 유지

- ✅ **Tier 1 — STT 정확 모드 기본값 전환**
  - `AppSettings.sttAccurateMode` 기본값을 `false` → `true`로 변경
  - `settings_screen` 문구를 "정확 모드 (권장) — Whisper Large V3 Q5_0" / "빠른 모드 — 오인식 多"로 조정
- ✅ **Tier 1 — 요약 프롬프트 강화**
  - `SummaryTemplates.general` instruction을 한국어 업무 회의 구조(안건·결정·액션·미결)로 상세화
  - `SummaryParser.buildPrompt` 에 두 섹션 추가:
    - `[STT 노이즈 필터링]` — "네/어/음/감사합니다" 등 환각 패턴 제외 + "(미언급)" fallback
    - `[한국어 비즈니스 회의 포맷]` — keyDiscussions/decisions/actionItems/openQuestions 별 권장 서술 스타일
- ✅ **UTF-8 스트리밍 디코드 버그 수정** (`lib/data/datasources/llm_service.dart`)
  - 한글(3바이트 UTF-8)이 llama.cpp 토큰 경계에서 잘려 `FormatException: Unfinished UTF-8 octet sequence` 발생
  - `Uint8List` 버퍼에 누적 → `Utf8Decoder(allowMalformed: false)` 시도, 실패 시 다음 토큰까지 대기, 루프 종료 시 `allowMalformed: true`로 flush
- ✅ **요약 시 LLM 선택 다이얼로그** (`lib/presentation/widgets/recording_view.dart`)
  - `_pickLlmDialog()` 추가 (ChoiceChip + Tooltip). 요약 버튼 클릭 → 다이얼로그 → 선택된 LLM 로드/요약
  - 하드코딩된 "Gemma 4 요약" 레이블을 `_llmDisplayName(selectedLlmModel)` 기반 동적 텍스트로 교체
- ✅ **요약 진행 UI 단순화**
  - 요약 중 전사 미리보기(`_summaryPreview`) 블록 제거, 진행 단계만 노출
- ✅ **whisper_free race condition SIGABRT 수정** (`lib/data/datasources/microphone_service.dart`)
  - `stopRecording()`이 `_processWindow` Isolate 실행 중에 `unloadStt()`(→ `whisper_free`)를 호출하면서 wsw_transcribe와 충돌
  - `_processing` 플래그가 내려갈 때까지 최대 30초 대기 후 언로드. 30초 초과 시 경고 로그 후 강제 해제

### 2026-04-25

- ✅ **화자 분리 (Speaker Diarization) 구현**
  - `sherpa_onnx` 패키지 도입 (v1.12.40, macOS arm64 지원 검증 완료)
  - `AppConstants`: `diarSegModelFile` / `diarEmbModelFile` / 다운로드 URL 2종 추가 (HuggingFace + GitHub, 실제 검증)
  - `AppSettings`: `diarizationEnabled` (기본 false) / `numSpeakersHint` (기본 0=자동) 추가
  - `Transcript` 엔티티: `speakerLabel: String?` 필드 추가 + Isar build_runner 재생성
  - `DiarizationService` 신규 (`lib/data/datasources/diarization_service.dart`)
    - pyannote-segmentation-3.0 + 3d-speaker eres2net + FastClustering 파이프라인
    - `diarizeWav()` + `assignLabels()` (STT↔화자 시간 겹침 매칭 → 'A'/'B'/'C'...)
  - `pipeline_service`: `PipelineStage.diarizing` 추가, 녹음 완료 후 자동 diarization
  - `meeting_detail_view`: STT 다시 돌리기 경로에도 diarization 적용
  - 설정 화면: "화자 분리" 섹션 — 활성화 토글, 화자 수 힌트(자동/2~6명), 모델 다운로드 2종
  - SetupScreen: 화자 분리 모델 선택 다운로드 카드 2종 추가
  - 전사 뷰: `speakerLabel` 있으면 "화자 A:", "화자 B:" 배지 표시
  - 요약 프롬프트: 화자 접두사 해석 지침 주입 (SummaryTemplates + ChunkedSummarizer)

### 2026-04-24 (오후)

- ✅ **LLM 3종 선택 시스템 도입**
  - 모델: Gemma 4 E2B Q8_0 (~3GB, 기본) / Qwen 2.5 7B Instruct Q4_K_M (~4.7GB, 한국어·구조화) / EXAONE 3.5 7.8B Q4_K_M (~4.8GB, 한국어 특화)
  - `AppConstants`: 3개 파일명·URL 상수 추가 (HuggingFace bartowski 레포, URL 실제 검증 완료)
  - `AppSettings.selectedLlmModel` + `llmModelFileFor(id)`/`llmDownloadUrlFor(id)` 정적 헬퍼
  - `SetupScreen`: `_Target` enum 5종 확장, LLM 3카드 + info 툴팁 (마우스 hover)
  - `settings_screen`: 모델관리에 LLM 3 row + "요약 기본 LLM" FilterChip picker
  - `meeting_detail_view`: `_pickLlmDialog` (ChoiceChip + Tooltip) 추가 — 요약 시점에 모델 선택, 설치된 LLM이 1개면 skip
  - 모든 LLM 로드 경로(`recording_view`, `meeting_sidebar`, `pipeline_service`, `meeting_detail`)를 `AppSettings.currentLlmModelFile` 기반으로 통일
  - `main.dart` 및 `recording_view._checkModels`: LLM 3종 중 하나라도 있으면 OK

### 2026-04-24

- ✅ **환각 cascade 필터 개선** (`lib/data/datasources/stt_service.dart`)
  - `_collapseRepeatedShort`에 `longRunThreshold=8` 추가. 16자 이상 긴 문장도 8회 이상 반복시 드롭.
  - 원인: "예전에는 계속 비교를 했었죠" (16자)가 `maxCharLen=12` 초과해 필터 건너뜀.
- ✅ **STT 모델 Fast/Accurate 분리 UI** (3곳)
  - 설정 모델 관리: `_DlTarget { sttFast, sttAccurate, llm }` enum, 3개 독립 다운로드 row
  - SetupScreen 초기 설치: `_Target` enum, 2개 STT 카드 + LLM, 최소 1개 STT 필수
  - 회의록 STT 다시 돌리기: `SegmentedButton<bool>` + `Tooltip` (모델명/크기/속도/파일명)
- ✅ **녹음 품질 개선 세트**
  - `AppSettings`: `recordAutoGain`/`recordEchoCancel`/`recordNormalize` 3개 토글 추가
  - `MicrophoneService`: `RecordConfig`에 autoGain/echoCancel 전달, `onLevel` 콜백, `_computeLevel` (RMS→dB→0~1), `_peakNormalize` (-1dBFS 타겟)
  - `recording_view.dart`: `_InputLevelMeter` VU 미터 위젯 (20 세그먼트, 녹음 중에만 표시)
  - 설정 화면에 "녹음 품질" 섹션 추가
