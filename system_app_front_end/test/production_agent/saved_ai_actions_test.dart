import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/automations/automation.dart';
import 'package:system_app_front_end/areas/automations/schedule_format.dart';
import 'package:system_app_front_end/areas/production_agent/agent_run_defaults.dart';
import 'package:system_app_front_end/areas/production_agent/ai_action.dart';
import 'package:system_app_front_end/areas/production_agent/ai_action_bar.dart';
import 'package:system_app_front_end/areas/ui/action_icons.dart';
import 'package:system_app_front_end/areas/ux/shortcuts/shortcut_catalog.dart';

void main() {
  group('a saved action carries its face and its seat', () {
    test('icon and bar slot survive the trip to JSON and back', () {
      final action = AiAction.fromJson({
        'id': 4,
        'workspace_id': 1,
        'name': 'Tidy the log',
        'prompt': 'tidy it',
        'apply_mode': 'review',
        'icon': 'checklist',
        'bar_slot': 3,
      });

      expect(action.icon, 'checklist');
      expect(action.barSlot, 3);
      expect(action.isOnBar, isTrue);
    });

    test('an action with no slot lives in the menu', () {
      final action = AiAction.fromJson({
        'id': 5,
        'workspace_id': 1,
        'name': 'Weekly summary',
        'prompt': 'summarise',
      });

      expect(action.isOnBar, isFalse);
      expect(action.icon, '');
      expect(action.topicTypeId, isNull);
      expect(action.topicId, isNull);
      expect(action.nameHe, isEmpty);
      expect(action.visibleOnTopicType(3), isTrue);
    });

    test('hebrew name and topic scope survive JSON', () {
      final action = AiAction.fromJson({
        'id': 8,
        'workspace_id': 1,
        'name': 'Tidy',
        'name_he': 'סידור',
        'prompt': 'tidy it',
        'topic_id': 4,
      });
      expect(action.nameHe, 'סידור');
      expect(action.topicId, 4);
      expect(action.topicTypeId, isNull);
      expect(action.isGlobal, isFalse);
    });

    test('a typed action is extra, not instead of globals', () {
      final action = AiAction.fromJson({
        'id': 6,
        'workspace_id': 1,
        'name': 'Process recap',
        'prompt': 'recap',
        'topic_type_id': 2,
      });
      expect(action.visibleOnTopicType(2), isTrue);
      expect(action.visibleOnTopicType(9), isFalse);
      expect(action.visibleOnTopicType(null), isFalse);
    });

    test('visibility is open topic, type, or a visiting file on Home', () {
      final global = AiAction.fromJson({
        'id': 1,
        'workspace_id': 1,
        'name': 'Everywhere',
        'prompt': 'go',
      });
      final typed = AiAction.fromJson({
        'id': 2,
        'workspace_id': 1,
        'name': 'Process',
        'prompt': 'go',
        'topic_type_id': 9,
      });
      final topical = AiAction.fromJson({
        'id': 3,
        'workspace_id': 1,
        'name': 'This one',
        'prompt': 'go',
        'topic_id': 4,
      });

      bool shown(
        AiAction action, {
        int? openTopicId,
        int? openTypeId,
        Set<int> visitingTopicIds = const {},
        Set<int> visitingTypeIds = const {},
      }) =>
          action.visibleIn(
            openTopicId: openTopicId,
            openTypeId: openTypeId,
            visitingTopicIds: visitingTopicIds,
            visitingTypeIds: visitingTypeIds,
          );

      expect(shown(global, openTopicId: 1), isTrue);
      expect(shown(typed, openTopicId: 2, openTypeId: 9), isTrue);
      expect(shown(typed, openTopicId: 2, openTypeId: 3), isFalse);
      expect(
        shown(
          typed,
          openTopicId: 1,
          visitingTypeIds: {9},
        ),
        isTrue,
      );
      expect(shown(topical, openTopicId: 4), isTrue);
      expect(shown(topical, openTopicId: 1), isFalse);
      expect(
        shown(
          topical,
          openTopicId: 1,
          visitingTopicIds: {4},
        ),
        isTrue,
      );
    });
  });

  group('an automation is a scope, a trigger, and steps', () {
    test('steps survive JSON', () {
      final automation = Automation.fromJson({
        'id': 2,
        'workspace_id': 1,
        'name': 'Sunday reset',
        'name_he': 'איפוס ראשון',
        'trigger': {'type': 'schedule'},
        'scope': {'kind': 'topic', 'topic_id': 3},
        'steps': [
          {'kind': 'unmark_tasks'},
          {'kind': 'ai', 'prompt': 'summarise', 'apply_mode': 'review'},
        ],
        'schedule': 'weekly sun 06:00',
      });

      expect(automation.nameHe, 'איפוס ראשון');
      expect(automation.steps.length, 2);
      expect(automation.steps.first['kind'], StepKinds.unmarkTasks);
      expect(AutomationScope.targetTopicId(automation.scope), 3);
      expect(automation.isScheduled, isTrue);
    });

    test('a type scope stores the type id', () {
      final scope = AutomationScope.ofType(4);
      expect(scope['kind'], AutomationScope.topicType);
      expect(AutomationScope.typeIdOf(scope), 4);
    });
  });

  group('schedule strings the backend can read', () {
    test('daily weekly monthly round-trip', () {
      expect(
        const AutomationSchedule(kind: 'daily', time: '8:05').toDsl(),
        'daily 08:05',
      );
      expect(
        const AutomationSchedule(
          kind: 'weekly',
          weekday: 'sun',
          time: '06:00',
        ).toDsl(),
        'weekly sun 06:00',
      );
      expect(
        const AutomationSchedule(
          kind: 'monthly',
          placement: 'last',
          weekday: 'fri',
          time: '18:00',
        ).toDsl(),
        'monthly last fri 18:00',
      );
    });

    test('an old cron line becomes a daily eight oclock', () {
      final parsed = AutomationSchedule.parse('0 8 * * *');
      expect(parsed.kind, 'daily');
      expect(parsed.toDsl(), 'daily 08:00');
    });

    test('a stored dsl is read back', () {
      final parsed = AutomationSchedule.parse('weekly mon 09:30');
      expect(parsed.kind, 'weekly');
      expect(parsed.weekday, 'mon');
      expect(parsed.time, '09:30');
    });

    test('a calendar tap infers weekday and monthly placement', () {
      const weekly = AutomationSchedule(kind: 'weekly');
      expect(
        weekly.applyingDate(DateTime(2026, 8, 18)).weekday,
        'tue',
      );
      expect(weekly.marksDate(DateTime(2026, 8, 18)), isFalse);
      expect(
        weekly.applyingDate(DateTime(2026, 8, 18)).marksDate(
              DateTime(2026, 8, 25),
            ),
        isTrue,
      );

      // August 2026 has five Sundays: 2, 9, 16, 23, 30.
      expect(
        AutomationSchedule.placementFromDate(DateTime(2026, 8, 2)),
        'first',
      );
      expect(
        AutomationSchedule.placementFromDate(DateTime(2026, 8, 9)),
        'second',
      );
      expect(
        AutomationSchedule.placementFromDate(DateTime(2026, 8, 16)),
        'third',
      );
      expect(
        AutomationSchedule.placementFromDate(DateTime(2026, 8, 23)),
        'third',
      );
      expect(
        AutomationSchedule.placementFromDate(DateTime(2026, 8, 30)),
        'last',
      );

      final monthly = const AutomationSchedule(kind: 'monthly')
          .applyingDate(DateTime(2026, 8, 30));
      expect(monthly.weekday, 'sun');
      expect(monthly.placement, 'last');
      expect(monthly.marksDate(DateTime(2026, 8, 30)), isTrue);
      expect(monthly.marksDate(DateTime(2026, 8, 23)), isFalse);
      expect(monthly.marksDate(DateTime(2026, 9, 27)), isTrue);
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
      for (var slot = 1;
          slot <= aiBarSlotCount + aiTopicExtraSlotCount;
          slot++) {
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

    test('the seven fixed slots default to Cmd+2 through 8', () {
      final slotActions = kShortcutCatalog
          .where((a) => ShortcutActionIds.slotOfAiAction(a.id) != null)
          .toList();
      expect(slotActions.length, aiBarSlotCount + aiTopicExtraSlotCount);

      const digits = [
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
      ];
      for (var slot = 1; slot <= aiBarSlotCount; slot++) {
        final binding = slotActions[slot - 1].defaultBinding;
        expect(binding.keyId, digits[slot - 1].keyId);
        expect(binding.meta, isTrue);
        expect(binding.shift, isFalse);
      }
      expect(ShortcutActionIds.slotOfAiAction(slotActions[7].id), 9);
      expect(
        slotActions[7].defaultBinding.keyId,
        LogicalKeyboardKey.digit9.keyId,
      );
      expect(ShortcutActionIds.slotOfAiAction(slotActions[8].id), 10);
      expect(
        slotActions[8].defaultBinding.keyId,
        LogicalKeyboardKey.digit0.keyId,
      );
    });

    test('agent keeps Cmd+1 — it is always on the bar', () {
      final agent = kShortcutCatalog
          .firstWhere((a) => a.id == ShortcutActionIds.aiConsult);
      expect(agent.defaultBinding.keyId, LogicalKeyboardKey.digit1.keyId);
      expect(agent.defaultBinding.meta, isTrue);
      expect(agent.defaultBinding.shift, isFalse);
    });

    test('no two catalog actions want the same keys', () {
      final seen = <String>{};
      for (final action in kShortcutCatalog) {
        final label = action.defaultBinding.displayLabel();
        expect(seen.add('$label'), isTrue, reason: '$label is claimed twice');
      }
    });
  });

  group('the bar is seven saved seats plus two extras for the open topic', () {
    AiAction action({
      required int id,
      int? barSlot,
      int? topicId,
      int? topicTypeId,
    }) =>
        AiAction.fromJson({
          'id': id,
          'workspace_id': 1,
          'name': 'A$id',
          'prompt': 'go',
          if (barSlot != null) 'bar_slot': barSlot,
          if (topicId != null) 'topic_id': topicId,
          if (topicTypeId != null) 'topic_type_id': topicTypeId,
        });

    test('a topic may have two specific actions and no more', () {
      final actions = [
        action(id: 1, topicId: 4, barSlot: 9),
        action(id: 2, topicId: 4, barSlot: 10),
        action(id: 3, topicId: 5, barSlot: 9),
      ];
      expect(topicAiActionSlotsFull(actions, 4), isTrue);
      expect(topicAiActionSlotsFull(actions, 5), isFalse);
      expect(topicAiActionSlotsFull(actions, 4, excludeId: 1), isFalse);
    });

    test('extras catch a spot only on their topic; another topic reuses 9–10', () {
      final actions = [
        action(id: 1, barSlot: 1),
        action(id: 2, topicId: 4, barSlot: 9),
        action(id: 3, topicId: 4, barSlot: 10),
        action(id: 4, topicId: 8, barSlot: 9),
      ];
      final onFour = composeBarAiActions(
        actions: actions,
        openTopicId: 4,
        openTypeId: null,
        visitingTopicIds: const {},
        visitingTypeIds: const {},
      );
      expect(onFour.map((a) => a.id), [1, 2, 3]);

      final onEight = composeBarAiActions(
        actions: actions,
        openTopicId: 8,
        openTypeId: null,
        visitingTopicIds: const {},
        visitingTypeIds: const {},
      );
      expect(onEight.map((a) => a.id), [1, 4]);
    });

    test('Home visits fill leftover extra spots after the open topic', () {
      final actions = [
        action(id: 1, topicId: 4, barSlot: 9),
        action(id: 2, topicId: 8, barSlot: 9),
        action(id: 3, topicId: 8, barSlot: 10),
      ];
      final bar = composeBarAiActions(
        actions: actions,
        openTopicId: 4,
        openTypeId: null,
        visitingTopicIds: {8},
        visitingTypeIds: const {},
      );
      expect(bar.map((a) => a.id), [1, 2]);
    });
  });
}
