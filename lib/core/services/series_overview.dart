import '../../domain/entities/meeting_group.dart';
import '../../domain/repositories/meeting_repository.dart';
import 'meeting_series_progress.dart';

/// 모든 시리즈(그룹)를 한눈에 비교하는 개요 분석.
///
/// 각 그룹마다 [MeetingSeriesProgress.analyze]를 한 번씩 돌려 [SeriesOverviewItem] 리스트 생성.
/// LLM 추가 호출 없이 저장된 [Summary]만 활용.
///
/// 회의가 0회인 그룹(`SeriesProgressReport.isEmpty`)은 결과에서 제외.
/// 정렬: 가장 최근 회의가 위에. 마지막 회의 날짜가 같으면 그룹 이름 알파벳 순.
class SeriesOverview {
  SeriesOverview._();

  static Future<List<SeriesOverviewItem>> analyze({
    required List<MeetingGroup> groups,
    required MeetingRepository meetingRepo,
    required SummaryRepository summaryRepo,
  }) async {
    final out = <SeriesOverviewItem>[];
    for (final g in groups) {
      final report = await MeetingSeriesProgress.analyze(
        groupId: g.id,
        meetingRepo: meetingRepo,
        summaryRepo: summaryRepo,
      );
      if (report.isEmpty) continue;
      out.add(SeriesOverviewItem(group: g, report: report));
    }
    out.sort((a, b) {
      final aLast = a.report.lastMeetingAt;
      final bLast = b.report.lastMeetingAt;
      if (aLast == null && bLast == null) {
        return a.group.name.compareTo(b.group.name);
      }
      if (aLast == null) return 1;
      if (bLast == null) return -1;
      final cmp = bLast.compareTo(aLast);
      if (cmp != 0) return cmp;
      return a.group.name.compareTo(b.group.name);
    });
    return out;
  }
}

class SeriesOverviewItem {
  final MeetingGroup group;
  final SeriesProgressReport report;

  const SeriesOverviewItem({required this.group, required this.report});

  /// 마지막 회의가 며칠 전인지 ([reference] 기준, 기본 now). null = 회의 없음.
  int? daysSinceLastMeeting([DateTime? reference]) {
    final last = report.lastMeetingAt;
    if (last == null) return null;
    final ref = reference ?? DateTime.now();
    return ref.difference(last).inDays;
  }
}
