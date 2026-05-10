import 'package:flutter/material.dart';
import '../../core/services/isar_service.dart';
import '../../data/repositories/glossary_repository_impl.dart';
import '../../domain/entities/glossary_entry.dart';

/// 단어집 관리 다이얼로그 열기
void showGlossaryDialog(BuildContext context) {
  showDialog(context: context, builder: (_) => const _GlossaryDialog());
}

/// 새 용어 추가 다이얼로그를 열고 DB에 저장합니다.
/// 저장되면 해당 GlossaryEntry 반환, 취소 시 null.
Future<GlossaryEntry?> showAddGlossaryDialog(
  BuildContext context, {
  String? prefilledTerm,
}) async {
  final result = await showDialog<GlossaryEntry>(
    context: context,
    builder: (_) => _EntryEditDialog(initialTerm: prefilledTerm),
  );
  if (result == null) return null;
  await GlossaryRepositoryImpl(IsarService.instance.db).saveEntry(result);
  return result;
}

class _GlossaryDialog extends StatefulWidget {
  const _GlossaryDialog();

  @override
  State<_GlossaryDialog> createState() => _GlossaryDialogState();
}

class _GlossaryDialogState extends State<_GlossaryDialog> {
  List<GlossaryEntry> _entries = [];
  bool _loading = true;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  late GlossaryRepositoryImpl _repo;

