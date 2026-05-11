import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/domain/entities/meeting_processing_report.dart';

void main() {
  test('processing report preserves STT language', () {
    final raw = const MeetingProcessingReport(
      sttModel: 'ggml-large-v3-q5_0.bin',
      sttLanguage: 'auto',
      sttElapsedMs: 1200,
      sttProcessingMode: 'accurate',
    ).toJsonString();

    final restored = MeetingProcessingReport.fromJsonString(raw);

    expect(restored.sttModel, 'ggml-large-v3-q5_0.bin');
    expect(restored.sttLanguage, 'auto');
    expect(restored.sttElapsedMs, 1200);
    expect(restored.sttProcessingMode, 'accurate');
  });
}
