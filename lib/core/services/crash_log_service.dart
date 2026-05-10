import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 앱 충돌·예외 로그 캡처 서비스.
///
/// 사용법:
///   1) main()에서 [installGlobalHandlers] 호출 (runApp 직전)
///   2) 모든 unhandled exception이 `<appSupport>/logs/crash.log`로 누적
///   3) [readLog]/[exportPath]/[clearLog]로 설정 화면에서 관리
///
/// 로그 회전: 5 MB 초과하면 .old로 백업 후 새로 시작
class CrashLogService {
  CrashLogService._();
  static final instance = CrashLogService._();

  bool _installed = false;
  File? _file;
  Future<File>? _initFuture;
  static const int _maxBytes = 5 * 1024 * 1024;

  /// 동일 에러 폭주 방지 — 같은 에러 메시지+stack 첫 줄을 1초 내에 100회 이상
  /// 기록하지 않음. 로그 파일 부풀음·디스크 I/O 폭주 방지.
  final Map<String, _DedupeEntry> _recentErrors = {};
  static const int _dedupeWindowMs = 1000;
  static const int _dedupeMaxPerWindow = 5;

  /// runApp() 호출 전에 한 번 부르세요.
  /// `runZonedGuarded`로 감싸서 zoned exception까지 잡으려면
  /// 호출자가 별도로 zoned 영역을 만들어야 합니다.
  void installGlobalHandlers() {
    if (_installed) return;
    _installed = true;

    // 1) Flutter 프레임워크 에러 (위젯 빌드, 렌더 등)
    FlutterError.onError = (FlutterErrorDetails details) {
      _writeLine(
        'FLUTTER ERROR',
        details.exceptionAsString(),
        details.stack,
        context: details.context?.toString(),
        library: details.library,
      );
      // 디버그 콘솔에도 그대로 출력 (개발자 편의)
      FlutterError.presentError(details);
    };

    // 2) 플랫폼/엔진 단의 unhandled exception
    PlatformDispatcher.instance.onError = (error, stack) {
      _writeLine('PLATFORM ERROR', error, stack);
      return true; // 앱 강제종료 방지
    };

    debugPrint('[CrashLog] global handlers installed');
  }

  /// 사용자가 명시적으로 기록하고 싶은 에러 (try-catch 안에서 호출)
  void recordCaught(Object error, StackTrace? stack, {String? context}) {
    _writeLine('CAUGHT', error, stack, context: context);
  }

  /// 진단용 정보 로그 — 에러 아님. 단계 진행 추적, 메모리 등 기록.
  /// stack 없이 짧게 누적되며 throttle 적용 안 됨.
  void info(String message, {String? context}) {
    _writeInfo(message, context: context);
  }

  Future<void> _writeInfo(String message, {String? context}) async {
    try {
      final f = await _ensureFile();
      final ts = DateTime.now().toIso8601String();
      final ctxPart = context != null ? '  context=$context' : '';
      final line = '[$ts] INFO$ctxPart  $message\n';
      await f.writeAsString(line, mode: FileMode.append, flush: false);
    } catch (_) {}
  }

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    if (_initFuture != null) return _initFuture!;
    _initFuture = _initImpl();
    final f = await _initFuture!;
    _file = f;
    return f;
  }

  Future<File> _initImpl() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/logs');
    if (!await dir.exists()) await dir.create(recursive: true);
    final f = File('${dir.path}/crash.log');
    if (!await f.exists()) await f.create();
    return f;
  }

  Future<void> _writeLine(
    String tag,
    Object error,
    StackTrace? stack, {
    String? context,
    String? library,
  }) async {
    // 동일 에러 폭주 throttle — 같은 메시지+stack 첫 라인 키
    try {
      final stackHead = stack == null
          ? ''
          : stack.toString().split('\n').take(2).join('|');
      final key = '$tag::$error::$stackHead';
      final now = DateTime.now().millisecondsSinceEpoch;
      final entry = _recentErrors[key];
      if (entry != null && now - entry.firstMs < _dedupeWindowMs) {
        entry.count++;
        if (entry.count > _dedupeMaxPerWindow) {
          if (entry.count == _dedupeMaxPerWindow + 1) {
            // 처음 한 번만 throttle 사실 알림
            // ignore: avoid_print
            print('[CrashLog] suppressing repeated error: $error');
          }
          return;
        }
      } else {
        _recentErrors[key] = _DedupeEntry(now);
      }
      // 최대 50개만 보관
      if (_recentErrors.length > 50) {
        final oldKeys = _recentErrors.entries
            .where((e) => now - e.value.firstMs > _dedupeWindowMs * 5)
            .map((e) => e.key)
            .toList();
        for (final k in oldKeys) {
          _recentErrors.remove(k);
        }
      }
    } catch (_) {
      // dedupe 실패는 무시하고 계속 진행
    }

    try {
      final f = await _ensureFile();
      // 회전: 크기 초과 시 .old 백업 후 새로 시작
      final stat = await f.stat();
      if (stat.size > _maxBytes) {
        final old = File('${f.path}.old');
        if (await old.exists()) await old.delete();
        await f.rename(old.path);
        _file = null; // ensureFile에서 새로 생성
      }
      final cur = await _ensureFile();
      final ts = DateTime.now().toIso8601String();
      final libPart = library != null ? '  library=$library' : '';
      final ctxPart = context != null ? '  context=$context' : '';
      final stackPart = stack == null ? '' : '\n$stack';
      final line = '[$ts] $tag$libPart$ctxPart\n  $error$stackPart\n';
      await cur.writeAsString(line, mode: FileMode.append, flush: false);
      // 디버그 콘솔에도 짧게 표시
      debugPrint('[CrashLog] $tag: $error');
    } catch (e) {
      // 로그 자체가 실패하면 stderr로만 남김
      // ignore: avoid_print
      print('[CrashLog] write failed: $e');
    }
  }

  /// 로그 파일 절대 경로 (없으면 생성)
  Future<String> exportPath() async {
    final f = await _ensureFile();
    return f.path;
  }

  /// 로그 파일 내용 전체 읽기 (최대 [maxChars]자 끝부분만)
  Future<String> readLog({int maxChars = 80000}) async {
    try {
      final f = await _ensureFile();
      final s = await f.readAsString();
      if (s.length <= maxChars) return s;
      return '... [앞부분 ${s.length - maxChars}자 생략]\n${s.substring(s.length - maxChars)}';
    } catch (e) {
      return '로그 읽기 실패: $e';
    }
  }

  /// 로그 파일 비우기
  Future<void> clearLog() async {
    try {
      final f = await _ensureFile();
      await f.writeAsString('', mode: FileMode.write);
      // 백업도 삭제
      final old = File('${f.path}.old');
      if (await old.exists()) await old.delete();
    } catch (e) {
      debugPrint('[CrashLog] clear failed: $e');
    }
  }

  /// 현재 로그 파일 크기 (바이트)
  Future<int> sizeBytes() async {
    try {
      final f = await _ensureFile();
      final s = await f.stat();
      return s.size;
    } catch (_) {
      return 0;
    }
  }
}

class _DedupeEntry {
  final int firstMs;
  int count = 1;
  _DedupeEntry(this.firstMs);
}
