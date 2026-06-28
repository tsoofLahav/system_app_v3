import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/models/task.dart';
import 'package:system_app_front_end/core/models/view_section.dart';
import 'package:system_app_front_end/core/models/view_section_flags.dart';

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
}
