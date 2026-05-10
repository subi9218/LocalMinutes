import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/isar_service.dart';
import '../../data/repositories/glossary_repository_impl.dart';
import '../../data/repositories/meeting_repository_impl.dart';
import '../../data/repositories/summary_repository_impl.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/entities/summary.dart';
import '../providers/meeting_providers.dart';
import 'glossary_screen.dart';

/// 통계 다이얼로그 열기 헬퍼
void showStatsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _StatsDialog(),
  );
}

// ── 통계 데이터 모델 ───────────────────────────────────────────────────
class _StatsData {
  final int totalMeetings;
  final int totalSeconds;
  final Map<String, int> monthlyCount;   // 'YYYY-MM' → 횟수
  final List<MapEntry<String, int>> topParticipants; // 이름 → 등장 횟수
  final List<MapEntry<String, int>> durationBuckets; // 구간 라벨 → 횟수
  final List<List<int>> heatmap; // [weekday 0=월..6=일][hourBucket 0..3]
  final List<MapEntry<String, int>> topKeywords; // 키워드 → 빈도
  final List<_TagStat> tagStats; // 태그 → 회의 수/평균 시간

  const _StatsData({
    required this.totalMeetings,
    required this.totalSeconds,
    required this.monthlyCount,
    required this.topParticipants,
    required this.durationBuckets,
    required this.heatmap,
    required this.topKeywords,
    required this.tagStats,
  });
}

class _TagStat {
  final String tag;
  final int count;
  final int totalSeconds;
  const _TagStat(this.tag, this.count, this.totalSeconds);
  int get avgSeconds => count == 0 ? 0 : totalSeconds ~/ count;
}

// ── 다이얼로그 ─────────────────────────────────────────────────────────
class _StatsDialog extends ConsumerStatefulWidget {
  const _StatsDialog();

  @override
  ConsumerState<_StatsDialog> createState() => _StatsDialogState();
}

