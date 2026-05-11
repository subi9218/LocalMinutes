// Extract reference outputs for a WAV file without writing to the app DB.
//
// Usage:
//   cd macos/Runner
//   dart run ../../tool/extract_meeting_outputs.dart "<wav_path>"

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:local_minutes/core/utils/silence_gate.dart';
import 'package:local_minutes/core/utils/summary_parser.dart';
import 'package:local_minutes/core/utils/wav_loader.dart';
import 'package:local_minutes/domain/entities/summary.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

typedef _LoadModelC = Pointer<Void> Function(Pointer<Utf8>);
typedef _LoadModelDart = Pointer<Void> Function(Pointer<Utf8>);
typedef _FreeModelC = Void Function(Pointer<Void>);
typedef _FreeModelDart = void Function(Pointer<Void>);
typedef _TranscribeC =
    Int32 Function(
      Pointer<Void>,
      Pointer<Float>,
      Int32,
      Pointer<Utf8>,
      Int32,
      Pointer<Utf8>,
    );
typedef _TranscribeDart =
    int Function(
      Pointer<Void>,
      Pointer<Float>,
      int,
      Pointer<Utf8>,
      int,
      Pointer<Utf8>,
    );
typedef _NSegmentsC = Int32 Function(Pointer<Void>);
typedef _NSegmentsDart = int Function(Pointer<Void>);
typedef _SegmentTextC = Pointer<Utf8> Function(Pointer<Void>, Int32);
typedef _SegmentTextDart = Pointer<Utf8> Function(Pointer<Void>, int);
typedef _SegmentTimeC = Int64 Function(Pointer<Void>, Int32);
typedef _SegmentTimeDart = int Function(Pointer<Void>, int);

typedef _VoidVoidC = Void Function();
typedef _VoidVoidDart = void Function();
typedef _LoadLlmModelC = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef _LoadLlmModelDart = Pointer<Void> Function(Pointer<Utf8>, int);
typedef _FreeHandleC = Void Function(Pointer<Void>);
typedef _FreeHandleDart = void Function(Pointer<Void>);
typedef _CreateContextC = Pointer<Void> Function(Pointer<Void>, Int32, Int32);
typedef _CreateContextDart = Pointer<Void> Function(Pointer<Void>, int, int);
typedef _TokenizeC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Int32>, Int32, Bool);
typedef _TokenizeDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Int32>, int, bool);
typedef _TokenToPieceC =
    Int32 Function(Pointer<Void>, Int32, Pointer<Char>, Int32);
typedef _TokenToPieceDart =
    int Function(Pointer<Void>, int, Pointer<Char>, int);
typedef _TokenScalarC = Int32 Function(Pointer<Void>);
typedef _TokenScalarDart = int Function(Pointer<Void>);
typedef _DecodePromptC = Int32 Function(Pointer<Void>, Pointer<Int32>, Int32);
typedef _DecodePromptDart = int Function(Pointer<Void>, Pointer<Int32>, int);
typedef _DecodeTokenC = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _DecodeTokenDart = int Function(Pointer<Void>, int, int);
typedef _CreateSamplerC = Pointer<Void> Function(Float, Float, Uint32);
typedef _CreateSamplerDart = Pointer<Void> Function(double, double, int);
typedef _SampleC = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _SampleDart = int Function(Pointer<Void>, Pointer<Void>);
typedef _SamplerAcceptC = Void Function(Pointer<Void>, Int32);
typedef _SamplerAcceptDart = void Function(Pointer<Void>, int);

const _modelDir =
    '/Users/channy/Library/Containers/com.example.meetingAssistant2/Data/Library/Application Support/com.example.meetingAssistant2/models';
const _frameworksDir =
    '/Users/channy/LocalMinutes/build/macos/Build/Products/Debug/적자생존.app/Contents/Frameworks';
const _sttModelFile = 'ggml-large-v3-q5_0.bin';
const _llmModelId = 'exaone35_7b';
const _llmModelFile = 'EXAONE-3.5-7.8B-Instruct-Q4_K_M.gguf';
const _diarSegModelFile = 'sherpa-onnx-pyannote-segmentation-3-0.onnx';
const _diarEmbModelFile =
    '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';

