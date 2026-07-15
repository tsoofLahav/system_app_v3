import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_app_front_end/core/shortcuts/shortcut_binding.dart';
import 'package:system_app_front_end/core/shortcuts/shortcut_bindings_store.dart';
import 'package:system_app_front_end/core/shortcuts/shortcut_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('bindingFor returns catalog default when no override', () {
    final store = ShortcutBindingsStore();
    final action = kShortcutCatalog.first;

    expect(store.bindingFor(action.id), action.defaultBinding);
    expect(store.hasOverride(action.id), isFalse);
  });

  test('setBinding overrides default and bindingOwner detects conflicts', () async {
    final store = ShortcutBindingsStore();
    final custom = ShortcutBinding(
      keyId: LogicalKeyboardKey.keyZ.keyId,
      meta: true,
    );

    await store.setBinding(ShortcutActionIds.goHome, custom);

    expect(store.bindingFor(ShortcutActionIds.goHome), custom);
    expect(store.hasOverride(ShortcutActionIds.goHome), isTrue);
    expect(
      store.bindingOwner(ShortcutActionIds.bringFile, custom),
      ShortcutActionIds.goHome,
    );
    expect(store.bindingOwner(ShortcutActionIds.goHome, custom), isNull);
  });

  test('resetBinding restores default', () async {
    final store = ShortcutBindingsStore();
    final custom = ShortcutBinding(
      keyId: LogicalKeyboardKey.keyZ.keyId,
      meta: true,
    );
    await store.setBinding(ShortcutActionIds.goHome, custom);
    await store.resetBinding(ShortcutActionIds.goHome);

    final action = shortcutActionById(ShortcutActionIds.goHome)!;
    expect(store.bindingFor(ShortcutActionIds.goHome), action.defaultBinding);
    expect(store.hasOverride(ShortcutActionIds.goHome), isFalse);
  });
}
