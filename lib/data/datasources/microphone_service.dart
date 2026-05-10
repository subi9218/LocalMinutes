import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:record/record.dart';
export 'package:record/record.dart' show InputDevice;
import '../../core/ffi/on_device_model_manager.dart';
import '../../core/services/app_settings.dart';
import '../../core/utils/vad_filter.dart';
import 'stt_service.dart';

/// 실시간 마이크 스트리밍 + 30초 슬라이딩 윈도우 + RMS VAD + Whisper 전사
///
/// 파이프라인:
///   마이크(PCM16 16kHz 모노)
///     → 30초 윈도우 버퍼링
///     → RMS VAD 필터 (무음 건너뜀)
///     → Whisper 전사 (Isolate)
///     → onSegment 콜백
///
/// 30초 윈도우 상수 (@16kHz mono PCM16):
///   windowSamples  = 480,000   (30s)
///   overlapSamples =  80,000   (5s 오버랩)
///   windowBytes    = 960,000   bytes
///   overlapBytes   = 160,000   bytes
///   advanceMs      = 25,000 ms (한 윈도우 이동 = 30-5초)
/// 마이크 권한 거부 시 던지는 예외 — UI는 이를 catch해 시스템 설정 안내 다이얼로그를 띄운다.
class MicrophonePermissionDeniedException implements Exception {
  final String message;
  const MicrophonePermissionDeniedException(this.message);

  @override
  String toString() => 'MicrophonePermissionDeniedException: $message';
}

class MicrophoneService {
  static final instance = MicrophoneService._();
  MicrophoneService._();

  // ── 상수 ─────────────────────────────────────────────────────────
  static const int _sampleRate = 16000;
  static const int _windowSec = 30;
  static const int _overlapSec = 5;
  static const int _windowSamples = _sampleRate * _windowSec; // 480,000
  static const int _overlapSamples = _sampleRate * _overlapSec; //  80,000
  static const int _windowBytes = _windowSamples * 2; // 960,000 bytes (PCM16)
  static const int _overlapBytes = _overlapSamples * 2; // 160,000 bytes
  // advanceMs = (_windowSec - _overlapSec) * 1000 = 25,000 ms (참고용)

  // ── 상태 ─────────────────────────────────────────────────────────
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;
  Timer? _windowTimer; // 30초 강제 처리 타이머
  final _buffer = BytesBuilder(copy: false); // STT 슬라이딩 윈도우 버퍼

  /// 전체 녹음 데이터 누적 (WAV 저장용, ~32KB/s × 녹음시간)
  final _fullAudioBytes = BytesBuilder();
  String? _audioSavePath; // 저장 경로 (startRecording 시 지정)

  bool _recording = false;
  int _baseOffsetMs = 0; // 다음 윈도우 기준 타임스탬프 오프셋
  bool _processing = false; // 윈도우 처리 중 중복 방지

  // ── 일시 정지 ─────────────────────────────────────────────────────
  bool _paused = false;
  Duration _totalPausedDuration = Duration.zero; // 누적 정지 시간
  DateTime? _pauseStartedAt; // 현재 정지 시작 시각

  final List<SttSegment> _segments = [];
  DateTime? _startTime;

  // ── 공개 상태 ─────────────────────────────────────────────────────
  bool get isRecording => _recording;
  bool get isPaused => _paused;

  /// 현재 녹음 세션에서 누적 수신한 총 바이트 수 (오디오 수신 여부 진단용)
  int _totalBytesReceived = 0;
  int get totalBytesReceived => _totalBytesReceived;

  /// 현재 버퍼에 쌓인 오디오 초 수 (0~30)
  double get bufferSeconds =>
      (_buffer.length / (_sampleRate * 2)).clamp(0, _windowSec).toDouble();

  /// 실제 녹음 경과 시간 (일시 정지 기간 제외)
  Duration get elapsed {
    if (_startTime == null) return Duration.zero;
    final paused = _paused && _pauseStartedAt != null
        ? _totalPausedDuration + DateTime.now().difference(_pauseStartedAt!)
        : _totalPausedDuration;
    final raw = DateTime.now().difference(_startTime!);
    final net = raw - paused;
    return net.isNegative ? Duration.zero : net;
  }

  List<SttSegment> get segments => List.unmodifiable(_segments);

  /// 저장된 WAV 파일 경로 (stopRecording 완료 후 유효)
  String? get savedAudioPath => _audioSavePath;

