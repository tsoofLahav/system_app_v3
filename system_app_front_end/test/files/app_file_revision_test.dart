import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';

void main() {
  test('parses content_revision from json', () {
    final file = AppFile.fromJson({
      'id': 1,
      'topic_id': 2,
      'name': 'Notes',
      'document_json': '%%system_app_document v4\nHi',
      'order_index': 0,
      'content_revision': 4,
    });
    expect(file.contentRevision, 4);
  });

  test('defaults content_revision when missing', () {
    final file = AppFile.fromJson({
      'id': 1,
      'topic_id': 2,
      'name': 'Notes',
    });
    expect(file.contentRevision, 1);
  });
}