const _sampleRate = 16000;
const _chunkSamples = _sampleRate * 30;
const _chunkOverlapSamples = _sampleRate * 5;
const _singlePassThreshold = 6000;
const _summaryChunkSize = 4500;
const _partialMaxTokens = 800;
const _generalSummaryInstruction =
    '아래 한국어 업무 회의 전사본을 분석해서 JSON만 출력하세요. '
    'keyDiscussions에는 실제 논의된 안건·이슈를 구체적으로 담고, '
    'decisions에는 회의에서 내린 결정·합의 사항만, '
    'actionItems에는 담당자와 기한이 있는 후속 조치를, '
    'openQuestions에는 미결·추가 확인이 필요한 사항을 정리하세요. '
    '설명이나 다른 텍스트는 절대 쓰지 마세요.';
const _summarySystemPrompt =
    '당신은 한국어 회의록을 정확하게 구조화하는 도우미입니다. '
    '전사본에 없는 내용은 만들지 말고, 수치와 고유명사는 원문을 보존하며, '
    '사용자가 요청한 형식만 출력하세요.';

class Segment {
  final String text;
  final int startMs;
  final int endMs;
  final String? speaker;

  const Segment({
    required this.text,
    required this.startMs,
    required this.endMs,
    this.speaker,
  });

  Segment copyWith({String? speaker}) => Segment(
    text: text,
    startMs: startMs,
    endMs: endMs,
    speaker: speaker ?? this.speaker,
  );

  Map<String, dynamic> toJson() => {
    'startMs': startMs,
    'endMs': endMs,
    'speaker': speaker,
    'text': text,
  };
}

class DiarSegment {
  final double startSec;
  final double endSec;
  final int speaker;

  const DiarSegment(this.startSec, this.endSec, this.speaker);
}

class _WhisperNative {
  final DynamicLibrary _lib;
  late final _LoadModelDart loadModel;
  late final _FreeModelDart freeModel;
  late final _TranscribeDart transcribe;
  late final _NSegmentsDart nSegments;
  late final _SegmentTextDart segmentText;
  late final _SegmentTimeDart segmentT0Ms;
  late final _SegmentTimeDart segmentT1Ms;

  _WhisperNative(String path) : _lib = DynamicLibrary.open(path) {
    loadModel = _lib.lookupFunction<_LoadModelC, _LoadModelDart>(
      'wsw_load_model',
    );
    freeModel = _lib.lookupFunction<_FreeModelC, _FreeModelDart>(
      'wsw_free_model',
    );
    transcribe = _lib.lookupFunction<_TranscribeC, _TranscribeDart>(
      'wsw_transcribe',
    );
    nSegments = _lib.lookupFunction<_NSegmentsC, _NSegmentsDart>(
      'wsw_n_segments',
    );
    segmentText = _lib.lookupFunction<_SegmentTextC, _SegmentTextDart>(
      'wsw_segment_text',
    );
    segmentT0Ms = _lib.lookupFunction<_SegmentTimeC, _SegmentTimeDart>(
      'wsw_segment_t0_ms',
    );
    segmentT1Ms = _lib.lookupFunction<_SegmentTimeC, _SegmentTimeDart>(
      'wsw_segment_t1_ms',
    );
  }
}

class _LlamaNative {
  final DynamicLibrary _lib;
  late final _VoidVoidDart backendInit;
  late final _VoidVoidDart backendFree;
  late final _LoadLlmModelDart loadModel;
  late final _FreeHandleDart freeModel;
  late final _CreateContextDart createContext;
  late final _FreeHandleDart freeContext;
  late final _FreeHandleDart kvCacheClear;
  late final _TokenizeDart tokenize;
  late final _TokenToPieceDart tokenToPiece;
  late final _TokenScalarDart tokenEos;
  late final _DecodePromptDart decodePrompt;
  late final _DecodeTokenDart decodeToken;
  late final _CreateSamplerDart createSampler;
  late final _SampleDart sample;
  late final _SamplerAcceptDart samplerAccept;
  late final _FreeHandleDart freeSampler;

