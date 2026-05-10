import 'dart:ffi';
import 'dart:async';
import 'package:ffi/ffi.dart';
import '../services/crash_log_service.dart';
import 'llama_ffi.dart';
import 'whisper_ffi.dart';

// 피크 메모리 추정:
//   앱 기본:          ~200 MB
//   STT (Whisper):    ~2 GB (로드) + ~500 MB (추론)
//   LLM (Gemma 4):    ~6–8 GB (로드) + ~1 GB (KV 캐시 @ n_ctx=8192)
//   언로드 후:        ~200 MB (mmap 반환)
//
// 단일 모델 강제:
//   파이프라인 = STT 완료 → unloadStt → loadLlm → 요약 → unloadLlm
//   LLM 로드 중 STT 로드 시도 → StateError
//   STT 로드 중 LLM 로드 시도 → StateError

class OnDeviceModelManager {
  static final OnDeviceModelManager instance = OnDeviceModelManager._();
  OnDeviceModelManager._();

  Future<void> _nativeTaskTail = Future<void>.value();
  String? _activeNativeTaskLabel;
  String? _lastQueuedNativeTaskLabel;
  int _queuedNativeTaskCount = 0;
  final _nativeTaskController =
      StreamController<NativeModelTaskSnapshot>.broadcast();

  bool get isNativeTaskBusy => _activeNativeTaskLabel != null;
  String? get activeNativeTaskLabel => _activeNativeTaskLabel;
  NativeModelTaskSnapshot get nativeTaskSnapshot => NativeModelTaskSnapshot(
    activeLabel: _activeNativeTaskLabel,
    queuedLabel: _lastQueuedNativeTaskLabel,
    queuedCount: _queuedNativeTaskCount,
  );
  Stream<NativeModelTaskSnapshot> get nativeTaskStream =>
      _nativeTaskController.stream;

  void _notifyNativeTaskChanged() {
    if (_nativeTaskController.isClosed) return;
    _nativeTaskController.add(nativeTaskSnapshot);
  }

  /// STT, 화자 분리, LLM 로드/추론/해제를 한 번에 하나만 실행한다.
  ///
  /// whisper.cpp, sherpa-onnx, llama.cpp 모두 Metal/네이티브 메모리를 쓰므로
  /// 서로 겹치면 앱 전체 abort로 이어질 수 있다. 긴 작업은 lease를 잡은 뒤
  /// 반드시 finally에서 release해야 한다.
  Future<NativeModelTaskLease> acquireNativeTask(String label) async {
    final previous = _nativeTaskTail;
    final myTurn = Completer<void>();
    _nativeTaskTail = myTurn.future;

    final shouldWait = _activeNativeTaskLabel != null;
    if (shouldWait) {
      _queuedNativeTaskCount++;
      _lastQueuedNativeTaskLabel = label;
      _notifyNativeTaskChanged();
      CrashLogService.instance.info(
        'native task queued: $label after $_activeNativeTaskLabel',
        context: 'model',
      );
    }

    await previous;
    if (shouldWait && _queuedNativeTaskCount > 0) {
      _queuedNativeTaskCount--;
      if (_queuedNativeTaskCount == 0) _lastQueuedNativeTaskLabel = null;
    }
    _activeNativeTaskLabel = label;
    final startedAt = DateTime.now();
    _notifyNativeTaskChanged();
    CrashLogService.instance.info(
      'native task start: $label',
      context: 'model',
    );

    return NativeModelTaskLease._(() {
      final elapsed = DateTime.now().difference(startedAt);
      CrashLogService.instance.info(
        'native task end: $label (${elapsed.inMilliseconds}ms)',
        context: 'model',
      );
      if (_activeNativeTaskLabel == label) {
        _activeNativeTaskLabel = null;
      }
      _notifyNativeTaskChanged();
      if (!myTurn.isCompleted) myTurn.complete();
    });
  }

  Future<T> runExclusiveNativeTask<T>(
    String label,
    Future<T> Function() action,
  ) async {
    final lease = await acquireNativeTask(label);
    try {
      return await action();
    } finally {
      lease.release();
    }
  }

  // ── LLM (Gemma 4) ─────────────────────────────────────────────
  Pointer<Void>? _model;
  Pointer<Void>? _context;
  int _llmGenerationDepth = 0;
  Completer<void>? _llmIdleCompleter;

  bool get isLlmLoaded => _model != null && _context != null;
  bool get isLlmBusy => _llmGenerationDepth > 0;

  // Step 1과의 하위 호환성: isLoaded → isLlmLoaded
  bool get isLoaded => isLlmLoaded;

  Pointer<Void> get model {
    if (!isLlmLoaded) throw StateError('LLM 모델이 로드되지 않았습니다');
    return _model!;
  }

  Pointer<Void> get context {
    if (!isLlmLoaded) throw StateError('LLM 컨텍스트가 생성되지 않았습니다');
    return _context!;
  }

  /// LLM 네이티브 컨텍스트를 사용하는 생성 작업 시작 표시.
  /// 같은 llama_context를 쓰는 동안 unload/free가 들어오면 Metal backend가
  /// SIGABRT를 일으킬 수 있으므로 unloadLlm()은 이 카운터가 0이 될 때까지 기다린다.
  void beginLlmGeneration() {
    _llmGenerationDepth++;
    _llmIdleCompleter ??= Completer<void>();
  }

