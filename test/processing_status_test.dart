import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/core/services/processing_status_service.dart';

void main() {
  // 싱글턴이므로 각 테스트 시작 시 상태를 초기화한다.
  setUp(() {
    ProcessingStatus.instance.clear();
    ProcessingStatus.instance.lastCompleted = null;
  });

  group('ProcessingStatus', () {
    test('start → isBusy true, active 값 설정', () {
      final s = ProcessingStatus.instance;
      expect(s.isBusy, isFalse);
      s.start(
        meetingId: 7,
        kind: 'transcribe',
        meetingTitle: '회의 A',
        label: '로드 중',
        progress: 0,
      );
      expect(s.isBusy, isTrue);
      expect(s.active.value!.meetingId, 7);
      expect(s.active.value!.kind, 'transcribe');
      expect(s.active.value!.meetingTitle, '회의 A');
    });

    test('update는 라벨/진행률만 바꾸고 식별자는 유지', () {
      final s = ProcessingStatus.instance;
      s.start(
        meetingId: 3,
        kind: 'summarize',
        meetingTitle: 'B',
        label: '준비',
        progress: -1,
      );
      s.update(label: '진행 중', progress: 0.5);
      expect(s.active.value!.label, '진행 중');
      expect(s.active.value!.progress, 0.5);
      expect(s.active.value!.meetingId, 3);
      expect(s.active.value!.kind, 'summarize');
    });

    test('작업 없을 때 update는 무시', () {
      final s = ProcessingStatus.instance;
      s.update(label: 'x', progress: 0.9);
      expect(s.active.value, isNull);
    });

    test('clear → active null, completionTick 증가, lastCompleted 기록', () {
      final s = ProcessingStatus.instance;
      final before = s.completionTick.value;
      s.start(
        meetingId: 11,
        kind: 'transcribe',
        meetingTitle: 'C',
        label: 'L',
      );
      s.clear();
      expect(s.active.value, isNull);
      expect(s.completionTick.value, before + 1);
      expect(s.lastCompleted!.meetingId, 11);
    });

    test('작업 없이 clear하면 completionTick은 그대로', () {
      final s = ProcessingStatus.instance;
      final before = s.completionTick.value;
      s.clear();
      expect(s.completionTick.value, before);
    });

    test('registerCancel + requestCancel은 등록된 콜백 호출', () {
      final s = ProcessingStatus.instance;
      var cancelled = false;
      s.start(
        meetingId: 1,
        kind: 'transcribe',
        meetingTitle: 'D',
        label: 'L',
      );
      expect(s.cancelable, isFalse);
      s.registerCancel(() => cancelled = true);
      expect(s.cancelable, isTrue);
      s.requestCancel();
      expect(cancelled, isTrue);
    });

    test('clear는 cancel 콜백도 해제', () {
      final s = ProcessingStatus.instance;
      var count = 0;
      s.start(meetingId: 1, kind: 'transcribe', meetingTitle: 'E', label: 'L');
      s.registerCancel(() => count++);
      s.clear();
      expect(s.cancelable, isFalse);
      s.requestCancel(); // 콜백이 해제되어 아무 일도 없어야 함
      expect(count, 0);
    });
  });
}