  _LlamaNative(String path) : _lib = DynamicLibrary.open(path) {
    backendInit = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'llw_backend_init',
    );
    backendFree = _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>(
      'llw_backend_free',
    );
    loadModel = _lib.lookupFunction<_LoadLlmModelC, _LoadLlmModelDart>(
      'llw_load_model',
    );
    freeModel = _lib.lookupFunction<_FreeHandleC, _FreeHandleDart>(
      'llw_free_model',
    );
    createContext = _lib.lookupFunction<_CreateContextC, _CreateContextDart>(
      'llw_create_context',
    );
    freeContext = _lib.lookupFunction<_FreeHandleC, _FreeHandleDart>(
      'llw_free_context',
    );
    kvCacheClear = _lib.lookupFunction<_FreeHandleC, _FreeHandleDart>(
      'llw_kv_cache_clear',
    );
    tokenize = _lib.lookupFunction<_TokenizeC, _TokenizeDart>('llw_tokenize');
    tokenToPiece = _lib.lookupFunction<_TokenToPieceC, _TokenToPieceDart>(
      'llw_token_to_piece',
    );
    tokenEos = _lib.lookupFunction<_TokenScalarC, _TokenScalarDart>(
      'llw_token_eos',
    );
    decodePrompt = _lib.lookupFunction<_DecodePromptC, _DecodePromptDart>(
      'llw_decode_prompt',
    );
    decodeToken = _lib.lookupFunction<_DecodeTokenC, _DecodeTokenDart>(
      'llw_decode_token',
    );
    createSampler = _lib.lookupFunction<_CreateSamplerC, _CreateSamplerDart>(
      'llw_create_sampler',
    );
    sample = _lib.lookupFunction<_SampleC, _SampleDart>('llw_sample');
    samplerAccept = _lib.lookupFunction<_SamplerAcceptC, _SamplerAcceptDart>(
      'llw_sampler_accept',
    );
    freeSampler = _lib.lookupFunction<_FreeHandleC, _FreeHandleDart>(
      'llw_free_sampler',
    );
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/extract_meeting_outputs.dart <wav>');
    exitCode = 64;
    return;
  }

  final wavPath = args.first;
  final wavFile = File(wavPath);
  if (!await wavFile.exists()) {
    throw FileSystemException('WAV 파일을 찾을 수 없습니다', wavPath);
  }

  final runStamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('.', '_');
  final baseName = wavFile.uri.pathSegments.last.replaceAll('.wav', '');
  final outDir = Directory(
    '/Users/channy/LocalMinutes/exports/${baseName}_reference_$runStamp',
  );
  await outDir.create(recursive: true);

  stdout.writeln('출력 폴더: ${outDir.path}');
  stdout.writeln('[1/5] WAV 로드');
  final rawSamples = await WavLoader.load(wavPath);
  final audioMs = (rawSamples.length / 16).round();
  stdout.writeln('오디오 길이: ${_formatDurationMs(audioMs)}');

  stdout.writeln('[2/5] STT 전사 시작 ($_sttModelFile, 30초 청크 + 5초 오버랩)');
  final gatedSamples = SilenceGate.apply(rawSamples);
  final sttSw = Stopwatch()..start();
  final segments = await _transcribe(gatedSamples, audioMs);
  sttSw.stop();
  final sttRtf = sttSw.elapsedMilliseconds / audioMs;
  stdout.writeln(
    'STT 완료: ${segments.length}개 세그먼트 · '
    '${_formatDurationMs(sttSw.elapsedMilliseconds)} · '
    'RTF ${sttRtf.toStringAsFixed(3)}x',
  );

  stdout.writeln('[3/5] 화자 분리 시작');
  final diarSw = Stopwatch()..start();
  var diarStatus = 'success';
  List<String?> speakerLabels = List<String?>.filled(segments.length, null);
  List<DiarSegment> diarSegments = [];
  try {
    diarSegments = await _diarize(rawSamples);
    speakerLabels = _assignLabels(segments, diarSegments);
  } catch (e) {
    diarStatus = 'failed: $e';
    stdout.writeln('화자 분리 실패: $e');
  }
  diarSw.stop();
  final diarizedSegments = [
    for (int i = 0; i < segments.length; i++)
      segments[i].copyWith(speaker: speakerLabels[i]),
  ];
  stdout.writeln(
    '화자 분리 완료: $diarStatus · '
    '${_formatDurationMs(diarSw.elapsedMilliseconds)}',
  );

  await _writeTranscriptOutputs(outDir, segments, diarizedSegments);

  stdout.writeln('[4/5] 요약 생성 시작 ($_llmModelId / $_llmModelFile)');
  final llama = _LlamaNative('$_frameworksDir/libllama_wrapper.dylib')
    ..backendInit();
  final llmModelPath = '$_modelDir/$_llmModelFile'.toNativeUtf8(
    allocator: calloc,
  );
  final Pointer<Void> llmModel;
  final Pointer<Void> llmContext;
  try {
    llmModel = llama.loadModel(llmModelPath, 99);
  } finally {
    calloc.free(llmModelPath);
  }
  if (llmModel == nullptr) throw StateError('LLM 모델 로드 실패');
  llmContext = llama.createContext(llmModel, 8192, 512);
  if (llmContext == nullptr) {
    llama.freeModel(llmModel);
    llama.backendFree();
    throw StateError('LLM 컨텍스트 생성 실패');
  }

  final summarySw = Stopwatch()..start();
  late final String rawSummary;
  try {
    final transcriptForSummary = _toTranscriptText(diarizedSegments);
    rawSummary = await _summarizeWithModel(
      transcript: transcriptForSummary,
      dateStr: _dateString(DateTime.now()),
      modelId: _llmModelId,
      llama: llama,
      model: llmModel,
      context: llmContext,
    );
  } finally {
    summarySw.stop();
    llama.freeContext(llmContext);
    llama.freeModel(llmModel);
    llama.backendFree();
  }

  final parsed = SummaryParser.parse(rawSummary, 0, DateTime.now());
  await _writeSummaryOutputs(outDir, rawSummary, parsed);
  stdout.writeln('요약 완료: ${_formatDurationMs(summarySw.elapsedMilliseconds)}');

  stdout.writeln('[5/5] 메트릭 저장');
  final metrics = {
    'wavPath': wavPath,
    'audioMs': audioMs,
    'audioDuration': _formatDurationMs(audioMs),
    'sttModel': _sttModelFile,
    'sttElapsedMs': sttSw.elapsedMilliseconds,
    'sttElapsed': _formatDurationMs(sttSw.elapsedMilliseconds),
    'sttRtf': sttRtf,
    'segments': segments.length,
    'diarizationStatus': diarStatus,
    'diarizationElapsedMs': diarSw.elapsedMilliseconds,
    'diarizationElapsed': _formatDurationMs(diarSw.elapsedMilliseconds),
    'diarizationSegments': diarSegments.length,
    'llmModelId': _llmModelId,
    'llmModelFile': _llmModelFile,
    'summaryElapsedMs': summarySw.elapsedMilliseconds,
    'summaryElapsed': _formatDurationMs(summarySw.elapsedMilliseconds),
    'outputDir': outDir.path,
    'createdAt': DateTime.now().toIso8601String(),
  };
  await File(
    '${outDir.path}/metrics.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(metrics));
  await File('${outDir.path}/README.md').writeAsString(_buildReadme(metrics));
  stdout.writeln('완료: ${outDir.path}');
}

