import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';
import 'package:system_app_front_end/areas/ux/arrange/file_arrange_draft.dart';
import 'package:system_app_front_end/areas/ux/layout/file_layouts.dart';

AppFile _file(int id) => AppFile(id: id, topicId: 1, name: 'f$id');

FileArrangeDraft _draft(List<int> ids, String layoutId) =>
    FileArrangeDraft(ordered: ids.map(_file).toList(), layoutId: layoutId);

List<int> _ids(List<AppFile> files) => files.map((f) => f.id).toList();

void main() {
  test('the layout decides how far down the order the screen reaches', () {
    expect(_ids(_draft([1, 2, 3, 4], FileLayouts.single).shown), [1]);
    expect(_ids(_draft([1, 2, 3, 4], FileLayouts.single).hidden), [2, 3, 4]);

    expect(_ids(_draft([1, 2, 3, 4], FileLayouts.hero).shown), [1, 2, 3]);
    expect(_ids(_draft([1, 2, 3, 4], FileLayouts.hero).hidden), [4]);
    expect(_ids(_draft([1, 2, 3, 4], FileLayouts.heroLeft).shown), [1, 2, 3]);

    expect(_ids(_draft([1, 2, 3, 4], FileLayouts.grid).shown), [1, 2, 3, 4]);
    expect(_draft([1, 2, 3, 4], FileLayouts.grid).hidden, isEmpty);
  });

  test('move places a file at the requested final index', () {
    final draft = _draft([1, 2, 3, 4], FileLayouts.hero);
    expect(draft.move(3, 0), isTrue);
    expect(_ids(draft.ordered), [4, 1, 2, 3]);
  });

  test('moving a hidden file above the cut makes it shown', () {
    final draft = _draft([1, 2, 3, 4], FileLayouts.hero);
    expect(_ids(draft.shown), [1, 2, 3]);
    expect(_ids(draft.hidden), [4]);

    expect(draft.move(3, 1), isTrue);

    expect(_ids(draft.ordered), [1, 4, 2, 3]);
    expect(_ids(draft.shown), [1, 4, 2]);
    expect(_ids(draft.hidden), [3]);
  });

  test('moving a shown file past the cut takes it off screen', () {
    final draft = _draft([1, 2, 3, 4], FileLayouts.hero);
    expect(draft.move(0, 3), isTrue);
    expect(_ids(draft.shown), [2, 3, 4]);
    expect(_ids(draft.hidden), [1]);
  });

  test('move is a no-op when the index does not change', () {
    final draft = _draft([1, 2, 3], FileLayouts.hero);
    expect(draft.move(1, 1), isFalse);
    expect(_ids(draft.ordered), [1, 2, 3]);
  });

  test('move rejects an out-of-range from index', () {
    final draft = _draft([1, 2], FileLayouts.split);
    expect(draft.move(-1, 0), isFalse);
    expect(draft.move(2, 0), isFalse);
    expect(_ids(draft.ordered), [1, 2]);
  });

  test('choosing a smaller layout pushes files off screen, not away', () {
    final draft = _draft([1, 2, 3], FileLayouts.hero);
    expect(draft.hidden, isEmpty);

    draft.setLayoutId(FileLayouts.single);

    expect(_ids(draft.shown), [1]);
    expect(_ids(draft.hidden), [2, 3]);
    expect(_ids(draft.ordered), [1, 2, 3]);
  });
}
