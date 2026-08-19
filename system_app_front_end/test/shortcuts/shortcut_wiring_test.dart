import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ux/shortcuts/app_shortcuts.dart';
import 'package:system_app_front_end/areas/ux/shortcuts/shortcut_bindings_store.dart';
import 'package:system_app_front_end/areas/ux/shortcuts/shortcut_catalog.dart';

void main() {
  test('every Preferences catalog action with a valid default is wired', () {
    final store = ShortcutBindingsStore();
    final map = shortcutActivatorsFor(store);
    final wiredIds = {
      for (final intent in map.values)
        if (intent is AppShortcutIntent) intent.actionId,
    };

    for (final action in kShortcutCatalog) {
      expect(
        action.defaultBinding.isValid,
        isTrue,
        reason: '${action.id} has no valid default',
      );
      expect(
        wiredIds,
        contains(action.id),
        reason: '${action.id} is listed in Preferences but not in the key map',
      );
    }
  });
}
