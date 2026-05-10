import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/meeting.dart';
import '../../domain/entities/summary.dart';
import '../../domain/entities/transcript.dart';

/// macOS 내보내기 서비스
///
/// 형식:
///   - 텍스트 (.txt): file_selector Save 패널 → dart:io File 저장
///   - Markdown (.md): Save 패널 저장 또는 클립보드 복사
///   - PDF (.pdf): pdf 패키지 + NanumGothic (앱 번들) → Save 패널 저장
///   - DOCX (.docx): 기본 WordprocessingML 패키지 생성
///   - 이메일: url_launcher mailto: (요약만 포함, URL 길이 한계)
///   - 공유: share_plus macOS Share Sheet (임시 파일 공유)
class ExportService {
  ExportService._();

  // 앱 번들 한국어 폰트 경로 (NanumGothic, OFL 라이선스)
  static const _koreanFontAsset = 'assets/fonts/NanumGothic-Regular.ttf';

  // ── 콘텐츠 생성 ─────────────────────────────────────────────────

  /// 회의록 전체를 포맷된 텍스트로 변환
  static String buildText(
    Meeting meeting,
    Summary? summary,
    List<Transcript> transcripts,
  ) {
    final buf = StringBuffer();
    final sep = '═' * 48;
    final thin = '─' * 48;

    buf.writeln(sep);
    buf.writeln('온디바이스 AI 회의록');
    buf.writeln(sep);
    buf.writeln();

    // 헤더
    buf.writeln(meeting.title);
    final dt = meeting.createdAt;
    final dtStr =
        '${dt.year}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    final durStr = meeting.durationSeconds > 0
        ? ' | 소요시간: ${meeting.durationSeconds ~/ 60}분 ${meeting.durationSeconds % 60}초'
        : '';
    buf.writeln('날짜: $dtStr$durStr');
    buf.writeln();

    if (summary != null) {
      // 참석자
      if (summary.participants.isNotEmpty) {
        buf.writeln('【참석자】');
        buf.writeln(summary.participants.join(', '));
        buf.writeln();
      }

      // 주요 논의
      if (summary.keyDiscussions.isNotEmpty) {
        buf.writeln('【주요 논의】');
        for (final item in summary.keyDiscussions) {
          buf.writeln('• $item');
        }
        buf.writeln();
      }

      // 결정 사항
      if (summary.decisions.isNotEmpty) {
        buf.writeln('【결정 사항】');
        for (final item in summary.decisions) {
          buf.writeln('• $item');
        }
        buf.writeln();
      }

      // 액션 아이템
      try {
        final items = (jsonDecode(summary.actionItemsJson) as List)
            .map((e) => ActionItem.fromJson(e as Map<String, dynamic>))
            .toList();
        if (items.isNotEmpty) {
          buf.writeln('【액션 아이템】');
          for (final a in items) {
            buf.writeln(
              '• ${a.task}  [담당: ${_actionOwnerText(a)}] [기한: ${_actionDeadlineText(a)}]',
            );
          }
          buf.writeln();
        }
      } catch (_) {}

      // 미해결 이슈
      if (summary.openQuestions.isNotEmpty) {
        buf.writeln('【미해결 이슈】');
        for (final item in summary.openQuestions) {
          buf.writeln('• $item');
        }
        buf.writeln();
      }
    }

    // 전사본
    if (transcripts.isNotEmpty) {
      buf.writeln(thin);
      buf.writeln('【전사본】');
      for (final seg in transcripts) {
        final start = _secToStr(seg.startTimeSeconds);
        final end = _secToStr(seg.endTimeSeconds);
        buf.writeln('[$start→$end] ${seg.text}');
      }
    }

    return buf.toString();
  }

