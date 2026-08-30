import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/l10n/app_tr.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/digest_report.dart';
import '../../core/services/meeting_keyword_search.dart';
import '../../core/services/processing_status_service.dart';
import '../../core/services/recovery_service.dart';
import '../../core/services/series_overview.dart';
import '../../core/ffi/on_device_model_manager.dart';
import '../../core/services/isar_service.dart';
import '../../core/services/meeting_series_detector.dart';
import '../../core/services/search_service.dart';
import '../../data/datasources/audio_convert_service.dart';
import '../../data/datasources/microphone_service.dart';
import '../../data/datasources/llm_service.dart';
import '../../data/repositories/meeting_repository_impl.dart';
import '../../data/repositories/meeting_group_repository_impl.dart';
import '../../data/repositories/summary_repository_impl.dart';
import '../../data/repositories/summary_version_repository_impl.dart';
import '../../data/repositories/transcript_repository_impl.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/entities/meeting_group.dart';
import '../../domain/entities/meeting_processing_report.dart';
import '../../domain/entities/summary.dart';
import '../providers/meeting_providers.dart';
import '../screens/glossary_screen.dart';
import '../screens/action_items_screen.dart';
import '../screens/stats_screen.dart';
import 'app_version_credit.dart';
import 'app_notice.dart';
import 'theme_tint.dart';

class MeetingSidebar extends ConsumerStatefulWidget {
  const MeetingSidebar({super.key});

  @override
  ConsumerState<MeetingSidebar> createState() => _MeetingSidebarState();
}

class _MeetingSidebarState extends ConsumerState<MeetingSidebar> {
  // 검색 controller/focus 는 SidebarSearchTop 위젯이 자체 보유.
  // _MeetingSidebarState 는 검색 텍스트를 searchQueryProvider 로만 읽는다.

  @override
  void dispose() {
    // 검색 controller/focus 는 SidebarSearchTop 위젯이 자체 dispose
    super.dispose();
  }

  // 단순 키워드 검색은 searchHitsProvider (SearchService) 로 대체됨

  // ── WAV 파일 불러오기 ────────────────────────────────────────────
  /// 기존 WAV 파일을 선택해 새 Meeting 레코드로 등록.
  /// 전사·요약은 생성되지 않으므로 상세 화면에서 "다시 전사"로 실행.
  /// WAV 헤더(fmt/data 청크)를 앞부분만 읽어 재생 길이(초)를 계산한다.
  /// 전체 파일을 메모리에 올리지 않는다(대용량 안전). 실패 시 0.
  static Future<int> _wavDurationSeconds(String path) async {
    RandomAccessFile? raf;
    try {
      raf = await File(path).open();
      final head = await raf.read(64 * 1024); // 헤더+청크 테이블은 충분
      if (head.length < 44) return 0;
      final data = ByteData.sublistView(head);
      int? byteRate;
      int pos = 12;
      while (pos + 8 <= head.length) {
        final id = String.fromCharCodes(head.sublist(pos, pos + 4));
        final size = data.getUint32(pos + 4, Endian.little);
        if (id == 'fmt ') {
          byteRate = data.getUint32(pos + 16, Endian.little);
        } else if (id == 'data') {
          if (byteRate == null || byteRate == 0) return 0;
          // data 크기가 파일보다 크게 선언된 손상 파일 방어
          final fileLen = await File(path).length();
          final dataLen = size.clamp(0, fileLen - (pos + 8));
          return dataLen ~/ byteRate;
        }
        pos += 8 + size + (size.isOdd ? 1 : 0);
      }
      return 0;
    } catch (_) {
      return 0;
    } finally {
      await raf?.close();
    }
  }

