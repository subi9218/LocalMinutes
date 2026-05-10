import 'package:isar/isar.dart';

part 'summary_version.g.dart';

/// 요약 재실행 시 이전 요약을 보관하는 이력 컬렉션
@collection
class SummaryVersion {
  Id id = Isar.autoIncrement;

  /// 소속 회의 ID
  @Index()
  late int meetingId;

  /// 이력 버전 번호 (1 = 최초 요약, 2 = 첫 번째 재요약 이전 버전, ...)
  late int version;

  late String meetingTitle;
  late List<String> participants;
  late List<String> keyDiscussions;
  late List<String> decisions;
  late String actionItemsJson;
  late List<String> openQuestions;

  /// 이 요약이 생성된 시각
  late DateTime createdAt;
}
