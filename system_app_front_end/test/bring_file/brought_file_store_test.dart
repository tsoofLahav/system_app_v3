import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';
import 'package:system_app_front_end/areas/ux/bring_file/brought_file_store.dart';
import 'package:system_app_front_end/areas/ux/layout/file_layouts.dart';
import 'package:system_app_front_end/areas/ux/layout/topic_file_slots.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('save and load restore visit ids and mixed canvas order', () async {
    final store = BroughtFileStore();
    await store.save(
      1,
      const BroughtFileLayout(visitIds: [42, 7], order: [42, 1, 7, 2]),
    );
    final loaded = await store.load(1);
    expect(loaded.visitIds, [42, 7]);
    expect(loaded.order, [42, 1, 7, 2]);
    expect((await store.load(2)).isEmpty, isTrue);
  });

  test('save empty clears visiting file ids', () async {
    final store = BroughtFileStore();
    await store.save(1, const BroughtFileLayout(visitIds: [42], order: [42, 1]));
    await store.save(1, const BroughtFileLayout());
    expect((await store.load(1)).isEmpty, isTrue);
  });

  test('load migrates a legacy single id', () async {
    SharedPreferences.setMockInitialValues({
      BroughtFileStore.legacyKeyFor(1): 9,
    });
    final store = BroughtFileStore();
    final loaded = await store.load(1);
    expect(loaded.visitIds, [9]);
    expect(loaded.order, isEmpty);
  });

  test('load migrates a legacy visit-id list', () async {
    SharedPreferences.setMockInitialValues({
      BroughtFileStore.keyFor(1): '[42, 7]',
    });
    final store = BroughtFileStore();
    final loaded = await store.load(1);
    expect(loaded.visitIds, [42, 7]);
    expect(loaded.order, isEmpty);
  });

  test('visits sit first until a mixed order is stored', () {
    final homeFiles = [
      AppFile(id: 1, topicId: 1, name: 'Daily', orderIndex: 0),
      AppFile(id: 2, topicId: 1, name: 'Inbox', orderIndex: 1),
    ];
    final visiting = [
      AppFile(id: 99, topicId: 2, name: 'Plan'),
      AppFile(id: 98, topicId: 3, name: 'Notes'),
    ];

    expect(
      mergeHomeCanvasFiles(
        homeFiles: homeFiles,
        visits: visiting,
      ).map((f) => f.id),
      [99, 98, 1, 2],
    );
    expect(
      shownFiles(
        mergeHomeCanvasFiles(homeFiles: homeFiles, visits: [visiting.first]),
        FileLayouts.split,
      ).map((f) => f.id),
      [99, 1],
    );
  });

  test('stored order interleaves visits among Home files', () {
    final homeFiles = [
      AppFile(id: 1, topicId: 1, name: 'Daily', orderIndex: 0),
      AppFile(id: 2, topicId: 1, name: 'Inbox', orderIndex: 1),
    ];
    final visiting = [
      AppFile(id: 99, topicId: 2, name: 'Plan'),
    ];

    expect(
      mergeHomeCanvasFiles(
        homeFiles: homeFiles,
        visits: visiting,
        storedOrder: [1, 99, 2],
      ).map((f) => f.id),
      [1, 99, 2],
    );
  });
}
