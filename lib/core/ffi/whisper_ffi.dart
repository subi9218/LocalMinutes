import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ── C 함수 시그니처 typedef ───────────────────────────────────────
typedef LoadModelC = Pointer<Void> Function(Pointer<Utf8>);
typedef LoadModelDart = Pointer<Void> Function(Pointer<Utf8>);

typedef FreeModelC = Void Function(Pointer<Void>);
typedef FreeModelDart = void Function(Pointer<Void>);

// 시그니처: (ctx, samples, n_samples, language, n_threads, initial_prompt, decode_mode)
typedef TranscribeC =
    Int32 Function(
      Pointer<Void>,
      Pointer<Float>,
      Int32,
      Pointer<Utf8>,
      Int32,
      Pointer<Utf8>,
      Int32,
    );
typedef TranscribeDart =
    int Function(
      Pointer<Void>,
      Pointer<Float>,
      int,
      Pointer<Utf8>,
      int,
      Pointer<Utf8>,
      int,
    );

typedef NSegmentsC = Int32 Function(Pointer<Void>);
typedef NSegmentsDart = int Function(Pointer<Void>);

typedef SegmentTextC = Pointer<Utf8> Function(Pointer<Void>, Int32);
typedef SegmentTextDart = Pointer<Utf8> Function(Pointer<Void>, int);

typedef SegmentTimeC = Int64 Function(Pointer<Void>, Int32);
typedef SegmentTimeDart = int Function(Pointer<Void>, int);

/// wsw_set_segment_callback(ctx, cb) — 진행률 콜백 등록/해제
/// cb: `void (*)(int n_new, int64_t t1_ms)` NativePointer (NULL=해제)
typedef SetSegCbC =
    Void Function(
      Pointer<Void>,
      Pointer<NativeFunction<Void Function(Int32, Int64)>>,
    );
typedef SetSegCbDart =
    void Function(
      Pointer<Void>,
      Pointer<NativeFunction<Void Function(Int32, Int64)>>,
    );

/// Dart에서 NativeCallable.listener 를 만들 때 사용할 서명
typedef WhisperSegmentCb = Void Function(Int32 nNew, Int64 t1Ms);

// ── WhisperFfi 싱글톤 ─────────────────────────────────────────────
class WhisperFfi {
  static WhisperFfi? _instance;
  static WhisperFfi get instance => _instance ??= WhisperFfi._();

  late final DynamicLibrary _lib;

  late final LoadModelDart loadModel;
  late final FreeModelDart freeModel;
  late final TranscribeDart transcribe;
  late final NSegmentsDart nSegments;
  late final SegmentTextDart segmentText;
  late final SegmentTimeDart segmentT0Ms;
  late final SegmentTimeDart segmentT1Ms;
  late final SetSegCbDart setSegmentCallback;

  WhisperFfi._() {
    _lib = _loadDylib();
    _bind();
  }

  DynamicLibrary _loadDylib() {
    const libName = 'libwhisper_wrapper.dylib';
    final exe = Platform.resolvedExecutable;
    final appContents = File(exe).parent.parent.path;

    final candidates = [
      '$appContents/Frameworks/$libName',
      '$appContents/MacOS/$libName',
      libName,
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) return DynamicLibrary.open(path);
    }

    throw UnsupportedError('''
libwhisper_wrapper.dylib을 찾을 수 없습니다.

  1. bash scripts/build_whisper_macos.sh
  2. Xcode → Runner → Build Phases → Copy Files → Frameworks
     libwhisper_wrapper.dylib 추가
  3. flutter run -d macos
''');
  }

  void _bind() {
    loadModel = _lib.lookupFunction<LoadModelC, LoadModelDart>(
      'wsw_load_model',
    );
    freeModel = _lib.lookupFunction<FreeModelC, FreeModelDart>(
      'wsw_free_model',
    );
    transcribe = _lib.lookupFunction<TranscribeC, TranscribeDart>(
      'wsw_transcribe',
    );
    nSegments = _lib.lookupFunction<NSegmentsC, NSegmentsDart>(
      'wsw_n_segments',
    );
    segmentText = _lib.lookupFunction<SegmentTextC, SegmentTextDart>(
      'wsw_segment_text',
    );
    segmentT0Ms = _lib.lookupFunction<SegmentTimeC, SegmentTimeDart>(
      'wsw_segment_t0_ms',
    );
    segmentT1Ms = _lib.lookupFunction<SegmentTimeC, SegmentTimeDart>(
      'wsw_segment_t1_ms',
    );
    setSegmentCallback = _lib.lookupFunction<SetSegCbC, SetSegCbDart>(
      'wsw_set_segment_callback',
    );
  }
}
