import 'package:isar/isar.dart';

part 'transcript.g.dart';

// 피크 메모리: Whisper 스트리밍 중 ~수 MB (세그먼트 버퍼)
// 30초 슬라이딩 윈도우 기준 세그먼트당 ~수백 바이트 텍스트

@collection
class Transcript {
  Id id = Isar.autoIncrement;

  /// 소속 회의 ID (Meeting.id)
  @Index()
  late int meetingId;

  /// 스트리밍 순서 인덱스 (0부터 시작)
  late int segmentIndex;

  /// 한국어 전사 텍스트
  late String text;

  /// 세그먼트 시작 시각 (녹음 시작 기준, 초)
  late double startTimeSeconds;

  /// 세그먼트 종료 시각 (녹음 시작 기준, 초)
  late double endTimeSeconds;

  /// 화자 라벨 ('A', 'B', 'C', ... 또는 null = 미판별)
  /// v1.9.9+4 Speaker Diarization. nullable로 추가 — 기존 전사는 null.
  String? speakerLabel;

  late DateTime createdAt;
}
