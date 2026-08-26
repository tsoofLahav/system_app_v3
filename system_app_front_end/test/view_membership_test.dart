import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/app_view.dart';

void main() {
  test('ViewMembership keeps topic_order_index apart from order_index', () {
    final row = ViewMembership.fromJson({
      'id': 1,
      'view_id': 2,
      'task_id': 3,
      'section_name': 'Later',
      'order_index': 4,
      'topic_order_index': 9,
      'topic_key': 'topic_1',
    });
    expect(row.orderIndex, 4);
    expect(row.topicOrderIndex, 9);
    expect(row.toReplaceJson()['topic_order_index'], 9);
    expect(row.toReplaceJson()['order_index'], 4);
  });

  test('ViewMembership falls back to order_index when topic column is absent', () {
    final row = ViewMembership.fromJson({
      'id': 1,
      'view_id': 2,
      'task_id': 3,
      'order_index': 5,
    });
    expect(row.topicOrderIndex, 5);
  });

  test('copyWith can clear section without touching topic order', () {
    const row = ViewMembership(
      id: 1,
      viewId: 2,
      taskId: 3,
      sectionName: 'Later',
      orderIndex: 1,
      topicOrderIndex: 8,
    );
    final next = row.copyWith(clearSection: true);
    expect(next.sectionName, isNull);
    expect(next.topicOrderIndex, 8);
    expect(next.orderIndex, 1);
  });
}
