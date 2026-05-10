import 'package:flutter/material.dart';

/// 메모 텍스트필드용 자동 글머리(`- `) 핸들러.
///
/// 동작:
///   1. 빈 상태 → 첫 글자 입력: 입력값 앞에 `- ` 자동 prepend.
///   2. 일반 Enter (텍스트 끝에서): 새 줄에 `- ` 자동 추가, 이전 줄의 들여쓰기 유지.
///   3. 빈 `- ` 줄에서 Enter 한 번 더: 그 줄의 `- ` 제거 (글머리 모드 종료).
///   4. Tab / Shift+Tab: 현재 줄의 들여쓰기 토글 ([handleIndent]).
///
/// 끝부분이 아닌 가운데에 사용자가 \n 을 삽입하는 경우는 우연히 룰에 매칭되어도
/// 무리하게 개입하지 않도록, selection 이 텍스트 끝에 있을 때만 동작한다.
class AutoBullet {
  static const String marker = '- ';
  static const String indentUnit = '  '; // 2 spaces (마크다운 표준)

  /// 텍스트가 [oldText] → [newText] 로 변하는 시점에 호출.
  /// 컨트롤러 값을 직접 수정하며, 호출자는 반환값을 다음 호출의 [oldText] 로 사용.
  static String handle(
    String oldText,
    String newText,
    TextEditingController controller,
  ) {
    final selectionEnd = controller.selection.baseOffset;
    final atEnd = selectionEnd == newText.length;

    // 1) 빈 상태에서 사용자가 첫 글자 입력 → "- " prepend.
    //    이미 사용자가 직접 "- " 로 시작했다면 건드리지 않는다.
    if (oldText.isEmpty && newText.isNotEmpty && !newText.startsWith(marker)) {
      final fixed = '$marker$newText';
      controller.value = TextEditingValue(
        text: fixed,
        selection: TextSelection.collapsed(offset: fixed.length),
      );
      return fixed;
    }

    // 끝부분 처리만 — 가운데 삽입/삭제는 건드리지 않는다.
    if (!atEnd) return newText;

    // 2/3) Enter 추가 감지: 길이가 정확히 +1이고 마지막 문자가 \n.
    if (newText.length == oldText.length + 1 && newText.endsWith('\n')) {
      final lines = oldText.split('\n');
      final prevLine = lines.isNotEmpty ? lines.last : '';
      // 이전 줄의 leading whitespace (들여쓰기 깊이) 추출
      final indentMatch = RegExp(r'^(\s*)').firstMatch(prevLine);
      final indent = indentMatch?.group(1) ?? '';
      final stripped = prevLine.substring(indent.length);

      // 3) 빈 마커 줄에서 Enter → 글머리 모드 종료 (들여쓰기도 함께 풀림).
      if (lines.isNotEmpty && (stripped == '-' || stripped == '- ')) {
        final trimmed = [...lines]..removeLast();
        trimmed.add('');
        final fixed = trimmed.join('\n');
        controller.value = TextEditingValue(
          text: fixed,
          selection: TextSelection.collapsed(offset: fixed.length),
        );
        return fixed;
      }
      // 2) 일반 Enter — 이전 줄의 들여쓰기를 그대로 이어받아 "- " 추가.
      //    들여쓴 줄에서 Enter 시 같은 깊이의 마커가 자동 생성됨.
      final fixed = '$newText$indent$marker';
      controller.value = TextEditingValue(
        text: fixed,
        selection: TextSelection.collapsed(offset: fixed.length),
      );
      return fixed;
    }

    return newText;
  }

  /// Tab / Shift+Tab → 현재 커서가 있는 줄의 들여쓰기 토글.
  /// [decrease] 가 true면 한 단계 outdent (앞 2 spaces 제거).
  /// 줄 시작에 [indentUnit] 을 추가/제거하고, 커서 위치도 그만큼 이동.
  static void handleIndent(
    TextEditingController controller, {
    bool decrease = false,
  }) {
    final text = controller.text;
    final cursor = controller.selection.baseOffset;
    if (cursor < 0) return;

    // 현재 줄의 시작/끝 위치
    final lineStart = cursor == 0 ? 0 : text.lastIndexOf('\n', cursor - 1) + 1;
    final nl = text.indexOf('\n', cursor);
    final lineEnd = nl == -1 ? text.length : nl;
    final line = text.substring(lineStart, lineEnd);

    String newLine;
    int delta;
    if (decrease) {
      if (!line.startsWith(indentUnit)) return; // 더 줄일 게 없음
      newLine = line.substring(indentUnit.length);
      delta = -indentUnit.length;
    } else {
      newLine = '$indentUnit$line';
      delta = indentUnit.length;
    }

    final before = text.substring(0, lineStart);
    final after = text.substring(lineEnd);
    final fixed = '$before$newLine$after';
    final newCursor = (cursor + delta).clamp(lineStart, fixed.length);

    controller.value = TextEditingValue(
      text: fixed,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }
}