Future<List<Segment>> _transcribe(Float32List samples, int totalMs) async {
  final whisper = _WhisperNative('$_frameworksDir/libwhisper_wrapper.dylib');
  final modelPath = '$_modelDir/$_sttModelFile'.toNativeUtf8(allocator: calloc);
  final ctx = whisper.loadModel(modelPath);
  calloc.free(modelPath);
  if (ctx == nullptr) throw StateError('Whisper 모델 로드 실패');

  final all = <Segment>[];
  final totalChunks =
      ((samples.length - _chunkOverlapSamples) /
              (_chunkSamples - _chunkOverlapSamples))
          .ceil()
          .clamp(1, 100000);
  final sw = Stopwatch()..start();

  try {
    var start = 0;
    var chunkIndex = 0;
    while (start < samples.length) {
      final end = math.min(start + _chunkSamples, samples.length);
      final chunk = Float32List.sublistView(samples, start, end);
      final baseOffsetMs = (start / 16).round();
      final chunkSegments = _transcribeChunk(whisper, ctx, chunk, baseOffsetMs);
      all.addAll(chunkSegments);

      chunkIndex++;
      final processedMs = (end / 16).round().clamp(0, totalMs);
      final progress = processedMs / totalMs;
      final elapsedMs = sw.elapsedMilliseconds;
      final etaMs = progress <= 0 ? 0 : (elapsedMs / progress - elapsedMs);
      stdout.writeln(
        '  STT $chunkIndex/$totalChunks · '
        '${_formatDurationMs(processedMs)} / ${_formatDurationMs(totalMs)} · '
        '${(progress * 100).toStringAsFixed(1)}% · '
        '경과 ${_formatDurationMs(elapsedMs)} · '
        '남은 ${_formatDurationMs(etaMs.round())} · '
        '세그먼트 +${chunkSegments.length}',
      );

      if (end >= samples.length) break;
      start += _chunkSamples - _chunkOverlapSamples;
    }
  } finally {
    whisper.freeModel(ctx);
  }

  return _mergeShortFragments(_collapseRepeatedShort(_dedupeOverlaps(all)));
}

