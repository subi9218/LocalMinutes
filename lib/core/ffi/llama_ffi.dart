import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ── C 함수 시그니처 typedef ────────────────────────────────────
// 규칙: _XxxC = C native 타입, _XxxDart = Dart 호출 타입

typedef VoidVoidC = Void Function();
typedef VoidVoidDart = void Function();

typedef LoadModelC = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef LoadModelDart = Pointer<Void> Function(Pointer<Utf8>, int);

typedef FreeHandleC = Void Function(Pointer<Void>);
typedef FreeHandleDart = void Function(Pointer<Void>);

typedef CreateContextC = Pointer<Void> Function(Pointer<Void>, Int32, Int32);
typedef CreateContextDart = Pointer<Void> Function(Pointer<Void>, int, int);

typedef TokenizeC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Int32>, Int32, Bool);
typedef TokenizeDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Int32>, int, bool);

typedef TokenToPieceC =
    Int32 Function(Pointer<Void>, Int32, Pointer<Char>, Int32);
typedef TokenToPieceDart = int Function(Pointer<Void>, int, Pointer<Char>, int);

typedef TokenScalarC = Int32 Function(Pointer<Void>);
typedef TokenScalarDart = int Function(Pointer<Void>);

typedef DecodePromptC = Int32 Function(Pointer<Void>, Pointer<Int32>, Int32);
typedef DecodePromptDart = int Function(Pointer<Void>, Pointer<Int32>, int);

typedef DecodeTokenC = Int32 Function(Pointer<Void>, Int32, Int32);
typedef DecodeTokenDart = int Function(Pointer<Void>, int, int);

typedef CreateSamplerC = Pointer<Void> Function(Float, Float, Uint32);
typedef CreateSamplerDart = Pointer<Void> Function(double, double, int);

typedef SampleC = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef SampleDart = int Function(Pointer<Void>, Pointer<Void>);

typedef SamplerAcceptC = Void Function(Pointer<Void>, Int32);
typedef SamplerAcceptDart = void Function(Pointer<Void>, int);

// ── LlamaFfi 싱글톤 ───────────────────────────────────────────
// Dart Isolate마다 독립 인스턴스가 생성되나,
// DynamicLibrary.open은 OS 레벨에서 동일 핸들 반환 (process-wide)
class LlamaFfi {
  static LlamaFfi? _instance;
  static LlamaFfi get instance => _instance ??= LlamaFfi._();

  late final DynamicLibrary _lib;

  late final VoidVoidDart backendInit;
  late final VoidVoidDart backendFree;
  late final LoadModelDart loadModel;
  late final FreeHandleDart freeModel;
  late final CreateContextDart createContext;
  late final FreeHandleDart freeContext;
  late final FreeHandleDart kvCacheClearRaw; // llw_kv_cache_clear(void* ctx)
  late final TokenizeDart tokenize;
  late final TokenToPieceDart tokenToPiece;
  late final TokenScalarDart tokenEos;
  late final TokenScalarDart tokenBos;
  late final DecodePromptDart decodePrompt;
  late final DecodeTokenDart decodeToken;
  late final CreateSamplerDart createSampler;
  late final SampleDart sample;
  late final SamplerAcceptDart samplerAccept;
  late final FreeHandleDart freeSampler;

  LlamaFfi._() {
    _lib = _loadDylib();
    _bind();
  }

  DynamicLibrary _loadDylib() {
    const libName = 'libllama_wrapper.dylib';
    final exe = Platform.resolvedExecutable;
    final appContents = File(exe).parent.parent.path;

    final candidates = [
      '$appContents/Frameworks/$libName', // 앱 번들 (flutter run + 배포)
      '$appContents/MacOS/$libName', // 대안 위치
      libName, // 현재 디렉토리 (테스트)
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) return DynamicLibrary.open(path);
    }

    throw UnsupportedError('''
libllama_wrapper.dylib을 찾을 수 없습니다.

빌드 및 Xcode 설정이 필요합니다:
  1. bash scripts/build_llama_macos.sh
  2. Xcode → Runner 타겟 → Build Phases → Copy Files
     Destination: Frameworks → libllama_wrapper.dylib 추가
  3. flutter run -d macos
''');
  }

  void _bind() {
    backendInit = _lib.lookupFunction<VoidVoidC, VoidVoidDart>(
      'llw_backend_init',
    );
    backendFree = _lib.lookupFunction<VoidVoidC, VoidVoidDart>(
      'llw_backend_free',
    );
    loadModel = _lib.lookupFunction<LoadModelC, LoadModelDart>(
      'llw_load_model',
    );
    freeModel = _lib.lookupFunction<FreeHandleC, FreeHandleDart>(
      'llw_free_model',
    );
    createContext = _lib.lookupFunction<CreateContextC, CreateContextDart>(
      'llw_create_context',
    );
    freeContext = _lib.lookupFunction<FreeHandleC, FreeHandleDart>(
      'llw_free_context',
    );
    kvCacheClearRaw = _lib.lookupFunction<FreeHandleC, FreeHandleDart>(
      'llw_kv_cache_clear',
    );
    tokenize = _lib.lookupFunction<TokenizeC, TokenizeDart>('llw_tokenize');
    tokenToPiece = _lib.lookupFunction<TokenToPieceC, TokenToPieceDart>(
      'llw_token_to_piece',
    );
    tokenEos = _lib.lookupFunction<TokenScalarC, TokenScalarDart>(
      'llw_token_eos',
    );
    tokenBos = _lib.lookupFunction<TokenScalarC, TokenScalarDart>(
      'llw_token_bos',
    );
    decodePrompt = _lib.lookupFunction<DecodePromptC, DecodePromptDart>(
      'llw_decode_prompt',
    );
    decodeToken = _lib.lookupFunction<DecodeTokenC, DecodeTokenDart>(
      'llw_decode_token',
    );
    createSampler = _lib.lookupFunction<CreateSamplerC, CreateSamplerDart>(
      'llw_create_sampler',
    );
    sample = _lib.lookupFunction<SampleC, SampleDart>('llw_sample');
    samplerAccept = _lib.lookupFunction<SamplerAcceptC, SamplerAcceptDart>(
      'llw_sampler_accept',
    );
    freeSampler = _lib.lookupFunction<FreeHandleC, FreeHandleDart>(
      'llw_free_sampler',
    );
  }

  void kvCacheClear(Pointer<Void> ctx) => kvCacheClearRaw(ctx);
}
