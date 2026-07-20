import 'package:flutter_test/flutter_test.dart';

import 'package:system_app_front_end/core/models/block.dart';
import 'package:system_app_front_end/core/models/task.dart';
import 'package:system_app_front_end/features/tasks/task_drag_data.dart';

Block _listBlock(int id) =>
    Block(id: id, fileId: 1, type: 'task_list', content: const {});

Task _task(int id, {int blockId = 1}) =>
    Task(id: id, blockId: blockId, title: 't$id', status: 'active');

TaskDragPayload _payload({
  required Task task,
  int listBlockId = 1,
  bool sourceDone = false,
  String? sourceViewType,
}) {
  return TaskDragPayload(
    task: task,
    sourceListBlock: _listBlock(listBlockId),
    sourceDone: sourceDone,
    sourceViewType: sourceViewType,
  );
}

TaskDropTarget _target({
  int listBlockId = 1,
  String? viewType,
  bool done = false,
  int insertIndex = 0,
}) {
  return TaskDropTarget(
    listBlockId: listBlockId,
    viewType: viewType,
    done: done,
    insertIndex: insertIndex,
  );
}

void main() {
  group('regular mode', () {
    test('same block same zone reorders', () {
      final action = resolveTaskDrop(
        payload: _payload(task: _task(1)),
        sourceIndexInZone: 0,
        target: _target(insertIndex: 2),
        isFlipMode: false,
        allowCrossBoundary: true,
      );
      expect(action.kind, TaskDropKind.reorder);
      expect(action.oldIndex, 0);
      expect(action.newIndex, 3);
    });

    test('same block cross zone moves across zones', () {
      final action = resolveTaskDrop(
        payload: _payload(task: _task(1), sourceDone: false),
        sourceIndexInZone: 0,
        target: _target(done: true, insertIndex: 0),
        isFlipMode: false,
        allowCrossBoundary: true,
      );
      expect(action.kind, TaskDropKind.moveAcrossZones);
    });

    test('different block moves to list block', () {
      final action = resolveTaskDrop(
        payload: _payload(task: _task(1), listBlockId: 1),
        sourceIndexInZone: 0,
        target: _target(listBlockId: 2, insertIndex: 1),
        isFlipMode: false,
        allowCrossBoundary: true,
      );
      expect(action.kind, TaskDropKind.moveToListBlock);
    });

    test('cross block blocked when allowCrossBoundary is false', () {
      final action = resolveTaskDrop(
        payload: _payload(task: _task(1), listBlockId: 1),
        sourceIndexInZone: 0,
        target: _target(listBlockId: 2),
        isFlipMode: false,
        allowCrossBoundary: false,
      );
      expect(action.kind, TaskDropKind.noop);
    });

    test('same block cross zone allowed without cross boundary flag', () {
      final action = resolveTaskDrop(
        payload: _payload(task: _task(1), sourceDone: false),
        sourceIndexInZone: 0,
        target: _target(done: true, insertIndex: 0),
        isFlipMode: false,
        allowCrossBoundary: false,
      );
      expect(action.kind, TaskDropKind.moveAcrossZones);
    });
  });

  group('flip mode', () {
    test('same view same zone reorders', () {
      final action = resolveTaskDrop(
        payload: _payload(task: _task(1), sourceViewType: 'daily'),
        sourceIndexInZone: 1,
        target: _target(viewType: 'daily', insertIndex: 0),
        isFlipMode: true,
        allowCrossBoundary: true,
      );
      expect(action.kind, TaskDropKind.reorder);
    });

    test('same view cross zone moves across zones', () {
      final action = resolveTaskDrop(
        payload: _payload(
          task: _task(1),
          sourceDone: false,
          sourceViewType: 'daily',
        ),
        sourceIndexInZone: 0,
        target: _target(viewType: 'daily', done: true, insertIndex: 0),
        isFlipMode: true,
        allowCrossBoundary: true,
      );
      expect(action.kind, TaskDropKind.moveAcrossZones);
    });

    test('different view assigns view', () {
      final action = resolveTaskDrop(
        payload: _payload(task: _task(1), sourceViewType: 'daily'),
        sourceIndexInZone: 0,
        target: _target(viewType: 'weekly', insertIndex: 0),
        isFlipMode: true,
        allowCrossBoundary: true,
      );
      expect(action.kind, TaskDropKind.assignView);
    });
  });
}
