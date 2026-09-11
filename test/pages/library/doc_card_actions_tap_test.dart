import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/pages/library/widgets/doc_card_actions.dart';

void main() {
  DocTapIntent resolve({
    bool isSelectionMode = false,
    bool isDesktop = true,
    bool isApple = false,
    bool shiftPressed = false,
    bool controlPressed = false,
    bool metaPressed = false,
  }) {
    return DocCardActions.resolveTap(
      isSelectionMode: isSelectionMode,
      isDesktop: isDesktop,
      isApple: isApple,
      shiftPressed: shiftPressed,
      controlPressed: controlPressed,
      metaPressed: metaPressed,
      canRange: true,
      canModifierToggle: true,
    );
  }

  test('普通单击打开文献', () {
    expect(resolve(), DocTapIntent.open);
  });

  test('移动端忽略修饰键，始终打开', () {
    expect(
      resolve(isDesktop: false, shiftPressed: true, controlPressed: true),
      DocTapIntent.open,
    );
  });

  test('Win/Linux 的 Meta（Win/Super）不进入多选', () {
    expect(resolve(metaPressed: true), DocTapIntent.open);
  });

  test('未进多选时 Shift 不进入多选', () {
    expect(resolve(shiftPressed: true), DocTapIntent.open);
  });

  test('已多选时 Shift 划选', () {
    expect(
      resolve(isSelectionMode: true, shiftPressed: true),
      DocTapIntent.range,
    );
  });

  test('Ctrl 点选进入/切换多选', () {
    expect(resolve(controlPressed: true), DocTapIntent.modifierToggle);
  });

  test('macOS 的 Cmd 点选进入/切换多选', () {
    expect(
      resolve(isApple: true, metaPressed: true),
      DocTapIntent.modifierToggle,
    );
  });

  test('已多选且无修饰键时单击切换勾选', () {
    expect(resolve(isSelectionMode: true), DocTapIntent.toggle);
  });
}