List<Segment> _transcribeChunk(
  _WhisperNative whisper,
  Pointer<Void> ctx,
  Float32List chunk,
  int baseOffsetMs,
) {
  final samplePtr = calloc<Float>(chunk.length);
  final langPtr = 'ko'.toNativeUtf8(allocator: calloc);
  final promptPtr = '회의록 전사.'.toNativeUtf8(allocator: calloc);
  try {
    final nativeSamples = samplePtr.asTypedList(chunk.length);
    nativeSamples.setAll(0, chunk);
    final rc = whisper.transcribe(
      ctx,
      samplePtr,
      chunk.length,
      langPtr,
      6,
      promptPtr,
    );
    if (rc != 0) throw StateError('Whisper transcribe 실패: rc=$rc');
    final count = whisper.nSegments(ctx);
    return [
      for (var i = 0; i < count; i++)
        Segment(
          text: whisper.segmentText(ctx, i).toDartString().trim(),
          startMs: baseOffsetMs + whisper.segmentT0Ms(ctx, i),
          endMs: baseOffsetMs + whisper.segmentT1Ms(ctx, i),
        ),
    ].where((s) => s.text.isNotEmpty).toList();
  } finally {
    calloc.free(samplePtr);
    calloc.free(langPtr);
    calloc.free(promptPtr);
  }
}

Future<List<DiarSegment>> _diarize(Float32List samples) async {
  so.initBindings(_frameworksDir);
  so.OfflineSpeakerDiarization? sd;
  try {
    final segConfig = so.OfflineSpeakerSegmentationModelConfig(
      pyannote: so.OfflineSpeakerSegmentationPyannoteModelConfig(
        model: '$_modelDir/$_diarSegModelFile',
      ),
    );
    final embConfig = so.SpeakerEmbeddingExtractorConfig(
      model: '$_modelDir/$_diarEmbModelFile',
    );
    final clusterConfig = so.FastClusteringConfig(
      numClusters: -1,
      threshold: 0.5,
    );
    final config = so.OfflineSpeakerDiarizationConfig(
      segmentation: segConfig,
      embedding: embConfig,
      clustering: clusterConfig,
      minDurationOn: 0.2,
      minDurationOff: 0.5,
    );
    sd = so.OfflineSpeakerDiarization(config);
    if (sd.ptr == nullptr) throw StateError('화자 분리 엔진 초기화 실패');
    final segments = sd.processWithCallback(
      samples: samples,
      callback: (done, total) {
        if (total > 0 && done % 20 == 0) {
          stdout.writeln('  화자 분리 ${(done * 100 / total).toStringAsFixed(1)}%');
        }
        return 0;
      },
    );
    return [for (final s in segments) DiarSegment(s.start, s.end, s.speaker)];
  } finally {
    sd?.free();
  }
}

List<String?> _assignLabels(List<Segment> stt, List<DiarSegment> diar) {
  final labels = List<String?>.filled(stt.length, null);
  if (diar.isEmpty) return labels;

  for (var i = 0; i < stt.length; i++) {
    final s = stt[i].startMs / 1000.0;
    final e = stt[i].endMs / 1000.0;
    var bestSpeaker = -1;
    var bestOverlap = 0.0;
    for (final d in diar) {
      final overlap =
          (e < d.endSec ? e : d.endSec) - (s > d.startSec ? s : d.startSec);
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        bestSpeaker = d.speaker;
      }
    }
    if (bestSpeaker >= 0) {
      labels[i] = String.fromCharCode(65 + (bestSpeaker % 26));
    }
  }
  return labels;
}

