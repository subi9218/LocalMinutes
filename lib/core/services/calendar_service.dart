import 'dart:io';

import 'package:flutter/foundation.dart';

/// macOS Calendar.app 이벤트 한 건
class CalendarEvent {
  final String title;
  final DateTime start;
  final DateTime end;
  final String calendarName;

  const CalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.calendarName,
  });

  Duration get duration => end.difference(start);

  @override
  String toString() =>
      'CalendarEvent($title, $start ~ $end, cal=$calendarName)';
}

/// macOS Calendar.app 이벤트 조회 서비스 — AppleScript(`osascript`) 활용.
///
/// 첫 호출 시 macOS가 자동화 권한 다이얼로그를 띄움
/// ("Local Minutes가 Calendar 앱을 제어하려고 합니다"). 수락 후부터 정상 동작.
///
/// 권한 거부 시 [getUpcomingEvents]는 빈 리스트를 반환 (silent fail).
class CalendarService {
  CalendarService._();
  static final instance = CalendarService._();

  /// 마지막으로 성공한 호출 시각 — 너무 잦은 호출 방지용 캐시.
  DateTime? _lastFetchAt;
  List<CalendarEvent> _cache = const [];
  static const _cacheTtl = Duration(seconds: 30);

  /// 권한 한 번 거부 후 매번 다이얼로그 뜨는 걸 방지하기 위한 토글.
  bool _disabled = false;

  /// 다가오는/현재 진행 중인 이벤트 조회.
  ///
  /// [windowBefore]: 현재 시각 기준 과거 X분까지 (이미 시작된 회의 포함)
  /// [windowAfter]:  현재 시각 기준 미래 Y분까지 (곧 시작할 회의 포함)
  Future<List<CalendarEvent>> getUpcomingEvents({
    Duration windowBefore = const Duration(minutes: 15),
    Duration windowAfter = const Duration(hours: 1),
    bool useCache = true,
  }) async {
    if (!Platform.isMacOS || _disabled) return const [];

    // 캐시 — UI 빌드마다 호출되어도 osascript가 매번 안 돌도록
    if (useCache &&
        _lastFetchAt != null &&
        DateTime.now().difference(_lastFetchAt!) < _cacheTtl) {
      return _cache;
    }

    final now = DateTime.now();
    final from = now.subtract(windowBefore);
    final to = now.add(windowAfter);

    // AppleScript로 Calendar 이벤트 조회.
    // - 모든 캘린더의 이벤트를 합쳐서 가져옴
    // - 출력 형식: title|start_iso|end_iso|cal_name (한 줄당 한 이벤트)
    // - 구분자에 |/줄바꿈이 들어가는 케이스는 드물지만, 발생 시 raw text로 안전 처리
    final script =
        '''
on iso(d)
  set y to year of d
  set mo to (month of d as integer)
  set da to day of d
  set hh to hours of d
  set mm to minutes of d
  set ss to seconds of d
  return (y as text) & "-" & my pad(mo) & "-" & my pad(da) & "T" & my pad(hh) & ":" & my pad(mm) & ":" & my pad(ss)
end iso

on pad(n)
  set s to (n as text)
  if (count of s) < 2 then return "0" & s
  return s
end pad

set fromDate to current date
set fromDate's year to ${from.year}
set fromDate's month to ${from.month}
set fromDate's day to ${from.day}
set fromDate's hours to ${from.hour}
set fromDate's minutes to ${from.minute}
set fromDate's seconds to ${from.second}

set toDate to current date
set toDate's year to ${to.year}
set toDate's month to ${to.month}
set toDate's day to ${to.day}
set toDate's hours to ${to.hour}
set toDate's minutes to ${to.minute}
set toDate's seconds to ${to.second}

set output to ""
tell application "Calendar"
  set calList to every calendar
  repeat with cal in calList
    set calName to title of cal
    try
      set evs to (every event of cal whose start date ≥ fromDate and start date ≤ toDate)
      repeat with e in evs
        set evTitle to summary of e
        set evStart to start date of e
        set evEnd to end date of e
        set output to output & evTitle & "|" & my iso(evStart) & "|" & my iso(evEnd) & "|" & calName & linefeed
      end repeat
    end try
  end repeat
end tell
return output
''';

    try {
      final result = await Process.run('osascript', [
        '-e',
        script,
      ]).timeout(const Duration(seconds: 6));
      if (result.exitCode != 0) {
        final stderr = (result.stderr ?? '').toString();
        debugPrint(
          '[CalendarService] osascript exit=${result.exitCode} '
          'stderr=$stderr',
        );
        // 권한 거부의 일반 패턴: "Not authorized" / "AppleEvent" / "1743"
        if (stderr.contains('Not authorized') || stderr.contains('-1743')) {
          _disabled = true;
        }
        return const [];
      }
      final raw = (result.stdout ?? '').toString();
      final events = <CalendarEvent>[];
      for (final line in raw.split('\n')) {
        final l = line.trim();
        if (l.isEmpty) continue;
        final parts = l.split('|');
        if (parts.length < 4) continue;
        try {
          final title = parts[0].trim();
          final start = DateTime.parse(parts[1].trim());
          final end = DateTime.parse(parts[2].trim());
          final cal = parts.sublist(3).join('|').trim();
          if (title.isEmpty) continue;
          events.add(
            CalendarEvent(
              title: title,
              start: start,
              end: end,
              calendarName: cal,
            ),
          );
        } catch (e) {
          debugPrint('[CalendarService] parse fail: $l → $e');
        }
      }
      // 시작 시간 기준 정렬 (가장 가까운 회의가 먼저)
      events.sort((a, b) => a.start.compareTo(b.start));
      _cache = events;
      _lastFetchAt = DateTime.now();
      debugPrint('[CalendarService] fetched ${events.length} events');
      return events;
    } catch (e) {
      debugPrint('[CalendarService] error: $e');
      return const [];
    }
  }