  @override
  void initState() {
    super.initState();
    _repo = GlossaryRepositoryImpl(IsarService.instance.db);
    _loadEntries();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    final entries = await _repo.getAllEntries();
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  List<GlossaryEntry> get _filtered {
    if (_searchQuery.isEmpty) return _entries;
    final q = _searchQuery.toLowerCase();
    return _entries
        .where(
          (e) =>
              e.term.toLowerCase().contains(q) ||
              e.description.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _showEditDialog({GlossaryEntry? existing}) async {
    final result = await showDialog<GlossaryEntry>(
      context: context,
      builder: (_) => _EntryEditDialog(existing: existing),
    );
    if (result == null) return;
    if (existing != null) result.id = existing.id;
    await _repo.saveEntry(result);
    await _loadEntries();
  }

  Future<void> _showBulkImportDialog() async {
    final result = await showDialog<List<GlossaryEntry>>(
      context: context,
      builder: (_) => const _BulkImportDialog(),
    );
    if (result == null || result.isEmpty) return;

    // 중복(같은 term) 체크 — 기존 용어는 skip
    final existingTerms = _entries.map((e) => e.term.toLowerCase()).toSet();
    int added = 0, skipped = 0;
    for (final entry in result) {
      if (existingTerms.contains(entry.term.toLowerCase())) {
        skipped++;
        continue;
      }
      await _repo.saveEntry(entry);
      added++;
    }
    await _loadEntries();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('추가 $added개${skipped > 0 ? ' · 중복 스킵 $skipped개' : ''}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _delete(GlossaryEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('용어 삭제'),
        content: Text('"${entry.term}" 을(를) 단어집에서 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteEntry(entry.id);
    await _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 560,
        height: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 헤더 ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '회사 단어집',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${_entries.length}개 등록됨 · 요약 생성 시 자동 참조',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.playlist_add),
                    tooltip: '일괄 가져오기 (여러 용어 한 번에 추가)',
                    onPressed: _showBulkImportDialog,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: '새 용어 추가',
                    onPressed: () => _showEditDialog(),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── 검색 ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: '용어 검색...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),

            // ── 목록 ────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.menu_book_outlined,
                            size: 40,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _entries.isEmpty
                                ? '등록된 용어가 없습니다.\n+ 버튼으로 추가하거나\n회의 화면에서 "용어 추출"을 이용하세요.'
                                : '검색 결과가 없습니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 8),
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        return InkWell(
                          onTap: () => _showEditDialog(existing: e),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                // 용어 + 설명
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            e.term,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (e.aliasList.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            ...e.aliasList
                                                .take(3)
                                                .map(
                                                  (a) => Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          right: 4,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 5,
                                                          vertical: 1,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.grey.shade200,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      a,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors
                                                            .grey
                                                            .shade600,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        e.description.isEmpty
                                            ? '(설명 없음)'
                                            : e.description,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: e.description.isEmpty
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade700,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                // 삭제 버튼
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: Colors.red.shade300,
                                  ),
                                  tooltip: '삭제',
                                  onPressed: () => _delete(e),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // ── 하단 안내 ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Text(
                '💡 회의 화면의 "용어 추출" 버튼으로 AI가 자동으로 용어를 찾아줍니다.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 용어 편집 다이얼로그 ──────────────────────────────────────────────
class _EntryEditDialog extends StatefulWidget {
  final GlossaryEntry? existing;
  final String? initialTerm;
  const _EntryEditDialog({this.existing, this.initialTerm});

  @override
  State<_EntryEditDialog> createState() => _EntryEditDialogState();
}

class _EntryEditDialogState extends State<_EntryEditDialog> {
  late TextEditingController _termCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _aliasCtrl;

  @override
  void initState() {
    super.initState();
    _termCtrl = TextEditingController(
      text: widget.existing?.term ?? widget.initialTerm ?? '',
    );
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
    _aliasCtrl = TextEditingController(text: widget.existing?.aliases ?? '');
  }

  @override
  void dispose() {
    _termCtrl.dispose();
    _descCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? '용어 수정' : '새 용어 추가'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _termCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '용어 *',
                hintText: '예: RPMS',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '설명 *',
                hintText: '예: 실시간 플레이어 매칭 서버 (게임 매칭 인프라)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _aliasCtrl,
              decoration: InputDecoration(
                labelText: '별칭 (선택, 콤마 구분)',
                hintText: '예: 알피엠에스, rpms서버',
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: '전사본에서 이 별칭도 같은 용어로 인식합니다.',
                helperStyle: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final term = _termCtrl.text.trim();
            final desc = _descCtrl.text.trim();
            if (term.isEmpty || desc.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('용어와 설명을 모두 입력해주세요.')),
              );
              return;
            }
            final entry = GlossaryEntry()
              ..term = term
              ..description = desc
              ..aliases = _aliasCtrl.text.trim();
            Navigator.pop(context, entry);
          },
          child: Text(isEdit ? '저장' : '추가'),
        ),
      ],
    );
  }
}

// ── 일괄 가져오기 다이얼로그 ───────────────────────────────────────────
/// 한 줄에 한 용어. 포맷:
///   term
///   term :: description
///   term :: description :: alias1, alias2
///
/// 구분자는 `::` 또는 `|` (탭 제외). 설명이 없으면 term만 저장 (description=term).
/// 빈 줄과 `#`로 시작하는 줄은 무시.
class _BulkImportDialog extends StatefulWidget {
  const _BulkImportDialog();

  @override
  State<_BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends State<_BulkImportDialog> {
  final _ctrl = TextEditingController();
  int _previewCount = 0;

  // 게임 프로젝트 샘플 (넷마블 팀 내부용)
  static const _gameProjectSample = '''# 한 줄에 하나씩 — "용어 :: 설명 :: 별칭(콤마 구분)" 형식
# `::` 이후는 생략 가능. 별칭은 선택.
왕의 귀환 :: 넷마블 MMORPG 프로젝트
세븐나이츠 2 :: 넷마블 모바일 RPG :: 세나2, 세나 리버스
블레이드 앤 소울 :: NCsoft 원작 기반 글로벌 서비스 :: 블소 글로벌
일곱 개의 대죄 :: 애니메이션 기반 RPG :: 7대죄
몬길 2 :: 몬스터 길들이기 2 — 후속작 :: 몽길2, 몽길은, 몽길투, 몬길은
나혼렙 :: 나 혼자만 레벨업 기반 게임 :: 나홀랩
MyBI :: 내부 BI 대시보드 :: MI, MBI, 마이비아이
엘리시움 :: 어트리뷰션 플랫폼 :: Elysium, 엘리시엄
앱스플라이어 :: 모바일 앱 어트리뷰션 SaaS :: Appsflyer, 앱스 플라이어
리세마라 :: 리셋 마라톤 — 초반 가챠 재시도 행위
어뷰저 :: 비정상 활동 유저
오리진 :: 유입 경로/캠페인 출처
s2s :: 서버 간 어트리뷰션 콜백 :: S2S, 에스투에스
미네르바 :: 내부 분석 툴 :: Minerva, 미네리바, 미네르파
콜럼버스 :: 내부 툴/프로젝트 명 :: Columbus, 콜롬부스, 콜롬부시, 컬럼버스''';

  // 데이터·인프라 팩 — BI/분석/클라우드 공통 용어 (빅쿼리 오인식 대응)
  static const _dataInfraSample = '''# 데이터·인프라 어휘팩 — 분석 회의 STT 오인식 방지
# ── 쿼리 / 데이터 웨어하우스 ────────────
빅쿼리 :: Google BigQuery — 데이터 웨어하우스 :: BigQuery, 비커리, 빅커리, 빅쿼이
SQL :: 구조화 질의 언어 :: 에스큐엘, 시퀄
쿼리 :: 데이터 조회 질의 :: 커리, 쿼이
테이블 :: DB 테이블
스키마 :: DB 구조 정의 :: 스키머
파티션 :: 테이블 분할 단위
인덱스 :: 조회 성능 인덱스
조인 :: JOIN 연산 :: join
# ── 클라우드 / 인프라 ───────────────────
GCP :: Google Cloud Platform :: 지씨피
AWS :: Amazon Web Services :: 에이더블유에스
패스워드 :: 비밀번호 :: 페소드, 패스워트, 페스워드
엔드포인트 :: API 엔드포인트 :: 엔드포이트
콘솔 :: 관리 콘솔 화면
# ── 지표 / 분석 ────────────────────────
DAU :: Daily Active Users :: 디에이유
MAU :: Monthly Active Users :: 엠에이유
ARPU :: 사용자당 평균 매출 :: 아르푸
ROAS :: 광고 투자 대비 매출 :: 로아스
CPI :: 설치당 광고 비용 :: 씨피아이
LTV :: 생애 가치 :: 엘티비
리텐션 :: 재방문율 :: 레텐션
세그먼트 :: 사용자 분류 구간
코호트 :: 동질 집단 분석 :: 커호트
# ── 회의 자주 등장 인명 패턴 (예시) ──────
# 실제 이름은 직접 추가하세요 — 별칭에 자주 오인식되는 발음 변형 기입
# 예: 김대현 :: PM :: 김대편, 김태현''';

  // 회의 어휘팩 — 일반 비즈니스·IT 회의에서 자주 오인식되는 용어
  static const _meetingVocabSample = '''# 회의 어휘팩 — STT 오인식 방지용 일반 용어
# 필요하면 설명·별칭을 추가하세요.
# ── IT / 개발 ───────────────────────────
대시보드 :: 데이터 지표 화면 :: 데시보드
프롬프트 :: LLM 입력 지시문 :: 프론프트, 프롱푹터, 프롬포드
에이전트 :: LLM 기반 자율 실행 도구 :: 애전트, 에이젼트
마켓플레이스 :: 앱/익스텐션 판매 플랫폼 :: 마켓프레이스
익스텐션 :: 확장 프로그램
MCP :: Model Context Protocol :: 엠씨피
API :: 프로그래밍 인터페이스 :: 에이피아이
슈퍼베이스 :: Supabase — 오픈소스 백엔드 :: Supabase
파이어베이스 :: Firebase
바이브 코딩 :: AI 보조 코딩 트렌드
디바이스 :: 기기 :: 디바이스
URL :: 웹 주소 :: 유알엘
TF :: Task Force 조직 :: 티에프
# ── 비즈니스 / 지표 ──────────────────────
잔존율 :: 리텐션 지표
매출 :: 총 판매 금액
구독 :: 정기 서비스 이용
브리핑 :: 짧은 보고
리포트 :: 분석 보고서
변화 감지 :: 지표 이상치 자동 알림
# ── 기타 빈출 명사 ───────────────────────
밀키트 :: 조리용 반조리 식품 :: 밀키떨
부대찌개 :: 한식 찌개 메뉴
된장찌개 :: 한식 찌개 메뉴
센트룸 :: 종합 비타민 브랜드 :: 센트료
S클래스 :: 벤츠 플래그십 세단 :: 에스클래스, 에스클라스, S-Class
GLS :: 벤츠 대형 SUV
GLE :: 벤츠 중형 SUV''';

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_updatePreview);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _updatePreview() {
    setState(() => _previewCount = _parse(_ctrl.text).length);
  }

  /// 기존 텍스트에 샘플 팩을 append (비어 있으면 교체).
  /// 여러 팩을 이어 붙여서 한 번에 import할 수 있게 한다.
  void _appendSample(String sample) {
    if (_ctrl.text.trim().isEmpty) {
      _ctrl.text = sample;
    } else {
      _ctrl.text = '${_ctrl.text.trimRight()}\n\n$sample';
    }
    _updatePreview();
  }

  static List<GlossaryEntry> _parse(String text) {
    final entries = <GlossaryEntry>[];
    final seen = <String>{};
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final parts = line.contains('::')
          ? line.split('::')
          : (line.contains('|') ? line.split('|') : [line]);
      final term = parts[0].trim();
      if (term.isEmpty) continue;

      final termKey = term.toLowerCase();
      if (seen.contains(termKey)) continue;
      seen.add(termKey);

      final desc = parts.length > 1 ? parts[1].trim() : '';
      final aliases = parts.length > 2 ? parts[2].trim() : '';

      entries.add(
        GlossaryEntry()
          ..term = term
          ..description = desc.isEmpty ? term : desc
          ..aliases = aliases,
      );
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('단어집 일괄 가져오기'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '한 줄에 한 용어씩 입력하세요. 형식: 용어 :: 설명 :: 별칭(콤마 구분)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              '· 설명·별칭은 생략 가능 · `#`으로 시작하는 줄은 무시 · 중복 용어는 스킵',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label: const Text(
                    '게임 프로젝트 샘플',
                    style: TextStyle(fontSize: 11),
                  ),
                  onPressed: () => _appendSample(_gameProjectSample),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.record_voice_over, size: 14),
                  label: const Text(
                    '회의 어휘팩 (일반)',
                    style: TextStyle(fontSize: 11),
                  ),
                  onPressed: () => _appendSample(_meetingVocabSample),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.analytics_outlined, size: 14),
                  label: const Text(
                    '데이터·인프라 팩',
                    style: TextStyle(fontSize: 11),
                  ),
                  onPressed: () => _appendSample(_dataInfraSample),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Text(
                  '$_previewCount개 감지',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText:
                      '예:\n왕의 귀환 :: 넷마블 MMORPG 프로젝트\n'
                      '세븐나이츠 2 :: 모바일 RPG :: 세나2, 세나 리버스\n'
                      '앱스플라이어 :: 모바일 어트리뷰션 :: Appsflyer',
                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _previewCount == 0
              ? null
              : () => Navigator.pop(context, _parse(_ctrl.text)),
          child: Text('$_previewCount개 추가'),
        ),
      ],
    );
  }
}