  Future<void> _importAudioFile() async {
    // 방어적 게이팅: 버튼 비활성화와 별개로, 진행 중 작업이 있으면 막는다.
    if (ProcessingStatus.instance.isBusy) {
      if (mounted) {
        AppNotice.show(
          tr('진행 중인 작업이 끝난 뒤 파일을 불러올 수 있습니다.',
                'You can import a file after the current task finishes.'),
          kind: NoticeKind.warning,
        );
      }
      return;
    }
    final picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: tr('오디오/영상', 'Audio/Video'),
          extensions: AudioConvertService.pickerExtensions,
        ),
      ],
      confirmButtonText: tr('불러오기', 'Import'),
    );
    if (picked == null) return;

    final file = File(picked.path);
    if (!await file.exists()) {
      if (mounted) {
        AppNotice.show(
          tr('파일을 읽을 수 없습니다.', 'Cannot read the file.'),
          kind: NoticeKind.info,
        );
      }
      return;
    }

    // 파일명에서 타이틀 추출 (마지막 확장자 제거)
    final basename = picked.name;
    final title = basename.replaceAll(RegExp(r'\.[^.]+$'), '');
    final ext = basename.contains('.')
        ? basename.split('.').last.toLowerCase()
        : '';
    final isWav = AudioConvertService.wavExtensions.contains(ext);

    // 파일 stat으로 녹음 시점 추정 (없으면 현재 시각)
    final stat = await file.stat();
    final createdAt = stat.modified;

    // 원본을 그대로 참조하지 않고 항상 앱 지원 폴더로 복사/변환한다.
    // 샌드박스에서는 파일 피커로 얻은 접근 권한이 앱 재실행 시 사라지므로,
    // 원본 경로를 저장하면 다음 실행에서 재생·재전사가 전부 실패한다.
    String audioPath = picked.path;
    int durationSeconds = 0;
    {
      final appSupport = await getApplicationSupportDirectory();
      final importDir = Directory('${appSupport.path}/imported');
      if (!await importDir.exists()) {
        await importDir.create(recursive: true);
      }
      final ts = DateTime.now().millisecondsSinceEpoch;
      final safe = title.replaceAll(RegExp(r'[^A-Za-z0-9가-힣 _-]'), '_').trim();
      final outPath =
          '${importDir.path}/${safe.isEmpty ? 'audio' : safe}-$ts.wav';
      if (isWav) {
        try {
          await file.copy(outPath);
          audioPath = outPath;
          durationSeconds = await _wavDurationSeconds(outPath);
        } catch (e) {
          // 부분 복사 잔재 정리 (회의 레코드가 없으므로 남기면 영구 쓰레기)
          await File(outPath).delete().catchError((_) => File(outPath));
          if (mounted) {
            AppNotice.show(
              tr('파일 복사에 실패했습니다.', 'Failed to copy the file.'),
              kind: NoticeKind.error,
            );
          }
          return;
        }
      } else {
        // 변환 진행 모달 (대개 수 초)
        if (mounted) {
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _ImportConvertingDialog(ext: ext.toUpperCase()),
          );
        }
        try {
          await AudioConvertService.instance.toWav16kMono(
            inputPath: picked.path,
            outputPath: outPath,
          );
          audioPath = outPath;
          final outLen = await File(outPath).length();
          // 16kHz mono 16-bit: bytes = 44(header) + seconds*16000*2
          durationSeconds = ((outLen - 44) / 2 / 16000).round();
          if (durationSeconds < 0) durationSeconds = 0;
        } on PlatformException catch (e) {
          await File(outPath).delete().catchError((_) => File(outPath));
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
          if (mounted) {
            AppNotice.show(
              tr(
                  '파일 변환 실패: ${e.message ?? ext.toUpperCase()}',
                  'Conversion failed: ${e.message ?? ext.toUpperCase()}',
                ),
              kind: NoticeKind.error,
              duration: const Duration(seconds: 5),
            );
          }
          return;
        } catch (e) {
          await File(outPath).delete().catchError((_) => File(outPath));
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
          if (mounted) {
            AppNotice.show(
              tr('파일 변환 중 오류가 발생했습니다.',
                    'An error occurred during conversion.'),
              kind: NoticeKind.error,
            );
          }
          return;
        }
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      }
    }

    final meeting = Meeting()
      ..title = tr('[불러옴] $title', '[Imported] $title')
      ..createdAt = createdAt
      // durationSeconds는 endedAt-createdAt 계산값 → 변환으로 길이를 알면 반영.
      ..endedAt = durationSeconds > 0
          ? createdAt.add(Duration(seconds: durationSeconds))
          : createdAt
      ..status = MeetingStatus.done
      ..audioFilePath = audioPath
      ..transcriptPreview = tr(
        '(전사본 없음 — 상세 화면에서 "다시 전사" 실행)',
        '(No transcript — run "Re-transcribe" in the detail view)',
      );

    final db = IsarService.instance.db;
    final meetingId = await MeetingRepositoryImpl(db).saveMeeting(meeting);

    if (!mounted) return;
    ref.invalidate(meetingsProvider);
    ref.read(selectedMeetingIdProvider.notifier).state = meetingId;
    AppNotice.show(
      tr(
          '${isWav ? 'WAV' : '${ext.toUpperCase()}(변환됨)'} 불러옴 — 상세 화면에서 "다시 전사"를 눌러 전사하세요.',
          '${isWav ? 'WAV' : '${ext.toUpperCase()} (converted)'} imported — tap "Re-transcribe" in the detail view to transcribe.',
        ),
      kind: NoticeKind.success,
      duration: const Duration(seconds: 4),
    );
  }

  // ── AI 검색 실행 ──────────────────────────────────────────────────
  Future<void> _runAiSearch(
    List<Meeting> meetings,
    List<Summary> summaries,
  ) async {
    final query = ref.read(searchQueryProvider).trim();
    if (query.isEmpty) return;

    if (ref.read(isRecordingActiveProvider)) {
      if (mounted) {
        AppNotice.show(
          tr('녹음 중에는 AI 검색을 사용할 수 없습니다.', 'AI search is unavailable while recording.'),
          kind: NoticeKind.warning,
        );
      }
      return;
    }

    ref.read(isAiSearchingProvider.notifier).state = true;
    ref.read(aiSearchStatusProvider.notifier).state = tr('AI 모델 로드 중...', 'Loading AI model...');
    ref.read(aiSearchResultsProvider.notifier).state = null;

    try {
      final appSupport = await getApplicationSupportDirectory();
      final llmPath =
          '${appSupport.path}/models/${AppSettings.instance.currentLlmModelFile}';

      await OnDeviceModelManager.instance.loadLlm(
        llmPath,
        nCtx: 4096,
        nBatch: 512,
      );

      if (mounted) {
        ref.read(aiSearchStatusProvider.notifier).state = tr('검색 중...', 'Searching...');
      }

      // ── 회의 목록 컨텍스트 구성 ────────────────────────────────
      // 너무 많으면 nCtx(4096)를 넘김 — 키워드 사전 필터로 후보 좁힌 뒤 LLM에 보냄.
      // 키워드 매칭 0이면 가장 최근 회의로 폴백(MeetingKeywordSearch 내부 처리).
      const maxMeetings = 30;
      const maxCharsPerMeeting = 140;
      final sliced = MeetingKeywordSearch.rank(
        query: query,
        meetings: meetings,
        summaries: summaries,
        topN: maxMeetings,
      );
      final sb = StringBuffer();
      for (final m in sliced) {
        final s = summaries.where((s) => s.meetingId == m.id).firstOrNull;
        final line = StringBuffer('ID:${m.id}|${m.title}');
        if (s != null) {
          final d = s.keyDiscussions.take(2).join(', ');
          if (d.isNotEmpty) line.write('|논의:$d');
          final dec = s.decisions.take(1).join(', ');
          if (dec.isNotEmpty) line.write('|결정:$dec');
        } else if (m.transcriptPreview?.isNotEmpty == true) {
          final preview = m.transcriptPreview!;
          line.write(
            '|내용:${preview.substring(0, preview.length.clamp(0, 80))}',
          );
        }
        // 회의 1개당 컨텍스트 길이 상한 — 토큰 예산 안정화
        var lineStr = line.toString();
        if (lineStr.length > maxCharsPerMeeting) {
          lineStr = lineStr.substring(0, maxCharsPerMeeting);
        }
        sb.writeln(lineStr);
      }

      final truncatedNotice = meetings.length > maxMeetings
          ? '\n(키워드 매칭 상위 $maxMeetings개 회의만 검색합니다.)'
          : '';

      final prompt =
          '회의 목록에서 "$query"와 관련된 회의를 찾아줘.$truncatedNotice\n\n'
          '반드시 JSON 배열만 출력. 다른 말 하지 마.\n'
          '형식: [{"id":숫자,"reason":"이유"}]\n'
          '관련 없으면: []\n\n'
          '회의 목록:\n${sb.toString()}\n\nJSON:';

      final buf = StringBuffer();
      await for (final tok in LlmService.instance.generate(
        userMessage: prompt,
        maxTokens: 512,
        temperature: 0.2,
        topP: 0.8,
      )) {
        buf.write(tok);
      }

      await OnDeviceModelManager.instance.unloadLlm();

      final results = _parseAiResults(buf.toString());
      if (mounted) {
        ref.read(aiSearchResultsProvider.notifier).state = results;
      }
    } catch (e) {
      await OnDeviceModelManager.instance.unloadLlm().catchError((_) {});
      if (mounted) {
        AppNotice.show(
          tr('AI 검색 오류: $e', 'AI search error: $e'),
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) {
        ref.read(isAiSearchingProvider.notifier).state = false;
        ref.read(aiSearchStatusProvider.notifier).state = '';
      }
    }
  }

  // ── AI 응답 파싱 ──────────────────────────────────────────────────
  List<AiSearchResult> _parseAiResults(String raw) {
    String? jsonStr;
    final cb = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(raw);
    if (cb != null) jsonStr = cb.group(1)?.trim();
    if (jsonStr == null) {
      final s = raw.indexOf('[');
      final e = raw.lastIndexOf(']');
      if (s != -1 && e > s) jsonStr = raw.substring(s, e + 1);
    }
    if (jsonStr == null) return [];
    try {
      final list = jsonDecode(jsonStr) as List;
      return list.map((item) {
        final m = item as Map<String, dynamic>;
        return AiSearchResult(
          meetingId: (m['id'] as num).toInt(),
          reason: m['reason'] as String? ?? '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // 검색 초기화는 SidebarSearchTop 의 clear 버튼이 처리.

  // ── 회의 탭 공통 핸들러 ──────────────────────────────────────────
  Future<void> _onTapMeeting(Meeting m) async {
    final nativeRecording =
        ref.read(nativeRecordingActiveProvider) ||
        MicrophoneService.instance.isRecording ||
        MicrophoneService.instance.isPaused;

    // 실제 녹음은 끝났는데 DB 상태만 진행 중으로 남은 회의는
    // 비정상 종료/화면 이탈 복구 대상으로 보고 스피너를 멈춘다.
    if (!nativeRecording &&
        m.status != MeetingStatus.done &&
        m.status != MeetingStatus.error) {
      await RecoveryService.markAsRecovered(m);
      ref.invalidate(meetingsProvider);
    }

    if (!nativeRecording) {
      ref.read(isRecordingActiveProvider.notifier).state = false;
    }
    ref.read(selectedMeetingIdProvider.notifier).state = m.id;
  }

  Future<void> _onDeleteMeeting(Meeting m) async {
    // 회의에 딸린 전사·요약·요약 이력까지 함께 삭제 (캐스케이드).
    // Meeting 행만 지우면 고아 레코드가 남고, Isar가 id를 재사용할 때
    // 새 회의에 남의 요약/전사가 붙는 심각한 데이터 오염이 발생한다.
    final db = IsarService.instance.db;
    await TranscriptRepositoryImpl(db).deleteByMeetingId(m.id);
    await SummaryRepositoryImpl(db).deleteSummaryByMeetingId(m.id);
    await SummaryVersionRepositoryImpl(db).deleteByMeetingId(m.id);
    await MeetingRepositoryImpl(db).deleteMeeting(m.id);
    // 앱이 만든 녹음/변환 파일은 함께 삭제 (회의가 사라지면 auto_delete도
    // 더는 이 파일을 볼 수 없어 영구 잔재가 된다). 사용자가 직접 가져온
    // 원본 파일은 앱 소유가 아니므로 남긴다.
    final audioPath = m.audioFilePath;
    if (audioPath != null && audioPath.isNotEmpty) {
      final sep = audioPath.lastIndexOf('/');
      final base = sep < 0 ? audioPath : audioPath.substring(sep + 1);
      final dir = sep < 0 ? '' : audioPath.substring(0, sep);
      final appOwned =
          (base.startsWith('meeting_') && base.endsWith('.wav')) ||
          dir.endsWith('/imported');
      if (appOwned) {
        await File(audioPath).delete().catchError((_) => File(audioPath));
      }
    }
    ref.invalidate(meetingsProvider);
    ref.invalidate(allSummariesProvider);
    if (ref.read(selectedMeetingIdProvider) == m.id) {
      ref.read(selectedMeetingIdProvider.notifier).state = null;
    }
  }

  Future<void> _onMoveGroup(Meeting m, int? groupId) async {
    m.groupId = groupId;
    await MeetingRepositoryImpl(IsarService.instance.db).updateMeeting(m);
    ref.invalidate(meetingsProvider);
  }

  Future<void> _onRenameMeeting(Meeting m, String newTitle) async {
    m.title = newTitle;
    await MeetingRepositoryImpl(IsarService.instance.db).updateMeeting(m);
    ref.invalidate(meetingsProvider);
  }

  /// 그룹 헤더의 시계열 아이콘 → 시리즈 진행 대시보드 토글.
  /// 같은 그룹을 다시 누르면 닫힌다.
  void _onShowSeriesDashboard(MeetingGroup g) {
    final current = ref.read(selectedGroupIdProvider);
    if (current == g.id) {
      ref.read(selectedGroupIdProvider.notifier).state = null;
      return;
    }
    ref.read(selectedMeetingIdProvider.notifier).state = null;
    ref.read(selectedGroupIdProvider.notifier).state = g.id;
  }

  Future<void> _showDigestSheet(BuildContext context) async {
    await showMacosSheet<void>(
      context: context,
      builder: (ctx) => _DigestSheet(
        onJump: (meetingId) {
          Navigator.pop(ctx);
          ref.read(selectedGroupIdProvider.notifier).state = null;
          ref.read(selectedMeetingIdProvider.notifier).state = meetingId;
        },
      ),
    );
  }

  Future<void> _showSeriesOverviewSheet(BuildContext context) async {
    await showMacosSheet<void>(
      context: context,
      builder: (ctx) => _SeriesOverviewSheet(
        onJumpToSeries: (groupId) {
          Navigator.pop(ctx);
          ref.read(selectedMeetingIdProvider.notifier).state = null;
          ref.read(selectedGroupIdProvider.notifier).state = groupId;
        },
      ),
    );
  }

  Future<void> _showSeriesSuggestionsDialog(
    List<Meeting> meetings,
    List<Summary> summaries,
    List<MeetingGroup> groups,
  ) async {
    final suggestions = MeetingSeriesDetector.suggestSeries(
      meetings: meetings,
      summaries: summaries,
    );

    if (suggestions.isEmpty) {
      if (!mounted) return;
      AppNotice.show(
        tr('아직 자동으로 묶을 정기 회의 후보가 없습니다.', 'No recurring meeting candidates to group yet.'),
        kind: NoticeKind.info,
      );
      return;
    }

    final selected = <int>{for (var i = 0; i < suggestions.length; i++) i};
    final shouldApply = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr('정기 회의 시리즈 추천', 'Recurring series suggestions')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < suggestions.length; i++)
                    _SeriesSuggestionTile(
                      suggestion: suggestions[i],
                      selected: selected.contains(i),
                      onChanged: (value) {
                        setDialogState(() {
                          if (value) {
                            selected.add(i);
                          } else {
                            selected.remove(i);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('취소', 'Cancel')),
            ),
            FilledButton.icon(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.folder_special_outlined, size: 16),
              label: Text(tr('${selected.length}개 적용', 'Apply ${selected.length}')),
            ),
          ],
        ),
      ),
    );

    if (shouldApply != true || selected.isEmpty) return;
    final picked = selected.map((i) => suggestions[i]).toList();
    await _applySeriesSuggestions(picked, groups);
  }

  Future<void> _applySeriesSuggestions(
    List<MeetingSeriesSuggestion> suggestions,
    List<MeetingGroup> existingGroups,
  ) async {
    final db = IsarService.instance.db;
    final groupRepo = MeetingGroupRepositoryImpl(db);
    final meetingRepo = MeetingRepositoryImpl(db);
    final usedNames = existingGroups.map((g) => g.name).toSet();

    for (final suggestion in suggestions) {
      final groupName = _uniqueGroupName(suggestion.suggestedName, usedNames);
      usedNames.add(groupName);
      final group = MeetingGroup()
        ..name = groupName
        ..createdAt = DateTime.now();
      final groupId = await groupRepo.saveGroup(group);
      for (final meeting in suggestion.meetings) {
        meeting.groupId = groupId;
        await meetingRepo.updateMeeting(meeting);
      }
    }

    if (!mounted) return;
    ref.invalidate(groupsProvider);
    ref.invalidate(meetingsProvider);
    AppNotice.show(
      tr('정기 회의 시리즈 ${suggestions.length}개를 만들었습니다.', 'Created ${suggestions.length} recurring series.'),
      kind: NoticeKind.success,
    );
  }

  String _uniqueGroupName(String base, Set<String> usedNames) {
    if (!usedNames.contains(base)) return base;
    var index = 2;
    while (usedNames.contains('$base ($index)')) {
      index++;
    }
    return '$base ($index)';
  }

  // ── BUILD ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final meetingsAsync = ref.watch(meetingsProvider);
    final groupsAsync = ref.watch(groupsProvider);
    final summariesAsync = ref.watch(allSummariesProvider);
    final selectedId = ref.watch(selectedMeetingIdProvider);
    final isRecording = ref.watch(nativeRecordingActiveProvider);
    final isSummarizing = ref.watch(isSummarizingProvider);
    final query = ref.watch(searchQueryProvider);

    // ⌘F 검색 포커스 단축키는 SidebarSearchTop 이 처리.
    final isAiMode = ref.watch(isAiSearchModeProvider);
    final isAiSearching = ref.watch(isAiSearchingProvider);
    final aiStatus = ref.watch(aiSearchStatusProvider);
    final aiResults = ref.watch(aiSearchResultsProvider);
    final dateFilter = ref.watch(dateFilterProvider);

    final allMeetings = meetingsAsync.asData?.value ?? <Meeting>[];
    final groups = groupsAsync.asData?.value ?? <MeetingGroup>[];
    final summaries = summariesAsync.asData?.value ?? <Summary>[];

    // 날짜 범위 필터 적용
    final now = DateTime.now();
    final meetings = allMeetings.where((m) {
      switch (dateFilter) {
        case DateFilter.thisWeek:
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          final start = DateTime(
            weekStart.year,
            weekStart.month,
            weekStart.day,
          );
          return m.createdAt.isAfter(start);
        case DateFilter.thisMonth:
          final start = DateTime(now.year, now.month, 1);
          return m.createdAt.isAfter(start);
        case DateFilter.all:
          return true;
      }
    }).toList();

    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          // ── 헤더 ────────────────────────────────────────────────
          // 앱 이름 헤더는 제거 — 툴바·메뉴바가 이미 앱 이름을 보여준다.
          // (창 안에 'Local Minutes'가 두 번 반복되던 중복 해소)
          // 유틸 아이콘도 툴바 기어(설정)와 겹치는 것·수동 새로고침은 정리하고
          // 사이드바는 검색·목록에 집중한다. 단어집/할 일/통계는 우측 정렬 유지.
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.menu_book_outlined, size: 16),
                  tooltip: tr('단어집', 'Glossary'),
                  onPressed: () => showGlossaryDialog(context),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.checklist_outlined, size: 16),
                  tooltip: tr('전체 할 일', 'All action items'),
                  onPressed: () => showActionItemsDialog(context),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.bar_chart_outlined, size: 16),
                  tooltip: tr('통계', 'Statistics'),
                  onPressed: () => showStatsDialog(context),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── 녹음 중 복귀 배너 ────────────────────────────────────
          if (isRecording)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                // 클릭하면 RecordingView로 복귀
                ref.read(isRecordingActiveProvider.notifier).state = true;
                ref.read(selectedMeetingIdProvider.notifier).state = null;
                ref.read(selectedGroupIdProvider.notifier).state = null;
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: tintBg(context, Colors.red),
                  border: Border(
                    bottom: BorderSide(color: tintBorder(context, Colors.red)),
                  ),
                ),
                child: Row(
                  children: [
                    // 깜빡이는 빨간 점
                    _PulsingDot(),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('녹음 진행 중', 'Recording in progress'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: tintFg(context, Colors.red),
                            ),
                          ),
                          Text(
                            tr('탭하면 녹음 화면으로 돌아갑니다', 'Tap to return to the recording screen'),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.red.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Colors.red.shade400,
                    ),
                  ],
                ),
              ),
            ),

          // ── 새 녹음 / WAV 불러오기 ──────────────────────────
          // 전사/요약이 진행 중이면(다른 회의 포함) 두 버튼 모두 비활성화한다.
          // (작업이 안 끝났는데 새 작업을 시작하면 '화면이 안 돌아오는' 문제 유발)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: ValueListenableBuilder<ProcessingJob?>(
              valueListenable: ProcessingStatus.instance.active,
              builder: (context, job, _) {
                final processing = job != null;
                // isSummarizing: 녹음 직후 요약 진행 신호(recording_view).
                // processing: 상세 화면의 다시 전사/재요약(ProcessingStatus).
                final blocked = isRecording || isSummarizing || processing;
                final newRecTip = processing
                    ? (job.kind == 'transcribe'
                        ? tr('전사가 끝난 뒤 녹음할 수 있습니다', 'You can record after transcription finishes')
                        : tr('요약이 끝난 뒤 녹음할 수 있습니다', 'You can record after summarization finishes'))
                    : '';
                final importTip = processing
                    ? (job.kind == 'transcribe'
                        ? tr('전사가 끝난 뒤 파일을 불러올 수 있습니다', 'You can import after transcription finishes')
                        : tr('요약이 끝난 뒤 파일을 불러올 수 있습니다', 'You can import after summarization finishes'))
                    : tr('기존 오디오 파일을 불러와 새 회의로 추가', 'Import an existing audio file as a new meeting');
                return Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: newRecTip,
                        child: FilledButton.icon(
                          onPressed: blocked
                              ? null
                              : () {
                                  ref
                                      .read(isRecordingActiveProvider.notifier)
                                      .state = true;
                                  ref
                                      .read(selectedMeetingIdProvider.notifier)
                                      .state = null;
                                },
                          icon: const Icon(Icons.fiber_manual_record, size: 16),
                          label: Text(tr('새 녹음', 'New recording')),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: importTip,
                      child: IconButton.outlined(
                        onPressed: blocked ? null : _importAudioFile,
                        icon: const Icon(Icons.file_upload_outlined, size: 16),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // ── 검색 모드 / 필터 영역 (검색 입력창은 Sidebar.top 의 SidebarSearchTop 이 담당) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 검색 모드 토글
                Row(
                  children: [
                    Expanded(
                      child: _ModeChip(
                        label: tr('단어', 'Words'),
                        icon: Icons.abc,
                        selected: !isAiMode,
                        onTap: () {
                          ref.read(isAiSearchModeProvider.notifier).state =
                              false;
                          ref.read(aiSearchResultsProvider.notifier).state =
                              null;
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ModeChip(
                        label: 'AI',
                        icon: Icons.auto_awesome,
                        selected: isAiMode,
                        color: Colors.deepPurple,
                        onTap: () =>
                            ref.read(isAiSearchModeProvider.notifier).state =
                                true,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // 날짜 범위 필터
                Row(
                  children: [
                    _DateChip(
                      label: tr('전체', 'All'),
                      selected: dateFilter == DateFilter.all,
                      onTap: () => ref.read(dateFilterProvider.notifier).state =
                          DateFilter.all,
                    ),
                    const SizedBox(width: 4),
                    _DateChip(
                      label: tr('이번 달', 'This month'),
                      selected: dateFilter == DateFilter.thisMonth,
                      onTap: () => ref.read(dateFilterProvider.notifier).state =
                          DateFilter.thisMonth,
                    ),
                    const SizedBox(width: 4),
                    _DateChip(
                      label: tr('이번 주', 'This week'),
                      selected: dateFilter == DateFilter.thisWeek,
                      onTap: () => ref.read(dateFilterProvider.notifier).state =
                          DateFilter.thisWeek,
                    ),
                  ],
                ),

                // AI 검색 실행 버튼 (AI 모드 + 쿼리 있을 때)
                if (isAiMode && query.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    onPressed: isAiSearching
                        ? null
                        : () => _runAiSearch(meetings, summaries),
                    icon: isAiSearching
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome, size: 14),
                    label: Text(
                      isAiSearching ? aiStatus : tr('AI로 검색', 'Search with AI'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── 요약 중 배너 ──────────────────────────────────────
          if (isSummarizing)
            Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: tintBg(context, Colors.deepPurple),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tintBorder(context, Colors.deepPurple)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.deepPurple.shade400,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr('요약 중...', 'Summarizing...'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: tintFg(context, Colors.deepPurple),
                    ),
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // ── 회의 목록 / 검색 결과 ─────────────────────────────
          Expanded(
            child: meetingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr('오류: $e', 'Error: $e'),
                    style: TextStyle(fontSize: 12, color: tintFg(context, Colors.red)),
                  ),
                ),
              ),
              data: (_) {
                // 검색 모드 분기
                if (query.trim().isNotEmpty) {
                  if (!isAiMode) {
                    // 전문 검색 (제목/메모/태그/요약/전사)
                    final hitsAsync = ref.watch(searchHitsProvider);
                    return hitsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            tr('검색 오류: $e', 'Search error: $e'),
                            style: TextStyle(
                              fontSize: 12,
                              color: tintFg(context, Colors.red),
                            ),
                          ),
                        ),
                      ),
                      data: (hits) => _buildSimpleResults(
                        context,
                        hits,
                        meetings,
                        groups,
                        selectedId,
                        query,
                      ),
                    );
                  } else {
                    // AI 검색
                    return _buildAiResults(
                      context,
                      aiResults,
                      meetings,
                      groups,
                      selectedId,
                      isAiSearching,
                      aiStatus,
                    );
                  }
                }
                // 일반 목록
                return _buildGroupedList(
                  context,
                  meetings,
                  groups,
                  selectedId,
                  isRecording,
                );
              },
            ),
          ),

          // ── 다이제스트 / 시리즈 비교 버튼 ──────────────────────
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: allMeetings.isEmpty
                        ? null
                        : () => _showDigestSheet(context),
                    icon: const Icon(Icons.event_note_outlined, size: 16),
                    label: Text(tr('다이제스트', 'Digest'), style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: groups.isEmpty
                        ? null
                        : () => _showSeriesOverviewSheet(context),
                    icon: const Icon(Icons.bar_chart_rounded, size: 16),
                    label: Text(tr('시리즈 비교', 'Compare series'), style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 그룹 추가 버튼 ────────────────────────────────────
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: _AddGroupButton(
                    onAdd: (name) async {
                      final group = MeetingGroup()
                        ..name = name
                        ..createdAt = DateTime.now();
                      await MeetingGroupRepositoryImpl(
                        IsarService.instance.db,
                      ).saveGroup(group);
                      ref.invalidate(groupsProvider);
                    },
                  ),
                ),
                Expanded(
                  child: Tooltip(
                    message: tr('제목, 태그, 참석자가 비슷한 회의를 자동으로 묶기', 'Auto-group meetings with similar titles, tags, and attendees'),
                    child: TextButton.icon(
                      onPressed: allMeetings.length < 2
                          ? null
                          : () => _showSeriesSuggestionsDialog(
                              allMeetings,
                              summaries,
                              groups,
                            ),
                      icon: const Icon(Icons.auto_awesome_motion, size: 16),
                      label: Text(
                        tr('시리즈 추천', 'Suggest series'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 버전 + 작성자 ─────────────────────────────────────
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: const AppVersionCredit(compact: true),
          ),
        ],
      ),
    );
  }

  // ── 단어 검색 결과 ─────────────────────────────────────────────
  Widget _buildSimpleResults(
    BuildContext context,
    List<MeetingSearchHit> hits,
    List<Meeting> meetings,
    List<MeetingGroup> groups,
    int? selectedId,
    String query,
  ) {
    if (hits.isEmpty) {
      return _SidebarEmptyState(
        icon: Icons.search_off,
        title: tr('검색 결과 없음', 'No search results'),
      );
    }
    final meetingById = {for (final m in meetings) m.id: m};
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            tr('검색 결과 ${hits.length}개', '${hits.length} results'),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ),
        for (final h in hits)
          if (meetingById[h.meetingId] != null) ...[
            _MeetingTile(
              meeting: meetingById[h.meetingId]!,
              isSelected: h.meetingId == selectedId,
              groups: groups,
              onTap: () => _onTapMeeting(meetingById[h.meetingId]!),
              onDelete: () => _onDeleteMeeting(meetingById[h.meetingId]!),
              onMoveGroup: (gId) =>
                  _onMoveGroup(meetingById[h.meetingId]!, gId),
              onRename: (title) =>
                  _onRenameMeeting(meetingById[h.meetingId]!, title),
            ),
            _SearchMatchList(hit: h, tokens: tokens),
          ],
      ],
    );
  }

  // ── AI 검색 결과 ──────────────────────────────────────────────
  Widget _buildAiResults(
    BuildContext context,
    List<AiSearchResult>? aiResults,
    List<Meeting> meetings,
    List<MeetingGroup> groups,
    int? selectedId,
    bool isSearching,
    String status,
  ) {
    // 검색 중
    if (isSearching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressCircle(borderColor: Colors.deepPurple.shade300),
            const SizedBox(height: 10),
            Text(
              status,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    // 아직 검색 안 함
    if (aiResults == null) {
      return _SidebarEmptyState(
        icon: Icons.auto_awesome,
        title: tr('AI 검색 대기 중', 'Waiting for AI search'),
      );
    }

    // 결과 없음
    if (aiResults.isEmpty) {
      return _SidebarEmptyState(
        icon: Icons.search_off,
        title: tr('관련 회의 없음', 'No matching meetings'),
      );
    }

    // 결과 표시
    final matched = aiResults
        .map(
          (r) => (
            result: r,
            meeting: meetings.where((m) => m.id == r.meetingId).firstOrNull,
          ),
        )
        .where((e) => e.meeting != null)
        .toList();

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 12,
                color: Colors.deepPurple.shade400,
              ),
              const SizedBox(width: 4),
              Text(
                tr('AI 검색 결과 ${matched.length}개', '${matched.length} AI results'),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.deepPurple.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ...matched.map(
          (e) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MeetingTile(
                meeting: e.meeting!,
                isSelected: e.meeting!.id == selectedId,
                groups: groups,
                onTap: () => _onTapMeeting(e.meeting!),
                onDelete: () => _onDeleteMeeting(e.meeting!),
                onMoveGroup: (gId) => _onMoveGroup(e.meeting!, gId),
                onRename: (title) => _onRenameMeeting(e.meeting!, title),
              ),
              if (e.result.reason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 10,
                        color: Colors.deepPurple.shade300,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          e.result.reason,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.deepPurple.shade400,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 일반 그룹 목록 ─────────────────────────────────────────────
  Widget _buildGroupedList(
    BuildContext context,
    List<Meeting> meetings,
    List<MeetingGroup> groups,
    int? selectedId,
    bool isRecording,
  ) {
    if (meetings.isEmpty) {
      return _SidebarEmptyState(
        icon: Icons.event_note_outlined,
        title: tr('회의 없음', 'No meetings'),
      );
    }

    final ungrouped = meetings.where((m) => m.groupId == null).toList();
    final grouped = {
      for (final g in groups)
        g: meetings.where((m) => m.groupId == g.id).toList(),
    };
    final selectedGroupId = ref.watch(selectedGroupIdProvider);

    return ListView(
      children: [
        for (final entry in grouped.entries)
          _GroupSection(
            group: entry.key,
            meetings: entry.value,
            groups: groups,
            selectedId: selectedId,
            selectedGroupId: selectedGroupId,
            isRecording: isRecording,
            onTap: _onTapMeeting,
            onDelete: _onDeleteMeeting,
            onMoveGroup: _onMoveGroup,
            onRenameMeeting: _onRenameMeeting,
            onShowSeriesDashboard: _onShowSeriesDashboard,
            onRenameGroup: (g, name) async {
              g.name = name;
              await MeetingGroupRepositoryImpl(
                IsarService.instance.db,
              ).saveGroup(g);
              ref.invalidate(groupsProvider);
            },
            onDeleteGroup: (g) async {
              for (final m in entry.value) {
                m.groupId = null;
                await MeetingRepositoryImpl(
                  IsarService.instance.db,
                ).updateMeeting(m);
              }
              await MeetingGroupRepositoryImpl(
                IsarService.instance.db,
              ).deleteGroup(g.id);
              ref.invalidate(groupsProvider);
              ref.invalidate(meetingsProvider);
            },
          ),
        if (ungrouped.isNotEmpty)
          _UngroupedSection(
            meetings: ungrouped,
            groups: groups,
            selectedId: selectedId,
            isRecording: isRecording,
            onTap: _onTapMeeting,
            onDelete: _onDeleteMeeting,
            onMoveGroup: _onMoveGroup,
            onRenameMeeting: _onRenameMeeting,
          ),
      ],
    );
  }
}

class _SidebarEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SidebarEmptyState({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.42),
            ),
            const SizedBox(height: 7),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 검색 매치 리스트 (필드 배지 + 하이라이트 스니펫) ─────────────────────
class _SearchMatchList extends ConsumerWidget {
  final MeetingSearchHit hit;
  final List<String> tokens;

  const _SearchMatchList({required this.hit, required this.tokens});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in hit.topMatches)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: m.field == SearchField.transcript
                    ? () {
                        // 회의 선택 + 전사 점프 요청
                        ref.read(selectedMeetingIdProvider.notifier).state =
                            hit.meetingId;
                        ref
                            .read(transcriptJumpRequestProvider.notifier)
                            .state = TranscriptJumpRequest(
                          meetingId: hit.meetingId,
                          snippet: m.snippet,
                          seq: DateTime.now().millisecondsSinceEpoch,
                        );
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldBadge(field: m.field),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _HighlightedText(
                          text: m.snippet,
                          tokens: tokens,
                          baseStyle: TextStyle(
                            fontSize: 11,
                            color: mutedText(context),
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (m.field == SearchField.transcript) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.east_rounded,
                          size: 12,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (hit.totalMatches > hit.topMatches.length)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 2),
              child: Text(
                tr('외 ${hit.totalMatches - hit.topMatches.length}건 더 일치', '${hit.totalMatches - hit.topMatches.length} more matches'),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FieldBadge extends StatelessWidget {
  final SearchField field;
  const _FieldBadge({required this.field});

  Color _color() {
    switch (field) {
      case SearchField.title:
      case SearchField.summaryTitle:
        return Colors.indigo;
      case SearchField.tags:
        return Colors.teal;
      case SearchField.notes:
        return Colors.brown;
      case SearchField.transcript:
        return Colors.blueGrey;
      case SearchField.participants:
        return Colors.orange;
      case SearchField.keyDiscussions:
        return Colors.deepPurple;
      case SearchField.decisions:
        return Colors.green;
      case SearchField.actionItems:
        return Colors.red;
      case SearchField.openQuestions:
        return Colors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        field.label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: c.withValues(alpha: 0.9),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  final String text;
  final List<String> tokens;
  final TextStyle baseStyle;

  const _HighlightedText({
    required this.text,
    required this.tokens,
    required this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (tokens.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    // 모든 토큰 매치 위치를 찾아 정렬된 구간 리스트로 병합
    final lower = text.toLowerCase();
    final ranges = <List<int>>[]; // [start, end]
    for (final t in tokens) {
      int idx = 0;
      while (true) {
        final found = lower.indexOf(t, idx);
        if (found < 0) break;
        ranges.add([found, found + t.length]);
        idx = found + t.length;
      }
    }
    ranges.sort((a, b) => a[0].compareTo(b[0]));
    // 겹치는 구간 병합
    final merged = <List<int>>[];
    for (final r in ranges) {
      if (merged.isNotEmpty && r[0] <= merged.last[1]) {
        merged.last[1] = r[1] > merged.last[1] ? r[1] : merged.last[1];
      } else {
        merged.add([r[0], r[1]]);
      }
    }

    final spans = <TextSpan>[];
    final hlColor = Theme.of(context).colorScheme.primary;
    int cursor = 0;
    for (final r in merged) {
      if (r[0] > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, r[0])));
      }
      spans.add(
        TextSpan(
          text: text.substring(r[0], r[1]),
          style: TextStyle(
            backgroundColor: hlColor.withValues(alpha: 0.22),
            fontWeight: FontWeight.w700,
            color: hlColor,
          ),
        ),
      );
      cursor = r[1];
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: baseStyle, children: spans),
    );
  }
}

// ── 날짜 필터 칩 ──────────────────────────────────────────────────────
class _DateChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.tertiary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected
                ? c.withValues(alpha: 0.42)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? c : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}

// ── 모드 칩 ──────────────────────────────────────────────────────────
class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.11) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected
                ? c.withValues(alpha: 0.42)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: selected ? c : Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? c : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 그룹 섹션 ─────────────────────────────────────────────────────────
class _GroupSection extends StatefulWidget {
  final MeetingGroup group;
  final List<Meeting> meetings;
  final List<MeetingGroup> groups;
  final int? selectedId;
  final int? selectedGroupId;
  final bool isRecording;
  final void Function(Meeting) onTap;
  final Future<void> Function(Meeting) onDelete;
  final Future<void> Function(Meeting, int?) onMoveGroup;
  final Future<void> Function(Meeting, String) onRenameMeeting;
  final Future<void> Function(MeetingGroup, String) onRenameGroup;
  final Future<void> Function(MeetingGroup) onDeleteGroup;
  final void Function(MeetingGroup) onShowSeriesDashboard;

  const _GroupSection({
    required this.group,
    required this.meetings,
    required this.groups,
    required this.selectedId,
    required this.selectedGroupId,
    required this.isRecording,
    required this.onTap,
    required this.onDelete,
    required this.onMoveGroup,
    required this.onRenameMeeting,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onShowSeriesDashboard,
  });

  @override
  State<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends State<_GroupSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groupSelected = widget.selectedGroupId == widget.group.id;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            hoverColor: scheme.onSurface.withValues(alpha: 0.04),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: groupSelected
                    ? scheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: groupSelected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.folder,
                    size: 14,
                    color: groupSelected
                        ? scheme.primary
                        : Colors.amber.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.group.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: groupSelected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${widget.meetings.length}',
                    style: TextStyle(
                      fontSize: 10,
                      color: groupSelected
                          ? Theme.of(context).colorScheme.primary
                          : scheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: tr('시리즈 진행', 'Series progress'),
                    icon: Icon(
                      Icons.timeline,
                      size: 14,
                      color: groupSelected
                          ? Theme.of(context).colorScheme.primary
                          : scheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                    iconSize: 14,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    splashRadius: 14,
                    onPressed: () => widget.onShowSeriesDashboard(widget.group),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 14,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                    iconSize: 14,
                    tooltip: tr('그룹 관리', 'Manage group'),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            const Icon(Icons.edit, size: 16),
                            const SizedBox(width: 8),
                            Text(tr('그룹명 수정', 'Rename group'), style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              tr('그룹 삭제', 'Delete group'),
                              style: const TextStyle(fontSize: 13, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (action) {
                      if (action == 'rename') _showRenameDialog(context);
                      if (action == 'delete') _showDeleteDialog(context);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          ...widget.meetings.map(
            (m) => _MeetingTile(
              meeting: m,
              isSelected: m.id == widget.selectedId && !widget.isRecording,
              groups: widget.groups,
              onTap: () => widget.onTap(m),
              onDelete: () => widget.onDelete(m),
              onMoveGroup: (gId) => widget.onMoveGroup(m, gId),
              onRename: (title) => widget.onRenameMeeting(m, title),
            ),
          ),
      ],
    );
  }

  void _showRenameDialog(BuildContext context) {
    final ctrl = TextEditingController(text: widget.group.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('그룹명 수정', 'Rename group')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('그룹명', 'Group name'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              widget.onRenameGroup(widget.group, v.trim());
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('취소', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                widget.onRenameGroup(widget.group, ctrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: Text(tr('저장', 'Save')),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showMacosAlertDialog<void>(
      context: context,
      builder: (ctx) => MacosAlertDialog(
        appIcon: const Icon(
          Icons.folder_delete_outlined,
          color: Colors.red,
          size: 48,
        ),
        title: Text(tr('그룹 삭제', 'Delete group')),
        message: Text(
          tr(
            '「${widget.group.name}」 그룹을 삭제합니다.\n그룹 내 회의는 미분류로 이동됩니다.',
            'Delete the group "${widget.group.name}".\nMeetings in it will move to Ungrouped.',
          ),
          textAlign: TextAlign.center,
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () {
            Navigator.pop(ctx);
            widget.onDeleteGroup(widget.group);
          },
          child: Text(tr('삭제', 'Delete')),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('취소', 'Cancel')),
        ),
      ),
    );
  }
}

// ── 미분류 섹션 ───────────────────────────────────────────────────────
class _UngroupedSection extends StatefulWidget {
  final List<Meeting> meetings;
  final List<MeetingGroup> groups;
  final int? selectedId;
  final bool isRecording;
  final void Function(Meeting) onTap;
  final Future<void> Function(Meeting) onDelete;
  final Future<void> Function(Meeting, int?) onMoveGroup;
  final Future<void> Function(Meeting, String) onRenameMeeting;

  const _UngroupedSection({
    required this.meetings,
    required this.groups,
    required this.selectedId,
    required this.isRecording,
    required this.onTap,
    required this.onDelete,
    required this.onMoveGroup,
    required this.onRenameMeeting,
  });

  @override
  State<_UngroupedSection> createState() => _UngroupedSectionState();
}

class _UngroupedSectionState extends State<_UngroupedSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        if (widget.groups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              hoverColor: scheme.onSurface.withValues(alpha: 0.04),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  children: [
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 16,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.folder_open,
                      size: 14,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('미분류', 'Ungrouped'),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      '${widget.meetings.length}',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_expanded)
          ...widget.meetings.map(
            (m) => _MeetingTile(
              meeting: m,
              isSelected: m.id == widget.selectedId && !widget.isRecording,
              groups: widget.groups,
              onTap: () => widget.onTap(m),
              onDelete: () => widget.onDelete(m),
              onMoveGroup: (gId) => widget.onMoveGroup(m, gId),
              onRename: (title) => widget.onRenameMeeting(m, title),
            ),
          ),
      ],
    );
  }
}

// ── 개별 회의 타일 ────────────────────────────────────────────────────
class _MeetingTile extends StatelessWidget {
  final Meeting meeting;
  final bool isSelected;
  final List<MeetingGroup> groups;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;
  final Future<void> Function(int?) onMoveGroup;
  final Future<void> Function(String) onRename;

  const _MeetingTile({
    required this.meeting,
    required this.isSelected,
    required this.groups,
    required this.onTap,
    required this.onDelete,
    required this.onMoveGroup,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final report = MeetingProcessingReport.fromJsonString(
      meeting.processingReportJson,
    );
    final qualityLabel = switch (report.inputQualityStatus) {
      'empty' => tr('마이크 입력 낮음', 'Low mic input'),
      'low' => tr('전사 부족', 'Sparse transcript'),
      _ => '',
    };
    final qualityColor = report.inputQualityStatus == 'empty'
        ? Colors.red.shade700
        : Colors.orange.shade700;
    final selectedTextColor = scheme.onPrimary;
    final secondaryTextColor = isSelected
        ? scheme.onPrimary.withValues(alpha: 0.74)
        : scheme.onSurfaceVariant;
    final tileBackground = isSelected ? scheme.primary : Colors.transparent;

    // macOS 관례: 스와이프 삭제(모바일) 대신 우클릭 컨텍스트 메뉴로 삭제.
    return GestureDetector(
        onSecondaryTapUp: (d) => _showContextMenu(context, d.globalPosition),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          hoverColor: scheme.onSurface.withValues(alpha: 0.045),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: tileBackground,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                _StatusIcon(status: meeting.status, selected: isSelected),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: meeting.title,
                        preferBelow: false,
                        waitDuration: const Duration(milliseconds: 500),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final useTwoLineTitle = constraints.maxWidth >= 300;
                            return Text(
                              meeting.title,
                              maxLines: useTwoLineTitle ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.22,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? selectedTextColor
                                    : scheme.onSurface,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitleFor(meeting),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: secondaryTextColor,
                        ),
                      ),
                      if (qualityLabel.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Tooltip(
                          message: report.inputQualityReason.isEmpty
                              ? qualityLabel
                              : report.inputQualityReason,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 12,
                                color: isSelected
                                    ? selectedTextColor.withValues(alpha: 0.86)
                                    : qualityColor,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  qualityLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: isSelected
                                        ? selectedTextColor.withValues(
                                            alpha: 0.86,
                                          )
                                        : qualityColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final ctrl = TextEditingController(text: meeting.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('제목 수정', 'Rename')),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: tr('회의 제목', 'Meeting title'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              if (ctrl.text.trim().isNotEmpty) {
                onRename(ctrl.text.trim());
                Navigator.pop(ctx);
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('취소', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                onRename(ctrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: Text(tr('저장', 'Save')),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset pos) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 15, color: mutedText(context)),
              const SizedBox(width: 8),
              Text(tr('제목 수정', 'Rename'), style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          height: 28,
          child: Text(
            tr('그룹으로 이동', 'Move to group'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        ),
        if (meeting.groupId != null)
          PopupMenuItem(
            value: 'group_null',
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 15),
                const SizedBox(width: 8),
                Text(tr('미분류', 'Ungrouped'), style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        for (final g in groups)
          if (g.id != meeting.groupId)
            PopupMenuItem(
              value: 'group_${g.id}',
              child: Row(
                children: [
                  Icon(Icons.folder, size: 15, color: tintFg(context, Colors.amber)),
                  const SizedBox(width: 8),
                  Text(g.name, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 15, color: Colors.red.shade600),
              const SizedBox(width: 8),
              Text(
                tr('삭제', 'Delete'),
                style: TextStyle(fontSize: 13, color: Colors.red.shade600),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (!context.mounted) return;
      if (value == 'rename') {
        _showRenameDialog(context);
      } else if (value == 'delete') {
        // Dismissible(스와이프 삭제) 제거로 확인창이 여기로 이동 — macOS 스타일
        showMacosAlertDialog<void>(
          context: context,
          builder: (ctx) => MacosAlertDialog(
            appIcon: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.red,
              size: 48,
            ),
            title: Text(tr('회의 삭제', 'Delete meeting')),
            message: Text(
              tr('「${meeting.title}」을(를) 삭제하시겠습니까?\n전사·요약도 함께 삭제됩니다.',
                  'Delete "${meeting.title}"?\nIts transcript and summary will also be deleted.'),
              textAlign: TextAlign.center,
            ),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              onPressed: () {
                Navigator.pop(ctx);
                onDelete();
              },
              child: Text(tr('삭제', 'Delete')),
            ),
            secondaryButton: PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('취소', 'Cancel')),
            ),
          ),
        );
      } else if (value == 'group_null') {
        onMoveGroup(null);
      } else if (value.startsWith('group_')) {
        final id = int.tryParse(value.substring(6));
        if (id != null) onMoveGroup(id);
      }
    });
  }

  static String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  /// 자동 생성 날짜 제목 패턴 (한국어 '26년 08월 23일 23:01' / 영어 'Aug 23, 2026 23:01').
  static final _autoDateTitleRe = RegExp(
    r'^(\d{2}년 \d{2}월 \d{2}일 \d{2}:\d{2}|[A-Z][a-z]{2} \d{1,2}, \d{4} \d{2}:\d{2})',
  );

  /// 리스트 부제 — 제목과 같은 날짜를 반복하지 않는다.
  /// 제목이 자동 날짜 제목이면: "길이 · 전사 미리보기" (날짜는 제목에 이미 있음).
  /// 제목이 사용자 지정이면: "날짜 · 길이".
  String _subtitleFor(Meeting m) {
    final isAutoTitle = _autoDateTitleRe.hasMatch(m.title.trim());
    final parts = <String>[];
    if (!isAutoTitle) parts.add(_formatDate(m.createdAt));
    final dur = m.durationSeconds;
    if (dur >= 60) {
      final h = dur ~/ 3600;
      final min = (dur % 3600) ~/ 60;
      parts.add(h > 0 ? tr('$h시간 $min분', '${h}h ${min}m') : tr('$min분', '$min min'));
    }
    if (isAutoTitle) {
      final preview = (m.transcriptPreview ?? '').replaceAll('\n', ' ').trim();
      // '(전사본 없음 — ...)' 류 안내문은 미리보기가 아니므로 제외
      if (preview.isNotEmpty && !preview.startsWith('(')) parts.add(preview);
    }
    if (parts.isEmpty) parts.add(_formatDate(m.createdAt));
    return parts.join(' · ');
  }
}

class _SeriesSuggestionTile extends StatelessWidget {
  final MeetingSeriesSuggestion suggestion;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _SeriesSuggestionTile({
    required this.suggestion,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confidence = (suggestion.confidence * 100).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged: (value) => onChanged(value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
        title: Row(
          children: [
            Expanded(
              child: Text(
                suggestion.suggestedName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$confidence%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  '${suggestion.meetings.length}개 회의 · ${suggestion.reasons.join(' · ')}',
                  '${suggestion.meetings.length} meetings · ${suggestion.reasons.join(' · ')}',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: mutedText(context)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final meeting in suggestion.meetings.take(4))
                    _MiniMeetingChip(meeting: meeting),
                  if (suggestion.meetings.length > 4)
                    _CountChip(count: suggestion.meetings.length - 4),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniMeetingChip extends StatelessWidget {
  final Meeting meeting;

  const _MiniMeetingChip({required this.meeting});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: meeting.title,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tintBorder(context, Colors.grey)),
        ),
        child: Text(
          '${_formatShortDate(meeting.createdAt)} ${meeting.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: mutedText(context)),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final int count;

  const _CountChip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '+$count',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _formatShortDate(DateTime dt) =>
    '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';

// ── 그룹 추가 버튼 ────────────────────────────────────────────────────
class _AddGroupButton extends StatelessWidget {
  final Future<void> Function(String) onAdd;
  const _AddGroupButton({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _showDialog(context),
      icon: const Icon(Icons.create_new_folder_outlined, size: 16),
      label: Text(tr('그룹 추가', 'Add group'), style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: Colors.grey.shade600,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  void _showDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('새 그룹', 'New group')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('그룹명', 'Group name'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) async {
            if (v.trim().isNotEmpty) {
              await onAdd(v.trim());
              if (ctx.mounted) Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('취소', 'Cancel')),
          ),
          FilledButton(
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                await onAdd(ctrl.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: Text(tr('추가', 'Add')),
          ),
        ],
      ),
    );
  }
}

// ── 상태 아이콘 ───────────────────────────────────────────────────────
class _StatusIcon extends StatelessWidget {
  final MeetingStatus status;
  final bool selected;

  const _StatusIcon({required this.status, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.onPrimary;
    switch (status) {
      case MeetingStatus.done:
        return Icon(
          Icons.check_circle,
          size: 16,
          color: selected ? selectedColor : Colors.green,
        );
      case MeetingStatus.error:
        return Icon(
          Icons.error,
          size: 16,
          color: selected ? selectedColor : Colors.red.shade600,
        );
      case MeetingStatus.recording:
        return Icon(
          Icons.fiber_manual_record,
          size: 16,
          color: selected ? selectedColor : Colors.red,
        );
      case MeetingStatus.transcribing:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: selected ? selectedColor : null,
          ),
        );
      case MeetingStatus.summarizing:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: selected ? selectedColor : Colors.deepPurple.shade400,
          ),
        );
    }
  }
}

// ── 깜빡이는 빨간 점 (녹음 중 표시) ─────────────────────────────────
class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Sidebar.top 영역의 검색 입력창 ──────────────────────────────────────
/// macos_ui Sidebar.top 영역에 배치되는 검색 필드.
/// 자체 controller/focus 를 보유하고, searchQueryProvider 와 양방향 동기화한다.
/// ⌘F (shortcutFocusSearchSignalProvider) 도 여기서 처리.
class SidebarSearchTop extends ConsumerStatefulWidget {
  const SidebarSearchTop({super.key});

  @override
  ConsumerState<SidebarSearchTop> createState() => _SidebarSearchTopState();
}

class _SidebarSearchTopState extends ConsumerState<SidebarSearchTop> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // ⌘F → 검색 포커스
    ref.listen<int>(shortcutFocusSearchSignalProvider, (_, _) {
      _focus.requestFocus();
    });
    // searchQueryProvider 가 외부에서 비워질 때 controller 도 동기화
    ref.listen<String>(searchQueryProvider, (_, next) {
      if (next != _ctrl.text) {
        _ctrl.text = next;
        _ctrl.selection = TextSelection.collapsed(offset: next.length);
      }
    });

    final query = ref.watch(searchQueryProvider);
    final isAiMode = ref.watch(isAiSearchModeProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        decoration: InputDecoration(
          hintText: tr('회의 검색...', 'Search meetings...'),
          hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          prefixIcon: Icon(Icons.search, size: 16, color: Colors.grey.shade500),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  onPressed: () {
                    ref.read(searchQueryProvider.notifier).state = '';
                    ref.read(aiSearchResultsProvider.notifier).state = null;
                  },
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: scheme.primary),
          ),
          filled: true,
          fillColor: scheme.surface.withValues(alpha: 0.82),
        ),
        style: const TextStyle(fontSize: 12),
        onChanged: (v) {
          ref.read(searchQueryProvider.notifier).state = v;
          if (isAiMode) {
            ref.read(aiSearchResultsProvider.notifier).state = null;
          }
        },
      ),
    );
  }
}

// ── 다이제스트 시트 ────────────────────────────────────────────────
class _DigestSheet extends ConsumerStatefulWidget {
  final void Function(int meetingId) onJump;
  const _DigestSheet({required this.onJump});

  @override
  ConsumerState<_DigestSheet> createState() => _DigestSheetState();
}

class _DigestSheetState extends ConsumerState<_DigestSheet> {
  DigestPeriod _period = DigestPeriod.week;

  Future<DigestReportData> _load() async {
    final db = IsarService.instance.db;
    return DigestReport.generate(
      period: _period,
      meetingRepo: MeetingRepositoryImpl(db),
      summaryRepo: SummaryRepositoryImpl(db),
    );
  }

  String _fmtRange(DigestReportData r) {
    final s = r.rangeStart;
    final e = r.rangeEnd.subtract(const Duration(days: 1));
    String d(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    return '${d(s)} ~ ${d(e)}';
  }

  @override
  Widget build(BuildContext context) {
    return MacosSheet(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.event_note_outlined,
                    size: 22,
                    color: MacosTheme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr('${_period.label} 다이제스트', '${_period.label} digest'),
                    style: MacosTheme.of(
                      context,
                    ).typography.title2.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  // 주/월 토글
                  SegmentedButton<DigestPeriod>(
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      ButtonSegment(
                        value: DigestPeriod.week,
                        label: Text(tr('주간', 'Weekly'), style: const TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: DigestPeriod.month,
                        label: Text(tr('월간', 'Monthly'), style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                    selected: {_period},
                    onSelectionChanged: (sel) =>
                        setState(() => _period = sel.first),
                  ),
                  const SizedBox(width: 8),
                  MacosTooltip(
                    message: tr('닫기', 'Close'),
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
              const Divider(height: 20),
              Expanded(
                child: FutureBuilder<DigestReportData>(
                  future: _load(),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: ProgressCircle());
                    }
                    if (snap.hasError) {
                      return Center(child: Text(tr('오류: ${snap.error}', 'Error: ${snap.error}')));
                    }
                    final r = snap.data!;
                    if (r.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_month_outlined,
                              size: 36,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr('${_period.label}에는 회의가 없습니다.', 'No meetings ${_period.label.toLowerCase()}.'),
                              style: TextStyle(color: mutedText(context)),
                            ),
                          ],
                        ),
                      );
                    }
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 메타 정보
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                _DigestMetaPill(
                                  icon: Icons.date_range,
                                  text: _fmtRange(r),
                                ),
                                _DigestMetaPill(
                                  icon: Icons.event,
                                  text: tr('회의 ${r.meetingCount}회', '${r.meetingCount} meetings'),
                                ),
                                _DigestMetaPill(
                                  icon: Icons.check_circle_outline,
                                  text: tr('미완료 액션 ${r.pendingActions.length}건', '${r.pendingActions.length} open actions'),
                                ),
                                _DigestMetaPill(
                                  icon: Icons.gavel_rounded,
                                  text: tr('결정 ${r.decisions.length}건', '${r.decisions.length} decisions'),
                                ),
                                _DigestMetaPill(
                                  icon: Icons.help_outline,
                                  text: tr('미해결 이슈 ${r.openIssues.length}건', '${r.openIssues.length} open issues'),
                                ),
                              ],
                            ),
                          ),
                          // 미완료 액션
                          _DigestSection(
                            icon: Icons.check_circle_outline,
                            title: tr('미완료 액션', 'Open actions'),
                            empty: r.pendingActions.isEmpty,
                            emptyText: tr('완료되지 않은 액션이 없습니다.', 'No incomplete actions.'),
                            children: [
                              for (final a in r.pendingActions)
                                _DigestRow(
                                  text: a.item.task,
                                  meta: [
                                    if (a.item.owner.trim().isNotEmpty)
                                      a.item.owner,
                                    if (a.item.deadline.trim().isNotEmpty)
                                      a.item.deadline,
                                    a.meetingTitle,
                                  ],
                                  onTap: () => widget.onJump(a.meetingId),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _DigestSection(
                            icon: Icons.gavel_rounded,
                            title: tr('결정 사항', 'Decisions'),
                            empty: r.decisions.isEmpty,
                            emptyText: tr('결정사항이 없습니다.', 'No decisions.'),
                            children: [
                              for (final d in r.decisions)
                                _DigestRow(
                                  text: d.text,
                                  meta: [d.meetingTitle],
                                  onTap: () => widget.onJump(d.meetingId),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _DigestSection(
                            icon: Icons.help_outline,
                            title: tr('미해결 이슈', 'Open issues'),
                            empty: r.openIssues.isEmpty,
                            emptyText: tr('미해결 이슈가 없습니다.', 'No open issues.'),
                            children: [
                              for (final q in r.openIssues)
                                _DigestRow(
                                  text: q.text,
                                  meta: [q.meetingTitle],
                                  onTap: () => widget.onJump(q.meetingId),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DigestMetaPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DigestMetaPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: mutedText(context)),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: mutedText(context)),
          ),
        ],
      ),
    );
  }
}

class _DigestSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool empty;
  final String emptyText;
  final List<Widget> children;
  const _DigestSection({
    required this.icon,
    required this.title,
    required this.empty,
    required this.emptyText,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
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
              ],
            ),
            const Divider(height: 12),
            if (empty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  emptyText,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

class _DigestRow extends StatelessWidget {
  final String text;
  final List<String> meta;
  final VoidCallback onTap;
  const _DigestRow({
    required this.text,
    required this.meta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.fiber_manual_record,
                size: 6,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: const TextStyle(fontSize: 13)),
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        meta.join(' · '),
                        style: TextStyle(
                          fontSize: 11,
                          color: mutedText(context),
                        ),
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
    );
  }
}

// ── 시리즈 비교 시트 ──────────────────────────────────────────────
class _SeriesOverviewSheet extends ConsumerStatefulWidget {
  final void Function(int groupId) onJumpToSeries;
  const _SeriesOverviewSheet({required this.onJumpToSeries});

  @override
  ConsumerState<_SeriesOverviewSheet> createState() =>
      _SeriesOverviewSheetState();
}

class _SeriesOverviewSheetState extends ConsumerState<_SeriesOverviewSheet> {
  Future<List<SeriesOverviewItem>> _load() async {
    final db = IsarService.instance.db;
    final groups = await MeetingGroupRepositoryImpl(db).getAllGroups();
    return SeriesOverview.analyze(
      groups: groups,
      meetingRepo: MeetingRepositoryImpl(db),
      summaryRepo: SummaryRepositoryImpl(db),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MacosSheet(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bar_chart_rounded,
                    size: 22,
                    color: MacosTheme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr('시리즈 비교', 'Compare series'),
                    style: MacosTheme.of(
                      context,
                    ).typography.title2.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  MacosTooltip(
                    message: tr('닫기', 'Close'),
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
              const SizedBox(height: 8),
              Text(
                tr(
                  '회의 1회 이상 묶인 시리즈를 마지막 회의가 최신인 순으로 표시합니다.',
                  'Series with at least one meeting, ordered by most recent meeting.',
                ),
                style: TextStyle(fontSize: 11, color: mutedText(context)),
              ),
              const Divider(height: 20),
              Expanded(
                child: FutureBuilder<List<SeriesOverviewItem>>(
                  future: _load(),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: ProgressCircle());
                    }
                    if (snap.hasError) {
                      return Center(child: Text(tr('오류: ${snap.error}', 'Error: ${snap.error}')));
                    }
                    final items = snap.data!;
                    if (items.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_motion,
                              size: 36,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr('아직 회의가 묶인 시리즈가 없습니다.', 'No series with grouped meetings yet.'),
                              style: TextStyle(color: mutedText(context)),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _SeriesOverviewCard(
                        item: items[i],
                        onTap: () => widget.onJumpToSeries(items[i].group.id),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeriesOverviewCard extends StatelessWidget {
  final SeriesOverviewItem item;
  final VoidCallback onTap;
  const _SeriesOverviewCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final report = item.report;
    final daysAgo = item.daysSinceLastMeeting();
    final pendingCount = report.pendingActionItems.length;
    final issuesCount = report.recurringIssues.length;
    final decisionsCount = report.recentDecisions.length;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 시리즈 이름 + 회의 횟수
              Row(
                children: [
                  Icon(
                    Icons.timeline,
                    size: 16,
                    color: MacosTheme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.group.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    tr('${report.meetingCount}회', '${report.meetingCount}×'),
                    style: TextStyle(
                      fontSize: 12,
                      color: mutedText(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 11,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 메타 정보 줄
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  if (report.averageIntervalDays != null)
                    _OverviewChip(
                      icon: Icons.schedule,
                      text: tr('평균 ${report.averageIntervalDays}일', 'Avg ${report.averageIntervalDays}d'),
                    ),
                  if (daysAgo != null)
                    _OverviewChip(
                      icon: Icons.history,
                      text: daysAgo == 0 ? tr('오늘 회의', 'Met today') : tr('$daysAgo일 전', '$daysAgo days ago'),
                    ),
                  _OverviewChip(
                    icon: Icons.check_circle_outline,
                    text: tr('미완료 $pendingCount', 'Open $pendingCount'),
                    color: pendingCount > 0
                        ? Colors.orange.shade700
                        : Colors.grey.shade600,
                  ),
                  _OverviewChip(
                    icon: Icons.warning_amber_rounded,
                    text: tr('지속 이슈 $issuesCount', 'Recurring $issuesCount'),
                    color: issuesCount > 0
                        ? Colors.red.shade600
                        : Colors.grey.shade600,
                  ),
                  _OverviewChip(
                    icon: Icons.gavel_rounded,
                    text: tr('결정 $decisionsCount', 'Decisions $decisionsCount'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _OverviewChip({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade700;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: c)),
      ],
    );
  }
}

/// 업로드 파일을 WAV로 변환하는 동안 표시하는 모달.
class _ImportConvertingDialog extends StatelessWidget {
  final String ext;
  const _ImportConvertingDialog({required this.ext});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: MacosTheme.of(context).canvasColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(height: 16),
            Text(
              tr('$ext 파일을 변환하는 중...', 'Converting $ext file...'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              tr('16kHz 모노 WAV로 변환합니다. 잠시만 기다려 주세요.',
                  'Converting to 16kHz mono WAV. Please wait.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: mutedText(context)),
            ),
          ],
        ),
      ),
    );
  }
}
