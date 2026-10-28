import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/task.dart';
import 'package:system_app_front_end/areas/objects/tasks/task_zones.dart';

Task _task(int id, String status) =>
    Task(id: id, title: 't$id', status: status);

void main() {
  test('mark and unmark preserve canonical order in both projections', () {
    final zones = TaskZones.fromOrdered([
      _task(1, 'active'),
      _task(2, 'done'),
      _task(3, 'active'),
      _task(4, 'done'),
      _task(5, 'active'),
    ]);
    final marked = zones.withStatus(3, true);
    expect(marked.orderedIds, [1, 2, 3, 4, 5]);
    expect(marked.done.map((t) => t.id), [2, 3, 4]);
    final restored = marked.withStatus(3, false);
    expect(restored.active.map((t) => t.id), [1, 3, 5]);
    expect(restored.orderedIds, zones.orderedIds);
  });

  test(
    'drag changes one canonical position without regrouping other tasks',
    () {
      final zones = TaskZones.fromOrdered([
        _task(1, 'active'),
        _task(2, 'done'),
        _task(3, 'active'),
        _task(4, 'done'),
        _task(5, 'active'),
      ]);
      final moved = zones.moved(taskId: 5, targetDone: false, indexInZone: 1);
      expect(moved.orderedIds, [1, 2, 5, 3, 4]);
      expect(moved.active.map((t) => t.id), [1, 5, 3]);
      expect(moved.done.map((t) => t.id), [2, 4]);
      expect(moved.withStatus(5, true).done.map((t) => t.id), [2, 5, 4]);
    },
  );

  test('file canonical order follows indices regardless of completion', () {
    final zones = TaskZones.fromTasks([
      const Task(id: 1, title: 'a', status: 'active', listOrderIndex: 2),
      const Task(id: 2, title: 'b', status: 'done', listOrderIndex: 0),
      const Task(id: 3, title: 'c', status: 'active', listOrderIndex: 1),
    ]);
    expect(zones.orderedIds, [2, 3, 1]);
    expect(zones.withStatus(2, false).active.map((t) => t.id), [2, 3, 1]);
  });

  test(
    'inactive and pending are not toggleable and stay off the view page',
    () {
      const inactive = Task(id: 1, title: 'a', status: 'inactive');
      const pending = Task(id: 2, title: 'b', status: 'pending');
      const active = Task(id: 3, title: 'c', status: 'active');
      const done = Task(id: 4, title: 'd', status: 'done');

      expect(inactive.canToggleMark, isFalse);
      expect(pending.canToggleMark, isFalse);
      expect(active.canToggleMark, isTrue);
      expect(done.canToggleMark, isTrue);

      expect(inactive.appearsInView, isFalse);
      expect(pending.appearsInView, isFalse);
      expect(active.appearsInView, isTrue);
      expect(done.appearsInView, isTrue);
      const archived = Task(
        id: 5,
        title: 'e',
        status: 'done',
        archivedAt: '2026-09-06T00:00:00Z',
      );
      expect(archived.appearsInView, isFalse);
    },
  );

  test('reordering inside the active zone keeps pending and inactive', () {
    final zones = TaskZones.fromOrdered([
      _task(1, 'pending'),
      _task(2, 'inactive'),
      _task(3, 'done'),
    ]);
    final moved = zones.moved(taskId: 1, targetDone: false, indexInZone: 2);
    expect(moved.active.map((t) => t.status).toList(), ['inactive', 'pending']);
    expect(moved.done.single.status, 'done');
  });
}