  /// 사용자가 명시적으로 다시 권한 시도하고 싶을 때 호출 (설정 화면 등)
  void resetDisabled() {
    _disabled = false;
    _cache = const [];
    _lastFetchAt = null;
  }

  /// 녹음한 회의를 macOS Calendar.app에 새 이벤트로 등록.
  /// 기본 캘린더(첫 번째 쓰기 가능 캘린더)에 추가됨.
  ///
  /// 반환: 성공 시 null, 실패 시 사용자에게 보여줄 사유.
  Future<String?> addEventToCalendar({
    required String title,
    required DateTime start,
    required DateTime end,
    String description = '',
  }) async {
    if (!Platform.isMacOS) return '이 기능은 macOS 전용입니다';
    if (_disabled) return '캘린더 권한이 거부되어 있습니다';
    if (title.trim().isEmpty) return '제목이 비어 있습니다';

    // AppleScript에서 문자열에 따옴표/줄바꿈이 들어가도 안전하도록 이스케이프.
    String escape(String s) =>
        s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

    final safeTitle = escape(title.trim());
    final safeDesc = escape(description.trim());

    final script =
        '''
set startDate to current date
set startDate's year to ${start.year}
set startDate's month to ${start.month}
set startDate's day to ${start.day}
set startDate's hours to ${start.hour}
set startDate's minutes to ${start.minute}
set startDate's seconds to ${start.second}

set endDate to current date
set endDate's year to ${end.year}
set endDate's month to ${end.month}
set endDate's day to ${end.day}
set endDate's hours to ${end.hour}
set endDate's minutes to ${end.minute}
set endDate's seconds to ${end.second}

tell application "Calendar"
  set targetCal to missing value
  -- "writable" 속성을 가진 첫 번째 캘린더 찾기 (휴일 캘린더 등 read-only는 제외)
  repeat with c in calendars
    try
      if writable of c is true then
        set targetCal to c
        exit repeat
      end if
    on error
      -- writable 속성이 없으면 그냥 첫 캘린더 시도
      if targetCal is missing value then set targetCal to c
    end try
  end repeat
  if targetCal is missing value then
    set targetCal to first calendar
  end if
  tell targetCal
    make new event with properties {summary:"$safeTitle", start date:startDate, end date:endDate, description:"$safeDesc"}
  end tell
end tell
return "OK"
''';

    try {
      final result = await Process.run('osascript', [
        '-e',
        script,
      ]).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) {
        final stderr = (result.stderr ?? '').toString();
        debugPrint(
          '[CalendarService] addEvent fail exit=${result.exitCode} '
          'stderr=$stderr',
        );
        if (stderr.contains('Not authorized') || stderr.contains('-1743')) {
          _disabled = true;
          return '캘린더 접근 권한이 거부되었습니다 (시스템 설정 > 개인정보 보호 > 자동화)';
        }
        return '캘린더 등록 실패: ${stderr.split('\n').first}';
      }
      // 캐시 무효화 — 새 이벤트가 다음 fetch에서 보이도록
      _lastFetchAt = null;
      _cache = const [];
      debugPrint('[CalendarService] event added: $title @ $start');
      return null;
    } catch (e) {
      debugPrint('[CalendarService] addEvent error: $e');
      return '캘린더 등록 오류: $e';
    }
  }
}
