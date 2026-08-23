import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../data/repositories/meeting_repository_impl.dart';
import '../../domain/entities/meeting.dart';
import 'isar_service.dart';

/// 오래된 녹음 WAV 파일만 삭제하는 공용 헬퍼.
///
/// 회의 레코드·전사·요약은 그대로 유지. `Meeting.audioFilePath` 만 null로
/// 설정해 "원본 오디오 없음" 상태로 전환한다.
///
/// main.dart(앱 시작 시 자동) / settings_screen(즉시 삭제 버튼) 두 호출자가
/// 동일 로직을 공유하도록 통합.
class AutoDeleteService {
  /// [days] 일 이상 지난 회의의 WAV 파일을 삭제.
  /// 반환: (deleted: 삭제된 파일 수, missing: DB에는 있었으나 파일이 이미 없던 수)
  static Future<AutoDeleteResult> run(int days) async {
    if (days <= 0) return const AutoDeleteResult(deleted: 0, missing: 0);

    final cutoff = DateTime.now().subtract(Duration(days: days));
    final repo = MeetingRepositoryImpl(IsarService.instance.db);

    int deleted = 0;
    int missing = 0;
    try {
      final meetings = await repo.getAllMeetings();
      for (final m in meetings) {
        if (!m.createdAt.isBefore(cutoff)) continue;
        // 복구 대기 중(진행형 상태) 회의는 건드리지 않는다 — WAV를 지우면
        // 복구 서비스가 회의를 통째로 파기한다. 단 error(실패 확정)는
        // 복구 대상이 아니므로 정상 삭제 대상에 포함한다.
        if (m.status != MeetingStatus.done && m.status != MeetingStatus.error) {
          continue;
        }
        final path = m.audioFilePath;
        if (path == null || path.isEmpty) continue;

        // 앱이 직접 만든 녹음/변환 파일만 삭제한다.
        // '파일 불러오기'로 등록된 회의의 audioFilePath는 사용자의 원본
        // 파일을 가리킬 수 있는데, 그걸 지우면 사용자 데이터 파괴다.
        final sep = path.lastIndexOf('/');
        final base = sep < 0 ? path : path.substring(sep + 1);
        final dir = sep < 0 ? '' : path.substring(0, sep);
        final appOwned =
            (base.startsWith('meeting_') && base.endsWith('.wav')) ||
            dir.endsWith('/imported');
        if (!appOwned) continue;

        final file = File(path);
        // 파일이 이미 없으면 delete 호출을 스킵해서 불필요한 예외 비용을 제거.
        final exists = await file.exists();
        if (exists) {
          try {
            await file.delete();
            deleted++;
          } catch (e) {
            debugPrint('[AutoDelete] 삭제 실패($path): $e');
            continue; // DB는 그대로 둬서 다음에 다시 시도 가능
          }
        } else {
          missing++;
        }

        // 파일이 실제로 삭제됐거나, 이미 없는 상태면 DB 경로 정리
        m.audioFilePath = null;
        await repo.updateMeeting(m);
      }
    } catch (e) {
      debugPrint('[AutoDelete] 전체 실행 실패: $e');
    }
    if (deleted > 0 || missing > 0) {
      debugPrint('[AutoDelete] 완료 — 삭제: $deleted개, 누락된 항목 정리: $missing개 (days=$days)');
    }
    return AutoDeleteResult(deleted: deleted, missing: missing);
  }
}

class AutoDeleteResult {
  final int deleted;
  final int missing;
  const AutoDeleteResult({required this.deleted, required this.missing});

  bool get isEmpty => deleted == 0 && missing == 0;
  int get total => deleted + missing;
}
