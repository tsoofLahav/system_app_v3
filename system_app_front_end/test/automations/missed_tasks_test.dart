import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';
import 'package:system_app_front_end/areas/automations/automation.dart';
import 'package:system_app_front_end/areas/automations/leftover_clear_dialog.dart';
import 'package:system_app_front_end/areas/objects/data/task.dart';
import 'package:system_app_front_end/areas/objects/tasks/task_mark.dart';
import 'package:system_app_front_end/areas/objects/tasks/task_list_surface.dart';

class _State extends AppState {
  String? choice;
  int? resolvedId;
  @override
  AppStrings get strings => AppStrings.en;
  @override
  Future<void> resolveLeftoverClear({required String disposition, int? windowId}) async {
    choice = disposition;
    resolvedId = windowId;
  }
}

void main() {
  for (final option in {'Was done': 'dismiss', 'I will do it': 'continue', 'Skip and report': 'report'}.entries) {
    testWidgets('missed-task choice ${option.key} targets its own window', (tester) async {
      final state = _State();
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
        onPressed: () => showLeftoverClearDialog(context: context, state: state,
          window: const Automation(id: 9, workspaceId: 1, name: 'Evening', pendingClear: {
            'view_name': 'Weekly', 'section_name': 'Evening',
            'leftovers': [{'id': 1, 'title': 'Write journal'}],
          })), child: const Text('Open')))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Was done'), findsOneWidget);
      expect(find.text('I will do it'), findsOneWidget);
      expect(find.text('Skip and report'), findsOneWidget);
      await tester.tap(find.text(option.key));
      await tester.pumpAndSettle();
      expect(state.choice, option.value);
      expect(state.resolvedId, 9);
    });
  }
  testWidgets('skipped task stays visible without a completed checkmark or review action', (tester) async {
    const task = Task(id: 1, title: 'Review', status: 'skipped', complimentaryRole: 'review');
    expect(task.appearsInView, isTrue);
    expect(task.isDone, isFalse);
    expect(complimentaryTaskPressable(task: task, automation: null, windowOpen: true, processing: false), isFalse);
    await tester.pumpWidget(const MaterialApp(home: TaskMark(status: 'skipped')));
    expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });
}
