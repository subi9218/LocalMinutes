import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/core/services/speaker_stats.dart';
import 'package:local_minutes/domain/entities/transcript.dart';

void main() {
  test('빈 입력 → empty report', () {
    final r = SpeakerStats.analyze(const []);
    expect(r.isEmpty, isTrue);
    expect(r.speakerCount, 0);
  });

  test('두 화자 균형 — A 50% / B 50%', () {
    final r = SpeakerStats.analyze([_t(0, 50, 'A'), _t(50, 100, 'B')]);
    expect(r.speakerCount, 2);
    expect(r.speakers[0].percentage, closeTo(0.5, 0.001));
    expect(r.speakers[1].percentage, closeTo(0.5, 0.001));
    expect(r.maxRatio, closeTo(0.5, 0.001));
    // 완벽 균형 → concentration 낮음
    expect(r.concentrationIndex, lessThan(0.05));
  });

  test('한 화자 완전 집중 — A 100%', () {
    final r = SpeakerStats.analyze([_t(0, 100, 'A')]);
    expect(r.speakerCount, 1);
    expect(r.speakers.first.percentage, closeTo(1.0, 0.001));
    // 1명만 있으면 concentration = 1.0
    expect(r.concentrationIndex, 1.0);
  });

  test('정렬 — 발화 시간 내림차순', () {
    final r = SpeakerStats.analyze([
      _t(0, 30, 'A'),
      _t(30, 90, 'B'),
      _t(90, 100, 'C'),
    ]);
    expect(r.speakers.map((s) => s.label).toList(), ['B', 'A', 'C']);
  });

  test('라벨 없는 세그먼트는 unlabeled로 집계되어 점유율 분모에 포함', () {
    final r = SpeakerStats.analyze([
      _t(0, 50, 'A'),
      _t(50, 100, null), // unlabeled
    ]);
    expect(r.speakerCount, 1);
    expect(r.speakers.first.percentage, closeTo(0.5, 0.001)); // A는 50/100
    expect(r.unlabeledDuration, const Duration(seconds: 50));
    expect(r.unlabeledSegmentCount, 1);
  });

  test('세그먼트 카운트 정확', () {
    final r = SpeakerStats.analyze([
      _t(0, 10, 'A'),
      _t(10, 20, 'A'),
      _t(20, 30, 'A'),
      _t(30, 40, 'B'),
    ]);
    final a = r.speakers.firstWhere((s) => s.label == 'A');
    final b = r.speakers.firstWhere((s) => s.label == 'B');
    expect(a.segmentCount, 3);
    expect(b.segmentCount, 1);
  });

  test('0 또는 음수 길이 세그먼트는 무시', () {
    final r = SpeakerStats.analyze([
      _t(0, 0, 'A'), // 0초
      _t(10, 5, 'B'), // 음수
      _t(20, 30, 'C'), // 정상
    ]);
    expect(r.speakerCount, 1);
    expect(r.speakers.first.label, 'C');
  });
}

Transcript _t(double start, double end, String? speaker) {
  return Transcript()
    ..meetingId = 1
    ..text = ''
    ..startTimeSeconds = start
    ..endTimeSeconds = end
    ..speakerLabel = speaker;
}
