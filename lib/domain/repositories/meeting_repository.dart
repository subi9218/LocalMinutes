import '../entities/meeting.dart';
import '../entities/transcript.dart';
import '../entities/summary.dart';

abstract class MeetingRepository {
  Future<int> saveMeeting(Meeting meeting);
  Future<Meeting?> getMeetingById(int id);
  Future<List<Meeting>> getAllMeetings();
  Future<List<Meeting>> getMeetingsByGroupId(int groupId);
  Future<void> updateMeeting(Meeting meeting);
  Future<void> deleteMeeting(int id);
}

abstract class TranscriptRepository {
  Future<int> saveSegment(Transcript segment);
  Future<List<Transcript>> getSegmentsByMeetingId(int meetingId);
  Future<void> deleteByMeetingId(int meetingId);
}

abstract class SummaryRepository {
  Future<int> saveSummary(Summary summary);
  Future<Summary?> getSummaryByMeetingId(int meetingId);
  Future<void> deleteSummaryByMeetingId(int meetingId);
}