  /// 회의록 전체를 Markdown으로 변환
  static String buildMarkdown(
    Meeting meeting,
    Summary? summary,
    List<Transcript> transcripts,
  ) {
    final buf = StringBuffer();
    final dt = meeting.createdAt;
    final dtStr =
        '${dt.year}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    final durStr = meeting.durationSeconds > 0
        ? '${meeting.durationSeconds ~/ 60}분 ${meeting.durationSeconds % 60}초'
        : '';

    buf.writeln('# ${_markdownText(meeting.title)}');
    buf.writeln();
    buf.writeln('- 날짜: $dtStr');
    if (durStr.isNotEmpty) buf.writeln('- 소요 시간: $durStr');
    buf.writeln('- 생성: 적자생존 온디바이스 AI 회의록');
    buf.writeln();

    if (summary == null) {
      buf.writeln('> 요약이 아직 생성되지 않았습니다.');
      buf.writeln();
    } else {
      if (summary.participants.isNotEmpty) {
        buf.writeln('## 참석자');
        buf.writeln();
        buf.writeln(summary.participants.map(_markdownText).join(', '));
        buf.writeln();
      }

      _writeMarkdownList(buf, '주요 논의', summary.keyDiscussions);
      _writeMarkdownList(buf, '결정 사항', summary.decisions);
      _writeMarkdownActionItems(buf, summary);
      _writeMarkdownList(buf, '미해결 이슈', summary.openQuestions);
    }

    if (transcripts.isNotEmpty) {
      buf.writeln('## 전사본');
      buf.writeln();
      for (final seg in transcripts) {
        final start = _secToStr(seg.startTimeSeconds);
        final end = _secToStr(seg.endTimeSeconds);
        final speaker = seg.speakerLabel == null ? '' : ' ${seg.speakerLabel}:';
        buf.writeln('- `[$start→$end]`$speaker ${_markdownText(seg.text)}');
      }
      buf.writeln();
    }

    return buf.toString();
  }

  /// Notion/문서 도구에 바로 붙여넣기 좋은 요약 중심 Markdown.
  ///
  /// 전체 전사본은 제외하고 회의 핵심, 결정, 액션, 미해결 이슈만 담는다.
  static String buildNotionMarkdown(Meeting meeting, Summary? summary) {
    final buf = StringBuffer();
    final dt = meeting.createdAt;
    final dtStr =
        '${dt.year}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';

    buf.writeln('# ${_markdownText(meeting.title)}');
    buf.writeln();
    buf.writeln('- 날짜: $dtStr');
    if (meeting.durationSeconds > 0) {
      buf.writeln(
        '- 소요 시간: ${meeting.durationSeconds ~/ 60}분 ${meeting.durationSeconds % 60}초',
      );
    }
    buf.writeln();

    if (summary == null) {
      buf.writeln('> 요약이 아직 생성되지 않았습니다.');
      return buf.toString();
    }

    if (summary.participants.isNotEmpty) {
      buf.writeln('## 참석자');
      buf.writeln(summary.participants.map(_markdownText).join(', '));
      buf.writeln();
    }

    _writeMarkdownList(buf, '주요 논의', summary.keyDiscussions);
    _writeMarkdownList(buf, '결정 사항', summary.decisions);
    _writeNotionActionItems(buf, summary);
    _writeMarkdownList(buf, '미해결 이슈', summary.openQuestions);

    return buf.toString();
  }

  /// 회사 보고서/업무 공유용으로 더 짧게 정리한 Markdown.
  static String buildBusinessReportMarkdown(Meeting meeting, Summary? summary) {
    final buf = StringBuffer();
    final dt = meeting.createdAt;
    final dtStr =
        '${dt.year}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';

    buf.writeln('# ${_markdownText(meeting.title)} 보고');
    buf.writeln();
    buf.writeln('| 항목 | 내용 |');
    buf.writeln('| --- | --- |');
    buf.writeln('| 일자 | $dtStr |');
    if (summary?.participants.isNotEmpty == true) {
      buf.writeln(
        '| 참석자 | ${_markdownTableCell(summary!.participants.join(', '))} |',
      );
    }
    buf.writeln();

    if (summary == null) {
      buf.writeln('> 요약이 아직 생성되지 않았습니다.');
      return buf.toString();
    }

    _writeMarkdownList(buf, '핵심 논의', summary.keyDiscussions.take(5).toList());
    _writeMarkdownList(buf, '결정 사항', summary.decisions);
    _writeNotionActionItems(buf, summary);
    _writeMarkdownList(buf, '리스크 / 확인 필요', summary.openQuestions);

    return buf.toString();
  }

