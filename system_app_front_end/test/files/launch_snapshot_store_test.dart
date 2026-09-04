import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';
import 'package:system_app_front_end/areas/files/data/launch_snapshot_store.dart';
import 'package:system_app_front_end/areas/files/data/topic.dart';
import 'package:system_app_front_end/areas/objects/data/object_embed.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('launch-snapshot-');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('hydrate round-trips last topic, sidebar, files, and embeds', () async {
    final store = LaunchSnapshotStore(directory: tempDir);
    final snapshot = LaunchSnapshot(
      workspaceId: 1,
      selectedTopicId: 2,
      topics: [
        const Topic(id: 1, workspaceId: 1, name: 'Home'),
        const Topic(
          id: 2,
          workspaceId: 1,
          name: 'Project',
          icon: '📁',
          color: '#aabbcc',
          orderIndex: 1,
          fileLayout: 'split',
          topicTypeId: 9,
        ),
      ],
      files: [
        const AppFile(
          id: 10,
          topicId: 2,
          name: 'Notes',
          documentJson: '%%system_app_document v4\nHello',
          orderIndex: 0,
        ),
        const AppFile(
          id: 11,
          topicId: 2,
          name: 'Scratch',
          documentJson: 'scratch',
          meta: {'automation_scratch': true},
        ),
      ],
      embedsByFileId: {
        10: [
          const ObjectEmbed(
            id: 44,
            fileId: 10,
            type: 'info',
            informationId: 7,
            information: {'title': 'T', 'body': 'B'},
          ),
        ],
      },
      homeVisitFileIds: const [99],
      homeCanvasOrderIds: const [99, 3],
    );

    await store.save(snapshot);
    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.workspaceId, 1);
    expect(loaded.selectedTopicId, 2);
    expect(loaded.topics.map((t) => t.name), ['Home', 'Project']);
    expect(loaded.topics.last.fileLayout, 'split');
    expect(loaded.topics.last.topicTypeId, 9);
    expect(
      loaded.files.singleWhere((f) => f.id == 10).documentJson,
      contains('Hello'),
    );
    expect(loaded.embedsByFileId[10]!.single.information!['title'], 'T');
    expect(loaded.homeVisitFileIds, [99]);
    expect(loaded.homeCanvasOrderIds, [99, 3]);
  });

  test('inbound body reaches filesById even when the editor is dirty', () {
    const local = AppFile(
      id: 10,
      topicId: 2,
      name: 'Notes',
      documentJson: 'local typing',
      orderIndex: 0,
    );
    const inbound = AppFile(
      id: 10,
      topicId: 2,
      name: 'Notes renamed',
      documentJson: 'server copy',
      orderIndex: 3,
    );

    final kept = mergeTopicFileForRefresh(
      local: local,
      inbound: inbound,
      bodyDirty: true,
    );
    expect(kept.documentJson, 'server copy');
    expect(kept.name, 'Notes renamed');
    expect(kept.orderIndex, 3);

    final taken = mergeTopicFileForRefresh(
      local: local,
      inbound: inbound,
      bodyDirty: false,
    );
    expect(taken.documentJson, 'server copy');
  });

  test('scratch files are skipped from a launch snapshot', () {
    expect(
      isScratchFile(
        const AppFile(
          id: 1,
          topicId: 1,
          name: 'Fill',
          meta: {'automation_scratch': true},
        ),
      ),
      isTrue,
    );
    expect(
      isScratchFile(const AppFile(id: 2, topicId: 1, name: 'Daily')),
      isFalse,
    );
  });

  test('missing snapshot file loads as null', () async {
    final store = LaunchSnapshotStore(directory: tempDir);
    expect(await store.load(), isNull);
  });
}
