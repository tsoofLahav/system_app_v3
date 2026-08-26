import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ux/widgets/main_pane_loader.dart';
import 'package:system_app_front_end/shared/utils/hardware_keyboard_guard.dart';

void main() {
  test('detects the already-pressed KeyDown assertion', () {
    expect(
      isHardwareKeyboardDesync(
        AssertionError(
          'A KeyDownEvent is dispatched, but the state shows that the physical '
          'key is already pressed.',
        ),
      ),
      isTrue,
    );
    expect(isHardwareKeyboardDesync(StateError('other')), isFalse);
  });

  testWidgets('releasing tracked keys lets a second KeyDown through', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    expect(
      HardwareKeyboard.instance.physicalKeysPressed,
      contains(PhysicalKeyboardKey.keyD),
    );

    releaseTrackedHardwareKeys();
    expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    expect(tester.takeException(), isNull);
    expect(
      HardwareKeyboard.instance.physicalKeysPressed,
      contains(PhysicalKeyboardKey.keyD),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
  });

  testWidgets('the loading pane drops tracked keys before the editor opens', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MainPaneLoader()));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    expect(HardwareKeyboard.instance.physicalKeysPressed, isNotEmpty);

    await tester.pump();
    expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
  });
}