Future<String> _summarizeWithModel({
  required String transcript,
  required String dateStr,
  required String modelId,
  required _LlamaNative llama,
  required Pointer<Void> model,
  required Pointer<Void> context,
}) async {
  if (transcript.length <= _singlePassThreshold) {
    final prompt = SummaryParser.buildPrompt(
      transcript,
      dateStr,
      instruction: _generalSummaryInstruction,
    );
    return _runLlm(
      prompt,
      2500,
      modelId,
      llama,
      model,
      context,
      temperature: 0.25,
      topP: 0.85,
    );
  }

  final chunks = _splitByNewline(transcript, _summaryChunkSize);
  final partials = <String>[];
  for (var i = 0; i < chunks.length; i++) {
    stdout.writeln('  구간 요약 ${i + 1}/${chunks.length}');
    final prompt = _buildChunkPrompt(chunks[i], i + 1, chunks.length);
    final partial = await _runLlm(
      prompt,
      _partialMaxTokens,
      modelId,
      llama,
      model,
      context,
      temperature: 0.3,
      topP: 0.85,
    );
    partials.add(_extractBullets(partial));
  }

  final merged = StringBuffer();
  for (var i = 0; i < partials.length; i++) {
    merged.writeln('## 구간 ${i + 1}');
    merged.writeln(partials[i].trim());
    merged.writeln();
  }

  final finalPrompt = SummaryParser.buildPrompt(
    merged.toString().trim(),
    dateStr,
    instruction:
        '$_generalSummaryInstruction\n\n'
        '아래는 긴 회의를 구간별로 미리 요약한 결과입니다. 전체 회의를 종합해 JSON만 출력하세요.',
  );
  stdout.writeln('  최종 통합 요약');
  return _runLlm(
    finalPrompt,
    2500,
    modelId,
    llama,
    model,
    context,
    temperature: 0.2,
    topP: 0.85,
  );
}

Future<String> _runLlm(
  String prompt,
  int maxTokens,
  String modelId,
  _LlamaNative llama,
  Pointer<Void> model,
  Pointer<Void> context, {
  required double temperature,
  required double topP,
}) async {
  final templatedPrompt = _buildPromptForModel(modelId, prompt);
  llama.kvCacheClear(context);

  const maxPromptTokens = 8192;
  final tokensBuf = calloc<Int32>(maxPromptTokens);
  final promptPtr = templatedPrompt.toNativeUtf8(allocator: calloc);
  late final int nPromptTokens;
  try {
    final n = llama.tokenize(
      model,
      promptPtr,
      tokensBuf,
      maxPromptTokens,
      true,
    );
    if (n < 0) throw StateError('프롬프트가 너무 깁니다');
    nPromptTokens = n;
    if (llama.decodePrompt(context, tokensBuf, nPromptTokens) != 0) {
      throw StateError('프롬프트 KV 캐시 구성 실패');
    }
  } finally {
    calloc.free(promptPtr);
    calloc.free(tokensBuf);
  }

  final sampler = llama.createSampler(temperature, topP, 42);
  final eosToken = llama.tokenEos(model);
  final pieceBuf = calloc<Char>(256);
  const utf8Dec = Utf8Decoder(allowMalformed: false);
  final utf8Buffer = <int>[];
  var tokCount = 0;
  final buf = StringBuffer();

  try {
    var pos = nPromptTokens;
    for (var i = 0; i < maxTokens; i++) {
      final token = llama.sample(sampler, context);
      if (token == eosToken) break;
      llama.samplerAccept(sampler, token);

      final len = llama.tokenToPiece(model, token, pieceBuf, 256);
      if (len > 0) {
        final bytePtr = pieceBuf.cast<Uint8>();
        for (var b = 0; b < len; b++) {
          utf8Buffer.add(bytePtr[b]);
        }
        try {
          final piece = utf8Dec.convert(Uint8List.fromList(utf8Buffer));
          utf8Buffer.clear();
          buf.write(piece);
        } on FormatException {
          // UTF-8 멀티바이트 문자가 다음 토큰에서 완성될 때까지 기다린다.
        }
      }

      if (llama.decodeToken(context, token, pos) != 0) break;
      pos++;
      tokCount++;
      if (tokCount % 100 == 0) stdout.write('.');
    }

    if (utf8Buffer.isNotEmpty) {
      buf.write(
        const Utf8Decoder(
          allowMalformed: true,
        ).convert(Uint8List.fromList(utf8Buffer)),
      );
    }
  } finally {
    llama.freeSampler(sampler);
    calloc.free(pieceBuf);
  }
  if (tokCount >= 100) stdout.writeln();
  return buf.toString();
}

