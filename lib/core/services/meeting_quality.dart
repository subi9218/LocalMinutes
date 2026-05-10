import 'dart:convert';

import '../../domain/entities/summary.dart';
import '../../domain/entities/transcript.dart';

/// 회의 품질 분석 (P2 인사이트)
///
/// 이미 저장된 [Summary] + [Transcript]만 사용 — LLM 추가 호출 없음.
/// 점수보다 [hints]의 개선 힌트가 사용자에게 더 가치 있다.
///
/// 4개 하위 점수의 가중 평균이 [overallScore]:
///   - decisions  30% : 결정사항 수/길이
///   - actions    30% : owner/deadline 채움률 + 확인 플래그
///   - balance    15% : 발화자 간 발화 시간 균형
///   - evidence   25% : 요약 카드의 근거 명시율
class MeetingQuality {
  MeetingQuality._();

  static MeetingQualityReport analyze({
    required Summary? summary,
    required List<Transcript> transcripts,
  }) {
    if (summary == null) return MeetingQualityReport.empty();

    final decisions = _decisionsScore(summary.decisions);
    final actions = _actionsScore(summary.actionItemsJson);
    final balance = _balanceScore(transcripts);
    final evidence = _evidenceScore(summary);

    final overall =
        (decisions.score * 0.30 +
                actions.score * 0.30 +
                balance.score * 0.15 +
                evidence.score * 0.25)
            .round();

    final hints = <QualityHint>[
      ...decisions.hints,
      ...actions.hints,
      ...balance.hints,
      ...evidence.hints,
    ];

    return MeetingQualityReport(
      overallScore: overall,
      decisionsScore: decisions.score,
      actionsScore: actions.score,
      balanceScore: balance.score,
      evidenceScore: evidence.score,
      hints: List.unmodifiable(hints),
    );
  }

  // ── decisions ─────────────────────────────────────────────────
  static _SubScore _decisionsScore(List<String> decisions) {
    final hints = <QualityHint>[];
    final clean = decisions
        .map((d) => d.trim())
        .where((d) => d.isNotEmpty)
        .toList();
    if (clean.isEmpty) {
      hints.add(
        const QualityHint(
          category: QualityCategory.decisions,
          severity: QualityHintSeverity.warning,
          message: '결정사항이 없습니다. 회의 후반에 결정을 명확히 하면 후속 액션이 줄어듭니다.',
        ),
      );
      return _SubScore(0, hints);
    }
    int countScore;
    if (clean.length >= 3) {
      countScore = 100;
    } else if (clean.length == 2) {
      countScore = 75;
    } else {
      countScore = 50;
    }
    final avgLen = clean.fold<int>(0, (a, b) => a + b.length) / clean.length;
    int lengthAdj;
    if (avgLen >= 20) {
      lengthAdj = 0;
    } else if (avgLen >= 12) {
      lengthAdj = -10;
    } else {
      lengthAdj = -25;
      hints.add(
        const QualityHint(
          category: QualityCategory.decisions,
          severity: QualityHintSeverity.info,
          message: '결정사항 표현이 짧습니다. 누가/무엇을/언제까지가 들어가면 후속 추적이 쉬워집니다.',
        ),
      );
    }
    final score = (countScore + lengthAdj).clamp(0, 100).toInt();
    return _SubScore(score, hints);
  }

  // ── actions ──────────────────────────────────────────────────
  static _SubScore _actionsScore(String actionItemsJson) {
    final hints = <QualityHint>[];
    final items = _parseActionItems(actionItemsJson);
    if (items.isEmpty) {
      // 액션이 없는 게 반드시 나쁜 신호는 아님 — 정보 회의일 수도. 중립 점수.
      return _SubScore(70, hints);
    }
    int ownerFilled = 0;
    int deadlineFilled = 0;
    int ownerConfirmed = 0;
    int deadlineConfirmed = 0;
    for (final it in items) {
      if (it.owner.trim().isNotEmpty && !_looksUnspecified(it.owner)) {
        ownerFilled++;
        if (it.ownerConfirmed) ownerConfirmed++;
      }
      if (it.deadline.trim().isNotEmpty && !_looksUnspecified(it.deadline)) {
        deadlineFilled++;
        if (it.deadlineConfirmed) deadlineConfirmed++;
      }
    }
    final ownerRate = ownerFilled / items.length;
    final deadlineRate = deadlineFilled / items.length;
    final ownerConfirmRate = ownerFilled == 0
        ? 0.0
        : ownerConfirmed / ownerFilled;
    final deadlineConfirmRate = deadlineFilled == 0
        ? 0.0
        : deadlineConfirmed / deadlineFilled;
    final score =
        (ownerRate * 50 +
                deadlineRate * 30 +
                (ownerConfirmRate * 0.6 + deadlineConfirmRate * 0.4) * 20)
            .round()
            .clamp(0, 100);
    final missingOwner = items.length - ownerFilled;
    final missingDeadline = items.length - deadlineFilled;
    if (missingOwner > 0) {
      hints.add(
        QualityHint(
          category: QualityCategory.actions,
          severity: missingOwner * 2 >= items.length
              ? QualityHintSeverity.warning
              : QualityHintSeverity.info,
          message:
              '액션 ${items.length}개 중 담당자 미지정 $missingOwner개 — 다음 회의 전에 주인을 정해두세요.',
        ),
      );
    }
    if (missingDeadline > 0) {
      hints.add(
        QualityHint(
          category: QualityCategory.actions,
          severity: missingDeadline * 2 >= items.length
              ? QualityHintSeverity.warning
              : QualityHintSeverity.info,
          message:
              '액션 ${items.length}개 중 마감일 미정 $missingDeadline개 — 기한이 있어야 진척이 추적됩니다.',
        ),
      );
    }
    return _SubScore(score, hints);
  }

