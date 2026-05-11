# Next AI Tasks — 적자생존 앱 이어서 개발하기

이 문서는 다른 AI/개발자가 `/Users/channy/LocalMinutes`에서 바로 이어서 개발할 수 있도록 남은 작업, 우선순위, 관련 파일, 검증 방법을 정리한 문서입니다.

## 현재 상태 요약

- 앱: Flutter macOS 회의록 앱 `적자생존`
- 핵심 가치: 녹음, 음성 인식, 발화자 라벨, 요약을 로컬 Mac에서 처리하는 프라이버시 중심 앱
- 최근 완료:
  - 첫 실행 온보딩과 저장 폴더 필수 선택
  - 녹음 시작 전 회의 정보/말할 사람 수 입력
  - STT/요약 중지 버튼
  - 긴 WAV 30초 청크 STT
  - 발화자 라벨 isolate 처리와 timeout fallback
  - 요약 프리셋 품질 개선
  - 요약 근거 보기 v1
  - 설정 화면 개발자 용어 축소
  - 왼쪽 사이드바 접기/펼치기
  - 회의 상세 요약/전사 영역 폭 조절
  - 정기 회의 시리즈 자동 인식 1차
  - P1 일반 사용자 UX 보강: Notion용 요약/보고서/액션아이템 복사
  - DOCX 내보내기
  - 보고서 형식 PDF/DOCX 저장
  - P0 앱스토어 안전 모델 정리: EXAONE 저장값 정리/다운로드 방어/fallback 테스트
  - 버전 관리 정리: 앱 표시 버전 동기화, build number 자동 증가 DMG 스크립트
  - DMG 설치 앱 실행 실패 수정: 직접 배포용 entitlements/ad-hoc 재서명 적용
  - 긴 WAV 다시 전사 예상 시간 보정: 이전 실제 STT RTF 반영, 빠른 모델 fallback 추정치 현실화
  - STT/요약 속도 개선: STT `빠름/표준/정밀`, 요약 `빠른/균형/정밀` 모드 추가
  - 49분 파일 벤치 후 긴 파일 재전사 오버랩 `5초 → 2초` 축소
  - Core ML STT 가속 통합: 빠른 모델 49분 25초 WAV 기준 Metal-only `628.387초` → Core ML encoder `203.654초`
  - 긴 회의 전사 품질 QA: generic initial prompt 누출을 막기 위해 실제 용어/참석자 힌트가 있을 때만 prompt 주입
  - 녹취록 검색 한글 입력 수정: 검색창 포커스 중 `J/K/Space` 단축키 비활성화
  - 처리 시간 카드 일반 사용자화: 기본 카드는 단계+소요시간만, RTF/모델 파일명/모델 ID는 `_AdvancedReportInfo` 접기로 이동
  - 요약 템플릿 UI 단순화: 설정/녹음 준비/다시 요약 다이얼로그 모두 "회의 유형"으로 표기, 긴 instruction은 `고급 설정 — 세부 정리 방식` 접기로
  - 요약 재생성 옵션: `SummaryStyleMode` 5종(기본/더 자세히/더 간결하게/액션아이템 중심/임원 보고용) modifier가 회의 유형 위에 누적 적용. `_pickTemplateDialog`에 `재생성 스타일` ChoiceChip 노출, 기존 요약은 `SummaryVersion` 이력에 자동 저장
  - 사용자 노출 텍스트 정리: `LLM` → `요약 모델`, `STT` → `음성 인식`로 다이얼로그/상태/모델 다운로드 라벨/에러 메시지 정리
  - 전사본 품질 보정 도구: 전사 영역 헤더의 `Icons.spellcheck` PopupMenu에 `단어집에 추가`/`전사본 단어 치환`/`단어집 별칭 재교정` 3종 액션. `TranscriptCorrector` + `GlossaryRepositoryImpl` 활용, 변경 후 자동 invalidate
  - 요약 신뢰도 v2: LLM 출력 스키마에 `*Evidence` 4종 배열 추가, `Summary.evidenceJson` 저장, evidence 클릭 시 직접 점프(없으면 v1 키워드 fallback), `ActionItem.ownerConfirmed/deadlineConfirmed` 환각 방지 시그널, "확인 필요" 배지(fallback 다이얼로그 + 액션 amber 배너)
  - 옵션 C macos_ui 도입 (build13~22): macos_ui ^2.2.2 의존성 추가, MacosApp + MacosThemeData root, 각 화면 자체 MacosWindow 보유. 사이드바는 macos_ui Sidebar 의 vibrancy 가 traffic light 영역에 검은 색을 강제 표시해 직접 그리기로 전환 — `Row(우리 사이드바, separator, MacosScaffold(toolBar, ContentArea))`. NSWindow chrome 모던 패턴: titlebarAppearsTransparent + fullSizeContentView, isMovableByWindowBackground=false(더블클릭 zoom 보존), backgroundColor=NSColor.windowBackgroundColor. Flutter traffic light 36px GestureDetector + windowManager.maximize 토글로 zoom 직접 처리. ScaffoldMessenger root 추가. `lib/core/services/native_appearance.dart` + macos/Runner/MainFlutterWindow.swift platform channel `app/appearance` setMode → NSApp.appearance light/dark/system 토글. main.dart builder brightness 를 themeMode + platformBrightness 직접 계산. ToolBar(사이드바 토글/새 녹음/설정 액션, 라벨 숨김 macOS 표준). 사이드바 검색을 SidebarSearchTop 로 분리, 회의 유형 정리(주제별 요약/강의 세미나/커스텀1·2/회고·인터뷰 삭제). _WelcomeView/SeriesDashboardView 는 MacosTheme.primaryColor + typography(title1/title2) + PushButton + MacosIconButton + ProgressCircle 로 다듬음
  - 옵션 C macos_ui Phase 3 완료 (2026-05-09): RecordingView/MeetingDetailView 메인 뷰 Material 위젯 23개를 macos_ui로 전환. `FilledButton.icon` → `PushButton(color)`, `OutlinedButton.icon` → `PushButton(secondary: true)`, `IconButton` → `MacosIconButton(backgroundColor: transparent)`, `Tooltip` → `MacosTooltip`. 빨강/녹색 강조는 `MacosColors.systemRedColor/systemGreenColor` 다이나믹 컬러 사용, 브랜드 색(deepPurple/indigo/teal)은 그대로 유지. `PopupMenuButton`·`Slider`는 변환 제외(macos_ui 대응 없음). `flutter analyze` 0 issues, `flutter test` 40/40 통과
  - 옵션 C macos_ui Phase 4 완료 (2026-05-09): 다이얼로그 23개를 9개 Step에 걸쳐 `MacosAlertDialog` / `MacosSheet`로 전환. `showDialog` → `showMacosAlertDialog` / `showMacosSheet`, `AlertDialog(title, content, actions)` → `MacosAlertDialog(appIcon, title, message, primaryButton, secondaryButton)`, `Dialog(shape:)` → `MacosSheet(child:)`, action 버튼은 `PushButton(secondary: true / color:)`. 2 buttons + 단순 콘텐츠는 `MacosAlertDialog`, 3+ buttons 또는 큰 layout(IconButton 닫기 등)은 `MacosSheet`. 파괴적 액션은 `MacosColors.systemRedColor`. 클래스 기반 다이얼로그(`_SummaryHistoryDialog`, `_TermExtractDialog`, `_SummaryEditDialog`)는 build의 `Dialog` → `MacosSheet`. 가장 큰 폼인 `_RecordingPrepDialog`(520×540)도 `MacosAlertDialog`로 변환. 내부 폼 위젯(`TextField`/`DropdownButtonFormField`/`SegmentedButton`/`SwitchListTile`/`RadioListTile`/`ChoiceChip`/`FilterChip`/`CheckboxListTile`)은 회귀 위험 최소화 차원에서 Material 그대로 유지. DMG 마커 `dist/적자생존_v2.1.1_build24.dmg`

