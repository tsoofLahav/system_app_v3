import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/task.dart';
import 'package:system_app_front_end/areas/objects/data/view_section.dart';
import 'package:system_app_front_end/areas/objects/data/view_section_flags.dart';

void main() {
  test('ViewSection parses importance flag', () {
    const section = ViewSection(
      id: 1,
      viewType: 'daily',
      name: 'Focus',
      sectionFlag: ViewSectionFlags.important,
    );
    expect(section.isImportant, isTrue);

    final restored = ViewSection.fromJson({
      'id': 2,
      'view_type': 'daily',
      'section_name': 'Later',
      'order_index': 0,
      'section_flag': ViewSectionFlags.important,
    });
    expect(restored.isImportant, isTrue);
  });

  test('Task inherits section_flag from view membership payload', () {
    final task = Task.fromJson({
      'id': 9,
      'block_id': 1,
      'title': 'Ship feature',
      'status': 'active',
      'section_name': 'Focus',
      'section_flag': ViewSectionFlags.important,
    });
    expect(task.isImportant, isTrue);
  });

  test('Task parses description_links from the payload', () {
    final task = Task.fromJson({
      'id': 3,
      'title': 'Call Alex',
      'status': 'active',
      'description_links': [
        {
          'id': 11,
          'kind': 'description',
          'source_type': 'task',
          'source_id': 3,
          'anchor': {'segment_id': 'task:3', 'start': 0, 'end': 4},
        },
      ],
    });
    expect(task.descriptionLinks, hasLength(1));
    expect(task.descriptionLinks.first['id'], 11);
    expect(task.copyWith(title: 'Call').descriptionLinks, hasLength(1));
  });
}
