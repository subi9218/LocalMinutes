class AppConstants {
  // ── LLM 모델 (v1.9.9+3) ─────────────────────────────────────────
  // 3종 지원. 사용자가 AppSettings.selectedLlmModel 로 선택.
  //   gemma4_e2b  : 기본. Q8_0 ~3GB, 빠름, 품질 기본급
  //   qwen25_7b   : Q4_K_M ~4.7GB, 한국어·구조화 출력 강함
  //   exaone35_7b : Q4_K_M ~4.8GB, 한국어 특화 (LG AI)
  static const String llmModelFileGemma4E2B = 'gemma-4-e2b-it-q8_0.gguf';
  static const String llmModelFileQwen25_7B = 'Qwen2.5-7B-Instruct-Q4_K_M.gguf';
  static const String llmModelFileExaone35_7B =
      'EXAONE-3.5-7.8B-Instruct-Q4_K_M.gguf';

  static const String llmDownloadUrlGemma4E2B =
      'https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF/resolve/main/google_gemma-4-E2B-it-Q8_0.gguf?download=true';
  static const String llmDownloadUrlQwen25_7B =
      'https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf?download=true';
  static const String llmDownloadUrlExaone35_7B =
      'https://huggingface.co/bartowski/EXAONE-3.5-7.8B-Instruct-GGUF/resolve/main/EXAONE-3.5-7.8B-Instruct-Q4_K_M.gguf?download=true';

  /// 하위호환용 기본값 (기존 호출부가 남아있을 때 E2B를 가리킴).
  /// 런타임 선택은 [AppSettings.instance.currentLlmModelFile] 사용.
  static const String llmModelFile = llmModelFileGemma4E2B;
  static const String llmDownloadUrl = llmDownloadUrlGemma4E2B;

  // ── STT 모델: 빠른 모드 vs 정확 모드 ───────────────────────────
  // v1.9.9: 사용자가 모드를 선택할 수 있게 토글 추가 (AppSettings.sttAccurateMode)
  //   빠른 모드  = turbo Q8 (디코더 4층, 5~8배 빠름) — ~900MB
  //   정확 모드  = full Large V3 Q5_0 (디코더 32층, 품질 우선) — ~1.1GB
  static const String sttModelFileFast = 'ggml-large-v3-turbo-q8_0.bin';
  static const String sttModelFileAccurate = 'ggml-large-v3-q5_0.bin';
  static const String sttCoreMlEncoderFileFast =
      'ggml-large-v3-turbo-encoder.mlmodelc';
  static const String sttCoreMlEncoderZipFast = '$sttCoreMlEncoderFileFast.zip';

  /// 기본 파일명 (기존 호출부 호환용 — 빠른 모드 가리킴).
  /// 런타임에 현재 모드에 따라 분기하려면 [AppSettings.instance.currentSttModelFile] 사용.
  static const String sttModelFile = sttModelFileFast;

  // 다운로드 URL (HuggingFace, 공개 접근)
  static const String sttDownloadUrlFast =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin';
  static const String sttDownloadUrlAccurate =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.bin';
  static const String sttCoreMlEncoderDownloadUrlFast =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-encoder.mlmodelc.zip';
  static const String sttDownloadUrl = sttDownloadUrlFast;

  // STT 스트리밍 설정
  static const int sttWindowSeconds = 30; // 슬라이딩 윈도우
  static const int sttOverlapSeconds = 5; // 오버랩
  static const String sttLanguage = 'ko';

  // LLM 설정
  static const int llmContextTokens = 128000;
  static const int llmChunkMaxTokens = 100000; // 청킹 임계값

  // ── Speaker Diarization (v1.9.9+4) ────────────────────────────────
  // sherpa-onnx 기반. 두 파일 필요:
  //   1. pyannote segmentation (.onnx 직접, ~6MB)
  //   2. 3D-Speaker embedding (.onnx 직접, ~25MB)
  static const String diarSegModelFile =
      'sherpa-onnx-pyannote-segmentation-3-0.onnx';
  static const String diarEmbModelFile =
      '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';

  static const String diarSegDownloadUrl =
      'https://huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0/resolve/main/model.onnx';
  static const String diarEmbDownloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';

  // 모델별 예상 다운로드 크기. 디스크 공간 사전 확인에만 사용한다.
  static const int sttModelBytesFast = 900 * 1024 * 1024;
  static const int sttModelBytesAccurate = 1100 * 1024 * 1024;
  static const int sttCoreMlEncoderBytesFast = 1200 * 1024 * 1024;
  static const int llmModelBytesGemma4E2B = 3000 * 1024 * 1024;
  static const int llmModelBytesQwen25_7B = 4700 * 1024 * 1024;
  static const int llmModelBytesExaone35_7B = 4800 * 1024 * 1024;
  static const int diarSegModelBytes = 6 * 1024 * 1024;
  static const int diarEmbModelBytes = 26 * 1024 * 1024;

  static int expectedModelBytes(String filename) => switch (filename) {
    sttModelFileFast => sttModelBytesFast,
    sttModelFileAccurate => sttModelBytesAccurate,
    sttCoreMlEncoderZipFast => sttCoreMlEncoderBytesFast,
    sttCoreMlEncoderFileFast => sttCoreMlEncoderBytesFast,
    llmModelFileGemma4E2B => llmModelBytesGemma4E2B,
    llmModelFileQwen25_7B => llmModelBytesQwen25_7B,
    llmModelFileExaone35_7B => llmModelBytesExaone35_7B,
    diarSegModelFile => diarSegModelBytes,
    diarEmbModelFile => diarEmbModelBytes,
    _ => 0,
  };

  // 키보드 단축키 (macOS)
  static const String shortcutRecord = 'cmd+r';
  static const String shortcutExport = 'cmd+e';
}