## 먼저 읽을 파일

- `TASKS.md`: 전체 작업 로그와 백로그
- `AI_HANDOFF.md`: 앱 구조, 구현 상태, 최근 의사결정
- `lib/presentation/screens/home_screen.dart`: 홈 레이아웃, 사이드바 접기/폭 조절
- `lib/presentation/widgets/meeting_detail_view.dart`: 회의 상세, 다시 전사, 다시 요약, 처리 시간, 근거 버튼, 요약/전사 분할
- `lib/presentation/widgets/recording_view.dart`: 녹음 시작/종료, 요약 실행, 모델 선택
- `lib/presentation/screens/settings_screen.dart`: 설정 화면, 모델 관리, 요약 템플릿
- `lib/presentation/screens/setup_screen.dart`: 첫 실행/모델 준비 화면
- `lib/core/constants/app_constants.dart`: 모델 파일명과 다운로드 URL
- `lib/core/services/app_settings.dart`: 설정값, 모델 선택값
- `lib/core/services/export_service.dart`: 내보내기
- `lib/core/services/summary_templates.dart`: 요약 프리셋

## 개발 규칙

- 사용자가 만든 변경을 되돌리지 말 것.
- 수동 수정은 `apply_patch`를 사용할 것.
- 검색은 `rg` 우선.
- 큰 변경 후 검증:
  - `dart format <수정 파일>`
  - `flutter analyze`
  - `flutter build macos --debug`
