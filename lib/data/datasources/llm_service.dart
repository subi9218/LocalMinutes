import 'dart:convert';
import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../../core/ffi/llama_ffi.dart';
import '../../core/ffi/on_device_model_manager.dart';
import '../../core/services/app_settings.dart';

// Hello World 하드코딩 입력
const _kHardcodedInput = '''아래 회의 내용을 핵심만 3줄로 한국어로 요약해주세요.

회의 내용:
"팀장: 이번 분기 매출 목표를 10% 상향해야 합니다. 기존 전략으로는 달성이 어렵습니다.
박과장: 마케팅 예산을 20% 늘리면 신규 고객 유입이 가능할 것 같습니다.
이대리: 소셜 미디어 캠페인을 2주 안에 시작하겠습니다. 제가 담당하겠습니다.
팀장: 좋습니다. 다음 주 월요일까지 구체적인 계획서를 제출해 주세요."''';

// Isolate 간 전달용 파라미터 (모든 필드가 SendPort 호환 타입)
class _GenerateParams {
  final SendPort sendPort;
  final int modelAddr; // Pointer<Void>.address
  final int ctxAddr;
  final String prompt;
  final int nPromptTokens; // 생성 루프 시작 pos
  final int maxTokens;
  final double temperature;
  final double topP;

  const _GenerateParams({
    required this.sendPort,
    required this.modelAddr,
    required this.ctxAddr,
    required this.prompt,
    required this.nPromptTokens,
    required this.maxTokens,
    required this.temperature,
    required this.topP,
  });
}

class LlmService {
  static final LlmService instance = LlmService._();
  LlmService._();

  static const String _controlPortMessage = '__llm_control_port__';
  static const String _cancelMessage = '__llm_cancel__';

  bool _generationActive = false;
  bool _cancelRequested = false;
  SendPort? _activeCancelPort;

  bool get isGenerationActive => _generationActive;

  /// 현재 진행 중인 LLM 생성에 안전한 취소 신호를 보낸다.
  ///
  /// 네이티브 decode 중간을 강제 중단하지 않고, 워커 isolate가 토큰 사이 경계에서
  /// 빠져나오도록 요청한다. 이렇게 해야 llama/Metal context free와 decode가 겹치지 않는다.
  void requestCancelActiveGeneration() {
    if (!_generationActive) return;
    _cancelRequested = true;
    _activeCancelPort?.send(_cancelMessage);
  }

  static String get hardcodedInput => _kHardcodedInput;

  static const String _summarySystemPrompt =
      '당신은 한국어 회의록을 정확하게 구조화하는 도우미입니다. '
      '전사본에 없는 내용은 만들지 말고, 수치와 고유명사는 원문을 보존하며, '
      '사용자가 요청한 형식만 출력하세요.';

  /// 선택된 LLM에 맞는 채팅 템플릿 적용.
  /// Qwen Instruct 계열은 ChatML 형식이 구조화 출력에 안정적이고,
  /// Gemma 계열은 기존 Gemma turn marker를 유지한다.
  static String buildPromptForModel(String modelId, String userMessage) {
    switch (modelId) {
      case 'qwen25_7b':
        return '<|im_start|>system\n$_summarySystemPrompt<|im_end|>\n'
            '<|im_start|>user\n$userMessage<|im_end|>\n'
            '<|im_start|>assistant\n';
      case 'gemma4_e2b':
      default:
        return '<start_of_turn>user\n'
            '$_summarySystemPrompt\n\n$userMessage'
            '<end_of_turn>\n<start_of_turn>model\n';
    }
  }

  /// Gemma 4 IT 채팅 템플릿 적용
  /// BOS 토큰은 llw_tokenize(add_bos=true)로 자동 추가
  static String buildGemma4Prompt(String userMessage) =>
      buildPromptForModel('gemma4_e2b', userMessage);

