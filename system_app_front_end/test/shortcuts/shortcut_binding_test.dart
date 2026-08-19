import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ux/shortcuts/shortcut_binding.dart';

void main() {
  test('toJson and fromJson round-trip', () {
    const binding = ShortcutBinding(
      keyId: 0x00000000000400000042,
      meta: true,
      shift: true,
    );

    final restored = ShortcutBinding.fromJson(binding.toJson());
    expect(restored, binding);
  });

  test('toLogicalKeySet includes modifiers and key', () {
    final binding = ShortcutBinding(
      keyId: LogicalKeyboardKey.keyH.keyId,
      meta: true,
      shift: true,
    );

    final keySet = binding.toLogicalKeySet();
    expect(keySet.keys, contains(LogicalKeyboardKey.meta));
    expect(keySet.keys, contains(LogicalKeyboardKey.shift));
    expect(keySet.keys, contains(LogicalKeyboardKey.keyH));
  });

  test('displayLabel formats bracket key', () {
    final binding = ShortcutBinding(
      keyId: LogicalKeyboardKey.bracketRight.keyId,
      meta: true,
    );

    expect(binding.displayLabel(), contains(']'));
  });

  test('toActivator follows the binding, including Shift+- aliases', () {
    final binding = ShortcutBinding(
      keyId: LogicalKeyboardKey.keyH.keyId,
      meta: true,
      shift: true,
    );

    final activator = binding.toActivator();
    expect(activator, isA<BindingShortcutActivator>());
    expect(
      (activator as BindingShortcutActivator).binding,
      binding,
    );

    final sizeDown = ShortcutBinding(
      keyId: LogicalKeyboardKey.minus.keyId,
      meta: true,
      shift: true,
    );
    expect(
      sizeDown.toActivator().triggers,
      contains(LogicalKeyboardKey.underscore),
    );
  });

  test('isValid requires modifier or function key', () {
    expect(
      ShortcutBinding(keyId: LogicalKeyboardKey.keyA.keyId).isValid,
      isFalse,
    );
    expect(
      ShortcutBinding(
        keyId: LogicalKeyboardKey.keyA.keyId,
        meta: true,
      ).isValid,
      isTrue,
    );
    expect(
      ShortcutBinding(keyId: LogicalKeyboardKey.f1.keyId).isValid,
      isTrue,
    );
  });

  testWidgets('Cmd+Shift+- matches when the key is reported as underscore', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final binding = ShortcutBinding(
      keyId: LogicalKeyboardKey.minus.keyId,
      meta: true,
      shift: true,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final event = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.minus,
      logicalKey: LogicalKeyboardKey.underscore,
      timeStamp: Duration.zero,
      character: '_',
    );
    expect(binding.matchesHardware(event), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  });
}