- 릴리즈/DMG가 필요하면:
  - `./scripts/version.sh show`로 현재 `x.y.z+n` 확인
  - 패치 릴리스는 `./scripts/version.sh bump-patch`, 마이너 릴리스는 `./scripts/version.sh bump-minor`
  - `./scripts/build_dmg.sh`는 build number를 자동으로 1 올리고 `dist/적자생존_v<version>_build<build>.dmg` 생성
  - 같은 버전으로 재빌드만 필요하면 `./scripts/build_dmg.sh --no-bump`
  - DMG 직접 배포용 앱은 `macos/Runner/DirectDistribution.entitlements`로 재서명됨. App Store용 `Release.entitlements`와 섞지 말 것.
- 최근 릴리즈 검증:
  - `dist/적자생존_v2.1.1_build22.dmg` (옵션 C macos_ui 도입 안정 마커)
  - `flutter analyze` 0 issues, `flutter test` 36/36, `flutter build macos --debug`, `hdiutil verify`, Release 앱 `codesign --verify --deep --strict` 통과
- macOS 빌드에서 `onnxruntime` dylib가 더 높은 macOS 버전으로 빌드됐다는 경고가 나올 수 있음. 최근까지 빌드는 성공했음.

## P0 — 앱스토어 제출 준비

### 1. 서명/Archive/제출 메타데이터 확정

현재 완료:

- 앱스토어 안전 모드는 기본값 `APP_STORE_COMPLIANCE_MODE=true`.
- EXAONE은 앱스토어 안전 모드에서 다운로드 카드/선택 옵션/설치 모델 카운트에서 제외됨.
- 과거 저장값 `selectedLlmModel=exaone35_7b`는 앱 시작 시 안전 기본 모델 `gemma4_e2b`로 정리됨.
- EXAONE 다운로드 함수가 직접 호출돼도 안전 모드에서는 즉시 반환.
- 제한 모델 파일/URL helper는 안전 기본 모델로 fallback.
- 설정 화면에 `사용 모델 및 라이선스` 고지 UI가 있음.
- 회귀 테스트: `test/app_settings_compliance_test.dart`.
- 2026-05-05 사용자 수동 QA 완료:
  - 녹음 준비 다이얼로그 실시간 마이크 레벨
  - macOS 메뉴바 트레이 빠른 녹음
  - 45분 이상 실제 회의 파일 안정성 재검증

남은 일:

- Privacy Policy URL, Support URL 확정.
- App Store Connect Bundle ID 확정.
- Apple Distribution 인증서/프로비저닝 준비.
- Xcode Archive 생성.
- `scripts/build_app_store.sh` strict 검사 통과.

관련 파일:

- `lib/core/constants/app_build_config.dart`
- `lib/core/constants/app_constants.dart`
- `lib/core/constants/legal_notices.dart`
- `lib/core/services/app_settings.dart`
- `lib/presentation/screens/setup_screen.dart`
- `lib/presentation/screens/settings_screen.dart`
- `test/app_settings_compliance_test.dart`
- `APP_STORE_COMPLIANCE.md`
- `scripts/build_app_store.sh`

완료 조건:

- Xcode Archive + Apple Distribution 서명으로 strict 검사 통과.
- App Store Connect 제출 메타데이터와 심사 메모 확정.

## P1 — 앱스토어 일반 사용자 UX 마무리

### 2. 처리 시간 카드 일반 사용자화 — 완료

구현 위치:

- 기본 카드: `lib/presentation/widgets/meeting_detail_view.dart` `_buildProcessingReport()` (음성 인식/발화자 라벨/요약 생성 + 소요 시간만)
- 고급 정보 접기: 같은 파일 `_AdvancedReportInfo` (RTF, 모델 파일명, 모델 ID, 처리 방식, 언어, 오디오 길이, 입력 레벨)
- 사용자 노출 텍스트 정리: 다이얼로그/상태/에러/다운로드 라벨에서 `LLM` → `요약 모델`, `STT` → `음성 인식` 로 변경

