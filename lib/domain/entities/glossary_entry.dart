import 'package:isar/isar.dart';

part 'glossary_entry.g.dart';

@collection
class GlossaryEntry {
  Id id = Isar.autoIncrement;

  /// 용어 (약어, 고유명사 등)
  @Index(type: IndexType.value, caseSensitive: false)
  late String term;

  /// 설명
  late String description;

  /// 콤마 구분 별칭 (예: "알피엠에스,rpms서버")
  String aliases = '';

  @Index()
  DateTime createdAt = DateTime.now();

  /// 별칭 목록
  List<String> get aliasList => aliases.isEmpty
      ? []
      : aliases
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

  /// 전사본에 이 용어(또는 별칭)가 포함되어 있는지 확인
  bool matchesTranscript(String transcriptLower) {
    if (transcriptLower.contains(term.toLowerCase())) return true;
    return aliasList.any((a) => transcriptLower.contains(a.toLowerCase()));
  }
}
