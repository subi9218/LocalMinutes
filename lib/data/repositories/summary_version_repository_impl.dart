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
}
