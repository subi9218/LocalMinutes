import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/glossary_entry.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/entities/meeting_group.dart';
import '../../domain/entities/transcript.dart';
import '../../domain/entities/summary.dart';
import '../../domain/entities/summary_version.dart';

class IsarService {
  static final instance = IsarService._();
  IsarService._();

  Isar? _isar;

  Isar get db {
    if (_isar == null || !_isar!.isOpen) {
      throw StateError('IsarService not initialized. Call init() first.');
    }
    return _isar!;
  }

  Future<void> init() async {
    if (_isar != null && _isar!.isOpen) return;
    final dir = await getApplicationSupportDirectory();
    _isar = await Isar.open(
      [MeetingSchema, MeetingGroupSchema, TranscriptSchema, SummarySchema, SummaryVersionSchema, GlossaryEntrySchema],
      directory: dir.path,
    );
  }
}
