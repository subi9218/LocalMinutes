import 'package:isar/isar.dart';

part 'meeting.g.dart';

// 피크 메모리: DB 읽기 시 ~수 KB (모델 미로드 상태)

@collection
class Meeting {
  Id id = Isar.autoIncrement;

  late String title;

  @Index()
  late DateTime createdAt;

  DateTime? endedAt;

  @Enumerated(EnumType.name)
  late MeetingStatus status;

  // 전체 전사본 미리보기 (처음 200자, 목록 표시용)
  String? transcriptPreview;

  /// 소속 그룹 ID (null = 미분류)
  @Index()
  int? groupId;

  /// 녹음 WAV 파일 경로 (null = 파일 없음 / 구버전 회의)
  String? audioFilePath;

  /// 녹음 중 사용자가 직접 입력한 메모
  String notes = '';

  /// 자유 태그 (예: 기획, 1on1, 리뷰)
  List<String> tags = [];

  /// 이 회의 요약에 적용할 템플릿 프리셋 id.
  /// null = 전역 설정(AppSettings.summaryTemplateId) 따라감.
  /// 값 예시: 'general', 'retrospective', 'interview', 'custom'
  String? summaryTemplateId;

  /// STT/화자분리/요약 처리 성능 리포트 JSON.
  /// 구버전 회의는 빈 문자열이면 리포트 없음으로 처리한다.
  String processingReportJson = '';

  /// 화자 라벨(A/B/C…)을 사용자가 직접 부여한 이름 매핑.
  /// JSON 스키마: {"A":"철수", "B":"영희"} (없는 키는 기본 라벨 그대로 표시)
  /// 빈 문자열 = 모두 기본 라벨.
  String speakerNamesJson = '';

  /// 회의 시작 전 사용자가 입력한 어젠다 (한 줄에 하나씩).
  /// 요약 프롬프트에 주입되어 "각 어젠다별 논의/결정/액션" 정리에 활용된다.
  /// 빈 문자열 = 어젠다 없음.
  String agenda = '';

  /// 녹음 중 사용자가 마킹한 핵심 순간(북마크) JSON 배열.
  /// 스키마: [{"sec": 155, "label": "결정"}, {"sec": 320, "label": ""}]
  ///   - sec: 녹음 시작 시점 기준 초
  ///   - label: 선택 (결정/액션/질문/메모 등)
  /// 요약 프롬프트에 주입되어 LLM이 해당 시점을 우선 분석하도록 유도.
  String bookmarksJson = '';

  int get durationSeconds {
    if (endedAt == null) return 0;
    return endedAt!.difference(createdAt).inSeconds;
  }
}

/// 북마크 단일 항목 — JSON 직렬화/파싱 헬퍼
class Bookmark {
  final int sec;
  final String label;
  const Bookmark({required this.sec, this.label = ''});

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        sec: (json['sec'] as num?)?.toInt() ?? 0,
        label: (json['label'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'sec': sec, 'label': label};

  /// MM:SS 또는 HH:MM:SS 형식 문자열
  String get timeStr {
    final s = sec;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = s % 60;
    final mmss =
        '${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$mmss' : mmss;
  }
}

enum MeetingStatus {
  recording, // 녹음 중
  transcribing, // STT 처리 중
  summarizing, // LLM 요약 중
  done, // 완료
  error, // 오류
}