String _buildPromptForModel(String modelId, String userMessage) {
  switch (modelId) {
    case 'qwen25_7b':
    case 'exaone35_7b':
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

List<String> _splitByNewline(String text, int maxChars) {
  final chunks = <String>[];
  var i = 0;
  while (i < text.length) {
    var end = i + maxChars;
    if (end >= text.length) {
      chunks.add(text.substring(i));
      break;
    }
    final lastNewline = text.lastIndexOf('\n', end);
    if (lastNewline > i + (maxChars * 0.75).toInt()) {
      end = lastNewline;
    }
    chunks.add(text.substring(i, end));
    i = end;
    while (i < text.length && (text[i] == '\n' || text[i] == ' ')) {
      i++;
    }
  }
  return chunks;
}

String _buildChunkPrompt(String chunk, int idx, int total) =>
    '''
아래는 회의 전사본의 $idx/$total 구간입니다. 이 구간에서 실제로 논의된 내용을 한국어 bullet list로 정리하세요.

규칙:
- 수치·고유명사·인용된 표현은 원문 그대로 보존 (추상화 금지).
- "~에 대해 논의" 같은 모호한 서술 대신, 실제 발언·결론을 구체적으로 쓰세요.
- 항목당 한 줄, 최대 10개 bullet.
- 각 줄은 "- " 로 시작. JSON이나 다른 포맷 쓰지 마세요.
- 이 구간에 결정 사항·액션 아이템이 있으면 문장 앞에 [결정] 또는 [액션] 태그를 붙이세요.

전사본 구간:
$chunk

요약:''';

String _extractBullets(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  final lines = cleaned.split('\n');
  final bullets = <String>[];
  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('-') || t.startsWith('•') || t.startsWith('*')) {
      bullets.add(
        t.startsWith('•') || t.startsWith('*')
            ? '- ${t.substring(1).trim()}'
            : t,
      );
    }
  }
  return bullets.isNotEmpty ? bullets.join('\n') : cleaned;
}

String _toTranscriptText(List<Segment> segments) => segments
    .map((s) {
      final label = s.speaker == null ? '' : '화자 ${s.speaker}: ';
      return '[${_formatTimestamp(s.startMs)} → ${_formatTimestamp(s.endMs)}] '
          '$label${s.text}';
    })
    .join('\n');

Future<void> _writeTranscriptOutputs(
  Directory outDir,
  List<Segment> segments,
  List<Segment> diarized,
) async {
  await File('${outDir.path}/transcript.txt').writeAsString(
    segments
        .map(
          (s) =>
              '[${_formatTimestamp(s.startMs)} → ${_formatTimestamp(s.endMs)}] ${s.text}',
        )
        .join('\n'),
  );
  await File(
    '${outDir.path}/transcript_diarized.txt',
  ).writeAsString(_toTranscriptText(diarized));
  await File('${outDir.path}/segments.json').writeAsString(
    const JsonEncoder.withIndent(
      '  ',
    ).convert(diarized.map((s) => s.toJson()).toList()),
  );
}

