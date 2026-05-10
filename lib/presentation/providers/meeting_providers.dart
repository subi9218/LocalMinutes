import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/isar_service.dart';
import '../../core/services/meeting_series_progress.dart';
import '../../core/services/search_service.dart';
import '../../data/repositories/meeting_repository_impl.dart';
import '../../data/repositories/meeting_group_repository_impl.dart';
import '../../data/repositories/transcript_repository_impl.dart';
import '../../data/repositories/summary_repository_impl.dart';
import '../../data/repositories/summary_version_repository_impl.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/entities/meeting_group.dart';
import '../../domain/entities/transcript.dart';
import '../../domain/entities/summary.dart';
import '../../domain/entities/summary_version.dart';

// ── 날짜 범위 필터 ────────────────────────────────────────────────
enum DateFilter { all, thisWeek, thisMonth }

// ── AI 검색 결과 모델 ─────────────────────────────────────────────
class AiSearchResult {
  final int meetingId;
  final String reason;
  const AiSearchResult({required this.meetingId, required this.reason});
}

// ── 회의 목록 (createdAt DESC) ────────────────────────────────
final meetingsProvider = FutureProvider<List<Meeting>>((ref) async {
  return MeetingRepositoryImpl(IsarService.instance.db).getAllMeetings();
});

// ── 그룹 목록 ─────────────────────────────────────────────────
final groupsProvider = FutureProvider<List<MeetingGroup>>((ref) async {
  return MeetingGroupRepositoryImpl(IsarService.instance.db).getAllGroups();
});

// ── 선택된 회의 ID ─────────────────────────────────────────────
final selectedMeetingIdProvider = StateProvider<int?>((ref) => null);

// ── 선택된 그룹 ID (시리즈 진행 대시보드) ─────────────────────────
// not null 이면 메인 영역에 SeriesDashboardView 표시.
// 회의를 선택하면 자동으로 null 로 되돌리는 게 아니라 사이드바 핸들러가 명시적으로 reset.
final selectedGroupIdProvider = StateProvider<int?>((ref) => null);

// ── 시리즈 진행 분석 (groupId별) ──────────────────────────────────
// meetingsProvider / allSummariesProvider 가 invalidate 되면 자동 재계산.
final seriesProgressProvider = FutureProvider.family<SeriesProgressReport, int>(
  (ref, groupId) async {
    // 회의/요약이 갱신되면 새 리포트 필요 — watch 로 종속성 명시.
    await ref.watch(meetingsProvider.future);
    await ref.watch(allSummariesProvider.future);
    return MeetingSeriesProgress.analyze(
      groupId: groupId,
      meetingRepo: MeetingRepositoryImpl(IsarService.instance.db),
      summaryRepo: SummaryRepositoryImpl(IsarService.instance.db),
    );
  },
);

// ── 전사 세그먼트 (meetingId별) ───────────────────────────────
final meetingTranscriptProvider = FutureProvider.family<List<Transcript>, int>((
  ref,
  meetingId,
) async {
  return TranscriptRepositoryImpl(
    IsarService.instance.db,
  ).getSegmentsByMeetingId(meetingId);
});

// ── 회의 요약 (meetingId별) ───────────────────────────────────
final meetingSummaryProvider = FutureProvider.family<Summary?, int>((
  ref,
  meetingId,
) async {
  return SummaryRepositoryImpl(
    IsarService.instance.db,
  ).getSummaryByMeetingId(meetingId);
});

// ── 전체 요약 목록 (검색용) ───────────────────────────────────────
final allSummariesProvider = FutureProvider<List<Summary>>((ref) async {
  return SummaryRepositoryImpl(IsarService.instance.db).getAllSummaries();
});

// ── 요약 이력 (meetingId별) ───────────────────────────────────
final summaryVersionsProvider =
    FutureProvider.family<List<SummaryVersion>, int>((ref, meetingId) async {
      return SummaryVersionRepositoryImpl(
        IsarService.instance.db,
      ).getVersionsByMeetingId(meetingId);
    });

// ── 녹음 활성화 여부 ──────────────────────────────────────────
final isRecordingActiveProvider = StateProvider<bool>((ref) => false);

// ── 요약 중 여부 (사이드바 표시용) ────────────────────────────
final isSummarizingProvider = StateProvider<bool>((ref) => false);

