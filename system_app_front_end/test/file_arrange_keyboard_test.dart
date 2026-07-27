import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ux/arrange/file_arrange_keyboard.dart';

void main() {
  test('moveArrangeFocusUp walks layouts to shown through hidden', () {
    expect(
      moveArrangeFocusUp(current: ArrangeFocusZone.layouts, hasHidden: true),
      ArrangeFocusZone.hidden,
    );
    expect(
      moveArrangeFocusUp(current: ArrangeFocusZone.hidden, hasHidden: true),
      ArrangeFocusZone.shown,
    );
    expect(
      moveArrangeFocusUp(current: ArrangeFocusZone.shown, hasHidden: true),
      ArrangeFocusZone.layouts,
    );
  });

  test('moveArrangeFocusDown skips the hidden band when nothing is hidden', () {
    expect(
      moveArrangeFocusDown(current: ArrangeFocusZone.shown, hasHidden: false),
      ArrangeFocusZone.layouts,
    );
    expect(
      moveArrangeFocusUp(current: ArrangeFocusZone.layouts, hasHidden: false),
      ArrangeFocusZone.shown,
    );
  });

  test('stepLayoutFocusIndex wraps around enabled layouts', () {
    expect(
      stepLayoutFocusIndex(currentIndex: 0, layoutCount: 3, delta: -1),
      2,
    );
    expect(
      stepLayoutFocusIndex(currentIndex: 2, layoutCount: 3, delta: 1),
      0,
    );
  });

  test('enabledLayoutIds respects how many files the topic has', () {
    expect(enabledLayoutIds(1), ['single', 'row', 'grid']);
    expect(enabledLayoutIds(2), contains('split'));
    expect(enabledLayoutIds(3), contains('hero_left'));
  });

  test('bottom bar focus steps left into done and cancel', () {
    const focus = ArrangeBottomFocus.layout(0);
    final done = focus.step(layoutCount: 3, delta: -1);
    expect(done.target, ArrangeBottomFocusTarget.done);

    final cancel = done.step(layoutCount: 3, delta: -1);
    expect(cancel.target, ArrangeBottomFocusTarget.cancel);

    final lastLayout = cancel.step(layoutCount: 3, delta: -1);
    expect(lastLayout.target, ArrangeBottomFocusTarget.layout);
    expect(lastLayout.layoutIndex, 2);
  });

  test('bottom bar focus steps right from last layout into cancel', () {
    const focus = ArrangeBottomFocus.layout(2);
    final cancel = focus.step(layoutCount: 3, delta: 1);
    expect(cancel.target, ArrangeBottomFocusTarget.cancel);

    final done = cancel.step(layoutCount: 3, delta: 1);
    expect(done.target, ArrangeBottomFocusTarget.done);
  });

  test('spatialHorizontalDelta mirrors arrows in RTL', () {
    expect(spatialHorizontalDelta(isRtl: false, isLeftArrow: true), -1);
    expect(spatialHorizontalDelta(isRtl: false, isLeftArrow: false), 1);
    expect(spatialHorizontalDelta(isRtl: true, isLeftArrow: true), 1);
    expect(spatialHorizontalDelta(isRtl: true, isLeftArrow: false), -1);
  });
}
