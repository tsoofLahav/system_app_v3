import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';
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

  test('cycledTopicFileOrder is null when fewer than two files exist', () {
    expect(cycledTopicFileOrder(ordered: [_file(1)]), isNull);
  });

  test(
    'cycledTopicFileOrder rotates every file, including those off screen',
    () {
      final next = cycledTopicFileOrder(
        ordered: [_file(1), _file(2), _file(3), _file(4)],
      );
      expect(next!.map((f) => f.id), [2, 3, 4, 1]);
    },
  );

  test('cycledTopicFileOrder reverse walks the other way', () {
    final files = [_file(1), _file(2), _file(3), _file(4)];
    final forward = cycledTopicFileOrder(ordered: files);
    final back = cycledTopicFileOrder(ordered: forward!, reverse: true);
    expect(back!.map((f) => f.id), [1, 2, 3, 4]);
  });
}
