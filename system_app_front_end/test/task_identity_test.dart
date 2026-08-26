import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/document_text_flow.dart';
import 'package:system_app_front_end/areas/files/rich_text/connect_info.dart';
import 'package:system_app_front_end/areas/objects/data/task.dart';

void main() {
  test('task title segments follow task id, not list slot', () {
    expect(taskIdSegmentId(12), 'task:12');
    expect(parseTaskIdSegmentId('task:12'), 12);
    expect(parseTaskIdSegmentId('list#t0'), isNull);
    expect(isTaskRowSegmentId('task:12'), isTrue);
    expect(isTaskRowSegmentId('task:pending:0'), isTrue);
    expect(isTaskRowSegmentId('list#t1'), isTrue);
    expect(isTaskRowSegmentId('list#c0:1'), isFalse);
  });

  test('description ranges on a task stay on that task after a sibling is added', () {
    const link = {
      'id': 8,
      'kind': 'description',
      'anchor': {'segment_id': 'task:3', 'start': 0, 'end': 4},
    };
    final original = Task.fromJson({
      'id': 3,
      'title': 'Ship',
      'status': 'active',
      'description_links': [link],
    });
    final inserted = Task.fromJson({
      'id': 9,
      'title': '',
      'status': 'active',
    });
    final rangesOnOriginal = descriptionRangesFromLinks(original.descriptionLinks);
    final rangesOnNew = descriptionRangesFromLinks(inserted.descriptionLinks);
    expect(rangesOnOriginal, isNotEmpty);
    expect(rangesOnNew, isEmpty);
  });
}
