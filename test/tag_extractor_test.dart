import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/core/services/tag_extractor.dart';

void main() {
  test('mergeTags keeps manual tags and appends unique suggestions', () {
    final merged = TagExtractor.mergeTags(
      const ['고객사', 'QA'],
      const ['QA', '출시 일정', '회의', '고객사 '],
    );

    expect(merged, const ['고객사', 'QA', '출시 일정']);
  });
}
