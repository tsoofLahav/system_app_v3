import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/shortcuts/shortcut_catalog.dart';

void main() {
  test('catalog default bindings are unique', () {
    final seen = <String, String>{};

    for (final action in kShortcutCatalog) {
      final label = action.defaultBinding.displayLabel();
      final owner = seen[label];
      expect(
        owner,
        isNull,
        reason:
            'Duplicate default binding $label on ${action.id} and $owner',
      );
      seen[label] = action.id;
    }
  });
}
