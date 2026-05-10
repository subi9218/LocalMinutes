import 'package:isar/isar.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/repositories/meeting_repository.dart';

class MeetingRepositoryImpl implements MeetingRepository {
  final Isar _db;
  MeetingRepositoryImpl(this._db);

  @override
  Future<int> saveMeeting(Meeting m) => _db.writeTxn(() => _db.meetings.put(m));

  @override
  Future<Meeting?> getMeetingById(int id) => _db.meetings.get(id);

  @override
  Future<List<Meeting>> getAllMeetings() =>
      _db.meetings.where().sortByCreatedAtDesc().findAll();

  @override
  Future<List<Meeting>> getMeetingsByGroupId(int groupId) => _db.meetings
      .filter()
      .groupIdEqualTo(groupId)
      .sortByCreatedAtDesc()
      .findAll();

  @override
  Future<void> updateMeeting(Meeting m) =>
      _db.writeTxn(() => _db.meetings.put(m));

  @override
  Future<void> deleteMeeting(int id) =>
      _db.writeTxn(() => _db.meetings.delete(id));
}
