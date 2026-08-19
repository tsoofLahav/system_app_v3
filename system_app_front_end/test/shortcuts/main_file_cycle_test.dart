import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';
import 'package:system_app_front_end/areas/ux/layout/file_layouts.dart';
import 'package:system_app_front_end/areas/ux/shortcuts/main_file_cycle.dart';

AppFile _file(int id) => AppFile(id: id, topicId: 1, name: 'File$id');

void main() {
  test('rotateMainFilesLeft is no-op for fewer than two files', () {
    expect(rotateMainFilesLeft([_file(1)]).map((f) => f.id), [1]);
    expect(rotateMainFilesLeft([]).map((f) => f.id), isEmpty);
  });

  test('rotateMainFilesLeft moves first file to end', () {
    final rotated = rotateMainFilesLeft([_file(1), _file(2), _file(3)]);

    expect(rotated.map((f) => f.id), [2, 3, 1]);
  });

  test('rotateMainFilesLeft loops through order', () {
    var main = [_file(1), _file(2), _file(3)];
    main = rotateMainFilesLeft(main);
    expect(main.map((f) => f.id), [2, 3, 1]);
    main = rotateMainFilesLeft(main);
    expect(main.map((f) => f.id), [3, 1, 2]);
    main = rotateMainFilesLeft(main);
    expect(main.map((f) => f.id), [1, 2, 3]);
  });

  test('rotateMainFilesRight moves last file to front', () {
    final rotated = rotateMainFilesRight([_file(1), _file(2), _file(3)]);
    expect(rotated.map((f) => f.id), [3, 1, 2]);
  });

  test('cycledShownFileOrder is null when fewer than two files are shown', () {
    expect(
      cycledShownFileOrder(
        ordered: [_file(1), _file(2), _file(3)],
        layoutId: FileLayouts.single,
      ),
      isNull,
    );
  });

  test('cycledShownFileOrder rotates only the on-screen band', () {
    final next = cycledShownFileOrder(
      ordered: [_file(1), _file(2), _file(3)],
      layoutId: FileLayouts.split,
    );
    expect(next!.map((f) => f.id), [2, 1, 3]);
  });

  test('cycledShownFileOrder reverse walks the other way', () {
    final files = [_file(1), _file(2), _file(3)];
    final forward = cycledShownFileOrder(
      ordered: files,
      layoutId: FileLayouts.split,
    );
    final back = cycledShownFileOrder(
      ordered: forward!,
      layoutId: FileLayouts.split,
      reverse: true,
    );
    expect(back!.map((f) => f.id), [1, 2, 3]);
  });
}
