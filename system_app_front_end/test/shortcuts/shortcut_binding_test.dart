import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/shortcuts/shortcut_binding.dart';

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

  test('toActivator builds SingleActivator with modifiers', () {
    final binding = ShortcutBinding(
      keyId: LogicalKeyboardKey.keyH.keyId,
      meta: true,
      shift: true,
    );

    final activator = binding.toActivator();
    expect(activator, isA<SingleActivator>());
    expect((activator as SingleActivator).trigger, LogicalKeyboardKey.keyH);
    expect(activator.meta, isTrue);
    expect(activator.shift, isTrue);
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
}
