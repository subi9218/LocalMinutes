import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/core/services/export_service.dart';
import 'package:local_minutes/domain/entities/meeting.dart';
import 'package:local_minutes/domain/entities/summary.dart';
import 'package:local_minutes/domain/entities/transcript.dart';

void main() {
  test('buildActionItemsMarkdown exports only action checklist', () {
    final meeting = _meeting();
    final summary = _summary()
      ..actionItemsJson = jsonEncode([
        {
          'task': 'QA 체크리스트 공유',
          'owner': '민지',
          'deadline': '금요일',
          'completed': false,
        },
      ]);

    final markdown = ExportService.buildActionItemsMarkdown(meeting, summary);

    expect(markdown, contains('# 제품 주간 회의 액션 아이템'));
    expect(markdown, contains('- [ ] QA 체크리스트 공유'));
    expect(markdown, contains('담당: 민지 / 기한: 금요일'));
    expect(markdown, isNot(contains('주요 논의')));
  });

  test('buildNotionMarkdown omits full transcript and keeps action items', () {
    final meeting = _meeting();
    final summary = _summary()
      ..keyDiscussions = const ['릴리즈 일정 조정 논의']
      ..actionItemsJson = jsonEncode([
        {'task': '릴리즈 후보 일정 재공유', 'owner': '(미언급)', 'deadline': ''},
      ]);

    final markdown = ExportService.buildNotionMarkdown(meeting, summary);

    expect(markdown, contains('## 주요 논의'));
    expect(markdown, contains('## 액션 아이템'));
    expect(markdown, contains('담당자 미확인'));
    expect(markdown, contains('기한 미확인'));
    expect(markdown, isNot(contains('## 전사본')));
  });

  test('buildBusinessReportMarkdown uses compact report sections', () {
    final meeting = _meeting();
    final summary = _summary()
      ..decisions = const ['5월 20일 릴리즈 후보 배포']
      ..openQuestions = const ['QA 인력 추가 투입 여부'];

    final markdown = ExportService.buildBusinessReportMarkdown(
      meeting,
      summary,
    );

    expect(markdown, contains('# 제품 주간 회의 보고'));
    expect(markdown, contains('## 결정 사항'));
    expect(markdown, contains('## 리스크 / 확인 필요'));
  });

  test('buildDocx creates a Word package with meeting content', () {
    final meeting = _meeting();
    final summary = _summary()
      ..decisions = const ['5월 20일 릴리즈 후보 배포']
      ..actionItemsJson = jsonEncode([
        {'task': 'QA 체크리스트 공유', 'owner': '민지', 'deadline': '금요일'},
      ]);

    final bytes = ExportService.buildDocx(meeting, summary, const []);
    final archive = ZipDecoder().decodeBytes(bytes);
    final document = archive.findFile('word/document.xml');

    expect(archive.findFile('[Content_Types].xml'), isNotNull);
    expect(archive.findFile('_rels/.rels'), isNotNull);
    expect(document, isNotNull);

    final xml = utf8.decode(document!.content);
    expect(xml, contains('제품 주간 회의'));
    expect(xml, contains('결정 사항'));
    expect(xml, contains('QA 체크리스트 공유'));
  });

  test('buildBusinessReportDocx creates compact report without transcript', () {
    final meeting = _meeting();
    final summary = _summary()
      ..keyDiscussions = const ['릴리즈 일정 조정 논의']
      ..openQuestions = const ['QA 인력 추가 투입 여부'];
    final transcript = Transcript()
      ..meetingId = 1
      ..segmentIndex = 0
      ..text = '보고서 파일에는 전체 전사본이 들어가지 않아야 합니다.'
      ..startTimeSeconds = 0
      ..endTimeSeconds = 3
      ..createdAt = DateTime(2026, 5, 5);

    final fullDocx = ExportService.buildDocx(meeting, summary, [transcript]);
    final reportDocx = ExportService.buildBusinessReportDocx(meeting, summary);
    final fullXml = utf8.decode(
      ZipDecoder().decodeBytes(fullDocx).findFile('word/document.xml')!.content,
    );
    final reportXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(reportDocx)
          .findFile('word/document.xml')!
          .content,
    );

    expect(fullXml, contains('전사본'));
    expect(reportXml, contains('제품 주간 회의 보고'));
    expect(reportXml, contains('핵심 논의'));
    expect(reportXml, contains('리스크 / 확인 필요'));
    expect(reportXml, isNot(contains('전사본')));
    expect(reportXml, isNot(contains('전체 전사본')));
  });
}

Meeting _meeting() {
  return Meeting()
    ..title = '제품 주간 회의'
    ..createdAt = DateTime(2026, 5, 5, 10)
    ..endedAt = DateTime(2026, 5, 5, 11)
    ..status = MeetingStatus.done;
}

Summary _summary() {
  return Summary()
    ..meetingId = 1
    ..meetingTitle = '제품 주간 회의'
    ..meetingDate = DateTime(2026, 5, 5)
    ..participants = const ['민지', '준호']
    ..keyDiscussions = const []
    ..decisions = const []
    ..actionItemsJson = '[]'
    ..openQuestions = const []
    ..createdAt = DateTime(2026, 5, 5);
}
