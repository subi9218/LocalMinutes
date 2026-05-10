class LegalNotice {
  final String name;
  final String role;
  final String license;
  final String source;
  final String note;

  const LegalNotice({
    required this.name,
    required this.role,
    required this.license,
    required this.source,
    required this.note,
  });
}

class LegalNotices {
  LegalNotices._();

  static const List<LegalNotice> items = [
    LegalNotice(
      name: 'whisper.cpp',
      role: '음성 인식 엔진',
      license: 'MIT License',
      source: 'https://github.com/ggml-org/whisper.cpp',
      note: '앱 안에서 음성을 텍스트로 변환하는 네이티브 엔진입니다.',
    ),
    LegalNotice(
      name: 'Whisper Large V3 / Large V3 Turbo',
      role: '음성 인식 모델',
      license: 'MIT License',
      source: 'https://huggingface.co/ggerganov/whisper.cpp',
      note: '사용자가 내려받아 로컬 Mac에서만 실행하는 음성 인식 모델입니다.',
    ),
    LegalNotice(
      name: 'llama.cpp',
      role: '요약 모델 실행 엔진',
      license: 'MIT License',
      source: 'https://github.com/ggml-org/llama.cpp',
      note: 'GGUF 요약 모델을 로컬에서 실행하는 네이티브 엔진입니다.',
    ),
    LegalNotice(
      name: 'Gemma',
      role: '기본 요약 모델',
      license: 'Google Gemma Terms of Use',
      source: 'https://ai.google.dev/gemma/terms',
      note: '앱스토어 빌드에서 기본 요약 모델 선택지로 제공합니다.',
    ),
    LegalNotice(
      name: 'Qwen 2.5 7B Instruct',
      role: '고품질 요약 모델',
      license: 'Apache License 2.0',
      source: 'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct',
      note: '구조화된 회의록 요약을 위한 선택 모델입니다.',
    ),
    LegalNotice(
      name: 'sherpa-onnx',
      role: '발화자 라벨 엔진',
      license: 'Apache License 2.0',
      source: 'https://github.com/k2-fsa/sherpa-onnx',
      note: '사람 이름 식별이 아닌 A/B/C 발화자 라벨 보조 기능에 사용합니다.',
    ),
  ];

  static const String restrictedModelNote =
      'EXAONE 3.5 계열은 NC 성격의 라이선스 리스크가 있어 앱스토어용 빌드에서는 '
      '다운로드, 선택, 기본 설정 노출을 비활성화했습니다. 내부 테스트 빌드에서만 '
      '명시적인 빌드 플래그로 다시 켤 수 있습니다.';
}
