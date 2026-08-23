import 'dart:ffi';
import 'dart:async';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import '../l10n/app_tr.dart';
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
        tr('LLM 모델 로드', 'Loading summary model'),
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

    // 로드(mmap + Metal 초기화, 수 초~10초)를 워커 isolate에서 실행해
    // 메인 isolate(UI 스레드)가 얼지 않게 한다. dylib 핸들은 process-wide라
    // isolate마다 lookup해도 같은 라이브러리이며, 포인터는 주소(int)로 전달한다.
    // (생성은 이미 _generateInIsolate 워커에서 실행 — 교차 스레드 사용은 기존 패턴)
    final path = modelPath;
    final ctxSize = nCtx;
    final batch = nBatch;
    final loadFuture = Isolate.run(() {
      final ffi = LlamaFfi.instance;
      ffi.backendInit();
      final pathPtr = path.toNativeUtf8(allocator: calloc);
      try {
        final model = ffi.loadModel(pathPtr, 99);
        if (model == nullptr) {
          ffi.backendFree();
          throw Exception('LLM 로드 실패: $path');
        }
        final ctx = ffi.createContext(model, ctxSize, batch);
        if (ctx == nullptr) {
          ffi.freeModel(model);
          ffi.backendFree();
          throw Exception('LLM 컨텍스트 생성 실패 (메모리 부족? n_ctx=$ctxSize)');
        }
        return [model.address, ctx.address];
      } finally {
        calloc.free(pathPtr);
      }
    });
    // STT 로드와 같은 이유의 안전선 (병리적 무한 대기 → lease 영구 점유 방지).
    final addrs = await loadFuture.timeout(
      const Duration(minutes: 10),
      onTimeout: () {
        loadFuture.then((late) {
          final ffi = LlamaFfi.instance;
          ffi.freeContext(Pointer<Void>.fromAddress(late[1]));
          ffi.freeModel(Pointer<Void>.fromAddress(late[0]));
          ffi.backendFree();
        }).catchError((_) {});
        throw TimeoutException(
          '요약 모델 로드가 10분을 초과했습니다. 다시 시도하거나 Mac을 재시동해주세요.',
        );
      },
    );
    _model = Pointer<Void>.fromAddress(addrs[0]);
    _context = Pointer<Void>.fromAddress(addrs[1]);
  }

  /// LLM 해제 (순서: context → model → backend)
  Future<void> unloadLlm() =>
      runExclusiveNativeTask(tr('LLM 모델 해제', 'Unloading summary model'), _unloadLlmUnlocked);

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
      runExclusiveNativeTask(tr('음성 인식 모델 로드', 'Loading speech recognition model'), () => _loadSttUnlocked(modelPath));

  Future<void> _loadSttUnlocked(String modelPath) async {
    if (isLlmLoaded) {
      throw StateError(
        'LLM 모델 언로드 후 STT 로드 가능\n'
        '파이프라인: unloadLlm() → loadStt()',
      );
    }
    if (isSttLoaded) await _unloadSttUnlocked();

    // CoreML 가속팩(mlmodelc) 최초 로드 시 macOS가 모델을 Neural Engine용으로
    // 재컴파일하는데, OS 업데이트·앱 재설치로 캐시가 비면 수십 초~수 분 걸린다.
    // 이 동기 FFI를 메인 isolate에서 부르면 UI 전체가 비치볼로 얼어붙으므로
    // (App Store 2.2.1 행 리포트: ANE 컴파일 XPC 대기 40초) 워커 isolate에서
    // 로드하고 컨텍스트 주소만 받는다. dylib 핸들은 process-wide.
    final path = modelPath;
    final loadFuture = Isolate.run(() {
      final ffi = WhisperFfi.instance;
      final pathPtr = path.toNativeUtf8(allocator: calloc);
      try {
        final ctx = ffi.loadModel(pathPtr);
        if (ctx == nullptr) {
          throw Exception('STT 로드 실패: $path');
        }
        return ctx.address;
      } finally {
        calloc.free(pathPtr);
      }
    });
    // ANE 컴파일 XPC가 영영 안 돌아오는 병리 케이스에서 lease가 영구 점유돼
    // 이후 모든 작업·앱 종료까지 조용히 막히는 것을 방지하는 안전선.
    // 정상 콜드 컴파일(수십 초~수 분)은 이 한도 안에 넉넉히 끝난다.
    final addr = await loadFuture.timeout(
      const Duration(minutes: 10),
      onTimeout: () {
        // 타임아웃 뒤 늦게 완료되면 컨텍스트를 해제해 누수를 막는다.
        loadFuture.then((late) {
          if (late != 0) {
            WhisperFfi.instance.freeModel(Pointer<Void>.fromAddress(late));
          }
        }).catchError((_) {});
        throw TimeoutException(
          '음성 인식 모델 로드가 10분을 초과했습니다. 다시 시도하거나 Mac을 재시동해주세요.',
        );
      },
    );
    _whisperCtx = Pointer<Void>.fromAddress(addr);
  }

  /// STT 해제 (메모리 반환 ~2 GB)
  Future<void> unloadStt() =>
      runExclusiveNativeTask(tr('음성 인식 모델 해제', 'Unloading speech recognition model'), _unloadSttUnlocked);

  /// 전사 행 타임아웃으로 버려진 컨텍스트 — 네이티브 스레드가 아직 쓰고
  /// 있을 수 있어 free도, 재사용도 불가. 의도적으로 누수시켜 보관만 한다
  /// (프로세스 종료 시 OS가 회수). 디버깅용으로 참조를 남겨둔다.
  // ignore: unused_field
  Pointer<Void>? _leakedWhisperCtx;

  /// 전사 행 타임아웃 시 호출 — 컨텍스트를 즉시 사용 불가로 만든다.
  /// (_whisperCtx=null → isSttLoaded=false → 이후 전사/free 자연 차단.
  ///  그대로 두면 다음 30초 윈도우가 행 중인 네이티브 스레드와 같은
  ///  컨텍스트로 두 번째 전사를 시작해 heap corruption이 난다.)
  void markSttContextPoisoned() {
    _leakedWhisperCtx = _whisperCtx;
    _whisperCtx = null;
    CrashLogService.instance.info(
      'whisper ctx poisoned (transcribe hang timeout) — leaked, not freed',
      context: 'model',
    );
  }

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
