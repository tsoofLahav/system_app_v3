import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/areas/objects/data/task.dart';
import 'package:system_app_front_end/areas/objects/tasks/task_list_surface.dart';
import 'package:system_app_front_end/areas/objects/tasks/task_mark.dart';
import 'package:system_app_front_end/areas/objects/views/view_frame_task_list_bridge.dart';

class _State extends AppState {
  final toggled = <int>[];
  @override
  Future<void> toggleTaskStatus(Task task, {bool notify = true}) async {
    toggled.add(task.id);
    tasksById[task.id] = task.copyWith(status: task.isDone ? 'active' : 'done');
  }

  @override
  Future<void> refreshOpenTaskSurfaces({bool notify = true}) async {}
}

class _Bridge extends ViewFrameTaskListBridge {
  _Bridge(_State state, List<Task> tasks)
    : super(
        state: state,
        frameTasks: tasks,
        sectionName: null,
        sectionFlag: null,
        topicKey: null,
      );
  @override
  Future<void> moveInZone({
    required Task task,
    required bool targetDone,
    required int insertIndexInZone,
  }) async {
    fail('A checkbox must not move the task');
  }

  @override
  Future<void> reorder(List<int> orderedIds) async {
    fail('A checkbox must not rewrite order');
  }
}

void main() {
  testWidgets('checkbox preserves view order through mark and unmark', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final state = _State();
    final tasks = [
      const Task(id: 1, title: 'First', status: 'active'),
      const Task(id: 2, title: 'Second', status: 'done'),
      const Task(id: 3, title: 'Third', status: 'active'),
      const Task(id: 4, title: 'Fourth', status: 'done'),
    ];
    for (final task in tasks) {
      state.tasksById[task.id] = task;
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskListSurface(
            state: state,
            bridge: _Bridge(state, tasks),
            allowEmptyList: true,
          ),
        ),
      ),
    );
    await tester.pump();
    // Initially visible: First, Third, Second, Fourth.
    await tester.tap(find.byType(TaskMark).at(1));
    await tester.pumpAndSettle();
    expect(state.toggled, [3]);
    // Done projection is Second, Third, Fourth, not Second, Fourth, Third.
    final fields = find.byType(EditableText);
    List<String> titles() => tester
        .widgetList<EditableText>(fields)
        .map((f) => f.controller.text.replaceAll('\u200b', ''))
        .toList();
    expect(titles(), ['First', 'Second', 'Third', 'Fourth']);
    await tester.tap(find.byType(TaskMark).at(2));
    await tester.pumpAndSettle();
    expect(state.toggled, [3, 3]);
    expect(titles(), ['First', 'Third', 'Second', 'Fourth']);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
