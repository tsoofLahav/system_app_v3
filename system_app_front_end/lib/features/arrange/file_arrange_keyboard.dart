import '../../design_system/file_layouts.dart';

enum ArrangeFocusZone {
  main,
  additional,
  layouts,
}

ArrangeFocusZone moveArrangeFocusUp({
  required ArrangeFocusZone current,
  required bool hasAdditional,
}) {
  return switch (current) {
    ArrangeFocusZone.layouts => hasAdditional
        ? ArrangeFocusZone.additional
        : ArrangeFocusZone.main,
    ArrangeFocusZone.additional => ArrangeFocusZone.main,
    ArrangeFocusZone.main => ArrangeFocusZone.layouts,
  };
}

ArrangeFocusZone moveArrangeFocusDown({
  required ArrangeFocusZone current,
  required bool hasAdditional,
}) {
  return switch (current) {
    ArrangeFocusZone.main => hasAdditional
        ? ArrangeFocusZone.additional
        : ArrangeFocusZone.layouts,
    ArrangeFocusZone.additional => ArrangeFocusZone.layouts,
    ArrangeFocusZone.layouts => ArrangeFocusZone.main,
  };
}

List<String> enabledLayoutIds(int mainCount) {
  return [
    for (final layout in FileLayouts.all)
      if (FileLayouts.isAvailable(layout.id, mainCount)) layout.id,
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

enum ArrangeBottomFocusTarget {
  layout,
  cancel,
  done,
}

class ArrangeBottomFocus {
  const ArrangeBottomFocus._(this.target, this.layoutIndex);

  const ArrangeBottomFocus.layout(int layoutIndex)
      : this._(ArrangeBottomFocusTarget.layout, layoutIndex);

  const ArrangeBottomFocus.cancel()
      : this._(ArrangeBottomFocusTarget.cancel, -1);

  const ArrangeBottomFocus.done()
      : this._(ArrangeBottomFocusTarget.done, -1);

  final ArrangeBottomFocusTarget target;
  final int layoutIndex;

  ArrangeBottomFocus step({
    required int layoutCount,
    required int delta,
  }) {
    final slotCount = layoutCount + 2;
    if (slotCount <= 0) return this;

    var slot = _toSlot(layoutCount);
    slot = (slot + delta) % slotCount;
    if (slot < 0) slot += slotCount;
    return _fromSlot(slot, layoutCount);
  }

  int _toSlot(int layoutCount) {
    return switch (target) {
      ArrangeBottomFocusTarget.layout =>
        layoutIndex.clamp(0, layoutCount > 0 ? layoutCount - 1 : 0),
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
int spatialHorizontalDelta({
  required bool isRtl,
  required bool isLeftArrow,
}) {
  final logical = isLeftArrow ? -1 : 1;
  return isRtl ? -logical : logical;
}
