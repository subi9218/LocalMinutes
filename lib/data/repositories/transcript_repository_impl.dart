import 'package:isar/isar.dart';
import '../../domain/entities/transcript.dart';
import '../../domain/repositories/meeting_repository.dart';

class TranscriptRepositoryImpl implements TranscriptRepository {
  final Isar _db;
  TranscriptRepositoryImpl(this._db);

  @override
  Future<int> saveSegment(Transcript segment) =>
      _db.writeTxn(() => _db.transcripts.put(segment));

  @override
  Future<List<Transcript>> getSegmentsByMeetingId(int meetingId) =>
      _db.transcripts
          .filter()
          .meetingIdEqualTo(meetingId)
          .sortBySegmentIndex()
          .findAll();

  Future<void> updateSegment(Transcript segment) =>
      _db.writeTxn(() => _db.transcripts.put(segment));

  @override
  Future<void> deleteByMeetingId(int meetingId) async {
    await _db.writeTxn(() async {
      final items = await _db.transcripts
          .filter()
          .meetingIdEqualTo(meetingId)
          .findAll();
      await _db.transcripts.deleteAll(items.map((t) => t.id).toList());
    });
  }
}
