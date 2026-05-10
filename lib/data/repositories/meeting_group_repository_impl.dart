import 'package:isar/isar.dart';
import '../../domain/entities/meeting_group.dart';

class MeetingGroupRepositoryImpl {
  final Isar _db;
  MeetingGroupRepositoryImpl(this._db);

  Future<List<MeetingGroup>> getAllGroups() =>
      _db.meetingGroups.where().sortByCreatedAt().findAll();

  Future<MeetingGroup?> getGroupById(int id) =>
      _db.meetingGroups.get(id);

  Future<int> saveGroup(MeetingGroup group) =>
      _db.writeTxn(() => _db.meetingGroups.put(group));

  Future<bool> deleteGroup(int id) =>
      _db.writeTxn(() => _db.meetingGroups.delete(id));
}
