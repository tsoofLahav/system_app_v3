/// Visual horizontal caret motion in RTL — part of the [RTL solution](RTL.md).
///
/// A Flutter text field moves the caret **through the string**, so in Hebrew the
/// left arrow walks backwards on screen. This flips horizontal motion intents
/// and hands them back to the field's own action so Flutter still performs the
/// move (key repeat, graphemes, shift-extend intact).
///
/// Flip only when the **run at the caret** is RTL. European numbers and Latin
/// inside a Hebrew paragraph paint LTR — flipping those would walk the wrong
/// way, which is what Super Editor already avoids.
///
/// Use via [wrapVisualCaretMotion] in `rtl.dart`. The wrap is always present
/// (same tree shape).
library;

import 'package:flutter/widgets.dart';

/// Flips a horizontal motion intent when [shouldFlip] is true.
class _FlipIfNeeded<T extends DirectionalTextEditingIntent> extends Action<T> {
  _FlipIfNeeded(this._flip, this._shouldFlip);

  final T Function(T intent) _flip;
  final bool Function() _shouldFlip;

  @override
  Object? invoke(T intent) {
    final next = _shouldFlip() ? _flip(intent) : intent;
    return callingAction?.invoke(next);
  }

  @override
  bool isEnabled(T intent) => callingAction?.isEnabled(intent) ?? false;

  @override
  bool consumesKey(T intent) => callingAction?.consumesKey(intent) ?? false;
}

/// Action overrides that turn logical caret movement into visual movement.
///
/// Only horizontal intents are flipped, and only when [shouldFlip] is true
/// (RTL glyph run). Vertical movement and Cmd+Up/Down are unaffected.
/// Cmd+Left/Right / Home / End are intentionally not flipped (shared
/// intents — see [RTL.md](RTL.md)).
Map<Type, Action<Intent>> rtlCaretMotionActions({
  required bool Function() shouldFlip,
}) => <Type, Action<Intent>>{
  ExtendSelectionByCharacterIntent:
      _FlipIfNeeded<ExtendSelectionByCharacterIntent>(
        (intent) => ExtendSelectionByCharacterIntent(
          forward: !intent.forward,
          collapseSelection: intent.collapseSelection,
        ),
        shouldFlip,
      ),
  ExtendSelectionToNextWordBoundaryIntent:
      _FlipIfNeeded<ExtendSelectionToNextWordBoundaryIntent>(
        (intent) => ExtendSelectionToNextWordBoundaryIntent(
          forward: !intent.forward,
          collapseSelection: intent.collapseSelection,
        ),
        shouldFlip,
      ),
  ExtendSelectionToNextWordBoundaryOrCaretLocationIntent:
      _FlipIfNeeded<ExtendSelectionToNextWordBoundaryOrCaretLocationIntent>(
        (intent) => ExtendSelectionToNextWordBoundaryOrCaretLocationIntent(
          forward: !intent.forward,
        ),
        shouldFlip,
      ),
};