  /// 액션아이템만 공유할 때 쓰는 Markdown 체크리스트.
  static String buildActionItemsMarkdown(Meeting meeting, Summary? summary) {
    final items = summary == null ? <ActionItem>[] : _actionItems(summary);
    final buf = StringBuffer();
    buf.writeln('# ${_markdownText(meeting.title)} 액션 아이템');
    buf.writeln();
    if (items.isEmpty) {
      buf.writeln('- 액션 아이템이 없습니다.');
      return buf.toString();
    }
    for (final item in items) {
      final done = item.completed ? 'x' : ' ';
      final owner = _actionOwnerText(item);
      final deadline = _actionDeadlineText(item);
      buf.writeln(
        '- [$done] ${_markdownText(item.task)} _(담당: ${_markdownText(owner)} / 기한: ${_markdownText(deadline)})_',
      );
    }
    return buf.toString();
  }

  /// 요약 내용만 이메일 본문용 텍스트로 변환 (전사본 제외)
  static String buildEmailBody(Meeting meeting, Summary? summary) {
    final buf = StringBuffer();

    buf.writeln(meeting.title);
    final dt = meeting.createdAt;
    buf.writeln(
      '날짜: ${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}',
    );
    buf.writeln();

    if (summary == null) {
      buf.writeln('(요약 없음)');
      return buf.toString();
    }

    if (summary.participants.isNotEmpty) {
      buf.writeln('참석자: ${summary.participants.join(', ')}');
      buf.writeln();
    }

    if (summary.keyDiscussions.isNotEmpty) {
      buf.writeln('[주요 논의]');
      for (final item in summary.keyDiscussions) {
        buf.writeln('• $item');
      }
      buf.writeln();
    }

    if (summary.decisions.isNotEmpty) {
      buf.writeln('[결정 사항]');
      for (final item in summary.decisions) {
        buf.writeln('• $item');
      }
      buf.writeln();
    }

    try {
      final items = (jsonDecode(summary.actionItemsJson) as List)
          .map((e) => ActionItem.fromJson(e as Map<String, dynamic>))
          .toList();
      if (items.isNotEmpty) {
        buf.writeln('[액션 아이템]');
        for (final a in items) {
          buf.writeln(
            '• ${a.task}  [${_actionOwnerText(a)}] [${_actionDeadlineText(a)}]',
          );
        }
        buf.writeln();
      }
    } catch (_) {}

    if (summary.openQuestions.isNotEmpty) {
      buf.writeln('[미해결 이슈]');
      for (final item in summary.openQuestions) {
        buf.writeln('• $item');
      }
    }

    return buf.toString();
  }

  // ── PDF 생성 ─────────────────────────────────────────────────────

