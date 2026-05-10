import 'package:isar/isar.dart';
import '../../domain/entities/glossary_entry.dart';

class GlossaryRepositoryImpl {
  final Isar _db;
  GlossaryRepositoryImpl(this._db);

  Future<List<GlossaryEntry>> getAllEntries() =>
      _db.glossaryEntrys.where().sortByTerm().findAll();

  Future<int> saveEntry(GlossaryEntry entry) =>
      _db.writeTxn(() => _db.glossaryEntrys.put(entry));

  Future<void> deleteEntry(Id id) =>
      _db.writeTxn(() => _db.glossaryEntrys.delete(id));

  /// 전사본에 등장하는 용어만 필터링 (최대 [maxCount]개)
  Future<List<GlossaryEntry>> getRelevantEntries(
    String transcript, {
    int maxCount = 20,
  }) async {
    final all = await getAllEntries();
    final lower = transcript.toLowerCase();
    return all
        .where((e) => e.matchesTranscript(lower))
        .take(maxCount)
        .toList();
  }

  /// 관련 용어를 프롬프트용 문자열로 변환.
  /// [maxChars] 상한(기본 1200자 ≈ 700 토큰)을 넘지 않도록 앞에서부터 잘라낸다.
  /// 토큰 예산 보호 — nCtx=8192 내에서 전사본 공간 확보.
  static String toPromptSection(
    List<GlossaryEntry> entries, {
    int maxChars = 1200,
  }) {
    if (entries.isEmpty) return '';
    final buf = StringBuffer();
    int used = 0;
    int included = 0;
    for (final e in entries) {
      final line = '- ${e.term}: ${e.description}\n';
      if (used + line.length > maxChars) break;
      buf.write(line);
      used += line.length;
      included++;
    }
    if (included == 0) return '';
    final omitted = entries.length - included;
    final footer =
        omitted > 0 ? '(… 외 $omitted개 생략 — 토큰 예산 제한)\n' : '';
    return '\n[회사 전용 단어집 — 아래 용어를 반드시 이 뜻으로 해석하세요]\n${buf.toString()}$footer';
  }
}