class _StatsDialogState extends ConsumerState<_StatsDialog> {
  _StatsData? _data;
  bool _loading = true;
  Set<String> _glossaryTerms = {}; // lowercase term + aliases

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = IsarService.instance.db;
    final meetings = await MeetingRepositoryImpl(db).getAllMeetings();
    final summaries = await SummaryRepositoryImpl(db).getAllSummaries();
    final entries = await GlossaryRepositoryImpl(db).getAllEntries();
    final terms = <String>{};
    for (final e in entries) {
      terms.add(e.term.toLowerCase());
      for (final a in e.aliasList) {
        terms.add(a.toLowerCase());
      }
    }
    setState(() {
      _data = _compute(meetings, summaries);
      _glossaryTerms = terms;
      _loading = false;
    });
  }

  Future<void> _addToGlossary(String term) async {
    final added = await showAddGlossaryDialog(context, prefilledTerm: term);
    if (added != null && mounted) {
      setState(() {
        _glossaryTerms.add(added.term.toLowerCase());
        for (final a in added.aliasList) {
          _glossaryTerms.add(a.toLowerCase());
        }
      });
    }
  }

  _StatsData _compute(List<Meeting> meetings, List<Summary> summaries) {
    // 총 녹음 시간
    final totalSeconds = meetings.fold<int>(0, (s, m) => s + m.durationSeconds);

    // 월별 횟수 (최근 6개월)
    final now = DateTime.now();
    final Map<String, int> monthly = {};
    for (int i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      monthly[key] = 0;
    }
    for (final m in meetings) {
      final key =
          '${m.createdAt.year}-${m.createdAt.month.toString().padLeft(2, '0')}';
      if (monthly.containsKey(key)) {
        monthly[key] = (monthly[key] ?? 0) + 1;
      }
    }

    // 자주 등장한 참석자 (요약에서 추출)
    final Map<String, int> freq = {};
    for (final s in summaries) {
      for (final p in s.participants) {
        final name = p.trim();
        if (name.isNotEmpty) freq[name] = (freq[name] ?? 0) + 1;
      }
    }
    final top = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 회의 길이 분포 (0-15 / 15-30 / 30-60 / 60-120 / 120+ 분)
    final bucketOrder = <String>['~15분', '15–30분', '30–60분', '1–2시간', '2시간+'];
    final Map<String, int> buckets = {for (final k in bucketOrder) k: 0};
    for (final m in meetings) {
      final minutes = m.durationSeconds ~/ 60;
      if (minutes < 15) {
        buckets['~15분'] = buckets['~15분']! + 1;
      } else if (minutes < 30) {
        buckets['15–30분'] = buckets['15–30분']! + 1;
      } else if (minutes < 60) {
        buckets['30–60분'] = buckets['30–60분']! + 1;
      } else if (minutes < 120) {
        buckets['1–2시간'] = buckets['1–2시간']! + 1;
      } else {
        buckets['2시간+'] = buckets['2시간+']! + 1;
      }
    }
    final durationBuckets =
        bucketOrder.map((k) => MapEntry(k, buckets[k]!)).toList();

    // 주간 히트맵: 요일(월=0..일=6) × 시간대 6구간
    // 0:이른(~10), 1:오전(10-12), 2:점심(12-14), 3:오후(14-17), 4:마감(17-19), 5:야근(19~)
    final heatmap = List.generate(7, (_) => List<int>.filled(6, 0));
    for (final m in meetings) {
      final wd = (m.createdAt.weekday - 1) % 7; // DateTime.weekday: 월=1..일=7
      final h = m.createdAt.hour;
      final int hb;
      if (h < 10) {
        hb = 0;
      } else if (h < 12) {
        hb = 1;
      } else if (h < 14) {
        hb = 2;
      } else if (h < 17) {
        hb = 3;
      } else if (h < 19) {
        hb = 4;
      } else {
        hb = 5;
      }
      heatmap[wd][hb] += 1;
    }

    // 키워드 Top N (요약본 텍스트 기반)
    final Map<String, int> kwFreq = {};
    for (final s in summaries) {
      final buf = StringBuffer()
        ..writeln(s.meetingTitle)
        ..writeAll(s.keyDiscussions, '\n')
        ..writeln()
        ..writeAll(s.decisions, '\n')
        ..writeln()
        ..writeAll(s.openQuestions, '\n');
      for (final tok in _tokenize(buf.toString())) {
        kwFreq[tok] = (kwFreq[tok] ?? 0) + 1;
      }
    }
    final topKeywords = kwFreq.entries
        .where((e) => e.value >= 2) // 1회만 등장한 노이즈 제거
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 태그별 통계
    final Map<String, int> tagCount = {};
    final Map<String, int> tagSec = {};
    for (final m in meetings) {
      for (final t in m.tags) {
        final k = t.trim();
        if (k.isEmpty) continue;
        tagCount[k] = (tagCount[k] ?? 0) + 1;
        tagSec[k] = (tagSec[k] ?? 0) + m.durationSeconds;
      }
    }
    final tagStats = tagCount.entries
        .map((e) => _TagStat(e.key, e.value, tagSec[e.key] ?? 0))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return _StatsData(
      totalMeetings: meetings.length,
      totalSeconds: totalSeconds,
      monthlyCount: monthly,
      topParticipants: top.take(8).toList(),
      durationBuckets: durationBuckets,
      heatmap: heatmap,
      topKeywords: topKeywords.take(10).toList(),
      tagStats: tagStats.take(12).toList(),
    );
  }

  // 한국어 간이 토크나이저 + 불용어 필터
  static const _stopwords = <String>{
    // 일반 대명사/접속사/조사 파생
    '그리고', '그래서', '하지만', '그러나', '그러므로', '따라서', '또한', '또는', '혹은',
    '우리', '저희', '본인', '이것', '그것', '저것', '이번', '다음', '이전',
    '이런', '그런', '저런', '같은', '다른', '어떤', '모든', '여러',
    // 회의 도메인 일반어
    '회의', '관련', '내용', '부분', '경우', '정도', '수준', '필요', '진행',
    '논의', '검토', '확인', '결정', '공유', '보고', '예정', '사항', '현재',
    '가능', '대상', '처리', '작업', '업무', '요청', '답변', '질문', '의견',
    '제안', '방안', '방법', '결과', '문제', '이슈', '기본', '전체', '일부',
    '시작', '완료', '종료', '중점', '중심', '초점', '기준', '방향', '상황',
    // 시간/수치 표현
    '오늘', '내일', '어제', '금주', '차주', '금월', '차월', '금년', '내년',
    '시간', '분간', '주간', '월간', '연간',
    // 약한 연결어
    '이를', '이에', '위해', '통해', '대해', '관해', '한편', '특히', '다만',
    '더욱', '매우', '아주', '많이', '조금', '약간',
    // 영문 일반어
    'the', 'and', 'for', 'with', 'from', 'this', 'that', 'was', 'are', 'not',
  };

  static Iterable<String> _tokenize(String text) sync* {
    // 한글/영문/숫자 외 모두 구분자로
    final re = RegExp(r'[가-힣a-zA-Z][가-힣a-zA-Z0-9]+');
    for (final m in re.allMatches(text)) {
      final tok = m.group(0)!.toLowerCase();
      if (tok.length < 2) continue;
      if (tok.length > 20) continue;
      if (_stopwords.contains(tok)) continue;
      // 숫자만 있는 토큰 제외 (re로 필터되지만 방어)
      if (RegExp(r'^\d+$').hasMatch(tok)) continue;
      yield tok;
    }
  }

  String _fmtTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$h시간 $m분';
    return '$m분';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.bar_chart,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Text('회의 통계',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_data != null)
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSummaryCards(),
                      const SizedBox(height: 24),
                      _buildMonthlyChart(),
                      const SizedBox(height: 24),
                      _buildDurationHistogram(),
                      const SizedBox(height: 24),
                      _buildHeatmap(),
                      const SizedBox(height: 24),
                      _buildKeywords(),
                      const SizedBox(height: 24),
                      _buildTagCloud(),
                      const SizedBox(height: 24),
                      _buildTags(),
                      const SizedBox(height: 24),
                      _buildParticipants(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 요약 카드 (총 회의 수 + 총 녹음 시간) ──────────────────────────
  Widget _buildSummaryCards() {
    final d = _data!;
    final now = DateTime.now();
    final thisMonthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final thisMonthCount = d.monthlyCount[thisMonthKey] ?? 0;

    return Row(children: [
      Expanded(
        child: _StatCard(
          icon: Icons.meeting_room_outlined,
          label: '전체 회의',
          value: '${d.totalMeetings}건',
          color: Colors.indigo,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _StatCard(
          icon: Icons.calendar_month_outlined,
          label: '이번 달',
          value: '$thisMonthCount건',
          color: Colors.teal,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _StatCard(
          icon: Icons.timer_outlined,
          label: '총 녹음',
          value: d.totalSeconds > 0 ? _fmtTime(d.totalSeconds) : '-',
          color: Colors.deepPurple,
        ),
      ),
    ]);
  }

  // ── 월별 회의 수 바 차트 ────────────────────────────────────────────
  Widget _buildMonthlyChart() {
    final d = _data!;
    if (d.monthlyCount.isEmpty) return const SizedBox.shrink();

    final maxCount =
        d.monthlyCount.values.fold(0, (a, b) => a > b ? a : b).clamp(1, 999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.bar_chart,
              size: 15,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text('최근 6개월',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary)),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: d.monthlyCount.entries.map((e) {
              final ratio = e.value / maxCount;
              final label = e.key.substring(5); // 'MM'만
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${e.value}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: e.value > 0
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade400)),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        height: (80 * ratio).clamp(4, 80),
                        decoration: BoxDecoration(
                          color: e.value > 0
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.75)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('$label월',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── 회의 길이 분포 히스토그램 ──────────────────────────────────────
  Widget _buildDurationHistogram() {
    final d = _data!;
    final total = d.durationBuckets.fold<int>(0, (s, e) => s + e.value);
    if (total == 0) return const SizedBox.shrink();

    final maxCount = d.durationBuckets
        .map((e) => e.value)
        .fold(0, (a, b) => a > b ? a : b)
        .clamp(1, 999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.timelapse,
              size: 15, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text('회의 길이 분포',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary)),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: d.durationBuckets.map((e) {
              final ratio = e.value / maxCount;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${e.value}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: e.value > 0
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade400)),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        height: (80 * ratio).clamp(4, 80),
                        decoration: BoxDecoration(
                          color: e.value > 0
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.75)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(e.key,
                          style: TextStyle(
                              fontSize: 10.5, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── 주간 히트맵 (요일 × 시간대) ────────────────────────────────────
  Widget _buildHeatmap() {
    final hm = _data!.heatmap;
    int maxVal = 0;
    for (final row in hm) {
      for (final v in row) {
        if (v > maxVal) maxVal = v;
      }
    }
    if (maxVal == 0) return const SizedBox.shrink();

    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    const timeLabels = ['이른', '오전', '점심', '오후', '마감', '야근'];
    final primary = Theme.of(context).colorScheme.primary;

    Color cellColor(int v) {
      if (v == 0) return Colors.grey.shade100;
      final intensity = (v / maxVal).clamp(0.15, 1.0);
      return primary.withValues(alpha: intensity * 0.85);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.grid_view_outlined,
              size: 15, color: primary),
          const SizedBox(width: 6),
          Text('요일 × 시간대',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: primary)),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              // 헤더 (시간대 라벨)
              Row(children: [
                const SizedBox(width: 28),
                ...timeLabels.map((t) => Expanded(
                      child: Center(
                        child: Text(t,
                            style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.grey.shade600)),
                      ),
                    )),
              ]),
              const SizedBox(height: 6),
              // 본문 (요일 행)
              for (int wd = 0; wd < 7; wd++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    SizedBox(
                      width: 28,
                      child: Text(weekdays[wd],
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700)),
                    ),
                    for (int tb = 0; tb < 6; tb++)
                      Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 2),
                          child: Container(
                            height: 26,
                            decoration: BoxDecoration(
                              color: cellColor(hm[wd][tb]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            alignment: Alignment.center,
                            child: hm[wd][tb] > 0
                                ? Text(
                                    '${hm[wd][tb]}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: (hm[wd][tb] / maxVal) > 0.55
                                          ? Colors.white
                                          : primary,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ]),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 키워드 Top N (요약본 기반) ─────────────────────────────────────
  Widget _buildKeywords() {
    final kws = _data!.topKeywords;
    final primary = Theme.of(context).colorScheme.primary;

    Widget header = Row(children: [
      Icon(Icons.tag, size: 15, color: primary),
      const SizedBox(width: 6),
      Text('자주 등장한 키워드',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: primary)),
    ]);

    if (kws.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 8),
          Text('요약된 회의 데이터가 부족합니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      );
    }

    final maxFreq = kws.first.value.clamp(1, 9999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('칩을 클릭하면 단어집에 추가할 수 있습니다. ✓ 는 이미 등록됨',
                  style: TextStyle(
                      fontSize: 10.5, color: Colors.grey.shade500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kws.map((e) {
                  final ratio = e.value / maxFreq;
                  final bg = primary.withValues(alpha: 0.08 + 0.25 * ratio);
                  final fg = primary.withValues(alpha: 0.75 + 0.25 * ratio);
                  final inGlossary =
                      _glossaryTerms.contains(e.key.toLowerCase());
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: inGlossary ? null : () => _addToGlossary(e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: inGlossary
                            ? Colors.green.withValues(alpha: 0.1)
                            : bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: inGlossary
                                ? Colors.green.withValues(alpha: 0.3)
                                : primary.withValues(alpha: 0.15)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (inGlossary) ...[
                          Icon(Icons.check_circle,
                              size: 12,
                              color: Colors.green.withValues(alpha: 0.7)),
                          const SizedBox(width: 4),
                        ],
                        Text(e.key,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: inGlossary
                                    ? Colors.green.shade700
                                    : fg)),
                        const SizedBox(width: 6),
                        Text('${e.value}',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600)),
                        if (!inGlossary) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.add_circle_outline,
                              size: 13, color: fg),
                        ],
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 태그 클라우드 — 빈도에 따라 폰트 크기 변하는 시각적 표현.
  /// 클릭 시 사이드바 검색에 자동 입력 + 다이얼로그 닫기.
  Widget _buildTagCloud() {
    final stats = _data!.tagStats;
    final primary = Theme.of(context).colorScheme.primary;

    final header = Row(children: [
      Icon(Icons.cloud_outlined, size: 15, color: primary),
      const SizedBox(width: 6),
      Text('태그 클라우드',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: primary)),
      const SizedBox(width: 6),
      Text('· 클릭하면 검색됩니다',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
    ]);

    if (stats.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 8),
          Text('회의에 태그가 추가되면 여기에 표시됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      );
    }

    final maxCount = stats.first.count;
    final minCount = stats.last.count;

    double sizeFor(int count) {
      if (maxCount == minCount) return 14;
      // 빈도에 비례한 폰트 크기 (10 ~ 20)
      final ratio = (count - minCount) / (maxCount - minCount);
      return 11 + 11 * ratio;
    }

    double opacityFor(int count) {
      if (maxCount == minCount) return 0.7;
      final ratio = (count - minCount) / (maxCount - minCount);
      return 0.45 + 0.55 * ratio;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: stats.map((s) {
              final fontSize = sizeFor(s.count);
              final alpha = opacityFor(s.count);
              return Tooltip(
                message: '#${s.tag} · ${s.count}회 회의',
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _searchByTag(s.tag),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: fontSize * 0.6,
                      vertical: fontSize * 0.25,
                    ),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: alpha * 0.15),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: primary.withValues(alpha: alpha * 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '#${s.tag}',
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w700,
                            color: primary.withValues(alpha: alpha),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${s.count}',
                          style: TextStyle(
                            fontSize: fontSize * 0.65,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// 태그 → 사이드바 검색 자동 입력 + 다이얼로그 닫기
  void _searchByTag(String tag) {
    ref.read(searchQueryProvider.notifier).state = tag;
    ref.read(isAiSearchModeProvider.notifier).state = false;
    ref.read(aiSearchResultsProvider.notifier).state = null;
    ref
        .read(shortcutFocusSearchSignalProvider.notifier)
        .update((s) => s + 1);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('태그 "$tag"로 검색합니다'),
        backgroundColor: Colors.indigo.shade600,
      ),
    );
  }

  // ── 자주 등장한 참석자 ─────────────────────────────────────────────
  Widget _buildTags() {
    final stats = _data!.tagStats;
    final header = Row(children: [
      Icon(Icons.sell_outlined,
          size: 15, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 6),
      Text('태그별 분석',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary)),
    ]);

    if (stats.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 8),
          Text('회의 상세에서 태그를 추가하면 여기에 분석이 표시됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      );
    }

    final maxCount = stats.first.count.clamp(1, 9999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: stats.map((s) {
              final ratio = s.count / maxCount;
              return InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _searchByTag(s.tag),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        '#${s.tag}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo.shade700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(
                              Colors.indigo.shade400),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      child: Text('${s.count}회',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 70,
                      child: Text('평균 ${_fmtTime(s.avgSeconds)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                    ),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildParticipants() {
    final top = _data!.topParticipants;
    if (top.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.people_outline,
                size: 15,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text('자주 등장한 참석자',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary)),
          ]),
          const SizedBox(height: 8),
          Text('요약된 회의에서 참석자 정보가 없습니다.',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      );
    }

    final maxFreq = top.first.value.clamp(1, 999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.people_outline,
              size: 15,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text('자주 등장한 참석자',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary)),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: top.map((e) {
              final ratio = e.value / maxFreq;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      e.key,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(
                          Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${e.value}회',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                ]),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── 요약 카드 위젯 ─────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color.withValues(alpha: 0.8)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
