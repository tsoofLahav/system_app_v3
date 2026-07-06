import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/models/app_file.dart';
import 'package:system_app_front_end/features/arrange/file_arrange_draft.dart';

AppFile _file(int id, {bool isMain = true}) => AppFile(
      id: id,
      topicId: 1,
      name: 'File$id',
      type: 'doc',
      isMain: isMain,
    );

void main() {
  test('moveMainToFirst moves tapped file to front', () {
    final draft = FileArrangeDraft(
      main: [_file(1), _file(2), _file(3)],
      additional: const [],
      layoutId: 'split',
    );

    expect(draft.moveMainToFirst(2), isTrue);
    expect(draft.main.map((f) => f.id), [3, 1, 2]);
  });

  test('moveMainToFirst is no-op when already first', () {
    final draft = FileArrangeDraft(
      main: [_file(1), _file(2)],
      additional: const [],
      layoutId: 'split',
    );

    expect(draft.moveMainToFirst(0), isFalse);
    expect(draft.main.map((f) => f.id), [1, 2]);
  });

  test('promoteFromAdditional moves file to main and evicts last main file', () {
    final draft = FileArrangeDraft(
      main: [_file(1), _file(2), _file(3)],
      additional: [_file(4)],
      layoutId: 'hero_left',
    );

    expect(draft.promoteFromAdditional(0), isTrue);
    expect(draft.main.map((f) => f.id), [1, 2, 4]);
    expect(draft.additional.map((f) => f.id), [3]);
  });

  test('promoteFromAdditional appends when main has room', () {
    final draft = FileArrangeDraft(
      main: [_file(1), _file(2)],
      additional: [_file(3)],
      layoutId: 'split',
    );

    expect(draft.promoteFromAdditional(0), isTrue);
    expect(draft.main.map((f) => f.id), [1, 2, 3]);
    expect(draft.additional, isEmpty);
  });

  test('demoteFromMain moves file to front of additional', () {
    final draft = FileArrangeDraft(
      main: [_file(1), _file(2)],
      additional: [_file(3)],
      layoutId: 'split',
    );

    expect(draft.demoteFromMain(1), isTrue);
    expect(draft.main.map((f) => f.id), [1]);
    expect(draft.additional.map((f) => f.id), [2, 3]);
  });

  test('setLayoutId does not mutate order', () {
    final draft = FileArrangeDraft(
      main: [_file(1), _file(2)],
      additional: [_file(3)],
      layoutId: 'split',
    );

    draft.setLayoutId('single');
    expect(draft.ordered.map((f) => f.id), [1, 2, 3]);
    expect(draft.layoutId, 'single');
  });
}