### 3. 요약 템플릿 UI 단순화 — 완료

구현 위치:

- 설정 화면: `lib/presentation/screens/settings_screen.dart` `_buildSummaryTemplateSection()` — 카드 제목 "회의 유형", 한 줄 description만 노출, 긴 instruction은 `고급 설정 — 세부 정리 방식` ExpansionTile 안에
- 녹음 준비 다이얼로그: `recording_view.dart` `labelText: '회의 유형'` (DropdownButtonFormField)
- 다시 요약 다이얼로그: `meeting_detail_view.dart` `_pickTemplateDialog` — `회의 유형` 라디오 + `재생성 스타일` ChoiceChip

### 4. 요약 재생성 옵션 — 완료

구현 위치:

- `SummaryStyleMode` enum 5종(`standard`/`detailed`/`concise`/`actionFocused`/`executive`): `lib/core/services/summary_templates.dart`
- 각 모드의 displayName/description/modifier instruction 포함
- `SummaryTemplates.resolveInstruction({styleMode})` — base instruction 위에 modifier를 누적
- UI: `meeting_detail_view.dart` `_pickTemplateDialog`의 `재생성 스타일` Wrap+ChoiceChip
- 적용 경로: `picked.styleMode` → `SummaryTemplates.resolveInstruction(styleMode:)` → `ChunkedSummarizer.summarize(instruction:)`
- 기존 요약은 `SummaryVersion` 이력에 자동 저장 (v1.7.1 인프라)

### 5. 전사본 품질 보정 도구 — 완료

구현 위치 (모두 `lib/presentation/widgets/meeting_detail_view.dart`):

- 전사 영역 헤더에 `PopupMenuButton` (`Icons.spellcheck`, tooltip "전사 보정") 노출
- 메뉴 항목 3종:
  - `단어집에 추가` → `_addToGlossary()` (term/description/aliases 다이얼로그)
  - `전사본 단어 치환` → `_replaceAcrossTranscript()` (찾기/바꾸기 + "단어집에 별칭으로 자동 추가" 옵션)
  - `단어집 별칭 재교정` → `_applyGlossaryAliases()` (`TranscriptCorrector.fromGlossary` 일괄 적용)
- 변경 후 `widget.onTranscriptChanged?.call()`로 상위 패널을 invalidate
- SnackBar로 변경된 세그먼트 수 안내

추가 미세 개선 여지(필수 아님):

- 현재는 사용자가 다이얼로그에 직접 입력. 전사본의 `SelectableText.rich`에 `contextMenuBuilder`를 붙이면 선택 텍스트가 자동으로 다이얼로그에 채워져 한 단계 더 매끄러워짐.

### 6. 회의록 내보내기 고도화

현재:

- Markdown 저장/복사, PDF 저장, DOCX 저장, 이메일, 공유 지원.
- Notion용 요약 복사, 보고서 형식 복사, 액션아이템만 복사 지원.
- 보고서 형식 PDF/DOCX 저장 지원.

다음 목표:

- 앱스토어 유료 앱으로서 결과물을 외부 업무 도구에 쉽게 가져갈 수 있게 함.

남은 추천 기능:

- 저장 템플릿 세부 디자인 옵션

관련 파일:

- `lib/core/services/export_service.dart`
- `lib/presentation/widgets/meeting_detail_view.dart`

완료 조건:

- 내보내기 결과가 실제 업무 보고/공유에 바로 사용 가능.

## P2 — 고급 기능

### 7. 요약 신뢰도 표시 v2 — 완료

구현 위치:

- LLM 출력 스키마: `lib/core/utils/summary_parser.dart` `[근거 타임스탬프 — 신뢰도 표시 v2]` 섹션. JSON 키 `keyDiscussionsEvidence` / `decisionsEvidence` / `actionItemsEvidence` / `openQuestionsEvidence`. main 배열과 1:1 매칭, 빈 문자열 = LLM이 명시 못 한 항목
- 저장: `lib/domain/entities/summary.dart` `evidenceJson` 필드 + `SummaryEvidence` 파서 + `parseStartSec(ts)` ("MM:SS"/"HH:MM:SS"/"MM:SS-MM:SS" 모두 처리)
- 점프: `meeting_detail_view.dart` `_handleEvidenceClick` — evidenceTs 있으면 직접 점프, 없으면 v1 키워드 fallback 다이얼로그
- 근거 버튼에 timestamp 직접 노출: `근거 02:55` 형태 (`_EvidenceButton`)
- `확인 필요` 표시: fallback 다이얼로그 헤더 주황 배지(score < 0.24) + 액션 카드 amber "확인 필요한 액션 정보" 배너
- 환각 방지: `ActionItem.ownerConfirmed`/`deadlineConfirmed`, "(미언급)" 정규화

