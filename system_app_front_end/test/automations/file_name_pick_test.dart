import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/automations/file_name_pick.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';

void main() {
  test('unique names keep the first spelling', () {
    expect(
      uniqueFileNames([
        const AppFile(id: 1, topicId: 1, name: 'Daily'),
        const AppFile(id: 2, topicId: 2, name: 'daily'),
        const AppFile(id: 3, topicId: 1, name: 'Inbox'),
      ]),
      ['Daily', 'Inbox'],
    );
  });

  test('step file name prefers stored name over a leftover id', () {
    expect(
      stepFileName(
        {'file_name': 'Plan', 'file_id': 9},
        [const AppFile(id: 9, topicId: 1, name: 'Old')],
      ),
      'Plan',
    );
  });

  test('step file name falls back to the live name of a leftover id', () {
    expect(
      stepFileName(
        {'file_id': 9},
        [const AppFile(id: 9, topicId: 1, name: 'Daily')],
      ),
      'Daily',
    );
  });
}