  // ── balance ──────────────────────────────────────────────────
  static _SubScore _balanceScore(List<Transcript> transcripts) {
    final hints = <QualityHint>[];
    final byLabel = <String, double>{};
    for (final t in transcripts) {
      final label = t.speakerLabel?.trim();
      if (label == null || label.isEmpty) continue;
      final dur = t.endTimeSeconds - t.startTimeSeconds;
      if (dur <= 0) continue;
      byLabel[label] = (byLabel[label] ?? 0) + dur;
    }
    if (byLabel.isEmpty) {
      // 라벨 없음 — 측정 불가, 중립 점수
      return _SubScore(70, hints);
    }
    if (byLabel.length == 1) {
      // 단일 화자 — 1:1 회의가 아닌 경우 불균형 신호
      hints.add(
        const QualityHint(
          category: QualityCategory.balance,
          severity: QualityHintSeverity.info,
          message: '한 화자만 식별되었습니다. 화자 분리가 약한 녹음일 수 있어요.',
        ),
      );
      return _SubScore(60, hints);
    }
    final values = byLabel.values.toList()..sort();
    final total = values.fold<double>(0, (a, b) => a + b);
    final maxRatio = values.last / total;
    int score;
    if (maxRatio <= 0.55) {
      score = 100;
    } else if (maxRatio <= 0.70) {
      score = 80;
    } else if (maxRatio <= 0.85) {
      score = 60;
    } else {
      score = 40;
    }
    if (maxRatio > 0.70) {
      final pct = (maxRatio * 100).round();
      hints.add(
        QualityHint(
          category: QualityCategory.balance,
          severity: maxRatio > 0.85
              ? QualityHintSeverity.warning
              : QualityHintSeverity.info,
          message: '한 화자의 발화가 $pct% 입니다 — 다른 의견이 충분히 나왔는지 확인해보세요.',
        ),
      );
    }
    return _SubScore(score, hints);
  }

  // ── evidence ─────────────────────────────────────────────────
  static _SubScore _evidenceScore(Summary s) {
    final hints = <QualityHint>[];
    final ev = _parseEvidence(s.evidenceJson);
    int total = 0;
    int filled = 0;

    void count(List<String> items, String key) {
      final list = ev[key] ?? const <String>[];
      for (var i = 0; i < items.length; i++) {
        total++;
        if (i < list.length && list[i].trim().isNotEmpty) filled++;
      }
    }

    count(s.keyDiscussions, 'keyDiscussions');
    count(s.decisions, 'decisions');
    count(s.openQuestions, 'openQuestions');

    if (total == 0) {
      // 분석할 항목이 없음 — 중립 점수
      return _SubScore(70, hints);
    }
    final score = (filled / total * 100).round();
    final missing = total - filled;
    if (missing > 0 && score < 70) {
      hints.add(
        QualityHint(
          category: QualityCategory.evidence,
          severity: score < 40
              ? QualityHintSeverity.warning
              : QualityHintSeverity.info,
          message:
              '근거 미명시 항목 $missing/$total — "근거 미명시" 배지가 있는 항목은 전사본에서 직접 확인하세요.',
        ),
      );
    }
    return _SubScore(score, hints);
  }

  // ── helpers ──────────────────────────────────────────────────
  static List<ActionItem> _parseActionItems(String json) {
    if (json.trim().isEmpty) return const [];
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ActionItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Map<String, List<String>> _parseEvidence(String json) {
    if (json.trim().isEmpty) return const {};
    try {
      final raw = jsonDecode(json);
      if (raw is! Map) return const {};
      final out = <String, List<String>>{};
      raw.forEach((k, v) {
        if (k is String && v is List) {
          out[k] = v.map((e) => e?.toString() ?? '').toList();
        }
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  static bool _looksUnspecified(String s) {
    final t = s.trim();
    if (t.isEmpty) return true;
    return t == '-' || t == '미정' || t == '미지정' || t == '(미언급)' || t == '(미정)';
  }
}

class _SubScore {
  final int score;
  final List<QualityHint> hints;
  const _SubScore(this.score, this.hints);
}

class MeetingQualityReport {
  final int overallScore;
  final int decisionsScore;
  final int actionsScore;
  final int balanceScore;
  final int evidenceScore;
  final List<QualityHint> hints;

  const MeetingQualityReport({
    required this.overallScore,
    required this.decisionsScore,
    required this.actionsScore,
    required this.balanceScore,
    required this.evidenceScore,
    required this.hints,
  });

  factory MeetingQualityReport.empty() => const MeetingQualityReport(
    overallScore: 0,
    decisionsScore: 0,
    actionsScore: 0,
    balanceScore: 0,
    evidenceScore: 0,
    hints: [],
  );

  bool get isEmpty => overallScore == 0 && hints.isEmpty;

  /// 사용자 노출 라벨 — 점수 자체보다 가독성 높은 등급.
  String get gradeLabel {
    if (overallScore >= 85) return '우수';
    if (overallScore >= 70) return '양호';
    if (overallScore >= 50) return '보통';
    return '개선 필요';
  }
}

enum QualityCategory { decisions, actions, balance, evidence }

enum QualityHintSeverity { info, warning }

class QualityHint {
  final QualityCategory category;
  final QualityHintSeverity severity;
  final String message;

  const QualityHint({
    required this.category,
    required this.severity,
    required this.message,
  });

  String get categoryLabel => switch (category) {
    QualityCategory.decisions => '결정',
    QualityCategory.actions => '액션',
    QualityCategory.balance => '발화 균형',
    QualityCategory.evidence => '근거',
  };
}
