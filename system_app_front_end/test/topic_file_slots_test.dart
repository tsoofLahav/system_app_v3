import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';
import 'package:system_app_front_end/areas/ux/layout/file_layouts.dart';
import 'package:system_app_front_end/areas/ux/layout/topic_file_slots.dart';

AppFile _file(int id, {int? order}) =>
    AppFile(id: id, topicId: 1, name: 'f$id', orderIndex: order ?? id);

List<int> _ids(List<AppFile> files) => files.map((f) => f.id).toList();

void main() {
  group('how many files a layout shows', () {
    test('the fixed layouts stop at their slot count', () {
      expect(shownFileCount(FileLayouts.single, 5), 1);
      expect(shownFileCount(FileLayouts.split, 5), 2);
      expect(shownFileCount(FileLayouts.hero, 5), 3);
      expect(shownFileCount(FileLayouts.heroLeft, 5), 3);
      expect(shownFileCount(FileLayouts.heroRight, 5), 3);
    });

    test('grid shows everything, and leftover row does too', () {
      expect(shownFileCount(FileLayouts.grid, 5), 5);
      expect(shownFileCount(FileLayouts.row, 5), 5);
    });

    test('a layout never shows more files than exist', () {
      expect(shownFileCount(FileLayouts.hero, 2), 2);
      expect(shownFileCount(FileLayouts.single, 0), 0);
    });
  });

  group('a layout that no longer fits', () {
    test('falls back while there are too few files', () {
      expect(effectiveLayoutId(FileLayouts.hero, 2), FileLayouts.split);
      expect(effectiveLayoutId(FileLayouts.split, 1), FileLayouts.single);
    });

    test('leftover ids draw as the four pickable layouts', () {
      expect(effectiveLayoutId(FileLayouts.heroLeft, 3), FileLayouts.hero);
      expect(effectiveLayoutId(FileLayouts.heroRight, 5), FileLayouts.hero);
      expect(effectiveLayoutId(FileLayouts.row, 4), FileLayouts.grid);
    });
  });

  group('auto layout follows file count until the user picks', () {
    test('1 file is single, 2 is split, 3+ is hero', () {
      expect(effectiveLayoutId(FileLayouts.auto, 1), FileLayouts.single);
      expect(effectiveLayoutId(FileLayouts.auto, 2), FileLayouts.split);
      expect(effectiveLayoutId(FileLayouts.auto, 3), FileLayouts.hero);
      expect(effectiveLayoutId(FileLayouts.auto, 8), FileLayouts.hero);
    });

    test('an explicit pick is kept when it still fits', () {
      expect(effectiveLayoutId(FileLayouts.grid, 4), FileLayouts.grid);
      expect(effectiveLayoutId(FileLayouts.single, 5), FileLayouts.single);
    });

    test('storing the count default writes auto', () {
      expect(
        FileLayouts.storedLayoutId(FileLayouts.single, 1),
        FileLayouts.auto,
      );
      expect(
        FileLayouts.storedLayoutId(FileLayouts.split, 2),
        FileLayouts.auto,
      );
      expect(FileLayouts.storedLayoutId(FileLayouts.hero, 4), FileLayouts.auto);
      expect(
        FileLayouts.storedLayoutId(FileLayouts.heroLeft, 4),
        FileLayouts.auto,
      );
      expect(FileLayouts.storedLayoutId(FileLayouts.grid, 4), FileLayouts.grid);
      expect(
        FileLayouts.storedLayoutId(FileLayouts.single, 3),
        FileLayouts.single,
      );
    });
  });

  group('splitting a topic by its layout', () {
    final files = [_file(1), _file(2), _file(3), _file(4)];

    test('the first files fill the slots and the rest come off screen', () {
      expect(_ids(shownFiles(files, FileLayouts.split)), [1, 2]);
      expect(_ids(hiddenFiles(files, FileLayouts.split)), [3, 4]);
    });

    test('nothing is hidden when the layout takes everything', () {
      expect(_ids(shownFiles(files, FileLayouts.grid)), [1, 2, 3, 4]);
      expect(hiddenFiles(files, FileLayouts.grid), isEmpty);
    });

    test('every file is either shown or hidden, never both or neither', () {
      for (final layout in FileLayouts.all) {
        final shown = shownFiles(files, layout.id);
        final hidden = hiddenFiles(files, layout.id);
        expect(
          [..._ids(shown), ..._ids(hidden)],
          [1, 2, 3, 4],
          reason: 'layout ${layout.id} lost or duplicated a file',
        );
      }
    });
  });

  group('the order that decides placement', () {
    test('follows order_index, not the order the API happened to return', () {
      final files = [
        _file(7, order: 2),
        _file(3, order: 0),
        _file(5, order: 1),
      ];
      expect(_ids(orderedFiles(files)), [3, 5, 7]);
    });

    test('breaks ties by id so the arrangement never flickers', () {
      final files = [_file(9, order: 0), _file(4, order: 0)];
      expect(_ids(orderedFiles(files)), [4, 9]);
    });
  });
}
