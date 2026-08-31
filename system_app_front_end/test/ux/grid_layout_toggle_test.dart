import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ux/layout/file_layouts.dart';
import 'package:system_app_front_end/areas/ux/layout/grid_layout_toggle.dart';

void main() {
  test('from any other layout goes to grid and remembers the stored id', () {
    final peek = GridLayoutPeek();
    expect(
      peek.take(
        topicId: 1,
        storedLayout: FileLayouts.auto,
        shownLayout: FileLayouts.hero,
      ),
      FileLayouts.grid,
    );
    expect(peek.topicId, 1);
    expect(peek.returnLayout, FileLayouts.auto);
  });

  test('on grid restores the peeked layout and forgets', () {
    final peek = GridLayoutPeek();
    peek.take(
      topicId: 1,
      storedLayout: FileLayouts.split,
      shownLayout: FileLayouts.split,
    );
    expect(
      peek.take(
        topicId: 1,
        storedLayout: FileLayouts.grid,
        shownLayout: FileLayouts.grid,
      ),
      FileLayouts.split,
    );
    expect(peek.topicId, isNull);
    expect(peek.returnLayout, isNull);
  });

  test('on grid with no peek falls back to auto', () {
    final peek = GridLayoutPeek();
    expect(
      peek.take(
        topicId: 1,
        storedLayout: FileLayouts.grid,
        shownLayout: FileLayouts.grid,
      ),
      FileLayouts.auto,
    );
  });

  test('a peeked grid restores as auto, not grid', () {
    final peek = GridLayoutPeek();
    peek.take(
      topicId: 1,
      storedLayout: FileLayouts.grid,
      shownLayout: FileLayouts.single,
    );
    expect(
      peek.take(
        topicId: 1,
        storedLayout: FileLayouts.grid,
        shownLayout: FileLayouts.grid,
      ),
      FileLayouts.auto,
    );
  });

  test('leaving the topic forgets; another topic cannot restore', () {
    final peek = GridLayoutPeek();
    peek.take(
      topicId: 1,
      storedLayout: FileLayouts.hero,
      shownLayout: FileLayouts.hero,
    );
    peek.forgetIfLeft(2);
    expect(peek.topicId, isNull);
    expect(
      peek.take(
        topicId: 2,
        storedLayout: FileLayouts.grid,
        shownLayout: FileLayouts.grid,
      ),
      FileLayouts.auto,
    );
  });

  test('staying on the same topic keeps the peek', () {
    final peek = GridLayoutPeek();
    peek.take(
      topicId: 1,
      storedLayout: FileLayouts.auto,
      shownLayout: FileLayouts.hero,
    );
    peek.forgetIfLeft(1);
    expect(peek.topicId, 1);
    expect(
      peek.take(
        topicId: 1,
        storedLayout: FileLayouts.grid,
        shownLayout: FileLayouts.grid,
      ),
      FileLayouts.auto,
    );
  });
}
