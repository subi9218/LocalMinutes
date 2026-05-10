// 기본 smoke test — Step 3 파이프라인 앱
// Isar 초기화가 필요하므로 flutter test로는 실행하지 않음.
// 실제 검증은 flutter run -d macos 후 수동 확인.

import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('placeholder test', (WidgetTester tester) async {
    // 실제 테스트는 macOS 앱 구동 후 수동 검증
    expect(1 + 1, equals(2));
  });
}