미세 개선 여지(필수 아님):

- ~~현재 카드 자체에는 evidenceTs 빈 문자열이어도 시각 표시가 약함~~ — 2026-05-09 완료. `_EvidenceButton`이 evidenceTs 빈 경우 ⚠️ 아이콘 + "근거 미명시" 라벨 + 명확한 tooltip로 표시.

### 8. 회의 검색 고도화

목표:

- 키워드 검색과 AI 검색을 통합해 “지난번 빅쿼리 얘기한 회의” 같은 자연어 검색 개선.

관련 파일:

- `lib/presentation/widgets/meeting_sidebar.dart`
- `lib/data/repositories/meeting_repository_impl.dart`
- `lib/data/repositories/transcript_repository_impl.dart`

### 9. 정기 회의 시리즈 고도화

현재:

- 사이드바 `시리즈 추천` 버튼으로 제목/태그/참석자가 비슷한 미분류 회의를 그룹화 가능.
- 기존 수동 그룹은 자동 추천 대상에서 제외.
- 시리즈 진행 분석 v1 (2026-05-06):
  - `lib/core/services/meeting_series_progress.dart` — `MeetingSeriesProgress.analyze(groupId)` → `SeriesProgressReport`(회의 수·평균 주기·누적 미완료 액션·최근 결정·반복 등장 미해결 이슈). LLM 추가 호출 없음, 기존 `Summary` 활용.
  - `lib/presentation/providers/meeting_providers.dart` — `selectedGroupIdProvider` + `seriesProgressProvider(groupId)` family
  - `lib/presentation/widgets/series_dashboard_view.dart` — 메인 영역 진행 대시보드 (메타 칩 + 누적 액션/반복 이슈/최근 결정 3카드, 클릭 시 회의 상세 점프)
  - `lib/presentation/widgets/meeting_sidebar.dart` `_GroupSection` — 그룹 헤더에 `Icons.timeline` 토글 아이콘, `_onShowSeriesDashboard`
  - `lib/presentation/screens/home_screen.dart` `_MainArea` — 회의 선택 우선, 그룹 선택 시 `SeriesDashboardView`
  - 단위 테스트: `test/meeting_series_progress_test.dart`

남은 개선 (Phase 3):

- ~~이슈 매칭 정밀도 강화~~ — 2026-05-09 완료. `MeetingSeriesProgress`가 `_roughlySame` 부분 일치(8자 이상 substring) 도입. 회귀 테스트 2개 추가.
- ~~액션아이템 회차별 변화 추적~~ — 2026-05-09 완료. `TrackedAction`/`ActionAppearance`/`TrackedActionStatus` 추가, 시리즈 대시보드에 `_ActionTimelineCard` (상태 칩 + 담당자/마감 변경 배지). 테스트 2개 추가.
- ~~시리즈 비교 대시보드~~ — 2026-05-09 완료. `SeriesOverview.analyze` + 사이드바 `📊 시리즈 비교` 버튼 → `MacosSheet`로 모든 그룹 카드 표시, 카드 클릭 시 해당 시리즈로 점프. 테스트 5개.

## 2026-05-09 추가 완료 (P2 — AI 검색 보강 + 시리즈 비교 + 회의 비교)

