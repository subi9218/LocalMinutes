import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../core/services/isar_service.dart';
import '../../core/services/meeting_comparison.dart';
import '../../core/services/meeting_series_progress.dart';
import '../../data/repositories/meeting_repository_impl.dart';
import '../../data/repositories/summary_repository_impl.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/entities/meeting_group.dart';
import '../providers/meeting_providers.dart';

/// 정기 회의 시리즈 진행 대시보드 (P2 #9 Phase 2).
///
/// 그룹 헤더의 시계열 아이콘 클릭 시 [selectedGroupIdProvider] 가 세팅되고
/// 메인 영역에 이 위젯이 표시된다. 닫기 또는 회의 클릭 시 자동 종료.
class SeriesDashboardView extends ConsumerWidget {
  final int groupId;
  const SeriesDashboardView({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsProvider);
    final reportAsync = ref.watch(seriesProgressProvider(groupId));
    // Phase 3b: macOS 친화 톤 — accent 색은 MacosTheme.primaryColor, 헤더 폰트는 typography.title2.
    final accent = MacosTheme.of(context).primaryColor;
    final titleStyle = MacosTheme.of(
      context,
    ).typography.title2.copyWith(fontWeight: FontWeight.w700);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 헤더 ────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.timeline, size: 22, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: groupsAsync.when(
                  data: (groups) {
                    final group = _findGroup(groups, groupId);
                    return Text(
                      group?.name ?? '시리즈',
                      style: titleStyle,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ),
              MacosTooltip(
                message: '회의 비교',
                child: MacosIconButton(
                  icon: const Icon(Icons.compare_arrows, size: 18),
                  backgroundColor: Colors.transparent,
                  onPressed: () => _showComparePicker(context, ref, groupId),
                  boxConstraints: const BoxConstraints(
                    minHeight: 26,
                    minWidth: 26,
                    maxWidth: 26,
                    maxHeight: 26,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              MacosTooltip(
                message: '닫기',
                child: MacosIconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () =>
                      ref.read(selectedGroupIdProvider.notifier).state = null,
                  boxConstraints: const BoxConstraints(
                    minHeight: 26,
                    minWidth: 26,
                    maxWidth: 26,
                    maxHeight: 26,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: reportAsync.when(
              loading: () => const Center(child: ProgressCircle()),
              error: (e, _) => Center(child: Text('진행 분석 오류: $e')),
              data: (report) {
                if (report.isEmpty) {
                  return Center(
                    child: Text(
                      '이 시리즈에 회의가 아직 없습니다.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  );
                }
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MetaRow(report: report),
                      const SizedBox(height: 12),
                      _PendingActionsCard(report: report, ref: ref),
                      const SizedBox(height: 12),
                      _ActionTimelineCard(report: report, ref: ref),
                      const SizedBox(height: 12),
                      _RecurringIssuesCard(report: report, ref: ref),
                      const SizedBox(height: 12),
                      _RecentDecisionsCard(report: report, ref: ref),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static MeetingGroup? _findGroup(List<MeetingGroup> groups, int id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  void _showComparePicker(BuildContext context, WidgetRef ref, int groupId) {
    showMacosSheet<void>(
      context: context,
      builder: (ctx) => _CompareSheet(groupId: groupId),
    );
  }
}

// ── 상단 메타 정보 줄 ──────────────────────────────────────────────
class _MetaRow extends StatelessWidget {
  final SeriesProgressReport report;
  const _MetaRow({required this.report});

  @override
  Widget build(BuildContext context) {
    final last = report.lastMeetingAt;
    final daysAgo = last == null
        ? null
        : DateTime.now().difference(last).inDays;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetaChip(
          icon: Icons.event_repeat,
          label: '회의 ${report.meetingCount}회',
        ),
        if (report.averageIntervalDays != null)
          _MetaChip(
            icon: Icons.schedule,
            label: '평균 주기 ${report.averageIntervalDays}일',
          ),
        if (daysAgo != null)
          _MetaChip(
            icon: Icons.history,
            label: daysAgo == 0 ? '오늘 회의' : '마지막 $daysAgo일 전',
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }
}

// ── 누적 미완료 액션 카드 ──────────────────────────────────────────
class _PendingActionsCard extends StatelessWidget {
  final SeriesProgressReport report;
  final WidgetRef ref;
  const _PendingActionsCard({required this.report, required this.ref});

  @override
  Widget build(BuildContext context) {
    final items = report.pendingActionItems;
    return _SectionShell(
      icon: Icons.check_circle_outline,
      title: '누적 미완료 액션',
      countLabel: '${items.length}건',
      empty: items.isEmpty,
      emptyText: '미완료 액션이 없습니다.',
      child: Column(
        children: [
          for (final p in items)
            _ActionRow(item: p, onJump: () => _jumpToMeeting(ref, p.meetingId)),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final PendingActionItem item;
  final VoidCallback onJump;
  const _ActionRow({required this.item, required this.onJump});

  @override
  Widget build(BuildContext context) {
    final ai = item.item;
    final ownerVague = ai.ownerNeedsConfirmation;
    final deadlineVague = ai.deadlineNeedsConfirmation;

    return InkWell(
      onTap: onJump,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.radio_button_unchecked,
              size: 14,
              color: Colors.grey.shade500,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ai.task, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _MiniMeta(
                        icon: Icons.person_outline,
                        text: ai.owner.isEmpty ? '(미언급)' : ai.owner,
                        warn: ownerVague,
                      ),
                      _MiniMeta(
                        icon: Icons.calendar_today_outlined,
                        text: ai.deadline.isEmpty ? '(미언급)' : ai.deadline,
                        warn: deadlineVague,
                      ),
                      _MiniMeta(
                        icon: Icons.folder_outlined,
                        text: item.meetingTitle,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_ios,
              size: 11,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMeta extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool warn;
  const _MiniMeta({required this.icon, required this.text, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final color = warn ? Colors.amber.shade800 : Colors.grey.shade600;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: warn ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

// ── 반복 등장 이슈 카드 ────────────────────────────────────────────
class _RecurringIssuesCard extends StatelessWidget {
  final SeriesProgressReport report;
  final WidgetRef ref;
  const _RecurringIssuesCard({required this.report, required this.ref});

  @override
  Widget build(BuildContext context) {
    final issues = report.recurringIssues;
    return _SectionShell(
      icon: Icons.flag_outlined,
      title: '반복 등장 미해결 이슈',
      countLabel: '${issues.length}건',
      empty: issues.isEmpty,
      emptyText: '여러 회에 반복 등장한 이슈가 없습니다.',
      child: Column(
        children: [
          for (final i in issues)
            _IssueRow(issue: i, onJump: (mid) => _jumpToMeeting(ref, mid)),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final RecurringIssue issue;
  final void Function(int meetingId) onJump;
  const _IssueRow({required this.issue, required this.onJump});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  '${issue.count}회 등장',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(issue.text, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final a in issue.appearances)
                ActionChip(
                  label: Text(
                    '${a.meetingTitle} · ${_dateOnly(a.date)}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  onPressed: () => onJump(a.meetingId),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 최근 결정 카드 ────────────────────────────────────────────────
class _RecentDecisionsCard extends StatelessWidget {
  final SeriesProgressReport report;
  final WidgetRef ref;
  const _RecentDecisionsCard({required this.report, required this.ref});

  @override
  Widget build(BuildContext context) {
    final decisions = report.recentDecisions;
    return _SectionShell(
      icon: Icons.gavel_outlined,
      title: '최근 결정 사항',
      countLabel: '${decisions.length}건',
      empty: decisions.isEmpty,
      emptyText: '결정 사항이 아직 없습니다.',
      child: Column(
        children: [
          for (final d in decisions)
            InkWell(
              onTap: () => _jumpToMeeting(ref, d.meetingId),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.task_alt,
                      size: 14,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.text, style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            '${d.meetingTitle} · ${_dateOnly(d.meetingDate)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 11,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 공통 카드 셸 ──────────────────────────────────────────────────
class _SectionShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String countLabel;
  final bool empty;
  final String emptyText;
  final Widget child;

  const _SectionShell({
    required this.icon,
    required this.title,
    required this.countLabel,
    required this.empty,
    required this.emptyText,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                countLabel,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (empty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                emptyText,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            )
          else
            child,
        ],
      ),
    );
  }
}

// ── 액션 타임라인 카드 ─────────────────────────────────────────────
class _ActionTimelineCard extends StatelessWidget {
  final SeriesProgressReport report;
  final WidgetRef ref;
  const _ActionTimelineCard({required this.report, required this.ref});

  @override
  Widget build(BuildContext context) {
    final tracked = report.actionTimeline;
    return _SectionShell(
      icon: Icons.timeline,
      title: '액션 회차별 변화',
      countLabel: '${tracked.length}건',
      empty: tracked.isEmpty,
      emptyText: '회차에 걸쳐 추적할 액션이 없습니다.',
      child: Column(
        children: [
          for (final t in tracked)
            _TrackedActionRow(tracked: t, onJump: _jumpToMeeting),
        ],
      ),
    );
  }
}

class _TrackedActionRow extends StatelessWidget {
  final TrackedAction tracked;
  final void Function(WidgetRef, int) onJump;
  const _TrackedActionRow({required this.tracked, required this.onJump});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final last = tracked.lastAppearance;
        return InkWell(
          onTap: () => onJump(ref, last.meetingId),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // task + status badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        tracked.task,
                        style: TextStyle(
                          fontSize: 13,
                          decoration:
                              tracked.status == TrackedActionStatus.resolved
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          color: tracked.status == TrackedActionStatus.resolved
                              ? Colors.grey.shade500
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(status: tracked.status),
                  ],
                ),
                const SizedBox(height: 4),
                // 회차별 작은 점들 + 변경 표식
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${tracked.appearances.length}회 등장',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (tracked.hasOwnerChange)
                      _ChangeBadge(icon: Icons.person_outline, label: '담당자 변경'),
                    if (tracked.hasDeadlineChange)
                      _ChangeBadge(
                        icon: Icons.calendar_today_outlined,
                        label: '마감 변경',
                      ),
                    Text(
                      '· ${_dateOnly(tracked.firstAppearance.meetingDate)} → ${_dateOnly(last.meetingDate)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final TrackedActionStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      TrackedActionStatus.resolved => ('완료', Colors.green.shade700),
      TrackedActionStatus.dropped => ('이후 미등장', Colors.amber.shade700),
      TrackedActionStatus.ongoing => ('진행 중', Colors.indigo.shade600),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ChangeBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.orange.shade800),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.orange.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 회의로 점프: 대시보드 닫고 회의 상세 표시 ──────────────────────
void _jumpToMeeting(WidgetRef ref, int meetingId) {
  ref.read(selectedGroupIdProvider.notifier).state = null;
  ref.read(selectedMeetingIdProvider.notifier).state = meetingId;
}

String _dateOnly(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

// ── 회의 비교 시트 ─────────────────────────────────────────────────
class _CompareSheet extends StatefulWidget {
  final int groupId;
  const _CompareSheet({required this.groupId});

  @override
  State<_CompareSheet> createState() => _CompareSheetState();
}

class _CompareSheetState extends State<_CompareSheet> {
  late Future<List<Meeting>> _meetingsFuture;
  Meeting? _earlier;
  Meeting? _later;
  Future<MeetingComparisonReport>? _reportFuture;

  @override
  void initState() {
    super.initState();
    _meetingsFuture = _loadMeetings();
  }

  Future<List<Meeting>> _loadMeetings() async {
    final db = IsarService.instance.db;
    final all = await MeetingRepositoryImpl(
      db,
    ).getMeetingsByGroupId(widget.groupId);
    // 옛날 → 최신 순
    all.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (all.length >= 2) {
      _earlier = all[all.length - 2];
      _later = all.last;
      _reportFuture = _runComparison(_earlier!, _later!);
    }
    return all;
  }

  Future<MeetingComparisonReport> _runComparison(Meeting a, Meeting b) async {
    final db = IsarService.instance.db;
    final repo = SummaryRepositoryImpl(db);
    final sa = await repo.getSummaryByMeetingId(a.id);
    final sb = await repo.getSummaryByMeetingId(b.id);
    return MeetingComparison.compare(
      earlier: a,
      later: b,
      earlierSummary: sa,
      laterSummary: sb,
    );
  }

  void _onPick(Meeting m, {required bool isEarlier}) {
    setState(() {
      if (isEarlier) {
        _earlier = m;
      } else {
        _later = m;
      }
      if (_earlier != null && _later != null && _earlier!.id != _later!.id) {
        // 시간순 보정
        Meeting a = _earlier!;
        Meeting b = _later!;
        if (a.createdAt.isAfter(b.createdAt)) {
          final tmp = a;
          a = b;
          b = tmp;
        }
        _earlier = a;
        _later = b;
        _reportFuture = _runComparison(a, b);
      } else {
        _reportFuture = null;
      }
    });
  }

  String _meetingLabel(Meeting m) {
    final d = m.createdAt;
    final ds =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '$ds  ·  ${m.title}';
  }

  @override
  Widget build(BuildContext context) {
    return MacosSheet(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<List<Meeting>>(
            future: _meetingsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: ProgressCircle());
              }
              if (snap.hasError) {
                return Center(child: Text('오류: ${snap.error}'));
              }
              final meetings = snap.data ?? const <Meeting>[];
              if (meetings.length < 2) {
                return _emptyState(context, '비교하려면 시리즈에 회의가 2회 이상 있어야 합니다.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.compare_arrows,
                        size: 22,
                        color: MacosTheme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '회의 비교',
                        style: MacosTheme.of(context).typography.title2
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      MacosTooltip(
                        message: '닫기',
                        child: MacosIconButton(
                          icon: const Icon(Icons.close, size: 18),
                          backgroundColor: Colors.transparent,
                          boxConstraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                            maxWidth: 26,
                            maxHeight: 26,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // picker 두 개
                  Row(
                    children: [
                      Expanded(
                        child: _CompareDropdown(
                          label: '이전 회의',
                          meetings: meetings,
                          selected: _earlier,
                          formatLabel: _meetingLabel,
                          onChanged: (m) => _onPick(m, isEarlier: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.arrow_right_alt, color: Colors.grey.shade500),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _CompareDropdown(
                          label: '이후 회의',
                          meetings: meetings,
                          selected: _later,
                          formatLabel: _meetingLabel,
                          onChanged: (m) => _onPick(m, isEarlier: false),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: _reportFuture == null
                        ? _emptyState(context, '두 회의를 선택하면 비교 결과가 표시됩니다.')
                        : FutureBuilder<MeetingComparisonReport>(
                            future: _reportFuture,
                            builder: (context, rs) {
                              if (rs.connectionState != ConnectionState.done) {
                                return const Center(child: ProgressCircle());
                              }
                              if (rs.hasError) {
                                return Center(child: Text('오류: ${rs.error}'));
                              }
                              final r = rs.data!;
                              if (!r.hasContent) {
                                return _emptyState(
                                  context,
                                  '두 회의 모두 요약이 비어 있습니다.',
                                );
                              }
                              return SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _CompareSection(
                                      title: '결정 사항',
                                      icon: Icons.gavel_rounded,
                                      diff: r.decisions,
                                    ),
                                    const SizedBox(height: 10),
                                    _CompareSection(
                                      title: '미해결 이슈',
                                      icon: Icons.help_outline,
                                      diff: r.openQuestions,
                                    ),
                                    const SizedBox(height: 10),
                                    _CompareActionsSection(diff: r.actions),
                                    const SizedBox(height: 10),
                                    _CompareSection(
                                      title: '주요 논의',
                                      icon: Icons.forum_outlined,
                                      diff: r.keyDiscussions,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compare_arrows, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareDropdown extends StatelessWidget {
  final String label;
  final List<Meeting> meetings;
  final Meeting? selected;
  final String Function(Meeting) formatLabel;
  final ValueChanged<Meeting> onChanged;
  const _CompareDropdown({
    required this.label,
    required this.meetings,
    required this.selected,
    required this.formatLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: selected?.id,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final m in meetings)
              DropdownMenuItem(
                value: m.id,
                child: Text(
                  formatLabel(m),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
          onChanged: (id) {
            if (id == null) return;
            final m = meetings.firstWhere((x) => x.id == id);
            onChanged(m);
          },
        ),
      ],
    );
  }
}

class _CompareSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final StringDiff diff;
  const _CompareSection({
    required this.title,
    required this.icon,
    required this.diff,
  });

  @override
  Widget build(BuildContext context) {
    if (!diff.hasContent) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: MacosTheme.of(context).primaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _CountChip(
                  label: '+${diff.added.length}',
                  color: Colors.green.shade700,
                ),
                const SizedBox(width: 4),
                _CountChip(
                  label: '−${diff.removed.length}',
                  color: Colors.red.shade600,
                ),
                const SizedBox(width: 4),
                _CountChip(
                  label: '·${diff.shared.length}',
                  color: Colors.grey.shade600,
                ),
              ],
            ),
            const Divider(height: 12),
            for (final s in diff.added)
              _DiffRow(
                marker: '+',
                color: Colors.green.shade700,
                text: s,
                meta: '새로 등장',
              ),
            for (final s in diff.removed)
              _DiffRow(
                marker: '−',
                color: Colors.red.shade600,
                text: s,
                meta: '이후 회의에서 사라짐',
              ),
            for (final s in diff.shared)
              _DiffRow(
                marker: '·',
                color: Colors.grey.shade500,
                text: s.text,
                meta: '양쪽 회의에 등장',
              ),
          ],
        ),
      ),
    );
  }
}

class _CompareActionsSection extends StatelessWidget {
  final ActionDiff diff;
  const _CompareActionsSection({required this.diff});

  @override
  Widget build(BuildContext context) {
    if (!diff.hasContent) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 14,
                  color: MacosTheme.of(context).primaryColor,
                ),
                const SizedBox(width: 6),
                const Text(
                  '액션 아이템',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                _CountChip(
                  label: '+${diff.added.length}',
                  color: Colors.green.shade700,
                ),
                const SizedBox(width: 4),
                _CountChip(
                  label: '−${diff.removed.length}',
                  color: Colors.red.shade600,
                ),
                const SizedBox(width: 4),
                _CountChip(
                  label: '·${diff.shared.length}',
                  color: Colors.grey.shade600,
                ),
              ],
            ),
            const Divider(height: 12),
            for (final a in diff.added)
              _DiffRow(
                marker: '+',
                color: Colors.green.shade700,
                text: a.task,
                meta: a.owner.isEmpty ? '새 액션' : '새 액션 · ${a.owner}',
              ),
            for (final s in diff.shared)
              _DiffRow(
                marker: switch (s.status) {
                  ActionTransition.completed => '✓',
                  ActionTransition.reopened => '↺',
                  ActionTransition.stillCompleted => '✓',
                  ActionTransition.stillOpen => '·',
                },
                color: switch (s.status) {
                  ActionTransition.completed => Colors.green.shade700,
                  ActionTransition.reopened => Colors.orange.shade700,
                  ActionTransition.stillCompleted => Colors.grey.shade500,
                  ActionTransition.stillOpen => Colors.grey.shade500,
                },
                text: s.later.task,
                meta: _sharedActionMeta(s),
              ),
            for (final a in diff.removed)
              _DiffRow(
                marker: '−',
                color: Colors.red.shade600,
                text: a.task,
                meta: a.completed ? '완료된 액션 · 이후 회의에서 미등장' : '이후 회의에서 미등장',
              ),
          ],
        ),
      ),
    );
  }

  static String _sharedActionMeta(SharedAction s) {
    final parts = <String>[];
    parts.add(switch (s.status) {
      ActionTransition.completed => '완료됨 ✓',
      ActionTransition.reopened => '재오픈',
      ActionTransition.stillCompleted => '계속 완료 상태',
      ActionTransition.stillOpen => '진행 중',
    });
    if (s.ownerChanged) {
      parts.add('담당자 ${s.earlier.owner} → ${s.later.owner}');
    }
    if (s.deadlineChanged) {
      parts.add('마감 ${s.earlier.deadline} → ${s.later.deadline}');
    }
    return parts.join(' · ');
  }
}

class _DiffRow extends StatelessWidget {
  final String marker;
  final Color color;
  final String text;
  final String meta;
  const _DiffRow({
    required this.marker,
    required this.color,
    required this.text,
    required this.meta,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(
              marker,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: const TextStyle(fontSize: 13)),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    meta,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final Color color;
  const _CountChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
