import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/features/arrange/file_arrange_keyboard.dart';

void main() {
  test('moveArrangeFocusUp walks layouts to main through additional', () {
    expect(
      moveArrangeFocusUp(
        current: ArrangeFocusZone.layouts,
        hasAdditional: true,
      ),
      ArrangeFocusZone.additional,
    );
    expect(
      moveArrangeFocusUp(
        current: ArrangeFocusZone.additional,
        hasAdditional: true,
      ),
      ArrangeFocusZone.main,
    );
    expect(
      moveArrangeFocusUp(
        current: ArrangeFocusZone.main,
        hasAdditional: true,
      ),
      ArrangeFocusZone.layouts,
    );
  });

  test('moveArrangeFocusDown skips additional when empty', () {
    expect(
      moveArrangeFocusDown(
        current: ArrangeFocusZone.main,
        hasAdditional: false,
      ),
      ArrangeFocusZone.layouts,
    );
    expect(
      moveArrangeFocusUp(
        current: ArrangeFocusZone.layouts,
        hasAdditional: false,
      ),
      ArrangeFocusZone.main,
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

  test('enabledLayoutIds respects main file count', () {
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
