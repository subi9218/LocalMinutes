import 'dart:convert';
import '../../domain/entities/meeting.dart' show Bookmark;
import '../../domain/entities/summary.dart';
import '../services/crash_log_service.dart';

/// Gemma 4 출력 JSON → Summary 파싱 공통 유틸
/// RecordingView / MeetingDetailView 양쪽에서 사용
class SummaryParser {
  // ── 불량 meetingTitle 필터 ────────────────────────────────────
  static const _badTitles = {
    '분석 불가',
    '분석불가',
    '분석 불가능',
    '분석불가능',
    'N/A',
    'n/a',
    'NA',
    'na',
    '없음',
    'null',
    'NULL',
    'undefined',
    '',
  };

  static String sanitizeTitle(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (_badTitles.contains(s)) return '회의 요약';
    return s.isEmpty ? '회의 요약' : s;
  }

  // ── Gemma 출력 JSON 정규화 ────────────────────────────────────
  static String sanitizeJson(String s) {
    // Gemma 채팅 템플릿 잔재 제거 (</start_of_turn>, <end_of_turn> 등)
    s = s.replaceAll(RegExp(r'<[^>]+>'), '').trim();

    // 마크다운 코드블록 제거
    final cb = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
    if (cb != null) s = cb.group(1)!.trim();

    // { } 범위 추출 — 중괄호 균형이 맞는 첫 번째 완결 오브젝트만 추출
    // (Gemma가 JSON 뒤에 여분의 } 나 </start_of_turn> 등을 붙이는 케이스 대응)
    final start = s.indexOf('{');
    if (start != -1) {
      int depth = 0;
      bool inStr2 = false;
      int closingIdx = -1;
      for (int i = start; i < s.length; i++) {
        final c = s[i];
        if (c == '"' && (i == 0 || s[i - 1] != '\\')) inStr2 = !inStr2;
        if (inStr2) continue;
        if (c == '{') depth++;
        if (c == '}') {
          depth--;
          if (depth == 0) {
            closingIdx = i;
            break;
          }
        }
      }
      if (closingIdx != -1) {
        s = s.substring(start, closingIdx + 1);
      } else {
        // 닫히지 않은 경우 — 기존 방식(lastIndexOf) 폴백
        final end = s.lastIndexOf('}');
        if (end > start) s = s.substring(start, end + 1);
      }
    }

    // 잘못된 키 이름 교정
    s = s.replaceAll(RegExp(r'"?bibitem"?\s*:'), '"actionItems":');
    s = s.replaceAll(RegExp(r'"?action_items"?\s*:'), '"actionItems":');
    s = s.replaceAll(RegExp(r'"?key_discussions"?\s*:'), '"keyDiscussions":');
    s = s.replaceAll(RegExp(r'"?open_questions"?\s*:'), '"openQuestions":');
    s = s.replaceAll(RegExp(r'"?meeting_title"?\s*:'), '"meetingTitle":');

    // 따옴표 없는 키 교정
    s = s.replaceAllMapped(
      RegExp(r'([{,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)(\s*:)'),
      (m) => '${m[1]}"${m[2]}"${m[3]}',
    );

    // trailing comma 제거
    s = s.replaceAll(RegExp(r',\s*}'), '}');
    s = s.replaceAll(RegExp(r',\s*]'), ']');

    // 잘린 JSON 복구
    int braces = 0, brackets = 0;
    bool inStr = false;
    for (int i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"' && (i == 0 || s[i - 1] != '\\')) inStr = !inStr;
      if (inStr) continue;
      if (c == '{') braces++;
      if (c == '}') braces--;
      if (c == '[') brackets++;
      if (c == ']') brackets--;
    }
    s += ']' * brackets.clamp(0, 10);
    s += '}' * braces.clamp(0, 10);

    return s;
  }

