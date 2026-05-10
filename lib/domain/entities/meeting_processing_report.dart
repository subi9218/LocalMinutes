import 'dart:convert';

class MeetingProcessingReport {
  final String sttModel;
  final String sttLanguage;
  final int sttElapsedMs;
  final int sttAudioMs;
  final double sttRtf;
  final String sttProcessingMode;

  final bool diarizationEnabled;
  final String diarizationStatus;
  final int diarizationElapsedMs;

  final String llmModel;
  final int summaryElapsedMs;

  final String inputQualityStatus;
  final String inputQualityReason;
  final int inputRecognizedChars;
  final int inputSegmentCount;
  final double inputMaxLevel;

  const MeetingProcessingReport({
    this.sttModel = '',
    this.sttLanguage = '',
    this.sttElapsedMs = 0,
    this.sttAudioMs = 0,
    this.sttRtf = 0,
    this.sttProcessingMode = '',
    this.diarizationEnabled = false,
    this.diarizationStatus = '',
    this.diarizationElapsedMs = 0,
    this.llmModel = '',
    this.summaryElapsedMs = 0,
    this.inputQualityStatus = '',
    this.inputQualityReason = '',
    this.inputRecognizedChars = 0,
    this.inputSegmentCount = 0,
    this.inputMaxLevel = 0,
  });

  bool get hasAnyData =>
      sttElapsedMs > 0 ||
      diarizationElapsedMs > 0 ||
      diarizationStatus.isNotEmpty ||
      summaryElapsedMs > 0 ||
      sttModel.isNotEmpty ||
      sttLanguage.isNotEmpty ||
      llmModel.isNotEmpty ||
      inputQualityStatus.isNotEmpty;

  MeetingProcessingReport copyWith({
    String? sttModel,
    String? sttLanguage,
    int? sttElapsedMs,
    int? sttAudioMs,
    double? sttRtf,
    String? sttProcessingMode,
    bool? diarizationEnabled,
    String? diarizationStatus,
    int? diarizationElapsedMs,
    String? llmModel,
    int? summaryElapsedMs,
    String? inputQualityStatus,
    String? inputQualityReason,
    int? inputRecognizedChars,
    int? inputSegmentCount,
    double? inputMaxLevel,
  }) {
    return MeetingProcessingReport(
      sttModel: sttModel ?? this.sttModel,
      sttLanguage: sttLanguage ?? this.sttLanguage,
      sttElapsedMs: sttElapsedMs ?? this.sttElapsedMs,
      sttAudioMs: sttAudioMs ?? this.sttAudioMs,
      sttRtf: sttRtf ?? this.sttRtf,
      sttProcessingMode: sttProcessingMode ?? this.sttProcessingMode,
      diarizationEnabled: diarizationEnabled ?? this.diarizationEnabled,
      diarizationStatus: diarizationStatus ?? this.diarizationStatus,
      diarizationElapsedMs: diarizationElapsedMs ?? this.diarizationElapsedMs,
      llmModel: llmModel ?? this.llmModel,
      summaryElapsedMs: summaryElapsedMs ?? this.summaryElapsedMs,
      inputQualityStatus: inputQualityStatus ?? this.inputQualityStatus,
      inputQualityReason: inputQualityReason ?? this.inputQualityReason,
      inputRecognizedChars: inputRecognizedChars ?? this.inputRecognizedChars,
      inputSegmentCount: inputSegmentCount ?? this.inputSegmentCount,
      inputMaxLevel: inputMaxLevel ?? this.inputMaxLevel,
    );
  }

  factory MeetingProcessingReport.fromJsonString(String raw) {
    if (raw.trim().isEmpty) return const MeetingProcessingReport();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return MeetingProcessingReport(
        sttModel: (json['sttModel'] ?? '').toString(),
        sttLanguage: (json['sttLanguage'] ?? '').toString(),
        sttElapsedMs: (json['sttElapsedMs'] as num?)?.toInt() ?? 0,
        sttAudioMs: (json['sttAudioMs'] as num?)?.toInt() ?? 0,
        sttRtf: (json['sttRtf'] as num?)?.toDouble() ?? 0,
        sttProcessingMode: (json['sttProcessingMode'] ?? '').toString(),
        diarizationEnabled: json['diarizationEnabled'] as bool? ?? false,
        diarizationStatus: (json['diarizationStatus'] ?? '').toString(),
        diarizationElapsedMs:
            (json['diarizationElapsedMs'] as num?)?.toInt() ?? 0,
        llmModel: (json['llmModel'] ?? '').toString(),
        summaryElapsedMs: (json['summaryElapsedMs'] as num?)?.toInt() ?? 0,
        inputQualityStatus: (json['inputQualityStatus'] ?? '').toString(),
        inputQualityReason: (json['inputQualityReason'] ?? '').toString(),
        inputRecognizedChars:
            (json['inputRecognizedChars'] as num?)?.toInt() ?? 0,
        inputSegmentCount: (json['inputSegmentCount'] as num?)?.toInt() ?? 0,
        inputMaxLevel: (json['inputMaxLevel'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return const MeetingProcessingReport();
    }
  }

  Map<String, dynamic> toJson() => {
    'sttModel': sttModel,
    'sttLanguage': sttLanguage,
    'sttElapsedMs': sttElapsedMs,
    'sttAudioMs': sttAudioMs,
    'sttRtf': sttRtf,
    'sttProcessingMode': sttProcessingMode,
    'diarizationEnabled': diarizationEnabled,
    'diarizationStatus': diarizationStatus,
    'diarizationElapsedMs': diarizationElapsedMs,
    'llmModel': llmModel,
    'summaryElapsedMs': summaryElapsedMs,
    'inputQualityStatus': inputQualityStatus,
    'inputQualityReason': inputQualityReason,
    'inputRecognizedChars': inputRecognizedChars,
    'inputSegmentCount': inputSegmentCount,
    'inputMaxLevel': inputMaxLevel,
  };

  String toJsonString() => jsonEncode(toJson());
}