  // ── 콜백 ─────────────────────────────────────────────────────────
  /// 새 전사 세그먼트가 생성될 때 호출 (메인 Isolate)
  void Function(SttSegment segment)? onSegment;

  /// 오류 발생 시 호출
  void Function(String error)? onError;

  /// 윈도우 처리 시작/완료 (UI 스피너 등)
  void Function(bool processing)? onProcessing;

  /// 실시간 입력 레벨 (0.0 ~ 1.0, 대략 RMS 기반)
  /// 최근 청크 기준으로 50ms 이내 디바운스
  void Function(double level)? onLevel;
  DateTime? _lastLevelEmit;

  // ── 제어 API ─────────────────────────────────────────────────────

  /// 녹음 시작
  ///
  /// [sttModelPath]: Whisper GGUF 모델 경로
  /// [audioSavePath]: 전체 녹음을 저장할 WAV 파일 경로 (null 이면 저장 안 함)
  /// 마이크 권한: DebugProfile.entitlements / Release.entitlements에
  ///   com.apple.security.device.audio-input 필요
  Future<void> startRecording(
    String sttModelPath, {
    String? audioSavePath,
    InputDevice? device,
  }) async {
    if (_recording) return;

    // STT 모델 로드 (단일 모델 강제 — LLM 로드 중이면 예외)
    await OnDeviceModelManager.instance.loadStt(sttModelPath);

    _recorder = AudioRecorder();

    // 마이크 권한 확인 — 시스템 단에서 거부 / 미설정 시 명확한 안내
    if (!await _recorder!.hasPermission()) {
      await OnDeviceModelManager.instance.unloadStt();
      throw const MicrophonePermissionDeniedException(
        '마이크 접근 권한이 거부되었습니다.\n'
        '시스템 설정 → 개인정보 보호 및 보안 → 마이크에서 "적자생존"을 켜주세요.',
      );
    }

    // PCM16 16kHz 모노 스트림 시작 (헤더 없는 raw PCM bytes)
    //
    // macOS Voice Processing (AVAudioEngine) 플래그:
    //   autoGain = AGC (자동 볼륨 조절)
    //   echoCancel = 에코 제거 (다중 화자 회의에서는 품질 저하 가능)
    //   noiseSuppress는 macOS에서 record 플러그인이 처리하지 않음
    final settings = AppSettings.instance;
    final stream = await _recorder!.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        device: device,
        autoGain: settings.recordAutoGain,
        echoCancel: settings.recordEchoCancel,
      ),
    );

    _recording = true;
    _paused = false;
    _totalPausedDuration = Duration.zero;
    _pauseStartedAt = null;
    _baseOffsetMs = 0;
    _processing = false;
    _buffer.clear();
    _fullAudioBytes.clear();
    _totalBytesReceived = 0;
    _audioSavePath = audioSavePath;
    _startTime = DateTime.now();

    // PCM16 바이트 수신 → 버퍼 누적 → 30초마다 처리
    _sub = stream.listen(
      _onBytes,
      onError: (Object e) {
        onError?.call('마이크 스트림 오류: $e');
        stopRecording();
      },
      onDone: () {
        if (_recording) stopRecording();
      },
    );

    // 타이머 기반 강제 처리: 30초마다 버퍼에 3초 이상 데이터 있으면 처리
    // → 버퍼가 정확히 30초를 채우지 못해도 중간 결과를 표시
    _windowTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final minBytes = _sampleRate * 2 * 3; // 3초 이상
      if (_recording &&
          !_paused &&
          !_processing &&
          _buffer.length >= minBytes) {
        _processWindow();
      }
    });
  }

  /// 녹음 일시 정지 (마이크는 계속 열려있지만 버퍼에 쌓지 않음)
  Future<void> pauseRecording() async {
    if (!_recording || _paused) return;
    _windowTimer?.cancel();
    _paused = true;
    _pauseStartedAt = DateTime.now();
  }

  /// 녹음 재개 (일시 정지 해제)
  Future<void> resumeRecording() async {
    if (!_recording || !_paused) return;
    if (_pauseStartedAt != null) {
      _totalPausedDuration += DateTime.now().difference(_pauseStartedAt!);
      _pauseStartedAt = null;
    }
    _paused = false;
    // 타이머 재시작
    _windowTimer?.cancel();
    final minBytes = _sampleRate * 2 * 3;
    _windowTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_recording &&
          !_paused &&
          !_processing &&
          _buffer.length >= minBytes) {
        _processWindow();
      }
    });
  }

  /// 녹음 중지.
  ///
  /// 이미 처리 중인 윈도우가 있으면 완료를 기다리고, 마지막에 남은 tail 버퍼도
  /// 한 번 더 전사한다. 회의 마지막 결정/액션이 30초 윈도우를 채우지 못해
  /// 누락되는 문제를 막기 위한 종료 전용 flush 경로다.
  /// WAV 파일 저장 후 반환 (audioSavePath 지정 시)
  Future<void> stopRecording() async {
    if (!_recording) return;
    _recording = false;
    _paused = false;

    _windowTimer?.cancel();
    _windowTimer = null;

    await _sub?.cancel();
    _sub = null;

    await _recorder?.stop();
    _recorder?.dispose();
    _recorder = null;

    // ── 전체 오디오 WAV 저장 ──────────────────────────────────
    if (_audioSavePath != null) {
      var pcm = _fullAudioBytes.takeBytes();
      if (pcm.isNotEmpty) {
        try {
          if (AppSettings.instance.recordNormalize) {
            pcm = _peakNormalize(pcm);
          }
          await _writeWav(_audioSavePath!, pcm);
          debugPrint('WAV 저장 완료: $_audioSavePath (${pcm.length ~/ 1024} KB)');
        } catch (e) {
          debugPrint('WAV 저장 실패: $e');
          _audioSavePath = null; // 실패 시 경로 초기화
        }
      } else {
        _audioSavePath = null;
      }
    }
    _fullAudioBytes.clear();

    // ── 핵심 수정: wsw_transcribe 완료 대기 ──────────────────────
    // _recording = false이므로 새 _processWindow()는 시작되지 않음.
    // 단, 이미 실행 중인 _processWindow() (= wsw_transcribe 중)가 있으면
    // whisper_free()를 호출하기 전에 반드시 완료를 기다려야 한다.
    // → whisper_free()와 wsw_transcribe() 동시 실행 → SIGABRT 방지.
    const maxWaitMs = 30000; // 최대 30초 대기
    var waited = 0;
    while (_processing && waited < maxWaitMs) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }
    if (_processing) {
      debugPrint('[MicService] 경고: _processWindow 30초 초과 — 강제 해제');
    }

    if (!_processing) {
      await _processFinalWindowIfNeeded();
    }
    _buffer.clear();

    await OnDeviceModelManager.instance.unloadStt().catchError((_) {});
  }

  /// 상태 초기화 (녹음 중지 후 재사용 시 호출)
  void reset() {
    if (_recording) return; // 녹음 중에는 reset 불가
    _segments.clear();
    _baseOffsetMs = 0;
    _startTime = null;
    _paused = false;
    _totalPausedDuration = Duration.zero;
    _pauseStartedAt = null;
    _audioSavePath = null;
    _fullAudioBytes.clear();
  }

  // ── 내부 처리 ─────────────────────────────────────────────────────

  void _onBytes(Uint8List chunk) {
    if (_paused) return; // 일시 정지 중: 바이트 무시 (WAV에도 포함 안 함)

    _totalBytesReceived += chunk.length;
    _buffer.add(chunk);
    _fullAudioBytes.add(chunk); // 전체 녹음 누적 (WAV 저장용)

    // 실시간 레벨 미터 — 50ms 간격 디바운스
    if (onLevel != null) {
      final now = DateTime.now();
      if (_lastLevelEmit == null ||
          now.difference(_lastLevelEmit!).inMilliseconds >= 50) {
        _lastLevelEmit = now;
        onLevel?.call(_computeLevel(chunk));
      }
    }

    // 버퍼가 30초 분량에 도달하면 처리 (처리 중 중복 방지)
    if (_buffer.length >= _windowBytes && !_processing) {
      _processWindow();
    }
  }

  /// PCM16 청크 → 0.0~1.0 레벨 (RMS 기반, 로그 스케일)
  static double _computeLevel(Uint8List chunk) {
    if (chunk.length < 2) return 0;
    final bd = ByteData.sublistView(chunk);
    double sumSq = 0;
    final n = chunk.length ~/ 2;
    for (int i = 0; i < n; i++) {
      final s = bd.getInt16(i * 2, Endian.little).toDouble() / 32768.0;
      sumSq += s * s;
    }
    final rms = math.sqrt(sumSq / n);
    if (rms <= 0) return 0;
    // -60dB(~0.001) ~ 0dB(1.0) 범위를 0~1 로그 스케일로 매핑
    final db = 20 * (math.log(rms) / math.ln10);
    final norm = ((db + 60) / 60).clamp(0.0, 1.0);
    return norm;
  }

  Future<void> _processFinalWindowIfNeeded() async {
    const minFinalTailBytes = _sampleRate * 2; // 1초 미만은 환각 리스크가 더 큼
    if (_buffer.length < minFinalTailBytes) return;

    // 정상 윈도우 처리 직후에는 버퍼가 오버랩 5초만 남을 수 있다.
    // 새 오디오가 없는 순수 오버랩만 다시 돌리면 중복만 늘어나므로 스킵한다.
    if (_segments.isNotEmpty && _buffer.length <= _overlapBytes) {
      debugPrint('[STT FINAL] 새 tail 없음 — 오버랩 ${_buffer.length} bytes 스킵');
      return;
    }

    debugPrint(
      '[STT FINAL] 마지막 tail 처리 시작: '
      '${(_buffer.length / (_sampleRate * 2)).toStringAsFixed(1)}s',
    );
    await _processWindow(finalWindow: true);
  }

  Future<void> _processWindow({bool finalWindow = false}) async {
    if (_processing) return;
    _processing = true;
    onProcessing?.call(true);

    try {
      final allBytes = _buffer.takeBytes(); // 버퍼 전체 + 초기화
      if (allBytes.isEmpty) return;

      Uint8List windowBytes;
      if (!finalWindow && allBytes.length >= _windowBytes) {
        windowBytes = allBytes.sublist(0, _windowBytes);
        // 오버랩 5초 → 다음 윈도우 시작에 사용
        final keepStart = _windowBytes - _overlapBytes;
        _buffer.add(allBytes.sublist(keepStart));
      } else if (finalWindow) {
        // 종료 flush에서는 남은 tail 전체를 처리하고 오버랩을 다시 보관하지 않는다.
        windowBytes = allBytes;
      } else {
        // 30초 미만: 있는 데이터만 처리 (Whisper가 내부적으로 30초까지 패딩)
        windowBytes = allBytes;
        // 오버랩: 마지막 5초 또는 전체 (짧은 경우)
        final keepStart = allBytes.length > _overlapBytes
            ? allBytes.length - _overlapBytes
            : 0;
        _buffer.add(allBytes.sublist(keepStart));
      }

      // PCM16 → Float32
      final samples = _pcm16ToFloat32(windowBytes);

      // 실제 전진량 계산: 처리한 샘플 수 - 오버랩 샘플 수 (ms 단위)
      // 버퍼가 30초 미만일 때도 정확한 오프셋 유지
      final processedSamples = windowBytes.length ~/ 2;
      final advanceSamples = finalWindow
          ? processedSamples
          : (processedSamples - _overlapSamples).clamp(
              0,
              _windowSamples - _overlapSamples,
            );
      final actualAdvanceMs = (advanceSamples * 1000) ~/ _sampleRate;

      // v1.9.9+5: VAD 게이트 강화.
      //   threshold 0.0001 → 0.002 (≈-54 dBFS). 거의 완전 무음만 막던 것을
      //   '사람이 말하지 않는 생활 소음' 수준까지 막도록 상향.
      //   speechRatio 0.01 → 0.03. 짧은 기침/노이즈 burst에 속아 whisper를
      //   깨우지 않도록 조금 더 엄격하게. 회의 발화는 최소 수초 지속되므로
      //   30초 윈도우 기준 3%(≈0.9s) 요건은 조용한 화자도 충분히 통과.
      final rmsAvg = VadFilter.averageRms(samples);
      debugPrint(
        '[VAD] rms avg: ${rmsAvg.toStringAsFixed(4)}, samples: $processedSamples, advanceMs: $actualAdvanceMs, bufTotal: $_totalBytesReceived bytes',
      );
      if (!VadFilter.hasSpeech(samples, threshold: 0.002, speechRatio: 0.03)) {
        _baseOffsetMs += actualAdvanceMs;
        debugPrint('[VAD] 무음/잡음만 — Whisper 스킵');
        return;
      }

      debugPrint(
        '[VAD] 통과 → Whisper 처리 시작 '
        '(baseOffset: ${_baseOffsetMs}ms, final=$finalWindow)',
      );

      // Whisper 처리
      if (!OnDeviceModelManager.instance.isSttLoaded) return;

      final newSegments = await SttService.instance.transcribeFromSamples(
        samples,
        _baseOffsetMs,
      );

      _baseOffsetMs += actualAdvanceMs;

      int added = 0;
      int halluc = 0;
      int dup = 0;
      for (final seg in newSegments) {
        if (_isHallucination(seg.text)) {
          debugPrint('[STT FILTER] 환각 제거: "${seg.text}"');
          halluc++;
          continue;
        }
        if (_isDuplicateOfRecent(seg)) {
          debugPrint('[STT DEDUP] 윈도우 경계 중복 제거: "${seg.text}"');
          dup++;
          continue;
        }
        _segments.add(seg);
        onSegment?.call(seg);
        added++;
      }

      debugPrint(
        '[STT] 세그먼트 $added개 추가 (총 ${newSegments.length}개 중 환각 $halluc개·중복 $dup개 제거)',
      );
    } catch (e) {
      onError?.call('변환 오류: $e');
      debugPrint('[STT ERROR] $e');
    } finally {
      _processing = false;
      onProcessing?.call(false);

      // 처리 완료 후 버퍼가 30초 이상이면 즉시 재처리
      if (!finalWindow && _recording && _buffer.length >= _windowBytes) {
        _processWindow();
      }
    }
  }

  // ── Whisper 환각 필터 ─────────────────────────────────────────
  // Whisper가 무음·잡음 구간에서 자주 생성하는 한국어 뉴스/방송 문구 목록
  static const _hallucinationPatterns = [
    // ── 뉴스 방송 채널 ──────────────────────────────────────────
    'MBC 뉴스', 'KBS 뉴스', 'SBS 뉴스', 'JTBC 뉴스',
    'MBN 뉴스', 'YTN 뉴스', 'TV조선', '채널A', 'OBS 뉴스',
    '연합뉴스', '뉴스데스크', '뉴스입니다', '뉴스 시작합니다',
    '이 시각 세계였습니다', '이시각 세계였습니다',
    '세계 뉴스', '국제 뉴스',

    // ── 유튜브/SNS 방송 투식어 ─────────────────────────────────
    '구독과 좋아요', '구독 좋아요', '좋아요 구독',
    '알림 설정', '구독 알림', '좋아요와 구독',
    '시청해 주셔서 감사합니다', '시청해주셔서 감사합니다',
    '봐주셔서 감사합니다', '봐주셔서 감사', '함께해 주셔서 감사합니다',
    '다음 영상에서 만나요', '다음 시간에 만나요',

    // ── 자막/번역 ─────────────────────────────────────────────
    '자막 제공', '자막: ', '번역: ', '자막 by',
    '한국어 자막', '자막 제작',

    // ── 종교 ─────────────────────────────────────────────────
    '아멘', 'Amen', 'amen', '할렐루야', 'Hallelujah',

    // ── 기타 반복 환각 ────────────────────────────────────────
    '영상 시청', '방문해 주세요', '홈페이지',
    '시청자 여러분', '안녕히 계세요',
  ];

  /// 텍스트 정규화 — 중복 판정용. 공백/문장부호/따옴표 제거 + 소문자화.
  static String _normText(String s) =>
      s.replaceAll(RegExp(r'''[\s.,!?…·"'“”‘’()\[\]]+'''), '').toLowerCase();

  /// 윈도우 경계(5초 오버랩)에서 직전 윈도우가 이미 뱉은 문장이 다음 윈도우에
  /// 다시 등장하는 케이스를 제거. 슬라이딩 윈도우의 본질적 중복 문제로,
  /// `_collapseRepeatedShort`는 **한 윈도우 내부**에서만 동작해서 걸러지지 않는다.
  ///
  /// 판정 규칙 (and):
  ///   1) 새 세그먼트의 startMs가 마지막 처리 세그먼트 endMs - (오버랩+1초) 이후
  ///      → 이론상 겹칠 수 있는 시간 범위에 있는가
  ///   2) 정규화 텍스트가 동일하거나, 한쪽이 다른 쪽을 포함 (최소 6자 이상)
  bool _isDuplicateOfRecent(SttSegment seg) {
    final normed = _normText(seg.text);
    if (normed.isEmpty) return false;
    // 과거 세그먼트를 뒤에서 훑되 오버랩 경계(+1초 여유) 밖이면 중단
    const lookbackMs = (_overlapSec * 1000) + 1000;
    final cutoffMs = seg.startMs - lookbackMs;
    for (int i = _segments.length - 1; i >= 0; i--) {
      final prev = _segments[i];
      if (prev.endMs < cutoffMs) break;
      final existing = _normText(prev.text);
      if (existing.isEmpty) continue;
      if (existing == normed) return true;
      // 긴 문장의 일부가 잘려서 재등장하는 케이스 완화
      if (normed.length >= 6 && existing.contains(normed)) return true;
      if (existing.length >= 6 && normed.contains(existing)) return true;
    }
    return false;
  }

  static bool _isHallucination(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    // 공백 제거 후 1글자 이하
    if (t.replaceAll(RegExp(r'\s'), '').length <= 1) return true;
    for (final p in _hallucinationPatterns) {
      if (t.contains(p)) return true;
    }
    return false;
  }

  // ── 피크 정규화 ────────────────────────────────────────────────

  /// PCM16 전체를 스캔해 피크를 -1dB(약 0.89 스케일)로 맞춤.
  /// 저음량 녹음의 Whisper 인식률 향상이 목적이며, 클리핑은 절대 발생하지 않음.
  /// 이미 음량이 충분하면 (> -3dB) 그대로 반환.
  static Uint8List _peakNormalize(Uint8List pcm) {
    if (pcm.length < 2) return pcm;
    final bd = ByteData.sublistView(pcm);
    final n = pcm.length ~/ 2;

    int peak = 0;
    for (int i = 0; i < n; i++) {
      final s = bd.getInt16(i * 2, Endian.little).abs();
      if (s > peak) peak = s;
    }
    if (peak == 0) return pcm;

    // -1 dBFS 목표 = 32768 * 10^(-1/20) ≈ 29205
    const int target = 29205;
    if (peak >= 29205) {
      // 이미 충분히 크다 — 증폭 불필요
      return pcm;
    }
    final gain = target / peak;
    debugPrint(
      '[정규화] peak=$peak (${(20 * math.log(peak / 32768) / math.ln10).toStringAsFixed(1)} dBFS) → gain x${gain.toStringAsFixed(2)}',
    );

    final out = Uint8List(pcm.length);
    final outBd = ByteData.sublistView(out);
    for (int i = 0; i < n; i++) {
      final s = bd.getInt16(i * 2, Endian.little);
      var scaled = (s * gain).round();
      if (scaled > 32767) scaled = 32767;
      if (scaled < -32768) scaled = -32768;
      outBd.setInt16(i * 2, scaled, Endian.little);
    }
    return out;
  }

  // ── WAV 파일 작성 ──────────────────────────────────────────────

  /// PCM16 16kHz mono 데이터를 WAV 파일로 저장
  ///
  /// WAV 헤더 44 bytes + PCM data
  static Future<void> _writeWav(String path, Uint8List pcm) async {
    final dataSize = pcm.length;
    final header = ByteData(44);

    // RIFF chunk
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, 36 + dataSize, Endian.little); // ChunkSize
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // fmt sub-chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (PCM = 16)
    header.setUint16(20, 1, Endian.little); // AudioFormat (PCM = 1)
    header.setUint16(22, 1, Endian.little); // NumChannels (mono)
    header.setUint32(24, _sampleRate, Endian.little); // SampleRate
    header.setUint32(28, _sampleRate * 2, Endian.little); // ByteRate
    header.setUint16(32, 2, Endian.little); // BlockAlign
    header.setUint16(34, 16, Endian.little); // BitsPerSample

    // data sub-chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final file = File(path);
    final sink = file.openWrite();
    sink.add(header.buffer.asUint8List());
    sink.add(pcm);
    await sink.close();
  }

  /// PCM16 little-endian → Float32 [-1.0, 1.0]
  static Float32List _pcm16ToFloat32(Uint8List bytes) {
    // Uint8List의 바이트 순서가 little-endian 인지 보장하기 위해
    // ByteData를 통해 Int16 값을 읽는다
    final bd = bytes.buffer.asByteData(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    final sampleCount = bytes.length ~/ 2;
    final out = Float32List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }
}