  /// PDF bytes 생성 (NanumGothic 한국어 폰트 사용)
  static Future<Uint8List> buildPdf(
    Meeting meeting,
    Summary? summary,
    List<Transcript> transcripts,
  ) async {
    final font = await _loadKoreanFont();
    final doc = pw.Document();

    final baseStyle = pw.TextStyle(font: font, fontSize: 11, lineSpacing: 2);
    final titleStyle = pw.TextStyle(
      font: font,
      fontSize: 16,
      fontWeight: pw.FontWeight.bold,
    );
    final sectionStyle = pw.TextStyle(
      font: font,
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.indigo800,
    );
    final smallStyle = pw.TextStyle(
      font: font,
      fontSize: 9,
      color: PdfColors.grey600,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('온디바이스 AI 회의록', style: smallStyle),
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${ctx.pageNumber} / ${ctx.pagesCount}',
            style: smallStyle,
          ),
        ),
        build: (ctx) => [
          // ── 제목 ──────────────────────────────────────────────
          pw.Text(meeting.title, style: titleStyle),
          pw.SizedBox(height: 4),
          _buildDateLine(meeting, baseStyle),
          pw.SizedBox(height: 16),

          // ── 요약 섹션 ──────────────────────────────────────────
          if (summary != null) ...[
            ..._buildSummaryWidgets(summary, sectionStyle, baseStyle),
            pw.SizedBox(height: 12),
          ],

          // ── 전사본 ─────────────────────────────────────────────
          if (transcripts.isNotEmpty) ...[
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
            pw.SizedBox(height: 6),
            pw.Text('전사본', style: sectionStyle),
            pw.SizedBox(height: 6),
            // 타임스탬프를 별도 컬럼 대신 같은 줄 접두어로 렌더링.
            //   pw.Row + SizedBox + Expanded 구조는 시각적으로는 맞지만
            //   pdftotext 등 텍스트 추출기에서 컬럼 단위로 읽혀 "타임스탬프만
            //   먼저 쭉 나오고 본문이 아래에 따로 붙는" 문제가 발생한다.
            //   RichText로 라벨만 회색/작게 주고 본문은 기본 스타일 유지.
            ...transcripts.map((seg) {
              final start = _secToStr(seg.startTimeSeconds);
              final end = _secToStr(seg.endTimeSeconds);
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.RichText(
                  text: pw.TextSpan(
                    style: baseStyle,
                    children: [
                      pw.TextSpan(text: '[$start→$end] ', style: smallStyle),
                      pw.TextSpan(text: seg.text),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );

    return doc.save();
  }

  /// 업무 보고서 스타일 PDF bytes 생성 (전사본 제외).
  static Future<Uint8List> buildBusinessReportPdf(
    Meeting meeting,
    Summary? summary,
  ) async {
    final font = await _loadKoreanFont();
    final doc = pw.Document();

    final baseStyle = pw.TextStyle(font: font, fontSize: 11, lineSpacing: 2);
    final titleStyle = pw.TextStyle(
      font: font,
      fontSize: 16,
      fontWeight: pw.FontWeight.bold,
    );
    final sectionStyle = pw.TextStyle(
      font: font,
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.blueGrey800,
    );
    final smallStyle = pw.TextStyle(
      font: font,
      fontSize: 9,
      color: PdfColors.grey600,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 42),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('회의 보고서', style: smallStyle),
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${ctx.pageNumber} / ${ctx.pagesCount}',
            style: smallStyle,
          ),
        ),
        build: (ctx) => [
          pw.Text('${meeting.title} 보고', style: titleStyle),
          pw.SizedBox(height: 4),
          _buildDateLine(meeting, baseStyle),
          if (summary?.participants.isNotEmpty == true) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              '참석자: ${summary!.participants.join(', ')}',
              style: baseStyle,
            ),
          ],
          pw.SizedBox(height: 16),
          if (summary == null)
            pw.Text('요약이 아직 생성되지 않았습니다.', style: baseStyle)
          else
            ..._buildBusinessReportWidgets(summary, sectionStyle, baseStyle),
        ],
      ),
    );