- AI 검색 keyword pre-filter ([meeting_keyword_search.dart](lib/core/services/meeting_keyword_search.dart)) — 쿼리 토크나이즈(2글자 미만 제거) → title/tags/notes/agenda/transcriptPreview + summary 필드 매칭, 키워드 등장 횟수 스코어, 상위 30개만 LLM에 전달, 매칭 0개면 입력 순서 폴백. `_runAiSearch`에서 사용. 테스트 9개.
- 시리즈 비교 대시보드 ([series_overview.dart](lib/core/services/series_overview.dart)) — `SeriesOverview.analyze(groups, repos)`가 모든 그룹의 `MeetingSeriesProgress` 결과를 수집·정렬. 사이드바 하단 `📊 시리즈 비교` 버튼 → `MacosSheet`. 카드마다 회의 N회/평균 주기/마지막 N일 전/누적 미완료/지속 이슈/결정 표시, 카드 클릭 시 해당 시리즈로 점프. 회의 0회 그룹 자동 제외. 테스트 5개.
- 회의 비교 ([meeting_comparison.dart](lib/core/services/meeting_comparison.dart)) — `MeetingComparison.compare(earlier, later, summaries)`가 4개 섹션(결정/이슈/액션/논의) diff 산출. 시리즈 대시보드 헤더 `⇄` 아이콘 → `MacosSheet` 비교 시트. 가장 최근 두 회의 자동 선택, dropdown으로 변경 가능. `+`/`−`/`·` 마커 + 액션 상태 전이(완료/재오픈/진행 중) + 담당자/마감 변경 표식. `_roughlySame` 부분 일치로 task 매칭. 테스트 8개.

## 2026-05-09 추가 완료 (P2 인사이트/업무 흐름)

- 회의 품질 점수 ([meeting_quality.dart](lib/core/services/meeting_quality.dart)) — decisions/actions/balance/evidence 4개 sub-score 가중 평균(30/30/15/25), 우수/양호/보통/개선 필요 등급, LLM 추가 호출 없음. 회의 상세 처리 시간 카드 아래 `_QualityScoreCard`. 단위 테스트 10개.
- 화자 발언 통계 ([speaker_stats.dart](lib/core/services/speaker_stats.dart)) — 화자별 발화 시간/세그먼트/점유율, 8색 팔레트, `Meeting.speakerNamesJson` 사용자 지정 이름 표시, 미식별 bucket 별도 집계. 회의 상세 `_SpeakerStatsCard`. 단위 테스트 7개.
- 주간/월간 다이제스트 ([digest_report.dart](lib/core/services/digest_report.dart)) — 주간(월요일 시작)/월간 토글, 기간 내 미완료 액션/결정/미해결 이슈 집계. 사이드바 하단 `📅 다이제스트` 버튼 → `MacosSheet`. 회의 클릭 시 시트 닫고 회의 상세로 점프. 단위 테스트 7개.
- AI 검색 KV 캐시 초과 fix — `_runAiSearch`가 `loadLlm`을 `nCtx: 2048`(기본값 4096의 절반)로 다운설정해서 회의 목록 컨텍스트 2574 토큰으로 초과되는 버그. `nCtx: 4096`로 정상화 + 회의 60개 상한 + 회의당 140자 상한 + 잘림 안내.

### 10. 장시간 회의 중간 진행 요약

현재 보류 이유:

- `OnDeviceModelManager`가 STT/LLM 동시 로드를 막고 있음.
- 녹음 중 LLM 요약을 돌리려면 Whisper unload → LLM load → 요약 → LLM unload → Whisper reload가 필요해 녹음 흐름이 깨질 수 있음.

재개 조건:

- 사용자가 녹음 일시정지를 허용할지 결정.
- “사용자 수동 중간 요약”인지 “자동 주기 요약”인지 제품 스펙 확정.

관련 파일:

- `lib/core/ffi/on_device_model_manager.dart`
- `lib/presentation/widgets/recording_view.dart`
- `lib/core/services/chunked_summarizer.dart`

## 알려진 리스크

- EXAONE은 앱스토어 안전 모드에서 숨김/저장값 정리/다운로드 방어가 적용됨. 내부 테스트 빌드에서만 플래그로 노출 가능하므로, 제출 전 빌드 플래그와 산출물 검사는 계속 필요함.
- 화자 라벨은 사람 이름을 식별하지 않고 A/B/C 라벨만 붙임. UI에서 기대치를 계속 낮춰야 함.
- 긴 회의 STT는 개선됐지만 장비 성능에 따라 여전히 오래 걸릴 수 있음.
- 요약 품질은 STT 품질에 크게 의존함. 전사 오류가 많은 파일은 요약도 흔들림.
- 모델 다운로드 크기가 큼. 온보딩에서 저장 공간과 다운로드 시간이 계속 명확해야 함.

## 마지막 확인된 빌드 상태

- `flutter analyze`: 통과
- `flutter build macos --debug`: 통과
- 최근 디버그 앱 경로:
  - `build/macos/Build/Products/Debug/적자생존.app`
