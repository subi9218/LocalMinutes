import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/isar_service.dart';
import '../../data/repositories/summary_repository_impl.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/entities/summary.dart';
import '../providers/meeting_providers.dart';

enum _ActionStatusFilter { open, all, done }

class _ActionEntry {
  final Summary summary;
  final Meeting? meeting;
  final ActionItem item;
  final int index;

  const _ActionEntry({
    required this.summary,
    required this.meeting,
    required this.item,
    required this.index,
  });
}

Future<void> showActionItemsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ActionItemsDialog(),
  );
}

class _ActionItemsDialog extends ConsumerStatefulWidget {
  const _ActionItemsDialog();

  @override
  ConsumerState<_ActionItemsDialog> createState() => _ActionItemsDialogState();
}

class _ActionItemsDialogState extends ConsumerState<_ActionItemsDialog> {
  _ActionStatusFilter _status = _ActionStatusFilter.open;
  String _owner = '';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final meetingsAsync = ref.watch(meetingsProvider);
    final summariesAsync = ref.watch(allSummariesProvider);
    final meetings = meetingsAsync.asData?.value ?? const <Meeting>[];
    final summaries = summariesAsync.asData?.value ?? const <Summary>[];
    final loading = meetingsAsync.isLoading || summariesAsync.isLoading;

    final entries = _collectEntries(meetings, summaries);
    final owners =
        entries
            .map((e) => e.item.owner.trim())
            .where((o) => o.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (_owner.isNotEmpty && !owners.contains(_owner)) _owner = '';

    final filtered = entries.where(_matchesFilters).toList();
    final openCount = entries.where((e) => !e.item.completed).length;
    final doneCount = entries.length - openCount;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: [
          Icon(Icons.checklist_outlined, color: Colors.indigo.shade600),
          const SizedBox(width: 8),
          const Expanded(child: Text('전체 할 일')),
          IconButton(
            tooltip: '새로고침',
            onPressed: () {
              ref.invalidate(meetingsProvider);
              ref.invalidate(allSummariesProvider);
            },
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 860,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStats(openCount, doneCount),
            const SizedBox(height: 12),
            _buildFilters(owners),
            const SizedBox(height: 12),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildList(filtered),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }

  Widget _buildStats(int openCount, int doneCount) {
    return Row(
      children: [
        _StatPill(
          icon: Icons.radio_button_unchecked,
          label: '미완료',
          value: '$openCount',
          color: Colors.orange.shade700,
        ),
        const SizedBox(width: 8),
        _StatPill(
          icon: Icons.check_circle_outline,
          label: '완료',
          value: '$doneCount',
          color: Colors.green.shade700,
        ),
      ],
    );
  }

  Widget _buildFilters(List<String> owners) {
    return Row(
      children: [
        SegmentedButton<_ActionStatusFilter>(
          segments: const [
            ButtonSegment(
              value: _ActionStatusFilter.open,
              icon: Icon(Icons.radio_button_unchecked, size: 15),
              label: Text('미완료'),
            ),
            ButtonSegment(
              value: _ActionStatusFilter.all,
              icon: Icon(Icons.list_alt, size: 15),
              label: Text('전체'),
            ),
            ButtonSegment(
              value: _ActionStatusFilter.done,
              icon: Icon(Icons.check_circle_outline, size: 15),
              label: Text('완료'),
            ),
          ],
          selected: {_status},
          onSelectionChanged: (v) => setState(() => _status = v.first),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            initialValue: _owner.isEmpty ? null : _owner,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '담당자',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: owners
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (v) => setState(() => _owner = v ?? ''),
          ),
        ),
        if (_owner.isNotEmpty) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: '담당자 필터 해제',
            onPressed: () => setState(() => _owner = ''),
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
              hintText: '할 일, 회의 제목, 마감 검색',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<_ActionEntry> entries) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          '조건에 맞는 할 일이 없습니다.',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final item = entry.item;
        final meetingTitle = entry.meeting?.title ?? '삭제된 회의';
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 4,
          ),
          leading: Checkbox(
            value: item.completed,
            onChanged: (v) => _toggle(entry, v ?? false),
            visualDensity: VisualDensity.compact,
          ),
          title: Text(
            item.task,
            style: TextStyle(
              decoration: item.completed ? TextDecoration.lineThrough : null,
              color: item.completed ? Colors.grey.shade500 : null,
              fontWeight: item.completed ? FontWeight.normal : FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _MetaChip(
                  icon: Icons.description_outlined,
                  label: meetingTitle,
                ),
                if (item.owner.isNotEmpty)
                  _MetaChip(icon: Icons.person_outline, label: item.owner),
                if (item.deadline.isNotEmpty)
                  _MetaChip(
                    icon: Icons.event_outlined,
                    label: item.deadline,
                    color: Colors.orange.shade700,
                  ),
              ],
            ),
          ),
          trailing: IconButton(
            tooltip: '회의 열기',
            icon: const Icon(Icons.open_in_new, size: 18),
            onPressed: entry.meeting == null
                ? null
                : () {
                    ref.read(isRecordingActiveProvider.notifier).state = false;
                    ref.read(selectedMeetingIdProvider.notifier).state =
                        entry.summary.meetingId;
                    Navigator.of(context).pop();
                  },
          ),
        );
      },
    );
  }

  List<_ActionEntry> _collectEntries(
    List<Meeting> meetings,
    List<Summary> summaries,
  ) {
    final meetingById = {for (final m in meetings) m.id: m};
    final entries = <_ActionEntry>[];
    for (final summary in summaries) {
      final items = _parseItems(summary.actionItemsJson);
      for (int i = 0; i < items.length; i++) {
        entries.add(
          _ActionEntry(
            summary: summary,
            meeting: meetingById[summary.meetingId],
            item: items[i],
            index: i,
          ),
        );
      }
    }
    entries.sort((a, b) {
      if (a.item.completed != b.item.completed) {
        return a.item.completed ? 1 : -1;
      }
      final ad = a.item.deadline.trim();
      final bd = b.item.deadline.trim();
      if (ad.isEmpty != bd.isEmpty) return ad.isEmpty ? 1 : -1;
      final byDeadline = ad.compareTo(bd);
      if (byDeadline != 0) return byDeadline;
      final at = a.meeting?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.meeting?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return entries;
  }

  bool _matchesFilters(_ActionEntry entry) {
    if (_status == _ActionStatusFilter.open && entry.item.completed) {
      return false;
    }
    if (_status == _ActionStatusFilter.done && !entry.item.completed) {
      return false;
    }

    if (_owner.isNotEmpty && entry.item.owner.trim() != _owner) return false;
    if (_query.isEmpty) return true;

    final haystack = [
      entry.item.task,
      entry.item.owner,
      entry.item.deadline,
      entry.meeting?.title ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(_query);
  }

  List<ActionItem> _parseItems(String raw) {
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ActionItem.fromJson(e as Map<String, dynamic>))
          .where((e) => e.task.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _toggle(_ActionEntry entry, bool completed) async {
    final items = _parseItems(entry.summary.actionItemsJson);
    if (entry.index < 0 || entry.index >= items.length) return;
    items[entry.index] = items[entry.index].copyWith(completed: completed);
    entry.summary.actionItemsJson = jsonEncode(
      items.map((item) => item.toJson()).toList(),
    );
    await SummaryRepositoryImpl(
      IsarService.instance.db,
    ).saveSummary(entry.summary);
    ref.invalidate(allSummariesProvider);
    ref.invalidate(meetingSummaryProvider(entry.summary.meetingId));
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MetaChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Colors.grey.shade600;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: effectiveColor),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: effectiveColor),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
