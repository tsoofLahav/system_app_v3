import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/automations/automation.dart';
import 'package:system_app_front_end/areas/objects/data/task.dart';
import 'package:system_app_front_end/areas/objects/data/view_layout.dart';
import 'package:system_app_front_end/areas/objects/tasks/task_list_surface.dart';
import 'package:system_app_front_end/areas/ui/app_colors.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';

void main() {
  test('section defs persist key and cadence', () {
    const section = ViewSectionDef(
      name: 'Focus',
      key: 'abc',
      cadence: ViewSectionCadence.routine,
    );
    final json = section.toJson();
    expect(json['key'], 'abc');
    expect(json['cadence'], 'routine');
    expect(json.containsKey('default'), isFalse);
    final restored = ViewSectionDef.fromJson(json, 0);
    expect(restored.key, 'abc');
    expect(restored.isRoutine, isTrue);
    expect(restored.isDefault, isFalse);
  });

  test('missing cadence defaults to routine and one_time is kept', () {
    final routine = ViewSectionDef.fromJson({'name': 'A'}, 0);
    expect(routine.cadence, ViewSectionCadence.routine);
    final once = ViewSectionDef.fromJson({
      'name': 'B',
      'cadence': 'one_time',
    }, 1);
    expect(once.cadence, ViewSectionCadence.oneTime);
    expect(once.isRoutine, isFalse);
  });

  test('complimentary placement is required for input or review steps', () {
    expect(
      Automation.needsComplimentaryPlacement([
        {'kind': 'ai', 'prompt': 'x', 'requires_user_input': true},
      ]),
      isTrue,
    );
    expect(
      Automation.needsComplimentaryPlacement([
        {'kind': 'ai', 'prompt': 'x', 'apply_mode': 'review'},
      ]),
      isTrue,
    );
    expect(
      Automation.needsComplimentaryPlacement([
        {'kind': 'unmark_tasks'},
      ]),
      isFalse,
    );
  });

  test('complimentary tasks expose role helpers', () {
    final input = Task.fromJson({
      'id': 1,
      'title': 'Weekly brief automation task',
      'status': 'active',
      'source_automation_id': 9,
      'complimentary_role': 'input',
      'complimentary_cycle': {'input_received': true},
    });
    expect(input.isComplimentaryTask, isTrue);
    expect(input.isInputComplimentary, isTrue);
    expect(input.complimentaryInputReceived, isTrue);
    expect(input.isCompanionTask, isTrue);
  });

  test('localized complimentary titles follow the plan', () {
    expect(
      AppStrings.en.complimentaryInputTitle('Weekly brief'),
      'Weekly brief automation task',
    );
    expect(
      AppStrings.en.complimentaryReviewTitle('Weekly brief'),
      'Weekly brief review task',
    );
    expect(
      AppStrings.he.complimentaryInputTitle('סקירה שבועית'),
      'סקירה שבועית משימת אוטומציה',
    );
    expect(
      AppStrings.he.complimentaryReviewTitle('סקירה שבועית'),
      'סקירה שבועית משימת סקירה',
    );
  });

  test('section window automation parses attention and leftover payload', () {
    final automation = Automation.fromJson({
      'id': 4,
      'workspace_id': 1,
      'name': 'Daily / Focus',
      'kind': 'section_window',
      'view_id': 2,
      'section_key': 'abc',
      'window_duration_minutes': 90,
      'window_open': true,
      'attention': true,
      'has_pending_review': false,
      'pending_clear': {
        'section_name': 'Focus',
        'leftovers': [
          {'id': 8, 'title': 'Call', 'cadence': 'routine'},
        ],
      },
    });
    expect(automation.isSectionWindow, isTrue);
    expect(automation.attention, isTrue);
    expect(automation.hasPendingClear, isTrue);
    expect(automation.hasPendingReview, isFalse);
    expect(automation.windowDurationMinutes, 90);
  });

  test('review hover flag is off until a pending review exists', () {
    final waiting = Automation.fromJson({
      'id': 8,
      'workspace_id': 1,
      'name': 'Daily docs',
      'kind': 'standard',
    });
    expect(waiting.hasPendingReview, isFalse);
    final pending = Automation.fromJson({
      'id': 8,
      'workspace_id': 1,
      'name': 'Daily docs',
      'kind': 'standard',
      'has_pending_review': true,
    });
    expect(pending.hasPendingReview, isTrue);
  });

  test('complimentary title is pressable only in an open section window', () {
    final input = Task.fromJson({
      'id': 1,
      'title': 'Weekly brief automation task',
      'status': 'active',
      'source_automation_id': 9,
      'complimentary_role': 'input',
    });
    expect(
      complimentaryTaskPressable(
        task: input,
        automation: null,
        windowOpen: true,
        processing: false,
      ),
      isTrue,
    );
    expect(
      complimentaryTaskPressable(
        task: input,
        automation: null,
        windowOpen: false,
        processing: false,
      ),
      isFalse,
    );
    expect(
      complimentaryTaskPressable(
        task: input.copyWith(status: 'done'),
        automation: null,
        windowOpen: true,
        processing: false,
      ),
      isFalse,
    );
    expect(
      complimentaryTaskPressable(
        task: input,
        automation: null,
        windowOpen: true,
        processing: true,
      ),
      isFalse,
    );
  });

  test('pressable complimentary title underlines without dropping strikethrough', () {
    final style = complimentaryTitleStyle(
      base: const TextStyle(
        decoration: TextDecoration.lineThrough,
        color: Color(0xFF9D988F),
      ),
      pressable: true,
    );
    expect(style.color, AppColors.descriptionLink);
    expect(
      style.decoration,
      TextDecoration.combine([
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]),
    );
  });
}
