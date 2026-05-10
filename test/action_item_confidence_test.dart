import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant2/domain/entities/summary.dart';

void main() {
  test('action item marks missing owner and deadline as unconfirmed', () {
    final item = ActionItem.fromJson({
      'task': 'QA 체크리스트 정리',
      'owner': '(미언급)',
      'deadline': '',
    });

    expect(item.ownerNeedsConfirmation, isTrue);
    expect(item.deadlineNeedsConfirmation, isTrue);
  });

  test('action item preserves explicit confidence flags', () {
    final item = ActionItem.fromJson({
      'task': 'API 문서 공유',
      'owner': '화자 A',
      'deadline': '이번 주 금요일',
      'ownerConfirmed': true,
      'deadlineConfirmed': false,
    });

    expect(item.ownerNeedsConfirmation, isFalse);
    expect(item.deadlineNeedsConfirmation, isTrue);
    expect(item.toJson()['deadlineConfirmed'], isFalse);
  });
}
