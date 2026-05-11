import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/core/services/summary_templates.dart';

void main() {
  test('topic report template is available as a preset', () {
    final ids = SummaryTemplates.presets.map((t) => t.id).toList();

    expect(ids, contains('topic_report'));
    expect(SummaryTemplates.byId('topic_report').name, '주제별 요약');
  });

  test(
    'presets contain general/topic_report/lecture only (retrospective/interview removed)',
    () {
      final ids = SummaryTemplates.presets.map((t) => t.id).toSet();
      expect(ids, {'general', 'topic_report', 'lecture'});
      expect(ids, isNot(contains('retrospective')));
      expect(ids, isNot(contains('interview')));
    },
  );

  test('lecture template guides knowledge curation', () {
    final t = SummaryTemplates.byId('lecture');
    expect(t.id, 'lecture');
    expect(t.name, '강의/세미나');
    expect(t.instruction, contains('지식 큐레이터'));
    expect(t.instruction, contains('가. 지식 테마'));
    expect(t.instruction, contains('용어 사전'));
    expect(t.instruction, contains('Self-Reflection'));
    // 환각 방지 가드 필수
    expect(t.instruction, contains('환각 방지'));
  });

  test('custom1 and custom2 slot ids exist', () {
    expect(SummaryTemplates.customId1, 'custom1');
    expect(SummaryTemplates.customId2, 'custom2');
  });

  test('topic report template guides topic-based report minutes', () {
    final instruction = SummaryTemplates.byId('topic_report').instruction;

    // 주제별 재배치 + ㄴ 마커 형식
    expect(instruction, contains('단순 시간순 나열 금지'));
    expect(instruction, contains('가. 회의 개요'));
    expect(instruction, contains('나. {대주제명}'));
    expect(instruction, contains('ㄴ'));
    // 명사형 개조식 톤
    expect(instruction, contains('명사형 개조식'));
    // 환각 방지 가드 — 출시 신뢰도의 핵심
    expect(instruction, contains('환각 방지'));
    expect(instruction, contains('만들어 추가하지 말 것'));
  });
}
