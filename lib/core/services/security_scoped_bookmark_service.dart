import 'dart:io';

import 'package:flutter/services.dart';

import 'app_settings.dart';

class SecurityScopedBookmarkService {
  SecurityScopedBookmarkService._();

  static const _channel = MethodChannel('app/security_scoped_bookmark');

  static Future<String?> createBookmarkForPath(String path) async {
    if (!Platform.isMacOS) return null;
    return _channel.invokeMethod<String>('createBookmark', {'path': path});
  }

  static Future<bool> startAccessingBookmark(String bookmark) async {
    if (!Platform.isMacOS || bookmark.isEmpty) return true;
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'startAccessingBookmark',
      {'bookmark': bookmark},
    );
    return result?['accessing'] == true;
  }

  static Future<void> stopAccessingBookmark(String bookmark) async {
    if (!Platform.isMacOS || bookmark.isEmpty) return;
    await _channel.invokeMethod<void>('stopAccessingBookmark', {
      'bookmark': bookmark,
    });
  }

  static Future<bool> restoreRecordingsFolderAccess() async {
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
    if (Platform.isMacOS) {
      final bookmark = await createBookmarkForPath(path);
      if (bookmark == null || bookmark.isEmpty) {
        throw const FileSystemException('선택한 폴더 권한을 저장하지 못했습니다.');
      }
      await AppSettings.instance.setRecordingsSaveBookmark(bookmark);
      final accessing = await startAccessingBookmark(bookmark);
      if (!accessing) {
        throw const FileSystemException('선택한 폴더 접근 권한을 시작하지 못했습니다.');
      }
    }
    await AppSettings.instance.setRecordingsSavePath(path);
  }
}