  /// 텍스트 요약 생성 (스트리밍)
  ///
  /// [userMessage]: null이면 하드코딩 입력 사용 (Hello World)
  /// [maxTokens]: 최대 생성 토큰 수
  ///
  /// 반환: 토큰 텍스트 Stream (UI에서 실시간 표시)
  /// 오류: StateError (모델 미로드), Exception (추론 실패)
  ///
  /// 피크 메모리: Gemma 4 Q8_0 ~6–8 GB (KV n_ctx=8192 기준 +~1 GB)
  Stream<String> generate({
    String? userMessage,
    int maxTokens = 1024,
    String? modelId,
    double temperature = 0.35,
    double topP = 0.85,
    bool Function()? isCancelled,
  }) async* {
    if (_generationActive) {
      throw StateError('요약 생성이 이미 진행 중입니다. 현재 작업을 끝낸 뒤 다시 시도하세요.');
    }
    _generationActive = true;
    _cancelRequested = false;
    _activeCancelPort = null;
    final manager = OnDeviceModelManager.instance;
    NativeModelTaskLease? nativeLease;
    try {
      nativeLease = await manager.acquireNativeTask('요약 생성');
      if (!manager.isLoaded) {
        throw StateError('LLM 모델 로드 후 호출하세요 (OnDeviceModelManager.loadLlm)');
      }

      final selectedModelId = modelId ?? AppSettings.instance.selectedLlmModel;
      final prompt = buildPromptForModel(
        selectedModelId,
        userMessage ?? _kHardcodedInput,
      );
      final ffi = LlamaFfi.instance;

      // 프롬프트 토큰 수를 메인 Isolate에서 미리 계산 (생성 루프 시작 pos 결정)
      const kMaxPromptTokens = 8192;
      final tokensBuf = calloc<Int32>(kMaxPromptTokens);
      final textPtr = prompt.toNativeUtf8(allocator: calloc);
      final int nPromptTokens;
      try {
        final n = ffi.tokenize(
          manager.model,
          textPtr,
          tokensBuf,
          kMaxPromptTokens,
          true,
        );
        if (n < 0) throw Exception('프롬프트가 너무 깁니다 (최대 $kMaxPromptTokens 토큰)');
        nPromptTokens = n;
      } finally {
        calloc.free(textPtr);
        calloc.free(tokensBuf);
      }

      // 워커 Isolate 생성 및 스트리밍
      final receivePort = ReceivePort();
      final exitPort = ReceivePort();
      final workerExited = Completer<void>();
      var generationMarked = false;
      exitPort.listen((_) {
        if (!workerExited.isCompleted) workerExited.complete();
        exitPort.close();
      });
      manager.beginLlmGeneration();
      generationMarked = true;
      try {
        await Isolate.spawn(
          _generateInIsolate,
          _GenerateParams(
            sendPort: receivePort.sendPort,
            modelAddr: manager.model.address,
            ctxAddr: manager.context.address,
            prompt: prompt,
            nPromptTokens: nPromptTokens,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
          ),
          onExit: exitPort.sendPort,
          onError: receivePort.sendPort,
        );
      } catch (_) {
        manager.endLlmGeneration();
        generationMarked = false;
        rethrow;
      }
      var completed = false;
      var cancelSignalSent = false;

      void sendCancelSignal() {
        _cancelRequested = true;
        if (cancelSignalSent) return;
        final port = _activeCancelPort;
        if (port != null) {
          port.send(_cancelMessage);
          cancelSignalSent = true;
        }
      }

      // 메인 Isolate: 토큰 수신 및 yield
      try {
        await for (final msg in receivePort) {
          if (isCancelled?.call() == true) {
            sendCancelSignal();
          }

          if (msg is List &&
              msg.length == 2 &&
              msg.first == _controlPortMessage &&
              msg[1] is SendPort) {
            _activeCancelPort = msg[1] as SendPort;
            if (_cancelRequested) sendCancelSignal();
          } else if (msg == null) {
            // 완료 신호
            completed = true;
            return;
          } else if (msg is String) {
            if (!_cancelRequested) yield msg;
          } else if (msg is Exception) {
            throw msg;
          } else if (msg is List && msg.length >= 2) {
            throw Exception('LLM 워커 오류: ${msg.first}\n${msg[1]}');
          }
        }
      } finally {
        if (!completed) {
          sendCancelSignal();
          // Stream 소비자가 중간에 취소해도 worker를 즉시 kill하지 않는다.
          // llama_decode/ggml_metal_get_tensor_async 실행 중 isolate를 죽인 뒤
          // 바로 llama_free를 호출하면 Metal backend가 SIGABRT를 일으킬 수 있다.
          // 대신 워커에 취소 신호를 보낸 뒤 현재 생성 루프를 자연 종료할 때까지
          // 기다린 뒤 unloadLlm()이 free하도록 보장한다.
          receivePort.close();
          await workerExited.future;
        } else {
          receivePort.close();
          await workerExited.future;
        }
        if (generationMarked) manager.endLlmGeneration();
      }
    } finally {
      _activeCancelPort = null;
      _cancelRequested = false;
      _generationActive = false;
      nativeLease?.release();
    }
  }

