import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/models/archive_files_page.dart';

void main() {
  test('archive page reads files, totals and heading labels', () {
    final page = ArchiveFilesPage.fromJson({
      'files': [
        {
          'id': 9,
          'topic_id': 2,
          'name': 'Weekly',
          'archived_at': '2026-08-01T12:00:00Z',
        },
      ],
      'total': 40,
      'has_more': true,
      'heading_texts_by_file_id': {
        '9': ['Goals', 'Notes'],
      },
    });

    expect(page.files, hasLength(1));
    expect(page.files.single.id, 9);
    expect(page.files.single.documentJson, isEmpty);
    expect(page.total, 40);
    expect(page.hasMore, isTrue);
    expect(page.headerTextsByFileId[9], ['Goals', 'Notes']);
  });

  test('archive page accepts the header_texts alias', () {
    final page = ArchiveFilesPage.fromJson({
      'files': const [],
      'total': 0,
      'has_more': false,
      'header_texts_by_file_id': {
        '4': ['Intro'],
      },
    });
    expect(page.headerTextsByFileId[4], ['Intro']);
  });
}