    return doc.save();
  }

  // ── DOCX 생성 ────────────────────────────────────────────────────

  /// Word에서 열 수 있는 기본 DOCX bytes 생성.
  static Uint8List buildDocx(
    Meeting meeting,
    Summary? summary,
    List<Transcript> transcripts,
  ) {
    final archive = Archive();
    archive.addFile(
      ArchiveFile.string('[Content_Types].xml', _docxContentTypes),
    );
    archive.addFile(ArchiveFile.string('_rels/.rels', _docxPackageRels));
    archive.addFile(ArchiveFile.string('docProps/app.xml', _docxAppProps));
    archive.addFile(
      ArchiveFile.string('docProps/core.xml', _docxCoreProps(meeting)),
    );
    archive.addFile(
      ArchiveFile.string('word/_rels/document.xml.rels', _docxDocumentRels),
    );
    archive.addFile(
      ArchiveFile.string(
        'word/document.xml',
        _buildDocxDocumentXml(meeting, summary, transcripts),
      ),
    );
    return ZipEncoder().encodeBytes(archive);
  }

  /// 업무 보고서 스타일 DOCX bytes 생성 (전사본 제외).
  static Uint8List buildBusinessReportDocx(Meeting meeting, Summary? summary) {
    final archive = Archive();
    archive.addFile(
      ArchiveFile.string('[Content_Types].xml', _docxContentTypes),
    );
    archive.addFile(ArchiveFile.string('_rels/.rels', _docxPackageRels));
    archive.addFile(ArchiveFile.string('docProps/app.xml', _docxAppProps));
    archive.addFile(
      ArchiveFile.string('docProps/core.xml', _docxCoreProps(meeting)),
    );
    archive.addFile(
      ArchiveFile.string('word/_rels/document.xml.rels', _docxDocumentRels),
    );
    archive.addFile(
      ArchiveFile.string(
        'word/document.xml',
        _buildDocxDocumentXml(meeting, summary, const [], reportStyle: true),
      ),
    );
    return ZipEncoder().encodeBytes(archive);
  }

  // ── 저장 (macOS Save 패널) ────────────────────────────────────────

  /// 텍스트 파일로 저장
  ///
  /// 반환값: 저장된 경로 (취소 시 null)
  static Future<String?> saveAsTxt(
    Meeting meeting,
    Summary? summary,
    List<Transcript> transcripts,
  ) async {
    final content = buildText(meeting, summary, transcripts);
    final safeName = _safeFilename(meeting.title);

    final location = await getSaveLocation(
      acceptedTypeGroups: [
        const XTypeGroup(label: '텍스트', extensions: ['txt']),
      ],
      suggestedName: '$safeName.txt',
    );
    if (location == null) return null;

    final path = location.path.endsWith('.txt')
        ? location.path
        : '${location.path}.txt';

    await File(path).writeAsString(content, encoding: utf8);
    return path;
  }

  /// Markdown 파일로 저장
  static Future<String?> saveAsMarkdown(
    Meeting meeting,
    Summary? summary,
    List<Transcript> transcripts,
  ) async {
    final content = buildMarkdown(meeting, summary, transcripts);
    final safeName = _safeFilename(meeting.title);

    final location = await getSaveLocation(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Markdown', extensions: ['md']),
      ],
      suggestedName: '$safeName.md',
    );
    if (location == null) return null;

    final path = location.path.endsWith('.md')
        ? location.path
        : '${location.path}.md';

    await File(path).writeAsString(content, encoding: utf8);
    return path;
  }

  /// PDF 파일로 저장
  static Future<String?> saveAsPdf(
    Meeting meeting,
    Summary? summary,
    List<Transcript> transcripts, {
    void Function()? onFontError,
  }) async {
    final bytes = await buildPdf(meeting, summary, transcripts);
    final safeName = _safeFilename(meeting.title);

    final location = await getSaveLocation(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
      suggestedName: '$safeName.pdf',
    );
    if (location == null) return null;

    final path = location.path.endsWith('.pdf')
        ? location.path
        : '${location.path}.pdf';

    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// 보고서 형식 PDF 파일로 저장
  static Future<String?> saveAsBusinessReportPdf(
    Meeting meeting,
    Summary? summary,
  ) async {
    final bytes = await buildBusinessReportPdf(meeting, summary);
    final safeName = _safeFilename('${meeting.title}_보고서');

    final location = await getSaveLocation(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
      suggestedName: '$safeName.pdf',
    );
    if (location == null) return null;

    final path = location.path.endsWith('.pdf')
        ? location.path
        : '${location.path}.pdf';

    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// DOCX 파일로 저장
  static Future<String?> saveAsDocx(
    Meeting meeting,
    Summary? summary,
    List<Transcript> transcripts,
  ) async {
    final bytes = buildDocx(meeting, summary, transcripts);
    final safeName = _safeFilename(meeting.title);

    final location = await getSaveLocation(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Word 문서', extensions: ['docx']),
      ],
      suggestedName: '$safeName.docx',
    );
    if (location == null) return null;

    final path = location.path.endsWith('.docx')
        ? location.path
        : '${location.path}.docx';

    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// 보고서 형식 DOCX 파일로 저장
  static Future<String?> saveAsBusinessReportDocx(
    Meeting meeting,
    Summary? summary,
  ) async {
    final bytes = buildBusinessReportDocx(meeting, summary);
    final safeName = _safeFilename('${meeting.title}_보고서');

    final location = await getSaveLocation(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Word 문서', extensions: ['docx']),
      ],
      suggestedName: '$safeName.docx',
    );
    if (location == null) return null;

    final path = location.path.endsWith('.docx')
        ? location.path
        : '${location.path}.docx';

    await File(path).writeAsBytes(bytes);
    return path;
  }

  // ── 공유 / 이메일 ─────────────────────────────────────────────────

  /// macOS Share Sheet 열기 (share_plus v10)
  ///
  /// macOS에서는 텍스트 직접 공유가 anchor rect 없이 실패할 수 있으므로
  /// 임시 .txt 파일을 생성 후 XFile로 공유합니다.
  static Future<void> shareText(
    Meeting meeting,
    Summary? summary,
    List<Transcript> transcripts,
  ) async {
    final text = buildText(meeting, summary, transcripts);
    final safeName = _safeFilename(meeting.title);

    // 임시 디렉토리에 파일 저장
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$safeName.txt');
    await tempFile.writeAsString(text, encoding: utf8);

    await Share.shareXFiles([XFile(tempFile.path)], subject: meeting.title);
  }

  /// Markdown 회의록을 클립보드에 복사
  static Future<void> copyMarkdown(
    Meeting meeting,
    Summary? summary,
    List<Transcript> transcripts,
  ) async {
    final markdown = buildMarkdown(meeting, summary, transcripts);
    await Clipboard.setData(ClipboardData(text: markdown));
  }

  /// Notion/문서용 요약 Markdown을 클립보드에 복사
  static Future<void> copyNotionMarkdown(
    Meeting meeting,
    Summary? summary,
  ) async {
    final markdown = buildNotionMarkdown(meeting, summary);
    await Clipboard.setData(ClipboardData(text: markdown));
  }

  /// 업무 보고서 스타일 Markdown을 클립보드에 복사
  static Future<void> copyBusinessReportMarkdown(
    Meeting meeting,
    Summary? summary,
  ) async {
    final markdown = buildBusinessReportMarkdown(meeting, summary);
    await Clipboard.setData(ClipboardData(text: markdown));
  }

  /// 액션아이템만 클립보드에 복사
  static Future<void> copyActionItems(Meeting meeting, Summary? summary) async {
    final markdown = buildActionItemsMarkdown(meeting, summary);
    await Clipboard.setData(ClipboardData(text: markdown));
  }

  /// mailto: 링크로 기본 메일 앱 열기 (요약만 포함)
  static Future<bool> openEmail(Meeting meeting, Summary? summary) async {
    final subject = Uri.encodeComponent(meeting.title);
    final body = Uri.encodeComponent(buildEmailBody(meeting, summary));
    final uri = Uri.parse('mailto:?subject=$subject&body=$body');
    return launchUrl(uri);
  }

  // ── 내부 헬퍼 ─────────────────────────────────────────────────────

  /// 앱 번들 한국어 폰트 로드 (NanumGothic, OFL 라이선스)
  static Future<pw.Font> _loadKoreanFont() async {
    final data = await rootBundle.load(_koreanFontAsset);
    return pw.Font.ttf(data);
  }

  static pw.Widget _buildDateLine(Meeting meeting, pw.TextStyle style) {
    final dt = meeting.createdAt;
    final dtStr =
        '${dt.year}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    final durStr = meeting.durationSeconds > 0
        ? '  ·  ${meeting.durationSeconds ~/ 60}분 ${meeting.durationSeconds % 60}초'
        : '';
    return pw.Text(
      '$dtStr$durStr',
      style: style.copyWith(color: PdfColors.grey700),
    );
  }

  static List<pw.Widget> _buildSummaryWidgets(
    Summary s,
    pw.TextStyle sectionStyle,
    pw.TextStyle baseStyle,
  ) {
    final widgets = <pw.Widget>[];

    void addSection(String title, List<String> items) {
      if (items.isEmpty) return;
      widgets.add(pw.Text(title, style: sectionStyle));
      widgets.add(pw.SizedBox(height: 4));
      for (final item in items) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2, left: 8),
            child: pw.Text('• $item', style: baseStyle),
          ),
        );
      }
      widgets.add(pw.SizedBox(height: 8));
    }

    if (s.participants.isNotEmpty) {
      widgets.add(pw.Text('참석자', style: sectionStyle));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 8, bottom: 8),
          child: pw.Text(s.participants.join(', '), style: baseStyle),
        ),
      );
    }

    addSection('주요 논의', s.keyDiscussions);
    addSection('결정 사항', s.decisions);

    try {
      final items = (jsonDecode(s.actionItemsJson) as List)
          .map((e) => ActionItem.fromJson(e as Map<String, dynamic>))
          .toList();
      if (items.isNotEmpty) {
        widgets.add(pw.Text('액션 아이템', style: sectionStyle));
        widgets.add(pw.SizedBox(height: 4));
        for (final a in items) {
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2, left: 8),
              child: pw.Text(
                '• ${a.task}  [담당: ${_actionOwnerText(a)}] [기한: ${_actionDeadlineText(a)}]',
                style: baseStyle,
              ),
            ),
          );
        }
        widgets.add(pw.SizedBox(height: 8));
      }
    } catch (_) {}

    addSection('미해결 이슈', s.openQuestions);

    return widgets;
  }

  static List<pw.Widget> _buildBusinessReportWidgets(
    Summary s,
    pw.TextStyle sectionStyle,
    pw.TextStyle baseStyle,
  ) {
    final widgets = <pw.Widget>[];

    void addSection(String title, List<String> items) {
      if (items.isEmpty) return;
      widgets.add(pw.Text(title, style: sectionStyle));
      widgets.add(pw.SizedBox(height: 4));
      for (final item in items) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3, left: 8),
            child: pw.Text('• $item', style: baseStyle),
          ),
        );
      }
      widgets.add(pw.SizedBox(height: 9));
    }

    addSection('핵심 논의', s.keyDiscussions.take(5).toList());
    addSection('결정 사항', s.decisions);

    final items = _actionItems(s);
    if (items.isNotEmpty) {
      widgets.add(pw.Text('액션 아이템', style: sectionStyle));
      widgets.add(pw.SizedBox(height: 4));
      for (final a in items) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3, left: 8),
            child: pw.Text(
              '• ${a.task}  [담당: ${_actionOwnerText(a)}] [기한: ${_actionDeadlineText(a)}]',
              style: baseStyle,
            ),
          ),
        );
      }
      widgets.add(pw.SizedBox(height: 9));
    }

    addSection('리스크 / 확인 필요', s.openQuestions);
    return widgets;
  }

  static String _buildDocxDocumentXml(
    Meeting meeting,
    Summary? summary,
    List<Transcript> transcripts, {
    bool reportStyle = false,
  }) {
    final body = StringBuffer();
    final dt = meeting.createdAt;
    final dtStr =
        '${dt.year}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';

    body.write(
      _docxParagraph(
        reportStyle ? '${meeting.title} 보고' : meeting.title,
        style: 'Title',
      ),
    );
    body.write(_docxParagraph('날짜: $dtStr'));
    if (meeting.durationSeconds > 0) {
      body.write(
        _docxParagraph(
          '소요 시간: ${meeting.durationSeconds ~/ 60}분 ${meeting.durationSeconds % 60}초',
        ),
      );
    }

    if (summary == null) {
      body.write(_docxParagraph('요약이 아직 생성되지 않았습니다.'));
    } else if (reportStyle) {
      if (summary.participants.isNotEmpty) {
        body.write(_docxParagraph('참석자: ${summary.participants.join(', ')}'));
      }
      _writeDocxList(body, '핵심 논의', summary.keyDiscussions.take(5).toList());
      _writeDocxList(body, '결정 사항', summary.decisions);
      _writeDocxActions(body, summary);
      _writeDocxList(body, '리스크 / 확인 필요', summary.openQuestions);
    } else {
      if (summary.participants.isNotEmpty) {
        body.write(_docxHeading('참석자'));
        body.write(_docxParagraph(summary.participants.join(', ')));
      }
      _writeDocxList(body, '주요 논의', summary.keyDiscussions);
      _writeDocxList(body, '결정 사항', summary.decisions);
      _writeDocxActions(body, summary);
      _writeDocxList(body, '미해결 이슈', summary.openQuestions);
    }

    if (transcripts.isNotEmpty) {
      body.write(_docxHeading('전사본'));
      for (final seg in transcripts) {
        final start = _secToStr(seg.startTimeSeconds);
        final end = _secToStr(seg.endTimeSeconds);
        final speaker = seg.speakerLabel == null ? '' : ' ${seg.speakerLabel}:';
        body.write(_docxParagraph('[$start→$end]$speaker ${seg.text}'));
      }
    }

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    ${body.toString()}
    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>
''';
  }

  static void _writeDocxList(
    StringBuffer body,
    String title,
    List<String> items,
  ) {
    if (items.isEmpty) return;
    body.write(_docxHeading(title));
    for (final item in items) {
      body.write(_docxParagraph('• $item'));
    }
  }

  static void _writeDocxActions(StringBuffer body, Summary summary) {
    final items = _actionItems(summary);
    if (items.isEmpty) return;
    body.write(_docxHeading('액션 아이템'));
    for (final item in items) {
      final done = item.completed ? '완료' : '미완료';
      body.write(
        _docxParagraph(
          '• [$done] ${item.task}  담당: ${_actionOwnerText(item)} / 기한: ${_actionDeadlineText(item)}',
        ),
      );
    }
  }

  static String _docxHeading(String text) =>
      _docxParagraph(text, style: 'Heading1');

  static String _docxParagraph(String text, {String? style}) {
    final styleXml = style == null
        ? ''
        : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>';
    return '<w:p>$styleXml<w:r><w:t xml:space="preserve">${_xmlText(text)}</w:t></w:r></w:p>';
  }

  static String _docxCoreProps(Meeting meeting) {
    final created = meeting.createdAt.toUtc().toIso8601String();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>${_xmlText(meeting.title)}</dc:title>
  <dc:creator>적자생존</dc:creator>
  <cp:lastModifiedBy>적자생존</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">$created</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">$created</dcterms:modified>
</cp:coreProperties>
''';
  }

  static const _docxContentTypes =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>
