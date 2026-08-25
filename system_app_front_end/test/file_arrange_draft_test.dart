import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';
import 'package:system_app_front_end/areas/ux/arrange/file_arrange_draft.dart';
import 'package:system_app_front_end/areas/ux/layout/file_layouts.dart';

AppFile _file(int id) => AppFile(id: id, topicId: 1, name: 'f$id');

FileArrangeDraft _draft(List<int> ids, String layoutId) => FileArrangeDraft(
  ordered: ids.map(_file).toList(),
  layoutId: layoutId,
);

List<int> _ids(List<AppFile> files) => files.map((f) => f.id).toList();

void main() {
  test('the layout decides how far down the order the screen reaches', () {
    expect(_ids(_draft([1, 2, 3, 4], FileLayouts.single).shown), [1]);
    expect(_ids(_draft([1, 2, 3, 4], FileLayouts.single).hidden), [2, 3, 4]);

    expect(_ids(_draft([1, 2, 3, 4], FileLayouts.heroLeft).shown), [1, 2, 3]);
    expect(_ids(_draft([1, 2, 3, 4], FileLayouts.heroLeft).hidden), [4]);

    expect(_ids(_draft([1, 2, 3, 4], FileLayouts.grid).shown), [1, 2, 3, 4]);
    expect(_draft([1, 2, 3, 4], FileLayouts.grid).hidden, isEmpty);
  });

  test('tapping a shown file makes it the first one', () {
    final draft = _draft([1, 2, 3], FileLayouts.heroLeft);
    expect(draft.moveShownToFirst(2), isTrue);
    expect(_ids(draft.ordered), [3, 1, 2]);
  });

  test('the first file is already first', () {
    final draft = _draft([1, 2, 3], FileLayouts.heroLeft);
    expect(draft.moveShownToFirst(0), isFalse);
    expect(_ids(draft.ordered), [1, 2, 3]);
  });

  test('showing a hidden file puts it first and pushes the last shown off', () {
    final draft = _draft([1, 2, 3, 4], FileLayouts.heroLeft);

    expect(draft.show(0), isTrue);

    expect(_ids(draft.shown), [4, 1, 2]);
    expect(_ids(draft.hidden), [3]);
  });

  test('hiding a shown file sends it to the end of the order', () {
    final draft = _draft([1, 2, 3, 4], FileLayouts.heroLeft);

    expect(draft.hide(0), isTrue);

    expect(_ids(draft.shown), [2, 3, 4]);
    expect(_ids(draft.hidden), [1]);
  });

  test('rotating cycles the shown files and leaves the hidden ones alone', () {
    final draft = _draft([1, 2, 3, 4], FileLayouts.heroLeft);

    expect(draft.rotateShownLeft(), isTrue);
    expect(_ids(draft.ordered), [2, 3, 1, 4]);

    expect(draft.rotateShownRight(), isTrue);
    expect(_ids(draft.ordered), [1, 2, 3, 4]);
  });

  test('one shown file has nothing to rotate', () {
    final draft = _draft([1, 2, 3], FileLayouts.single);
    expect(draft.rotateShownLeft(), isFalse);
    expect(_ids(draft.ordered), [1, 2, 3]);
  });

  test('choosing a smaller layout pushes files off screen, not away', () {
    final draft = _draft([1, 2, 3], FileLayouts.heroLeft);
    expect(draft.hidden, isEmpty);

    draft.setLayoutId(FileLayouts.single);

    expect(_ids(draft.shown), [1]);
    expect(_ids(draft.hidden), [2, 3]);
    expect(_ids(draft.ordered), [1, 2, 3]);
  });
}
