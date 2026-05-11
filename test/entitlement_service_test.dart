import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/core/services/entitlement_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EntitlementService.init();
  });

  test('default tier is pro and all gates allow (결제 통합 전 hardcode)', () {
    final svc = EntitlementService.instance;
    expect(svc.currentTier, EntitlementTier.pro);
    expect(svc.isUnlocked, isTrue);

    expect(svc.canStartMeeting().allowed, isTrue);
    expect(svc.canContinueRecording(120).allowed, isTrue);
    expect(svc.canUseAccurateMode().allowed, isTrue);
    expect(svc.canExportWithoutWatermark().allowed, isTrue);
    expect(svc.canUseAdvancedSummary().allowed, isTrue);
    expect(svc.canAddGlossaryEntry(999).allowed, isTrue);
  });

  test('remainingFreeMeetingsThisMonth is null for pro user', () {
    final svc = EntitlementService.instance;
    expect(svc.remainingFreeMeetingsThisMonth, isNull);
  });

  test(
    'incrementMonthMeetingCount tracks usage even for pro (출시 후 free 전환 대비)',
    () async {
      final svc = EntitlementService.instance;
      expect(svc.currentMonthMeetingCount, 0);

      await svc.incrementMonthMeetingCount();
      expect(svc.currentMonthMeetingCount, 1);

      await svc.incrementMonthMeetingCount();
      expect(svc.currentMonthMeetingCount, 2);
    },
  );

  test('PaywallTrigger has Korean title/description', () {
    for (final trigger in PaywallTrigger.values) {
      expect(trigger.title, isNotEmpty);
      expect(trigger.description, isNotEmpty);
    }
  });
}