''';

  static const _docxPackageRels =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
''';

  static const _docxDocumentRels =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
''';

  static const _docxAppProps =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>적자생존</Application>
</Properties>
''';

  static String _xmlText(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _secToStr(double sec) {
    final s = sec.toInt();
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }

  static String _safeFilename(String title) {
    return title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
  }

  static void _writeMarkdownList(
    StringBuffer buf,
    String title,
    List<String> items,
  ) {
    if (items.isEmpty) return;
    buf.writeln('## $title');
    buf.writeln();
    for (final item in items) {
      buf.writeln('- ${_markdownText(item)}');
    }
    buf.writeln();
  }

  static void _writeMarkdownActionItems(StringBuffer buf, Summary summary) {
    final items = _actionItems(summary);
    if (items.isEmpty) return;

    buf.writeln('## 액션 아이템');
    buf.writeln();
    buf.writeln('| 완료 | 할 일 | 담당 | 기한 |');
    buf.writeln('| --- | --- | --- | --- |');
    for (final item in items) {
      final done = item.completed ? 'x' : ' ';
      buf.writeln(
        '| [$done] | ${_markdownTableCell(item.task)} | ${_markdownTableCell(_actionOwnerText(item))} | ${_markdownTableCell(_actionDeadlineText(item))} |',
      );
    }
    buf.writeln();
  }

  static void _writeNotionActionItems(StringBuffer buf, Summary summary) {
    final items = _actionItems(summary);
    if (items.isEmpty) return;

    buf.writeln('## 액션 아이템');
    buf.writeln();
    for (final item in items) {
      final done = item.completed ? 'x' : ' ';
      buf.writeln(
        '- [$done] ${_markdownText(item.task)} _(담당: ${_markdownText(_actionOwnerText(item))} / 기한: ${_markdownText(_actionDeadlineText(item))})_',
      );
    }
    buf.writeln();
  }

  static List<ActionItem> _actionItems(Summary summary) {
    try {
      return (jsonDecode(summary.actionItemsJson) as List)
          .map((e) => ActionItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String _actionOwnerText(ActionItem item) =>
      item.ownerNeedsConfirmation ? '담당자 미확인' : item.owner;

  static String _actionDeadlineText(ActionItem item) =>
      item.deadlineNeedsConfirmation ? '기한 미확인' : item.deadline;

  static String _markdownText(String value) =>
      value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();

  static String _markdownTableCell(String value) {
    final clean = _markdownText(
      value,
    ).replaceAll('|', r'\|').replaceAll('\n', '<br>');
    return clean.isEmpty ? '(미언급)' : clean;
  }
}
