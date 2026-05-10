import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/repositories/meeting_repository_impl.dart';
import '../../data/repositories/transcript_repository_impl.dart';
import '../../domain/entities/meeting.dart';
import 'isar_service.dart';

/// 비정상 종료된 녹음(앱 크래시·강제 종료) 복구 서비스.
///
/// 정상 흐름:
///   녹음 시작 → Meeting(status=recording) 즉시 저장
///   30초마다 진행 중인 transcripts를 DB에 flush
///   녹음 종료 → status=transcribing → summarizing → done
///
/// 크래시 발생 시:
///   - WAV 파일은 OS 버퍼링이지만 보통 디스크에 부분 기록됨
///   - DB의 Meeting은 status=recording/transcribing/summarizing 상태로 남음
///   - 다음 앱 시작 시 [findRecoverable]가 이를 탐지
///
/// 사용자에게 "복구 / 삭제 / 나중에" 선택지를 보여준다.
class RecoveryService {
  RecoveryService._();

  /// 비정상 종료로 보이는 회의 목록을 반환.
  /// 조건:
  ///   - status가 done/error가 아니고
  ///   - 전사본이 1개 이상 존재 (체크포인트로 일부 저장됨)
  ///   OR transcripts 없으면 audio 파일이 실제로 존재해야만 복구 후보로 판단.
  ///   (즉, 빈 깡통 Meeting은 자동 정리)
  static Future<List<Meeting>> findRecoverable() async {
    try {
      final db = IsarService.instance.db;
      final repo = MeetingRepositoryImpl(db);
      final transcriptRepo = TranscriptRepositoryImpl(db);
      final all = await repo.getAllMeetings();
      final candidates = all
          .where(
            (m) =>
                m.status != MeetingStatus.done &&
                m.status != MeetingStatus.error,
          )
          .toList();

      debugPrint(
        '[RecoveryService] candidates before filter: ${candidates.length}',
      );

      final result = <Meeting>[];
      for (final m in candidates) {
        final segs = await transcriptRepo.getSegmentsByMeetingId(m.id);
        final hasTranscripts = segs.isNotEmpty;
        bool hasAudio = false;
        if (m.audioFilePath != null && m.audioFilePath!.isNotEmpty) {
          try {
            hasAudio = await File(m.audioFilePath!).exists();
          } catch (_) {}
        }
        if (hasTranscripts || hasAudio) {
          result.add(m);
        } else {
          // 데이터가 전혀 없는 빈 깡통 — 자동 삭제
          debugPrint(
            '[RecoveryService] auto-discard empty meeting id=${m.id} '
            'title=${m.title}',
          );
          try {
            await repo.deleteMeeting(m.id);
          } catch (_) {}
        }
      }
      debugPrint('[RecoveryService] recoverable: ${result.length}');
      return result;
    } catch (e) {
      debugPrint('[RecoveryService] findRecoverable failed: $e');
      return const [];
    }
  }

  /// 복구를 확정(녹음은 끝난 것으로 간주, 사용자에게 일반 회의로 보이게).
  /// status를 `done`으로 변경하고, endedAt이 비어있으면 createdAt + transcript의
  /// 마지막 시점으로 추정 채움.
  static Future<void> markAsRecovered(Meeting meeting) async {
    final db = IsarService.instance.db;
    final transcriptRepo = TranscriptRepositoryImpl(db);
    final segments = await transcriptRepo.getSegmentsByMeetingId(meeting.id);

    DateTime? estimatedEnd;
    if (segments.isNotEmpty) {
      final lastSec = segments.last.endTimeSeconds;
      estimatedEnd = meeting.createdAt.add(
        Duration(milliseconds: (lastSec * 1000).round()),
      );
    }

    meeting.status = MeetingStatus.done;
    meeting.endedAt ??= estimatedEnd ?? DateTime.now();
    if (meeting.transcriptPreview == null ||
        meeting.transcriptPreview!.isEmpty) {
      final fullText = segments.map((s) => s.text).join(' ');
      meeting.transcriptPreview = fullText.length > 200
          ? fullText.substring(0, 200)
          : fullText;
    }
    await MeetingRepositoryImpl(db).updateMeeting(meeting);
  }

  /// 복구 거부 — 회의·전사·녹음 파일 모두 삭제.
  static Future<void> discardMeeting(Meeting meeting) async {
    final db = IsarService.instance.db;
    final transcriptRepo = TranscriptRepositoryImpl(db);
    final meetingRepo = MeetingRepositoryImpl(db);

    // 1) 오디오 파일 삭제
    final path = meeting.audioFilePath;
    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('[RecoveryService] audio delete failed: $e');
      }
    }
    // 2) 전사 세그먼트 삭제
    try {
      await transcriptRepo.deleteByMeetingId(meeting.id);
    } catch (e) {
      debugPrint('[RecoveryService] transcript delete failed: $e');
    }
    // 3) Meeting 삭제
    try {
      await meetingRepo.deleteMeeting(meeting.id);
    } catch (e) {
      debugPrint('[RecoveryService] meeting delete failed: $e');
    }
  }

  /// 사람이 읽을 수 있는 상태 라벨 반환
  static String statusLabel(MeetingStatus s) {
    switch (s) {
      case MeetingStatus.recording:
        return '녹음 중 종료';
      case MeetingStatus.transcribing:
        return '음성 인식 중 종료';
      case MeetingStatus.summarizing:
        return '요약 중 종료';
      case MeetingStatus.done:
        return '완료';
      case MeetingStatus.error:
        return '오류';
    }
  }
}
