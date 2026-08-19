import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';
import 'package:system_app_front_end/areas/files/data/topic.dart';
import 'package:system_app_front_end/areas/ux/bring_file/bring_file_catalog.dart';

Topic _topic(int id, String name, {String? archivedAt}) => Topic(
      id: id,
      workspaceId: 1,
      name: name,
      archivedAt: archivedAt,
    );

AppFile _file(int id, int topicId, String name, {String? archivedAt}) =>
    AppFile(
      id: id,
      topicId: topicId,
      name: name,
      archivedAt: archivedAt,
    );

void main() {
  final home = _topic(1, 'Home');
  final work = _topic(2, 'Work');
  final notes = _topic(3, 'Notes');

  final workDoc = _file(10, 2, 'Plan');
  final notesDoc = _file(11, 3, 'Journal');
  final homeDoc = _file(12, 1, 'Daily');

  test('catalog skips Home files, archived files, and archived topics', () {
    final entries = buildBringFileCatalog(
      topics: [home, work, notes, _topic(4, 'Old', archivedAt: '2026-01-01')],
      files: [
        homeDoc,
        workDoc,
        notesDoc,
        _file(13, 2, 'Gone', archivedAt: '2026-01-01'),
        _file(14, 4, 'Stale'),
      ],
      mainTopic: home,
    );

    expect(entries.map((e) => e.file.id), [11, 10]);
  });

  test('first search word matches topic, the rest matches file name', () {
    final entries = buildBringFileCatalog(
      topics: [home, work, notes],
      files: [workDoc, notesDoc, _file(15, 2, 'Log')],
      mainTopic: home,
    );

    expect(
      filterBringFileCatalog(entries, 'work').map((e) => e.file.name),
      ['Log', 'Plan'],
    );
    expect(
      filterBringFileCatalog(entries, 'work plan').map((e) => e.file.id),
      [10],
    );
    expect(filterBringFileCatalog(entries, 'notes plan'), isEmpty);
  });

  test('catalog can skip files already visiting Home', () {
    final entries = buildBringFileCatalog(
      topics: [home, work, notes],
      files: [workDoc, notesDoc],
      mainTopic: home,
      excludeFileIds: {10},
    );

    expect(entries.map((e) => e.file.id), [11]);
  });
}
