import 'dart:io';

import 'package:flutter/services.dart';

import 'app_settings.dart';

class SecurityScopedBookmarkService {
  SecurityScopedBookmarkService._();

  static const _channel = MethodChannel('app/security_scoped_bookmark');
  static Future<bool>? _sandboxed;

  static Future<bool> isSandboxed() {
    if (!Platform.isMacOS) return Future.value(false);
    return _sandboxed ??= _channel
        .invokeMethod<bool>('isSandboxed')
        .timeout(const Duration(seconds: 2), onTimeout: () => false)
        .then((value) => value ?? false)
        .catchError((_) => false);
  }

  static Future<String?> createBookmarkForPath(String path) async {
    if (!Platform.isMacOS) return null;
    return _channel
        .invokeMethod<String>('createBookmark', {'path': path})
        .timeout(const Duration(seconds: 3));
  }

  /// 현재 접근 중인 북마크 — 같은 북마크로 start를 중복 호출하면
  /// 네이티브 쪽 URL 맵이 덮어써져 이전 start를 stop할 수 없게 되고
  /// (커널 리소스 누수), macOS의 start/stop 쌍이 어긋난다.
  static final Set<String> _activeBookmarks = {};

  static Future<bool> startAccessingBookmark(String bookmark) async {
    if (!Platform.isMacOS || bookmark.isEmpty) return true;
    if (_activeBookmarks.contains(bookmark)) return true; // 이미 접근 중
    final result = await _channel
        .invokeMethod<Map<Object?, Object?>>('startAccessingBookmark', {
          'bookmark': bookmark,
        })
        .timeout(const Duration(seconds: 3));
    final accessing = result?['accessing'] == true;
    if (accessing) _activeBookmarks.add(bookmark);
    return accessing;
  }

  static Future<void> stopAccessingBookmark(String bookmark) async {
    if (!Platform.isMacOS || bookmark.isEmpty) return;
    await _channel.invokeMethod<void>('stopAccessingBookmark', {
      'bookmark': bookmark,
    });
    _activeBookmarks.remove(bookmark);
  }

  static Future<bool> restoreRecordingsFolderAccess() async {
    if (!await isSandboxed()) return true;
    final bookmark = AppSettings.instance.recordingsSaveBookmark;
    if (bookmark.isEmpty) {
      return AppSettings.instance.recordingsSavePath.isEmpty;
    }
    try {
      return await startAccessingBookmark(bookmark);
    } on PlatformException {
      return false;
    }
  }

  static Future<void> saveRecordingsFolderSelection(String path) async {
    final oldBookmark = AppSettings.instance.recordingsSaveBookmark;
    if (await isSandboxed()) {
      final bookmark = await createBookmarkForPath(path);
      if (bookmark == null || bookmark.isEmpty) {
        throw const FileSystemException('선택한 폴더 권한을 저장하지 못했습니다.');
      }
      await AppSettings.instance.setRecordingsSaveBookmark(bookmark);
      final accessing = await startAccessingBookmark(bookmark);
      if (!accessing) {
        throw const FileSystemException('선택한 폴더 접근 권한을 시작하지 못했습니다.');
      }
      // 새 폴더 접근이 확정된 뒤에만 이전 폴더의 보안 스코프를 해제한다.
      // (중간에 실패하면 사용자가 접근 권한을 모두 잃지 않도록 순서를 보장)
      if (oldBookmark.isNotEmpty && oldBookmark != bookmark) {
        try {
          await stopAccessingBookmark(oldBookmark);
        } catch (_) {
          // 이전 스코프 해제 실패는 폴더 선택을 막지 않는다(best-effort).
        }
      }
    }
    await AppSettings.instance.setRecordingsSavePath(path);
  }
}
