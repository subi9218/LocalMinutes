import 'package:isar/isar.dart';
import '../../domain/entities/summary_version.dart';

class SummaryVersionRepositoryImpl {
  final Isar _db;
  SummaryVersionRepositoryImpl(this._db);

  Future<int> saveVersion(SummaryVersion v) =>
      _db.writeTxn(() => _db.summaryVersions.put(v));

  Future<List<SummaryVersion>> getVersionsByMeetingId(int meetingId) =>
      _db.summaryVersions
          .filter()
          .meetingIdEqualTo(meetingId)
          .sortByVersionDesc()
          .findAll();

  Future<int> nextVersion(int meetingId) async {
    final versions = await getVersionsByMeetingId(meetingId);
    return versions.isEmpty ? 1 : versions.first.version + 1;
  }

  /// 회의 삭제 시 이력도 함께 제거 (고아 레코드 방지 — Isar id 재사용 시
  /// 새 회의에 남의 이력이 붙는 것을 막는다).
  Future<void> deleteByMeetingId(int meetingId) async {
    await _db.writeTxn(() async {
      await _db.summaryVersions
          .filter()
          .meetingIdEqualTo(meetingId)
          .deleteAll();
    });
  }
}
