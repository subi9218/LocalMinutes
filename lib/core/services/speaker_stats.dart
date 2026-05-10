import '../../domain/entities/transcript.dart';

/// 화자별 발언 통계 (P2 인사이트)
///
/// `Transcript.speakerLabel` + `start/endTimeSeconds` 만으로 산출.
/// 발화자 라벨이 없는 세그먼트는 `unlabeled` bucket에 집계.
class SpeakerStats {
  SpeakerStats._();

  static SpeakerStatsReport analyze(List<Transcript> transcripts) {
    if (transcripts.isEmpty) return SpeakerStatsReport.empty();

    final byLabel = <String, _Bucket>{};
    var unlabeledDur = 0.0;
    var unlabeledSegs = 0;
    for (final t in transcripts) {
      final dur = t.endTimeSeconds - t.startTimeSeconds;
      if (dur <= 0) continue;
      final label = t.speakerLabel?.trim();
      if (label == null || label.isEmpty) {
        unlabeledDur += dur;
        unlabeledSegs += 1;
        continue;
      }
      final b = byLabel.putIfAbsent(label, () => _Bucket());
      b.duration += dur;
      b.segmentCount += 1;
    }

    final labeledTotal = byLabel.values.fold<double>(
      0,
      (a, b) => a + b.duration,
    );
    final grandTotal = labeledTotal + unlabeledDur;
    if (grandTotal <= 0) return SpeakerStatsReport.empty();

    final entries =
        byLabel.entries
            .map(
              (e) => SpeakerEntry(
                label: e.key,
                duration: Duration(
                  milliseconds: (e.value.duration * 1000).round(),
                ),
                segmentCount: e.value.segmentCount,
                percentage: e.value.duration / grandTotal,
              ),
            )
            .toList()
          ..sort((a, b) => b.duration.compareTo(a.duration));

    return SpeakerStatsReport(
      totalDuration: Duration(milliseconds: (grandTotal * 1000).round()),
      labeledDuration: Duration(milliseconds: (labeledTotal * 1000).round()),
      unlabeledDuration: Duration(milliseconds: (unlabeledDur * 1000).round()),
      unlabeledSegmentCount: unlabeledSegs,
      speakers: List.unmodifiable(entries),
    );
  }
}

class _Bucket {
  double duration = 0;
  int segmentCount = 0;
}

class SpeakerStatsReport {
  /// 발화 시간 합계(라벨 + 비라벨).
  final Duration totalDuration;

  /// 라벨이 붙은 세그먼트의 발화 시간 합계.
  final Duration labeledDuration;

  /// 라벨이 없는 세그먼트의 발화 시간 합계.
  final Duration unlabeledDuration;

  /// 라벨이 없는 세그먼트 수.
  final int unlabeledSegmentCount;

  /// 발화 시간 내림차순 정렬.
  final List<SpeakerEntry> speakers;

  const SpeakerStatsReport({
    required this.totalDuration,
    required this.labeledDuration,
    required this.unlabeledDuration,
    required this.unlabeledSegmentCount,
    required this.speakers,
  });

  factory SpeakerStatsReport.empty() => const SpeakerStatsReport(
    totalDuration: Duration.zero,
    labeledDuration: Duration.zero,
    unlabeledDuration: Duration.zero,
    unlabeledSegmentCount: 0,
    speakers: [],
  );

  bool get isEmpty => totalDuration == Duration.zero;

  /// 식별된 화자 수 (라벨 기준).
  int get speakerCount => speakers.length;

  /// 가장 많이 발언한 화자의 점유율 (없으면 0).
  double get maxRatio => speakers.isEmpty ? 0 : speakers.first.percentage;

  /// 라벨이 붙은 부분만 기준으로 한 균형 점수 (지니 계수와 유사).
  /// 0(완벽 균형) ~ 1(한 명에게 완전 집중).
  double get concentrationIndex {
    if (speakers.length < 2) return 1.0;
    final n = speakers.length;
    final ideal = 1 / n;
    var sumDeviation = 0.0;
    for (final s in speakers) {
      sumDeviation += (s.percentage - ideal).abs();
    }
    // 정규화: 최대 편차는 2*(1 - 1/n)
    final maxDeviation = 2 * (1 - ideal);
    return maxDeviation == 0 ? 0 : (sumDeviation / maxDeviation).clamp(0, 1);
  }
}

class SpeakerEntry {
  final String label;
  final Duration duration;
  final int segmentCount;

  /// 전체(라벨+비라벨) 대비 점유율 (0~1).
  final double percentage;

  const SpeakerEntry({
    required this.label,
    required this.duration,
    required this.segmentCount,
    required this.percentage,
  });
}
