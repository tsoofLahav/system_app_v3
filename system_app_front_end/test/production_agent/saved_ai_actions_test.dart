import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/automations/automation.dart';
import 'package:system_app_front_end/areas/production_agent/agent_run_defaults.dart';
import 'package:system_app_front_end/areas/ui/action_icons.dart';
import 'package:system_app_front_end/areas/ux/shortcuts/shortcut_catalog.dart';

void main() {
  group('a saved action carries its face and its seat', () {
    test('icon and bar slot survive the trip to JSON and back', () {
      final action = Automation.fromJson({
        'id': 4,
        'workspace_id': 1,
        'name': 'Tidy the log',
        'prompt': 'tidy it',
        'apply_mode': 'review',
        'trigger': {'type': 'manual'},
        'icon': 'checklist',
        'bar_slot': 3,
      });

      expect(action.icon, 'checklist');
      expect(action.barSlot, 3);
      expect(action.isOnBar, isTrue);
      expect(action.isManual, isTrue);

      final json = action.toJson(workspaceId: 1);
      expect(json['icon'], 'checklist');
      expect(json['bar_slot'], 3);
    });

    test('an action with no slot lives in the menu', () {
      final action = Automation.fromJson({
        'id': 5,
        'workspace_id': 1,
        'name': 'Weekly summary',
        'prompt': 'summarise',
        'trigger': {'type': 'manual'},
      });

      expect(action.isOnBar, isFalse);
      expect(action.icon, '');
      expect(action.toJson(workspaceId: 1).containsKey('bar_slot'), isFalse);
    });
  });

  group('icon vocabulary', () {
    test('a stored key gives back its icon', () {
      expect(actionIcon('checklist'), isNot(actionIcon('calendar')));
    });

    test('an empty or retired key still gets a face', () {
      expect(actionIcon(''), actionIcon(defaultActionIconKey));
      expect(actionIcon('no_such_icon_here'), actionIcon(defaultActionIconKey));
      expect(actionIcon(null), actionIcon(defaultActionIconKey));
    });

    test('every key in the picker resolves', () {
      for (final key in actionIconKeys) {
        expect(actionIcon(key), isNotNull);
      }
    });
  });

  group('a slot is also a keyboard shortcut', () {
    test('slot ids round-trip', () {
      for (var slot = 1; slot <= aiBarSlotCount; slot++) {
        final id = ShortcutActionIds.aiActionSlot(slot);
        expect(ShortcutActionIds.slotOfAiAction(id), slot);
      }
    });

    test('other actions are not slots', () {
      expect(ShortcutActionIds.slotOfAiAction(ShortcutActionIds.aiConsult),
          isNull);
      expect(ShortcutActionIds.slotOfAiAction(ShortcutActionIds.addFile),
          isNull);
    });

    test('the six slots default to Cmd+Shift+2 through 7', () {
      final slotActions = kShortcutCatalog
          .where((a) => ShortcutActionIds.slotOfAiAction(a.id) != null)
          .toList();
      expect(slotActions.length, aiBarSlotCount);

      const digits = [
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
      ];
      for (var slot = 1; slot <= aiBarSlotCount; slot++) {
        final binding = slotActions[slot - 1].defaultBinding;
        expect(binding.keyId, digits[slot - 1].keyId);
        expect(binding.meta, isTrue);
        expect(binding.shift, isTrue);
      }
    });

    test('consult keeps Cmd+Shift+1 — it is always on the bar', () {
      final consult = kShortcutCatalog
          .firstWhere((a) => a.id == ShortcutActionIds.aiConsult);
      expect(consult.defaultBinding.keyId, LogicalKeyboardKey.digit1.keyId);
      expect(consult.defaultBinding.meta, isTrue);
      expect(consult.defaultBinding.shift, isTrue);
    });

    test('no two catalog actions want the same keys', () {
      final seen = <String>{};
      for (final action in kShortcutCatalog) {
        final label = action.defaultBinding.displayLabel();
        expect(seen.add('$label'), isTrue, reason: '$label is claimed twice');
      }
    });
  });
}
