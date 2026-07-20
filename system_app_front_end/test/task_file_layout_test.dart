import 'package:flutter_test/flutter_test.dart';

import 'package:system_app_front_end/core/models/block.dart';
import 'package:system_app_front_end/core/models/task.dart';
import 'package:system_app_front_end/core/task_file_layout.dart';

Block _block({
  required int id,
  required String type,
  required int orderIndex,
  Map<String, dynamic>? content,
}) {
  return Block(
    id: id,
    fileId: 1,
    type: type,
    content: content ?? const {},
    orderIndex: orderIndex,
  );
}

Task _task({required int id, required int blockId, String title = 't'}) {
  return Task(id: id, blockId: blockId, title: title, status: 'active');
}

void main() {
  test('taskListRegion stops at next task_list', () {
    final blocks = [
      _block(id: 1, type: 'header', orderIndex: 0),
      _block(id: 2, type: 'task_list', orderIndex: 1),
      _block(id: 3, type: 'task', orderIndex: 2, content: {'task_id': 10}),
      _block(id: 4, type: 'task_list', orderIndex: 3),
      _block(id: 5, type: 'task', orderIndex: 4, content: {'task_id': 20}),
    ];

    final region = taskListRegion(blocks, blocks[1]);
    expect(region.startIndex, 1);
    expect(region.endIndex, 3);
  });

  test('orderedTasksForListBlock follows block order not task id', () {
    final list = _block(id: 2, type: 'task_list', orderIndex: 1);
    final blocks = [
      list,
      _block(id: 3, type: 'task', orderIndex: 2, content: {'task_id': 11}),
      _block(id: 4, type: 'task', orderIndex: 3, content: {'task_id': 3}),
    ];
    final tasksByBlockId = {
      2: [_task(id: 3, blockId: 2), _task(id: 11, blockId: 2)],
    };

    final ordered = orderedTasksForListBlock(blocks, list, tasksByBlockId);
    expect(ordered.map((t) => t.id).toList(), [11, 3]);
  });

  test('groupTasksByView orders registry views then unassigned', () {
    final tasks = [
      _task(id: 1, blockId: 1),
      _task(id: 2, blockId: 1),
      _task(id: 3, blockId: 1),
      _task(id: 4, blockId: 1),
    ];
    String? lookup(int id) {
      return switch (id) {
        1 => 'daily',
        2 => 'weekly',
        4 => 'daily',
        _ => null,
      };
    }

    final groups = groupTasksByView(tasks, lookup, unassignedLabel: 'Unassigned');
    expect(groups.map((g) => g.viewType).toList(), ['daily', 'weekly', null]);
    expect(groups[0].tasks.map((t) => t.id).toList(), [1, 4]);
    expect(groups[1].tasks.map((t) => t.id).toList(), [2]);
    expect(groups[2].tasks.map((t) => t.id).toList(), [3]);
  });
}
