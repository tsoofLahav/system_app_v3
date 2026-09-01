import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/task.dart';
import 'package:system_app_front_end/areas/objects/tasks/task_zones.dart';

Task _task(int id, String status) => Task(id: id, title: 't$id', status: status);

void main() {
  test('inactive and pending are not toggleable and stay off the view page', () {
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
  });

  test('reordering inside the active zone keeps pending and inactive', () {
    final zones = TaskZones.fromOrdered([
      _task(1, 'pending'),
      _task(2, 'inactive'),
      _task(3, 'done'),
    ]);
    final moved = zones.moved(
      taskId: 1,
      targetDone: false,
      indexInZone: 2,
    );
    expect(moved.active.map((t) => t.status).toList(), ['inactive', 'pending']);
    expect(moved.done.single.status, 'done');
  });
}
