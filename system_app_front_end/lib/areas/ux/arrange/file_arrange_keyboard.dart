import '../layout/file_layouts.dart';

/// The bands of the arrange overlay: the files on screen, the files that
/// are not, and cancel / done.
enum ArrangeFocusZone { shown, hidden, actions }

ArrangeFocusZone moveArrangeFocusUp({
  required ArrangeFocusZone current,
  required bool hasHidden,
}) {
  return switch (current) {
    ArrangeFocusZone.actions =>
      hasHidden ? ArrangeFocusZone.hidden : ArrangeFocusZone.shown,
    ArrangeFocusZone.hidden => ArrangeFocusZone.shown,
    ArrangeFocusZone.shown => ArrangeFocusZone.actions,
  };
}

ArrangeFocusZone moveArrangeFocusDown({
  required ArrangeFocusZone current,
  required bool hasHidden,
}) {
  return switch (current) {
    ArrangeFocusZone.shown =>
      hasHidden ? ArrangeFocusZone.hidden : ArrangeFocusZone.actions,
    ArrangeFocusZone.hidden => ArrangeFocusZone.actions,
    ArrangeFocusZone.actions => ArrangeFocusZone.shown,
  };
}

/// Layouts the topic can pick with this many files in total.
///
/// Counted over every file, not just the shown ones: a layout with three slots
/// is a valid choice as soon as the topic has three files, whatever the current
/// layout happens to show.
List<String> enabledLayoutIds(int fileCount) {
  return [
    for (final layout in FileLayouts.all)
      if (FileLayouts.isAvailable(layout.id, fileCount)) layout.id,
  ];
}

int stepLayoutFocusIndex({
  required int currentIndex,
  required int layoutCount,
  required int delta,
}) {
  if (layoutCount <= 0) return 0;
  var next = (currentIndex + delta) % layoutCount;
  if (next < 0) next += layoutCount;
  return next;
}

int stepCarouselIndex({
  required int currentIndex,
  required int itemCount,
  required int delta,
}) {
  if (itemCount <= 0) return 0;
  return (currentIndex + delta).clamp(0, itemCount - 1);
}

enum ArrangeBottomFocusTarget { layout, cancel, done }

class ArrangeBottomFocus {
  const ArrangeBottomFocus._(this.target, this.layoutIndex);

  const ArrangeBottomFocus.layout(int layoutIndex)
    : this._(ArrangeBottomFocusTarget.layout, layoutIndex);

  const ArrangeBottomFocus.cancel()
    : this._(ArrangeBottomFocusTarget.cancel, -1);

  const ArrangeBottomFocus.done() : this._(ArrangeBottomFocusTarget.done, -1);

  final ArrangeBottomFocusTarget target;
  final int layoutIndex;

  ArrangeBottomFocus step({required int layoutCount, required int delta}) {
    final slotCount = layoutCount + 2;
    if (slotCount <= 0) return this;

    var slot = _toSlot(layoutCount);
    slot = (slot + delta) % slotCount;
    if (slot < 0) slot += slotCount;
    return _fromSlot(slot, layoutCount);
  }

  int _toSlot(int layoutCount) {
    return switch (target) {
      ArrangeBottomFocusTarget.layout => layoutIndex.clamp(
        0,
        layoutCount > 0 ? layoutCount - 1 : 0,
      ),
      ArrangeBottomFocusTarget.cancel => layoutCount,
      ArrangeBottomFocusTarget.done => layoutCount + 1,
    };
  }

  static ArrangeBottomFocus _fromSlot(int slot, int layoutCount) {
    if (slot < layoutCount) return ArrangeBottomFocus.layout(slot);
    if (slot == layoutCount) return const ArrangeBottomFocus.cancel();
    return const ArrangeBottomFocus.done();
  }

  static ArrangeBottomFocus forLayoutId(
    String layoutId,
    List<String> enabledLayoutIds,
  ) {
    final index = enabledLayoutIds.indexOf(layoutId);
    if (index < 0) return const ArrangeBottomFocus.layout(0);
    return ArrangeBottomFocus.layout(index);
  }
}

/// Maps arrow keys to spatial prev/next; mirrored in RTL so left/right follow
/// on-screen direction in Hebrew.
int spatialHorizontalDelta({required bool isRtl, required bool isLeftArrow}) {
  final logical = isLeftArrow ? -1 : 1;
  return isRtl ? -logical : logical;
}
