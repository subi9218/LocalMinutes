import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';

enum TrayStartState { ready, storageRequired, modelsRequired, busy }

/// macOS 메뉴바 트레이 서비스 — 앱 안 열고도 빠른 녹음 시작/정지/북마크.
///
/// 상태:
///   - idle:      회색 마이크 아이콘
///   - recording: 회색 마이크 + 빨간 점 (+ 메뉴 라벨에 경과 시간)
///
/// 콜백:
///   - [onStartRecord]: "빠른 녹음 시작" / 트레이 아이콘 좌클릭(idle 상태)
///   - [onStopRecord]:  "녹음 정지"
///   - [onBookmark]:    "북마크 추가" (녹음 중일 때만)
///   - [onShowWindow]:  "앱 창 열기" / 트레이 아이콘 좌클릭(녹음 중)
class MenuBarService with TrayListener {
  MenuBarService._();
  static final instance = MenuBarService._();

  bool _initialized = false;
  bool _recording = false;
  TrayStartState _startState = TrayStartState.ready;
  String? _busyLabel;
  Duration _elapsed = Duration.zero;
  Timer? _recordingTicker;

  VoidCallback? onStartRecord;
  VoidCallback? onStopRecord;
  VoidCallback? onBookmark;
  VoidCallback? onShowWindow;
  VoidCallback? onQuit;

  /// macOS 외 플랫폼은 noop. (현재 macOS 전용 앱이지만 안전장치)
  bool get _supported => Platform.isMacOS;

  Future<void> init() async {
    if (_initialized || !_supported) return;
    try {
      trayManager.addListener(this);
      await trayManager.setIcon(
        'assets/tray/mic_idle.png',
        isTemplate: true, // macOS dark/light 모드 자동 대응 (단색 아이콘)
      );
      await _rebuildMenu();
      _initialized = true;
      debugPrint('[MenuBarService] initialized');
    } catch (e) {
      debugPrint('[MenuBarService] init failed: $e');
    }
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    _recordingTicker?.cancel();
    _recordingTicker = null;
    trayManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
    _initialized = false;
  }

  /// 녹음 상태 업데이트 → 아이콘/메뉴 갱신
  Future<void> setRecordingState({
    required bool isRecording,
    Duration elapsed = Duration.zero,
  }) async {
    if (!_initialized || !_supported) return;
    final stateChanged = _recording != isRecording;
    _recording = isRecording;
    _elapsed = elapsed;
    try {
      if (stateChanged) {
        await trayManager.setIcon(
          isRecording
              ? 'assets/tray/mic_recording.png'
              : 'assets/tray/mic_idle.png',
          isTemplate: !isRecording, // 녹음 중엔 빨간 점이 색상 정보를 갖도록 비-템플릿
        );
        _syncRecordingTicker();
      }
      await _rebuildMenu();
    } catch (e) {
      debugPrint('[MenuBarService] setRecordingState failed: $e');
    }
  }

  /// 녹음하지 않는 상태에서 트레이 메뉴에 표시할 "시작 가능 여부"를 갱신한다.
  Future<void> setStartState(TrayStartState state, {String? busyLabel}) async {
    final changed = _startState != state || _busyLabel != busyLabel;
    _startState = state;
    _busyLabel = busyLabel;
    if (!_initialized || !_supported || !changed || _recording) return;
    try {
      await _rebuildMenu();
    } catch (e) {
      debugPrint('[MenuBarService] setStartState failed: $e');
    }
  }

  void _syncRecordingTicker() {
    _recordingTicker?.cancel();
    _recordingTicker = null;
    if (!_recording) return;

    _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_initialized || !_recording) return;
      _elapsed += const Duration(seconds: 1);
      try {
        await _rebuildMenu();
      } catch (e) {
        debugPrint('[MenuBarService] ticker rebuild failed: $e');
      }
    });
  }

  Future<void> _rebuildMenu() async {
    final elapsedStr = _formatElapsed(_elapsed);
    final menu = Menu(
      items: [
        if (_recording) ...[
          MenuItem(
            key: 'recording_status',
            label: '🔴 녹음 중 · $elapsedStr',
            disabled: true,
          ),
          MenuItem.separator(),
          MenuItem(key: 'bookmark', label: '📍 북마크 추가  (⌘B)'),
          MenuItem(key: 'stop', label: '■ 녹음 정지  (⌘⇧R)'),
        ] else ...[
          _startMenuItem(),
        ],
        MenuItem.separator(),
        MenuItem(key: 'show', label: '📂 앱 창 열기'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '종료'),
      ],
    );
    await trayManager.setContextMenu(menu);
    await trayManager.setToolTip(
      _recording ? '적자생존 — 녹음 중 ($elapsedStr)' : _idleToolTip(),
    );
  }

  MenuItem _startMenuItem() {
    switch (_startState) {
      case TrayStartState.ready:
        return MenuItem(key: 'start', label: '🎙 빠른 녹음 시작  (⌘⇧R)');
      case TrayStartState.storageRequired:
        return MenuItem(
          key: 'storage_required',
          label: '⚠ 저장 폴더 설정 필요',
          disabled: true,
        );
      case TrayStartState.modelsRequired:
        return MenuItem(
          key: 'models_required',
          label: '⚠ AI 모델 준비 필요',
          disabled: true,
        );
      case TrayStartState.busy:
        return MenuItem(
          key: 'busy',
          label: '⏳ ${_busyLabel ?? '처리 중...'}',
          disabled: true,
        );
    }
  }

  String _idleToolTip() {
    switch (_startState) {
      case TrayStartState.ready:
        return '적자생존';
      case TrayStartState.storageRequired:
        return '적자생존 — 저장 폴더 설정 필요';
      case TrayStartState.modelsRequired:
        return '적자생존 — AI 모델 준비 필요';
      case TrayStartState.busy:
        return '적자생존 — ${_busyLabel ?? '처리 중'}';
    }
  }

  static String _formatElapsed(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── TrayListener ────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    // 좌클릭: 녹음 중이면 창 열기, 아니면 우클릭 메뉴 열기
    if (_recording) {
      onShowWindow?.call();
    } else {
      // macOS는 좌클릭에도 컨텍스트 메뉴 노출
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'start':
        if (_startState == TrayStartState.ready) {
          onStartRecord?.call();
        } else {
          onShowWindow?.call();
        }
        break;
      case 'stop':
        onStopRecord?.call();
        break;
      case 'bookmark':
        onBookmark?.call();
        break;
      case 'show':
        onShowWindow?.call();
        break;
      case 'quit':
        if (onQuit != null) {
          onQuit!.call();
        } else {
          // 기본: 정상 종료 시도 (lifecycle 정리 호출)
          SystemNavigator.pop();
        }
        break;
    }
  }
}
