import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/browse/bring_file_catalog.dart';
import 'package:system_app_front_end/core/models/app_file.dart';
import 'package:system_app_front_end/core/models/topic.dart';

Topic _topic(int id, String name) => Topic(
      id: id,
      name: name,
      type: 'project',
    );

AppFile _file(int id, int topicId, String name) => AppFile(
      id: id,
      topicId: topicId,
      name: name,
      type: 'doc',
    );

void main() {
  final mainTopic = _topic(1, 'main');
  final project = _topic(2, 'Alpha Project');
  final process = _topic(3, 'Beta Process');

  final catalog = buildBringFileCatalog(
    topics: [mainTopic, project, process],
    files: [
      _file(10, 1, 'Daily'),
      _file(11, 2, 'Plan'),
      _file(12, 2, 'Tasks'),
      _file(13, 3, 'Documentation'),
    ],
    mainTopic: mainTopic,
  );

  test('buildBringFileCatalog excludes main topic files', () {
    expect(catalog.map((e) => e.file.id), [11, 12, 13]);
  });

  test('filterBringFileCatalog filters by topic word', () {
    final filtered = filterBringFileCatalog(catalog, 'alpha');
    expect(filtered.map((e) => e.file.id), [11, 12]);
  });

  test('filterBringFileCatalog filters by topic then file name', () {
    final filtered = filterBringFileCatalog(catalog, 'alpha plan');
    expect(filtered.map((e) => e.file.id), [11]);
  });

  test('filterBringFileCatalog matches localized file labels', () {
    final vision = _topic(4, 'ראייה');
    final entries = [
      BrowseFileEntry(topic: vision, file: _file(20, 4, 'Tasks')),
    ];
    final filtered = filterBringFileCatalog(
      entries,
      'רא מ',
      fileLabel: (_) => 'משימות',
    );
    expect(filtered.map((e) => e.file.id), [20]);
  });

  test('filterBringFileCatalog returns empty when no match', () {
    expect(filterBringFileCatalog(catalog, 'alpha missing'), isEmpty);
  });
}