  /// LLM 생성 작업 종료 표시.
  void endLlmGeneration() {
    if (_llmGenerationDepth <= 0) return;
    _llmGenerationDepth--;
    if (_llmGenerationDepth == 0) {
      final completer = _llmIdleCompleter;
      _llmIdleCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
  }

  /// 현재 진행 중인 LLM decode가 끝날 때까지 대기.
  Future<void> waitForLlmIdle() async {
    while (_llmGenerationDepth > 0) {
      final completer = _llmIdleCompleter;
      if (completer == null) return;
      await completer.future;
    }
  }

  // ── STT (Whisper) ─────────────────────────────────────────────
  Pointer<Void>? _whisperCtx;

  bool get isSttLoaded => _whisperCtx != null;

  Pointer<Void> get whisperCtx {
    if (!isSttLoaded) throw StateError('STT 모델이 로드되지 않았습니다');
    return _whisperCtx!;
  }

  // ── LLM 로드/해제 ─────────────────────────────────────────────

  /// Gemma 4 GGUF 모델 로드
  /// STT 모델 로드 중이면 예외 → 먼저 unloadStt() 호출
  Future<void> loadLlm(String modelPath, {int nCtx = 4096, int nBatch = 512}) =>
      runExclusiveNativeTask(
        'LLM 모델 로드',
        () => _loadLlmUnlocked(modelPath, nCtx: nCtx, nBatch: nBatch),
      );

  Future<void> _loadLlmUnlocked(
    String modelPath, {
    int nCtx = 4096,
    int nBatch = 512,
  }) async {
    if (isSttLoaded) {
      throw StateError(
        'STT 모델 언로드 후 LLM 로드 가능\n'
        '파이프라인: unloadStt() → loadLlm()',
      );
    }
    if (isLlmLoaded) await _unloadLlmUnlocked();

    final ffi = LlamaFfi.instance;
    ffi.backendInit();

    final pathPtr = modelPath.toNativeUtf8(allocator: calloc);
    try {
      final model = ffi.loadModel(pathPtr, 99);
      if (model == nullptr) {
        ffi.backendFree();
        throw Exception('LLM 로드 실패: $modelPath');
      }

      final ctx = ffi.createContext(model, nCtx, nBatch);
      if (ctx == nullptr) {
        ffi.freeModel(model);
        ffi.backendFree();
        throw Exception('LLM 컨텍스트 생성 실패 (메모리 부족? n_ctx=$nCtx)');
      }

      _model = model;
      _context = ctx;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// LLM 해제 (순서: context → model → backend)
  Future<void> unloadLlm() =>
      runExclusiveNativeTask('LLM 모델 해제', _unloadLlmUnlocked);

  Future<void> _unloadLlmUnlocked() async {
    if (!isLlmLoaded) return;
    await waitForLlmIdle();
    if (!isLlmLoaded) return;
    final ffi = LlamaFfi.instance;
    ffi.freeContext(_context!);
    ffi.freeModel(_model!);
    ffi.backendFree();
    _context = null;
    _model = null;
  }

  // ── STT 로드/해제 ─────────────────────────────────────────────

  /// Whisper GGUF 모델 로드
  /// LLM 모델 로드 중이면 예외 → 먼저 unloadLlm() 호출
  Future<void> loadStt(String modelPath) =>
      runExclusiveNativeTask('음성 인식 모델 로드', () => _loadSttUnlocked(modelPath));

  Future<void> _loadSttUnlocked(String modelPath) async {
    if (isLlmLoaded) {
      throw StateError(
        'LLM 모델 언로드 후 STT 로드 가능\n'
        '파이프라인: unloadLlm() → loadStt()',
      );
    }
    if (isSttLoaded) await _unloadSttUnlocked();

    final ffi = WhisperFfi.instance;
    final pathPtr = modelPath.toNativeUtf8(allocator: calloc);
    try {
      final ctx = ffi.loadModel(pathPtr);
      if (ctx == nullptr) {
        throw Exception('STT 로드 실패: $modelPath');
      }
      _whisperCtx = ctx;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// STT 해제 (메모리 반환 ~2 GB)
  Future<void> unloadStt() =>
      runExclusiveNativeTask('음성 인식 모델 해제', _unloadSttUnlocked);

  Future<void> _unloadSttUnlocked() async {
    if (!isSttLoaded) return;
    WhisperFfi.instance.freeModel(_whisperCtx!);
    _whisperCtx = null;
  }
}

class NativeModelTaskLease {
  final void Function() _onRelease;
  bool _released = false;

  NativeModelTaskLease._(this._onRelease);

  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}

class NativeModelTaskSnapshot {
  final String? activeLabel;
  final String? queuedLabel;
  final int queuedCount;

  const NativeModelTaskSnapshot({
    required this.activeLabel,
    required this.queuedLabel,
    required this.queuedCount,
  });

  bool get hasWork => activeLabel != null || queuedCount > 0;
}
