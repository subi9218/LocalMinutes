import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant2/core/utils/auto_bullet.dart';

void main() {
  late TextEditingController ctrl;

  setUp(() {
    ctrl = TextEditingController();
  });

  tearDown(() => ctrl.dispose());

  /// 헬퍼: 텍스트와 selection 을 동시에 세팅하고 handle 호출
  String simulate(String oldText, String newText) {
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    return AutoBullet.handle(oldText, newText, ctrl);
  }

  test('empty → first char prepends "- "', () {
    final next = simulate('', '회');
    expect(next, '- 회');
    expect(ctrl.text, '- 회');
    expect(ctrl.selection.baseOffset, 3);
  });

  test('user already starts with "- " → no double prepend', () {
    final next = simulate('', '- ');
    expect(next, '- ');
    expect(ctrl.text, '- ');
  });

  test('enter at end appends "\\n- "', () {
    final next = simulate('- 첫 줄', '- 첫 줄\n');
    expect(next, '- 첫 줄\n- ');
    expect(ctrl.text, '- 첫 줄\n- ');
  });

  test('enter on empty bullet line removes the bullet (exit mode)', () {
    // "- 첫\n- " 상태에서 Enter → 끝 빈 - 줄을 빈 줄로 변환
    final next = simulate('- 첫\n- ', '- 첫\n- \n');
    expect(next, '- 첫\n');
    expect(ctrl.text, '- 첫\n');
  });

  test('mid-text edit (cursor not at end) does not interfere', () {
    // 사용자가 텍스트 가운데에 글자 추가: 끝이 아니므로 그대로 둠
    ctrl.value = const TextEditingValue(
      text: '- 첫A 줄',
      selection: TextSelection.collapsed(offset: 4), // 끝 아님
    );
    final next = AutoBullet.handle('- 첫 줄', '- 첫A 줄', ctrl);
    expect(next, '- 첫A 줄');
    expect(ctrl.text, '- 첫A 줄');
  });

  test('non-trivial typing keeps text unchanged', () {
    final next = simulate('- 안녕', '- 안녕하');
    expect(next, '- 안녕하');
  });

  // ── Tab / Shift+Tab 들여쓰기 ──────────────────────────────────────

  test('Tab indents current line by 2 spaces', () {
    ctrl.value = const TextEditingValue(
      text: '- 첫 줄',
      selection: TextSelection.collapsed(offset: 5),
    );
    AutoBullet.handleIndent(ctrl);
    expect(ctrl.text, '  - 첫 줄');
    expect(ctrl.selection.baseOffset, 7);
  });

  test('Shift+Tab outdents current line', () {
    ctrl.value = const TextEditingValue(
      text: '  - 하위',
      selection: TextSelection.collapsed(offset: 6),
    );
    AutoBullet.handleIndent(ctrl, decrease: true);
    expect(ctrl.text, '- 하위');
    expect(ctrl.selection.baseOffset, 4);
  });

  test('Shift+Tab on already-flush line is no-op', () {
    ctrl.value = const TextEditingValue(
      text: '- 첫 줄',
      selection: TextSelection.collapsed(offset: 5),
    );
    AutoBullet.handleIndent(ctrl, decrease: true);
    expect(ctrl.text, '- 첫 줄');
  });

  test('Tab only affects current line in multi-line text', () {
    ctrl.value = const TextEditingValue(
      text: '- 첫 줄\n- 둘째 줄',
      selection: TextSelection.collapsed(offset: 11), // 둘째 줄 안
    );
    AutoBullet.handleIndent(ctrl);
    expect(ctrl.text, '- 첫 줄\n  - 둘째 줄');
  });

  test('Enter on indented line preserves indentation', () {
    // "  - 하위" 끝에서 Enter → 다음 줄도 "  - " 자동
    final next = simulate('  - 하위', '  - 하위\n');
    expect(next, '  - 하위\n  - ');
  });

  test('Enter on empty indented bullet exits bullet mode', () {
    // "  - " 빈 들여쓰인 마커 → Enter 시 들여쓰기와 함께 종료(빈 줄)
    final next = simulate('- 위\n  - ', '- 위\n  - \n');
    expect(next, '- 위\n');
  });
}