// ── 검색 ──────────────────────────────────────────────────────────
final searchQueryProvider = StateProvider<String>((ref) => '');
final isAiSearchModeProvider = StateProvider<bool>((ref) => false);
final isAiSearchingProvider = StateProvider<bool>((ref) => false);
final aiSearchStatusProvider = StateProvider<String>((ref) => '');
final aiSearchResultsProvider = StateProvider<List<AiSearchResult>?>(
  (ref) => null,
);

// ── 날짜 범위 필터 ─────────────────────────────────────────────────
final dateFilterProvider = StateProvider<DateFilter>((ref) => DateFilter.all);

// ── 전문 검색 결과 (단어 모드) ─────────────────────────────────────
// searchQueryProvider + meetings + summaries 를 watch해서 자동 재계산.
// Transcript 본문까지 DB 스캔하므로 FutureProvider로 노출.
final searchHitsProvider = FutureProvider<List<MeetingSearchHit>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const [];
  final meetings = await ref.watch(meetingsProvider.future);
  final summaries = await ref.watch(allSummariesProvider.future);
  return SearchService.search(
    query: query,
    meetings: meetings,
    summaries: summaries,
  );
});

// ── 검색 결과에서 전사 구간으로 점프 요청 ──────────────────────────
// 사이드바 검색 결과에서 전사 스니펫을 클릭하면 회의 상세에서
// 해당 텍스트가 포함된 첫 번째 세그먼트로 자동 점프 + 하이라이트한다.
class TranscriptJumpRequest {
  final int meetingId;
  final String snippet;
  final int seq; // 같은 meetingId/snippet 재요청 트리거용
  const TranscriptJumpRequest({
    required this.meetingId,
    required this.snippet,
    required this.seq,
  });
}

final transcriptJumpRequestProvider = StateProvider<TranscriptJumpRequest?>(
  (ref) => null,
);

// ── 메뉴바 트레이 → 앱 본체로 보내는 시그널 ────────────────────────
// 카운터를 1 증가시키면 listener가 한 번 트리거된다 (idempotent 신호).
// RecordingView가 이미 마운트된 상태에서 트레이 액션이 발생한 케이스용.
final trayStartRecordingSignalProvider = StateProvider<int>((ref) => 0);
final trayStopRecordingSignalProvider = StateProvider<int>((ref) => 0);
final trayBookmarkSignalProvider = StateProvider<int>((ref) => 0);

/// 트레이 "빠른 녹음 시작" → RecordingView가 새로 마운트되는 경우 처리.
/// RecordingView initState에서 true를 발견하면 자동으로 _startRecording 호출
/// 후 false로 되돌린다 (one-shot consume).
final pendingTrayQuickStartProvider = StateProvider<bool>((ref) => false);

/// 빠른 녹음 시작 요청이 실제 트레이 메뉴에서 온 것인지 표시한다.
/// 실패 시 창을 앞으로 띄우고 더 명확한 안내를 보여주기 위한 one-shot flag.
final pendingTrayQuickStartFromTrayProvider = StateProvider<bool>(
  (ref) => false,
);

/// 트레이 "녹음 정지" → RecordingView가 현재 화면에 없어서 새로 마운트되는 경우 처리.
/// 예: 녹음 중 사이드바에서 기존 회의를 열어 상세 화면을 보고 있을 때.
final pendingTrayStopProvider = StateProvider<bool>((ref) => false);

/// 트레이 "북마크 추가" → RecordingView가 현재 화면에 없어서 새로 마운트되는 경우 처리.
/// 카운트로 저장해 여러 번 눌러도 누락되지 않게 한다.
final pendingTrayBookmarkCountProvider = StateProvider<int>((ref) => 0);

// ── 전역 키보드 단축키 시그널 ─────────────────────────────────────
// 트레이 시그널과 같은 패턴(카운터 증가). listener가 픽업 후 동작.
final shortcutFocusSearchSignalProvider = StateProvider<int>((ref) => 0);
final shortcutOpenSettingsSignalProvider = StateProvider<int>((ref) => 0);
final shortcutRunSummarySignalProvider = StateProvider<int>((ref) => 0);
final shortcutToggleRecordSignalProvider = StateProvider<int>((ref) => 0);
