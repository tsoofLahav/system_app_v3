import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/core/services/api_service.dart';
import 'package:system_app_front_end/areas/objects/data/app_view.dart';

const one = AppView(id: 1, workspaceId: 1, name: 'One', layoutConfig: {});
const two = AppView(id: 2, workspaceId: 1, name: 'Two', layoutConfig: {});

class SyncApi extends ApiService {
  Map<String, dynamic> task = {
    'id': 10,
    'title': 'Task',
    'status': 'active',
    'revision': 1,
  };
  List<Map<String, dynamic>> rows = [
    {
      'id': 1,
      'view_id': 1,
      'task_id': 10,
      'section_name': 'A',
      'order_index': 0,
      'topic_order_index': 0,
    },
    {
      'id': 2,
      'view_id': 1,
      'task_id': 11,
      'section_name': 'B',
      'order_index': 0,
      'topic_order_index': 0,
    },
  ];
  Completer<void>? holdWrite;
  Completer<void>? holdRead;
  bool offline = false;
  int taskWrites = 0;
  int orderWrites = 0;
  @override
  Future<dynamic> get(String path) async {
    if (path == '/tasks/10') return Map<String, dynamic>.of(task);
    if (path == '/views/1/memberships') {
      final snapshot = [
        for (final row in rows)
          {
            ...row,
            if (row['task_id'] == 10) 'task': Map<String, dynamic>.of(task),
          },
      ];
      await holdRead?.future;
      return snapshot;
    }
    return [];
  }

  @override
  Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    if (path == '/tasks/10') {
      taskWrites++;
      await holdWrite?.future;
      if (offline) throw TimeoutException('offline');
      if (body['base_revision'] != task['revision'])
        throw ApiException('conflict', statusCode: 409);
      task = {...task, ...body, 'revision': (task['revision'] as int) + 1}
        ..remove('base_revision');
      return Map<String, dynamic>.of(task);
    }
    orderWrites++;
    await holdWrite?.future;
    for (final change in body['changes'] as List) {
      final row = rows.firstWhere((row) => row['task_id'] == change['task_id']);
      row.addAll(Map<String, dynamic>.from(change['patch'] as Map));
    }
    return [
      for (final row in rows) {...row},
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> tick() => Future.delayed(Duration.zero);
  test(
    'a view refresh started before completion cannot revert the saved status',
    () async {
      final api = SyncApi();
      final state = AppState(api: api)..userViews = [one, two];
      await state.selectView(one.type);
      api.holdRead = Completer<void>();
      final poll = state.refreshOpenTaskSurfaces(notify: false);
      await tick();
      await state.toggleTaskStatus(state.tasksById[10]!, notify: false);
      api.holdRead!.complete();
      await poll;
      expect(state.tasksById[10]!.status, 'done');
      expect(state.tasksById[10]!.revision, 2);
      state.dispose();
    },
  );

  test('navigation joins a pending title save and then switches', () async {
    final api = SyncApi()..holdWrite = Completer<void>();
    final state = AppState(api: api)..userViews = [one, two];
    await state.selectView(one.type);
    final save = state.updateTaskTitle(state.tasksById[10]!, 'New');
    var switched = false;
    final navigation = state.selectView(two.type).then((_) {
      switched = true;
    });
    await tick();
    expect(switched, isFalse);
    expect(state.tasksById[10]!.title, 'New');
    api.holdWrite!.complete();
    await Future.wait([save, navigation]);
    expect(state.selectedView?.id, 2);
    expect(api.taskWrites, 1);
    state.dispose();
  });

  test(
    'a title acknowledgement does not overwrite a concurrent linked status',
    () async {
      final api = SyncApi()..holdWrite = Completer<void>();
      final state = AppState(api: api)..userViews = [one, two];
      await state.selectView(one.type);
      final save = state.updateTaskTitle(state.tasksById[10]!, 'New title');
      await tick();
      // A linked checklist can change the same task while its title is saving.
      state.tasksById[10] = state.tasksById[10]!.copyWith(status: 'done');
      api.holdWrite!.complete();
      await save;
      expect(state.tasksById[10]!.title, 'New title');
      expect(state.tasksById[10]!.status, 'done');
      state.dispose();
    },
  );

  test(
    'failed navigation retains the draft and succeeds after recovery',
    () async {
      final api = SyncApi()..offline = true;
      final state = AppState(api: api)..userViews = [one, two];
      await state.selectView(one.type);
      await expectLater(
        state.updateTaskTitle(state.tasksById[10]!, 'Unsaved'),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        state.selectView(two.type),
        throwsA(isA<TimeoutException>()),
      );
      expect(state.selectedView?.id, 1);
      expect(state.tasksById[10]!.title, 'Unsaved');
      api.offline = false;
      await state.selectView(two.type);
      expect(state.selectedView?.id, 2);
      expect(api.task['title'], 'Unsaved');
      state.dispose();
    },
  );

  test(
    'queued edits in two sections both survive and navigation waits',
    () async {
      final api = SyncApi()..holdWrite = Completer<void>();
      final state = AppState(api: api)..userViews = [one, two];
      await state.selectView(one.type);
      final first = state.reorderViewMemberships([
        for (final row in state.viewMemberships)
          {...row.toReplaceJson(), if (row.taskId == 10) 'order_index': 1},
      ], notify: false);
      await tick();
      final second = state.reorderViewMemberships([
        for (final row in state.viewMemberships)
          {...row.toReplaceJson(), if (row.taskId == 11) 'order_index': 2},
      ], notify: false);
      var switched = false;
      final navigation = state.selectView(two.type).then((_) {
        switched = true;
      });
      await tick();
      expect(switched, isFalse);
      api.holdWrite!.complete();
      await Future.wait([first, second, navigation]);
      expect(api.rows.map((row) => row['order_index']), [1, 2]);
      expect(api.rows.map((row) => row['topic_order_index']), [0, 0]);
      expect(api.orderWrites, 2);
      expect(state.selectedView?.id, 2);
      state.dispose();
    },
  );
}