  // ── 워커 Isolate 진입점 ─────────────────────────────────────
  // 주의: DynamicLibrary는 Isolate마다 독립 로드되나
  //       OS(macOS dlopen)가 동일 핸들 반환 → 네이티브 함수 공유
  // 주의: 네이티브 메모리(model/ctx)는 process-wide 공유
  //       → 동시에 2개 Isolate가 동일 ctx를 사용하면 안 됨 (단일 생성 보장됨)
  static Future<void> _generateInIsolate(_GenerateParams p) async {
    ReceivePort? controlPort;
    var cancelled = false;
    try {
      controlPort = ReceivePort();
      controlPort.listen((msg) {
        if (msg == _cancelMessage) cancelled = true;
      });
      p.sendPort.send([_controlPortMessage, controlPort.sendPort]);

      final ffi = LlamaFfi.instance;
      final model = Pointer<Void>.fromAddress(p.modelAddr);
      final ctx = Pointer<Void>.fromAddress(p.ctxAddr);

      // 이전 KV 캐시 초기화
      ffi.kvCacheClear(ctx);

      // ── Step 1: 토크나이즈 + 프롬프트 디코드 ────────────────
      // 피크 메모리: llama.cpp 내부 처리 ~수십 MB
      const kMaxTokens = 8192;
      final tokensBuf = calloc<Int32>(kMaxTokens);
      final textPtr = p.prompt.toNativeUtf8(allocator: calloc);

      try {
        final n = ffi.tokenize(model, textPtr, tokensBuf, kMaxTokens, true);
        if (n <= 0) throw Exception('토크나이즈 실패 (n=$n)');
        if (ffi.decodePrompt(ctx, tokensBuf, n) != 0) {
          // n_ctx 초과가 가장 흔한 원인. 실제 토큰 수를 노출해 진단을 쉽게 함.
          throw Exception(
            '프롬프트 KV 캐시 구성 실패 (입력 토큰 $n개 · n_ctx 초과 가능). '
            '회의가 너무 긴 경우 분할 녹음을 권장합니다.',
          );
        }
      } finally {
        calloc.free(textPtr);
        calloc.free(tokensBuf);
      }
      if (cancelled) {
        p.sendPort.send(null);
        return;
      }

      // ── Step 2: 생성 루프 ────────────────────────────────────
      // seed=42로 재현 가능성을 유지하되 호출 목적에 맞는 sampling 값을 사용.
      final sampler = ffi.createSampler(p.temperature, p.topP, 42);
      final eosToken = ffi.tokenEos(model);
      final pieceBuf = calloc<Char>(256);

      // 멀티바이트 UTF-8 문자(한국어 3바이트 등)가 토큰 경계에서 잘리는 경우
      // FormatException이 발생하지 않도록 바이트를 누적한 뒤 완성된 시퀀스만 디코딩
      final utf8Buffer = <int>[];
      const utf8Dec = Utf8Decoder(allowMalformed: false);

      try {
        int pos = p.nPromptTokens;

        for (int i = 0; i < p.maxTokens; i++) {
          // controlPort의 취소 메시지가 처리될 수 있도록 주기적으로 이벤트 루프에 양보.
          if (i % 4 == 0) await Future<void>.delayed(Duration.zero);
          if (cancelled) break;
          final token = ffi.sample(sampler, ctx);
          if (token == eosToken) break;
          ffi.samplerAccept(sampler, token);

          // 토큰 → 원시 바이트 누적
          final len = ffi.tokenToPiece(model, token, pieceBuf, 256);
          if (len > 0) {
            final bytePtr = pieceBuf.cast<Uint8>();
            for (int b = 0; b < len; b++) {
              utf8Buffer.add(bytePtr[b]);
            }
            // 완성된 UTF-8 시퀀스가 있을 때만 디코딩해서 전송
            try {
              final piece = utf8Dec.convert(Uint8List.fromList(utf8Buffer));
              utf8Buffer.clear();
              p.sendPort.send(piece);
            } on FormatException {
              // 아직 바이트 시퀀스 미완성 — 다음 토큰까지 누적 계속
            }
          }

          // 다음 토큰을 위한 KV 캐시 확장
          if (cancelled) break;
          if (ffi.decodeToken(ctx, token, pos) != 0) break;
          pos++;
        }

        // 루프 종료 후 잔여 바이트 강제 플러시 (손상 허용)
        if (utf8Buffer.isNotEmpty) {
          final flushed = const Utf8Decoder(
            allowMalformed: true,
          ).convert(Uint8List.fromList(utf8Buffer));
          if (flushed.isNotEmpty) p.sendPort.send(flushed);
        }
      } finally {
        ffi.freeSampler(sampler);
        calloc.free(pieceBuf);
      }

      p.sendPort.send(null); // 완료 신호
    } catch (e) {
      p.sendPort.send(e is Exception ? e : Exception('추론 중 오류: $e'));
    } finally {
      controlPort?.close();
    }
  }
}