  // ── JSON → Summary 파싱 ───────────────────────────────────────
  static Summary parse(
    String raw,
    int meetingId,
    DateTime date, {
    List<String> forcedParticipants = const [],
  }) {
    Map<String, dynamic>? m;

    try {
      m = jsonDecode(sanitizeJson(raw)) as Map<String, dynamic>;
    } catch (_) {}

    if (m == null) {
      try {
        m = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (m != null) {
      List<String> asList(dynamic v) =>
          v is List ? v.map((e) => e.toString()).toList() : [];

      final rawItems =
          m['actionItems'] ??
          m['bibitem'] ??
          m['action_items'] ??
          m['actions'] ??
          [];
      List<ActionItem> items = [];
      List<String> rawActionItemsEvidence = [];
      try {
        // actionItems가 task/owner/deadline 외에 evidence를 갖는 경우(LLM이 nested로 출력) 별도 추출
        items = (rawItems as List).map((e) {
          final map = e as Map<String, dynamic>;
          rawActionItemsEvidence.add((map['evidence'] ?? '').toString().trim());
          return ActionItem.fromJson(map);
        }).toList();
      } catch (_) {}
      // dedupe 전 rawActionItemsEvidence를 함께 정렬해야 정확하지만,
      // 단순화 위해 dedupe 후 길이가 줄면 evidence 배열을 처음부터 자른다.
      final beforeDedupe = items.length;
      items = _dedupeActionItems(items);
      if (items.length < beforeDedupe &&
          rawActionItemsEvidence.length == beforeDedupe) {
        // dedupe로 길이 줄었으면 앞에서부터 잘라 1:1 매칭 유지
        rawActionItemsEvidence = rawActionItemsEvidence
            .take(items.length)
            .toList();
      }

      final safeParticipants = _dedupeStrings(
        forcedParticipants
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList(),
      );

      // ── Evidence 배열 수집 (병렬 배열 + nested evidence 병합) ──
      final keyDiscussionsList = _dedupeStrings(
        asList(m['keyDiscussions'] ?? m['key_discussions'] ?? m['discussions']),
      );
      final decisionsList = _dedupeStrings(asList(m['decisions']));
      final openQuestionsList = _dedupeStrings(
        asList(m['openQuestions'] ?? m['open_questions'] ?? m['questions']),
      );

      List<String> evList(dynamic v, int targetLen) {
        final l = v is List ? v.map((e) => e.toString()).toList() : <String>[];
        // 길이 맞추기: 모자라면 빈 문자열 채움, 넘치면 자름
        if (l.length < targetLen) {
          return [...l, ...List.filled(targetLen - l.length, '')];
        }
        if (l.length > targetLen) return l.take(targetLen).toList();
        return l;
      }

      final actionItemsEvidence = evList(
        m['actionItemsEvidence'] ?? m['action_items_evidence'],
        items.length,
      );
      // nested evidence가 있으면 빈 슬롯에만 적용
      for (int i = 0; i < actionItemsEvidence.length; i++) {
        if (actionItemsEvidence[i].isEmpty &&
            i < rawActionItemsEvidence.length) {
          actionItemsEvidence[i] = rawActionItemsEvidence[i];
        }
      }

      final evidenceMap = <String, dynamic>{
        'keyDiscussions': evList(
          m['keyDiscussionsEvidence'] ?? m['key_discussions_evidence'],
          keyDiscussionsList.length,
        ),
        'decisions': evList(
          m['decisionsEvidence'] ?? m['decisions_evidence'],
          decisionsList.length,
        ),
        'openQuestions': evList(
          m['openQuestionsEvidence'] ?? m['open_questions_evidence'],
          openQuestionsList.length,
        ),
        'actionItems': actionItemsEvidence,
      };

      return Summary()
        ..meetingId = meetingId
        ..meetingTitle = sanitizeTitle(
          m['meetingTitle'] ?? m['meeting_title'] ?? m['title'],
        )
        ..meetingDate = date
        ..participants = safeParticipants
        ..keyDiscussions = keyDiscussionsList
        ..decisions = decisionsList
        ..actionItemsJson = jsonEncode(items.map((a) => a.toJson()).toList())
        ..openQuestions = openQuestionsList
        ..evidenceJson = jsonEncode(evidenceMap)
        ..createdAt = DateTime.now();
    }

    // 파싱 완전 실패. 회의 내용이 crash.log에 남지 않도록 길이만 기록한다.
    try {
      CrashLogService.instance.recordCaught(
        'SummaryParser fallback (JSON decode failed)\n'
        'rawLength=${raw.length}',
        StackTrace.current,
        context: 'summary_parser',
      );
    } catch (_) {
      // 로깅 실패는 절대 사용자 경험을 방해하지 않게 무시
    }

    return Summary()
      ..meetingId = meetingId
      ..meetingTitle = '회의 요약'
      ..meetingDate = date
      ..participants = _dedupeStrings(
        forcedParticipants
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList(),
      )
      ..keyDiscussions = ['AI가 회의 내용을 분석했으나 구조화에 실패했습니다. 녹취록에서 전체 내용을 확인하세요.']
      ..decisions = []
      ..actionItemsJson = '[]'
      ..openQuestions = []
      ..createdAt = DateTime.now();
  }

  // ── 전사본 트런케이션 ─────────────────────────────────────────
  // nCtx=8192 기준 토큰 예산:
  //   출력 예약 (maxTokens):   2500 토큰
  //   지시문 + JSON 스키마:     ~600 토큰
  //   용어집 섹션 (최대):       ~700 토큰 (20개 × ~35토큰)
  //   참석자 + 메모 + 기타:     ~500 토큰
  //   ────────────────────────────────
  //   전사본 여유:            ~3800 토큰 ≈ 6800자 (한국어 ~1.8 chars/tok)
  // 안전 마진 두어 5500자로 제한.
  static const int _maxTranscriptChars = 5500;

  static String _truncateTranscript(String transcript) {
    if (transcript.length <= _maxTranscriptChars) return transcript;

    // 앞 30% + 뒤 70% 유지 (회의 결론·결정사항은 보통 후반부에 집중)
    final headLen = (_maxTranscriptChars * 0.3).toInt();
    final tailLen = _maxTranscriptChars - headLen;
    final head = transcript.substring(0, headLen);
    final tail = transcript.substring(transcript.length - tailLen);
    return '$head\n\n[... 중간 내용 생략 (전체 ${transcript.length}자 중 $_maxTranscriptChars자 요약) ...]\n\n$tail';
  }

  // ── 프롬프트 빌더 ─────────────────────────────────────────────
  /// [instruction] 이 비어있으면 범용 지침을 사용. SummaryTemplates.resolveInstruction() 결과를 넘겨 템플릿별 분석 지침을 주입할 수 있다.
  /// [agenda] 가 비어있지 않으면 어젠다 섹션을 추가해 LLM이 항목별로 정리하도록 유도.
  /// [bookmarks] 가 있으면 사용자가 마킹한 핵심 시점을 LLM에 우선 분석 지시.
  static String buildPrompt(
    String transcript,
    String dateStr, {
    String notes = '',
    List<String> participants = const [],
    String glossary = '',
    String instruction = '',
    String agenda = '',
    List<Bookmark> bookmarks = const [],
  }) {
    final truncated = _truncateTranscript(transcript);
    final wasTruncated = truncated.length < transcript.length;

    final participantsSection = participants.isNotEmpty
        ? '\n사용자가 직접 입력한 참석자: ${participants.join(', ')}\n'
        : '\n사용자가 직접 입력한 참석자: 없음\n';
    final noteSection = notes.trim().isNotEmpty
        ? '\n참석자 메모 (아래 내용을 요약에 반드시 반영하세요):\n${notes.trim()}\n'
        : '';
    // 어젠다 섹션 — 입력된 어젠다가 있으면 항목별 요약 정리를 유도
    final agendaTrimmed = agenda.trim();
    final agendaSection = agendaTrimmed.isEmpty
        ? ''
        : '''

[회의 어젠다 — 사용자가 회의 시작 전 미리 정한 항목]
$agendaTrimmed

[어젠다 활용 지침 — 필수]
- 위 어젠다는 회의에서 다루기로 약속한 항목입니다. 가능한 한 어젠다 순서를 유지해 정리하세요.
- keyDiscussions의 각 항목은 가능하면 "어젠다명 — 핵심 논점" 형태로 작성하세요. 예: "신규 피처 일정 — QA 2주 필요 vs 마케팅 압박".
- 어젠다에 있지만 전사본에서 충분히 다뤄지지 않은 항목은 openQuestions에 "어젠다명 — 충분히 논의되지 않음 (확인 필요)" 형태로 남기세요.
- 전사본에 등장했지만 어젠다에 없는 추가 주제도 누락하지 말고 keyDiscussions 끝부분에 포함하세요.
- 어젠다 항목을 그대로 베끼지 말고, 회의에서 실제로 나온 논점·결정·근거를 함께 묶어 정리하세요.
''';
    // 북마크 섹션 — 사용자가 녹음 중 ★ 마킹한 핵심 시점
    final bookmarksSection = bookmarks.isEmpty
        ? ''
        : () {
            final lines = bookmarks
                .map(
                  (b) => b.label.isEmpty
                      ? '- ${b.timeStr}'
                      : '- ${b.timeStr} (${b.label})',
                )
                .join('\n');
            return '''

[사용자 핵심 마킹 — 우선 분석 필수]
사용자가 녹음 중 직접 표시한 중요 시점입니다:
$lines

이 시점 앞뒤 30초 구간의 발화는 회의 핵심으로 간주하고:
- 결정사항(decisions) 또는 액션아이템(actionItems)에 우선 반영하세요.
- 해당 시점에 미해결 질문이 있으면 openQuestions에 우선 포함하세요.
- 사용자 마킹 시점이 누락되지 않도록 keyDiscussions 작성 시 점검하세요.
''';
          }();

    final truncNotice = wasTruncated
        ? '\n[참고: 전사본이 길어 앞부분과 뒷부분 위주로 요약합니다]\n'
        : '';
    final intro = instruction.trim().isNotEmpty
        ? instruction.trim()
        : '아래 회의 전사본을 분석해서 JSON만 출력하세요. 설명이나 다른 텍스트는 절대 쓰지 마세요.';
    return '''$intro$glossary

[화자 정보 활용]
- 전사본에 "화자 A:", "화자 B:" 같은 접두사가 있으면 화자별 입장·발언 맥락을 파악에 활용하세요.
- actionItems의 owner 필드는 사용자가 직접 입력한 참석자명 또는 "화자 A" 같은 화자 라벨만 사용하세요.
- 사용자가 직접 입력하지 않은 사람 이름을 participants 배열이나 owner 필드에 새로 넣지 마세요. 불명확하면 "(미언급)"으로 쓰세요.

[참석자 이름 제한 — 필수]
- participants 배열은 반드시 "사용자가 직접 입력한 참석자" 목록과 같아야 합니다.
- 사용자가 직접 입력한 참석자가 없으면 participants는 반드시 빈 배열 [] 로 출력하세요.
- 전사본 본문에 사람 이름처럼 보이는 단어가 있어도 participants에 자동 추가하지 마세요.
- 참석자 이름을 추측하거나 화자 라벨을 실제 사람 이름으로 바꾸지 마세요.

[디테일 보존 원칙 — 모든 템플릿 공통]
- 수치(금액·퍼센트·일자·버전·용량·건수)는 전사본에 등장한 그대로 보존하세요. 반올림·생략 금지.
- 고유명사(프로젝트명·팀명·제품명·인명·회사명·기술용어·약어)는 원문 표기 그대로 쓰세요.
- 인용된 핵심 발언·숫자 근거는 추상화하지 말고 구체적으로 남기세요.
- "~에 대해 논의" 같은 모호한 서술 대신, 실제 논의된 내용/숫자/대안을 담으세요.
- 항목당 한 문장이 짧아지더라도 구체성을 우선합니다.

[중복 제거 원칙 — 배열 작성 시 필수]
- keyDiscussions/decisions/actionItems/openQuestions 각 배열 내 항목이 의미상 같으면 하나만 남기세요.
- 같은 액션이 다른 구간에서 다시 언급됐다면 하나로 합치세요 (task 문장 병합, owner/deadline은 가장 구체적인 값 채택).
- "같은 얘기 반복"이거나 "앞서 결정된 내용의 재확인"이면 배열에 중복해 넣지 마세요.

[STT 노이즈 필터링 — 요약 오염 방지]
- 전사본에 "네", "네네", "어", "음", "아", "그", "자", "오픈클로우가", "감사합니다", "수고하셨습니다" 같은 짧은 단어가 연속 반복되면 환각(오인식)이므로 요약에 포함하지 마세요.
- 맥락이 불분명한 한 줄짜리 짧은 발화는 무시하세요. 문맥상 의미가 이어지는 대화만 분석에 활용하세요.
- 전사본에 없는 내용(담당자·일정·숫자)은 절대 만들어내지 마세요. 불분명하면 "(미언급)"으로 남기세요.

[한국어 비즈니스 회의 포맷 — 권장 서술 스타일]
- keyDiscussions: "주제 — 핵심 논점" 형태. 예: "신규 피처 일정 — QA 2주 필요 vs 마케팅 일정 압박".
- decisions: 능동형 단문. 예: "다음 주 금요일까지 RC 배포 확정".
- actionItems.task: 동사로 시작하는 명확한 업무. 예: "API 문서 초안 작성 후 공유".
- actionItems.ownerConfirmed: owner가 전사본이나 사용자가 입력한 참석자/화자 라벨로 확인되면 true, 불명확해서 "(미언급)"이면 false.
- actionItems.deadlineConfirmed: deadline이 전사본에 명확히 등장하면 true, 불명확해서 "(미언급)"이면 false.
- openQuestions: 의문문 또는 "~ 확인 필요". 예: "QA 리소스 확보 가능 여부 확인 필요".

[근거 타임스탬프 — 신뢰도 표시 v2]
- 전사본 각 라인 앞에는 [MM:SS→MM:SS] 또는 [HH:MM:SS→HH:MM:SS] 형식의 시간이 붙어 있습니다.
- keyDiscussions / decisions / openQuestions / actionItems 각 항목마다 그 내용이 실제로 등장한 전사본 구간의 시작 시간을 별도 배열로 출력하세요.
- 형식: "MM:SS" 또는 더 정확히 "MM:SS-MM:SS" (구간). HH:MM:SS도 허용.
- 각 evidence 배열의 길이는 대응되는 main 배열 길이와 반드시 같아야 합니다.
- 전사본에서 분명한 근거 구간을 찾기 어려운 항목은 그 인덱스에 빈 문자열 ""을 넣으세요. 추측 금지.
- 근거가 흩어져 있으면 가장 핵심 발화 시간 1개만 선택하세요.

반드시 아래 키 이름을 그대로 사용하세요:
- meetingTitle (문자열) ← 반드시 실제 회의 주제를 담은 제목. "분석 불가", "N/A", "없음" 같은 값은 절대 사용하지 마세요. 내용이 불명확하면 "회의 내용 정리" 라고 하세요.
- participants (배열) ← 사용자가 직접 입력한 참석자만. 입력값이 없으면 반드시 []
- keyDiscussions (배열)
- keyDiscussionsEvidence (배열, keyDiscussions와 동일 길이의 시간 문자열)
- decisions (배열)
- decisionsEvidence (배열, decisions와 동일 길이의 시간 문자열)
- actionItems (배열, 각 항목은 task/owner/deadline/ownerConfirmed/deadlineConfirmed 포함)
- actionItemsEvidence (배열, actionItems와 동일 길이의 시간 문자열)
- openQuestions (배열)
- openQuestionsEvidence (배열, openQuestions와 동일 길이의 시간 문자열)

출력 예시:
{"meetingTitle":"팀 주간 회의","participants":[],"keyDiscussions":["신규 기능 개발 일정 논의","버그 수정 우선순위 결정"],"keyDiscussionsEvidence":["02:55","04:20-04:35"],"decisions":["다음 주 금요일까지 배포"],"decisionsEvidence":["12:18"],"actionItems":[{"task":"API 문서 작성","owner":"화자 A","deadline":"2026-04-25","ownerConfirmed":true,"deadlineConfirmed":true},{"task":"QA 체크리스트 정리","owner":"(미언급)","deadline":"(미언급)","ownerConfirmed":false,"deadlineConfirmed":false}],"actionItemsEvidence":["07:42-08:10",""],"openQuestions":["QA 일정 확정 필요"],"openQuestionsEvidence":[""]}
$participantsSection$noteSection$agendaSection$bookmarksSection$truncNotice
날짜: $dateStr
전사본:
$truncated

JSON:''';
  }

  // ── 중복 제거 유틸 ────────────────────────────────────────────
  //
  // map-reduce 요약은 인접 chunk에서 같은 액션을 각각 뽑아낼 수 있다.
  // Gemma에 중복 제거를 지시해도 100% 믿을 수 없어 파싱 단계에서 한 번 더 걸러낸다.
  //
  // 유사도 판정:
  //   - 문자열: 공백/구두점 제거 + 소문자화 후 완전일치 OR 짧은 쪽이 긴 쪽에 포함
  //   - ActionItem: task 문자열끼리 위 규칙으로 비교 (owner/deadline은 참고만)

  static String _normKey(String s) {
    return s.toLowerCase().replaceAll(
      RegExp(r'[\s·.,·、。,!?~\-–—\[\]\(\)\{\}:;"]+'),
      '',
    );
  }

  static bool _roughlySame(String a, String b) {
    final na = _normKey(a);
    final nb = _normKey(b);
    if (na.isEmpty || nb.isEmpty) return na == nb;
    if (na == nb) return true;
    // 한쪽이 다른 쪽을 감싸는 경우도 중복으로 판정 (8자 이상일 때)
    if (na.length >= 8 && nb.length >= 8) {
      if (na.contains(nb) || nb.contains(na)) return true;
    }
    return false;
  }

  static List<String> _dedupeStrings(List<String> items) {
    final out = <String>[];
    for (final s in items) {
      final t = s.trim();
      if (t.isEmpty) continue;
      if (out.any((kept) => _roughlySame(kept, t))) continue;
      out.add(t);
    }
    return out;
  }

  static List<ActionItem> _dedupeActionItems(List<ActionItem> items) {
    final out = <ActionItem>[];
    for (final cur in items) {
      if (cur.task.trim().isEmpty) continue;
      final dupIdx = out.indexWhere((k) => _roughlySame(k.task, cur.task));
      if (dupIdx == -1) {
        out.add(cur);
        continue;
      }
      // 중복 발견 — owner/deadline 중 더 구체적인 값으로 승격
      final kept = out[dupIdx];
      String pickMoreSpecific(String a, String b) {
        bool isVague(String v) {
          final n = v.trim();
          return n.isEmpty ||
              n == '(미언급)' ||
              n == '미정' ||
              n == '미상' ||
              n == 'N/A' ||
              n == 'TBD';
        }

        if (isVague(a) && !isVague(b)) return b;
        if (!isVague(a) && isVague(b)) return a;
        return a; // 둘 다 구체적이거나 둘 다 모호
      }

      out[dupIdx] = ActionItem(
        task: kept.task.length >= cur.task.length ? kept.task : cur.task,
        owner: pickMoreSpecific(kept.owner, cur.owner),
        deadline: pickMoreSpecific(kept.deadline, cur.deadline),
      );
    }
    return out;
  }
}
