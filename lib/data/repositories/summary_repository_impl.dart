import 'package:isar/isar.dart';
import '../../domain/entities/summary.dart';
import '../../domain/repositories/meeting_repository.dart';

class SummaryRepositoryImpl implements SummaryRepository {
  final Isar _db;
  SummaryRepositoryImpl(this._db);

  @override
  Future<int> saveSummary(Summary s) async {
    // meetingId unique index 충돌 방지:
    // 동일 meetingId의 기존 요약이 있으면 해당 id를 재사용(upsert)
    final existing = await _db.summarys
        .filter()
        .meetingIdEqualTo(s.meetingId)
        .findFirst();
    if (existing != null) {
      s.id = existing.id;
    }
    return _db.writeTxn(() => _db.summarys.put(s));
  }

  @override
  Future<Summary?> getSummaryByMeetingId(int meetingId) =>
      _db.summarys.filter().meetingIdEqualTo(meetingId).findFirst();

  Future<List<Summary>> getAllSummaries() =>
      _db.summarys.where().findAll();

  @override
  Future<void> deleteSummaryByMeetingId(int meetingId) async {
    await _db.writeTxn(() async {
      final items = await _db.summarys
          .filter()
          .meetingIdEqualTo(meetingId)
          .findAll();
      await _db.summarys.deleteAll(items.map((s) => s.id).toList());
    });
  }
}