Future<void> _writeSummaryOutputs(
  Directory outDir,
  String rawSummary,
  Summary summary,
) async {
  await File('${outDir.path}/summary_raw.txt').writeAsString(rawSummary);
  final actionItems = _decodeActionItems(summary.actionItemsJson);
  final summaryJson = {
    'meetingTitle': summary.meetingTitle,
    'participants': summary.participants,
    'keyDiscussions': summary.keyDiscussions,
    'decisions': summary.decisions,
    'actionItems': actionItems,
    'openQuestions': summary.openQuestions,
  };
  await File(
    '${outDir.path}/summary.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(summaryJson));

  final summaryMd = StringBuffer()
    ..writeln('# ${summary.meetingTitle}')
    ..writeln()
    ..writeln('## 참석자')
    ..writeln(_markdownList(summary.participants))
    ..writeln()
    ..writeln('## 주요 논의')
    ..writeln(_markdownList(summary.keyDiscussions))
    ..writeln()
    ..writeln('## 결정사항')
    ..writeln(_markdownList(summary.decisions))
    ..writeln()
    ..writeln('## 액션아이템')
    ..writeln(_markdownActionItems(actionItems))
    ..writeln()
    ..writeln('## 미해결 이슈')
    ..writeln(_markdownList(summary.openQuestions));
  await File('${outDir.path}/summary.md').writeAsString(summaryMd.toString());

  final decisionsMd = StringBuffer()
    ..writeln('# 결정사항 / 액션아이템')
    ..writeln()
    ..writeln('## 결정사항')
    ..writeln(_markdownList(summary.decisions))
    ..writeln()
    ..writeln('## 액션아이템')
    ..writeln(_markdownActionItems(actionItems));
  await File(
    '${outDir.path}/decisions_action_items.md',
  ).writeAsString(decisionsMd.toString());
}

List<Map<String, dynamic>> _decodeActionItems(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((m) => m.map((key, value) => MapEntry(key.toString(), value)))
      .toList();
}

String _markdownList(List<String> items) {
  if (items.isEmpty) return '- (없음)';
  return items.map((e) => '- $e').join('\n');
}

String _markdownActionItems(List<Map<String, dynamic>> items) {
  if (items.isEmpty) return '- (없음)';
  return items
      .map(
        (e) =>
            '- ${e['task'] ?? ''} / 담당: ${e['owner'] ?? '(미언급)'} / 기한: ${e['deadline'] ?? '(미언급)'}',
      )
      .join('\n');
}

String _buildReadme(Map<String, dynamic> metrics) =>
    '''
# WAV 기준 추출 결과

- WAV: `${metrics['wavPath']}`
- 오디오 길이: ${metrics['audioDuration']}
- STT 모델: `${metrics['sttModel']}`
- STT 소요: ${metrics['sttElapsed']} / RTF ${(metrics['sttRtf'] as double).toStringAsFixed(3)}x
- 화자 분리: ${metrics['diarizationStatus']} / ${metrics['diarizationElapsed']}
- LLM 모델: `${metrics['llmModelId']}` (`${metrics['llmModelFile']}`)
- 요약 소요: ${metrics['summaryElapsed']}

## 파일

- `transcript.txt`: 전체 전사 텍스트
- `transcript_diarized.txt`: 화자 분리 포함 전사
- `segments.json`: 타임스탬프/화자 포함 세그먼트 JSON
- `summary.md`: 회의록 요약
- `summary.json`: 구조화 요약 JSON
- `decisions_action_items.md`: 결정사항/액션아이템만 분리
- `summary_raw.txt`: LLM 원문 출력
- `metrics.json`: 처리 시간/RTF
''';

List<Segment> _dedupeOverlaps(List<Segment> segments) {
  if (segments.length <= 1) return segments;
  String norm(String s) =>
      s.replaceAll(RegExp(r'[\s.,!?…·"“”‘’()\[\]{}:;~\-]+'), '').toLowerCase();
  bool isDuplicate(Segment a, Segment b) {
    final gapMs = b.startMs - a.endMs;
    final overlaps = b.startMs <= a.endMs + 3500 && gapMs <= 3500;
    if (!overlaps) return false;
    final at = norm(a.text);
    final bt = norm(b.text);
    if (at.isEmpty || bt.isEmpty) return false;
    return at == bt ||
        (at.length >= 6 && bt.contains(at)) ||
        (bt.length >= 6 && at.contains(bt));
  }

  final sorted = [...segments]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final result = <Segment>[];
  for (final seg in sorted) {
    if (result.isEmpty) {
      result.add(seg);
      continue;
    }
    final last = result.last;
    if (isDuplicate(last, seg)) {
      final keep = seg.text.length > last.text.length ? seg : last;
      result[result.length - 1] = Segment(
        text: keep.text,
        startMs: math.min(last.startMs, seg.startMs),
        endMs: math.max(last.endMs, seg.endMs),
      );
    } else {
      result.add(seg);
    }
  }
  return result;
}

List<Segment> _collapseRepeatedShort(List<Segment> segments) {
  final result = <Segment>[];
  for (final seg in segments) {
    final t = seg.text.trim();
    if (result.isNotEmpty) {
      final last = result.last;
      if (t == last.text.trim() &&
          t.length <= 8 &&
          seg.startMs - last.endMs <= 1500) {
        result[result.length - 1] = Segment(
          text: last.text,
          startMs: last.startMs,
          endMs: seg.endMs,
        );
        continue;
      }
    }
    result.add(seg);
  }
  return result;
}

List<Segment> _mergeShortFragments(List<Segment> segments) {
  final result = <Segment>[];
  for (final seg in segments) {
    if (result.isEmpty) {
      result.add(seg);
      continue;
    }
    final last = result.last;
    final duration = seg.endMs - seg.startMs;
    final gap = seg.startMs - last.endMs;
    if (duration < 900 && gap >= 0 && gap <= 700) {
      result[result.length - 1] = Segment(
        text: '${last.text.trim()} ${seg.text.trim()}'.trim(),
        startMs: last.startMs,
        endMs: seg.endMs,
      );
    } else {
      result.add(seg);
    }
  }
  return result;
}

String _formatTimestamp(int ms) {
  final totalSec = ms ~/ 1000;
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = totalSec % 60;
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}';
}

String _formatDurationMs(int ms) {
  final totalSec = (ms / 1000).round();
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = totalSec % 60;
  if (h > 0) {
    return '$h시간 ${m.toString().padLeft(2, '0')}분 ${s.toString().padLeft(2, '0')}초';
  }
  return '$m분 ${s.toString().padLeft(2, '0')}초';
}

String _dateString(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
