/// Visual horizontal caret motion in RTL — part of the [RTL solution](RTL.md).
///
/// A Flutter text field moves the caret **through the string**, so in Hebrew the
/// left arrow walks backwards on screen. This flips horizontal motion intents
/// and hands them back to the field's own action so Flutter still performs the
/// move (key repeat, graphemes, shift-extend intact).
///
/// Use via [wrapVisualCaretMotion] in `rtl.dart`. The wrap is always present
/// (same tree shape); flip actions apply only when the field is RTL.
library;

import 'package:flutter/widgets.dart';

/// Flips a horizontal motion intent and hands it back to the editor's own action.
class _FlipDirection<T extends DirectionalTextEditingIntent> extends Action<T> {
  _FlipDirection(this._flip);

  final T Function(T intent) _flip;

  @override
  Object? invoke(T intent) => callingAction?.invoke(_flip(intent));

  @override
  bool isEnabled(T intent) => callingAction?.isEnabled(intent) ?? false;

  @override
  bool consumesKey(T intent) => callingAction?.consumesKey(intent) ?? false;
}

/// Action overrides that turn logical caret movement into visual movement.
///
/// Only horizontal intents are flipped. Vertical movement and Cmd+Up/Down are
/// unaffected. Cmd+Left/Right / Home / End are intentionally not flipped (shared
/// intents — see [RTL.md](RTL.md)).
Map<Type, Action<Intent>> rtlCaretMotionActions() => <Type, Action<Intent>>{
      ExtendSelectionByCharacterIntent:
          _FlipDirection<ExtendSelectionByCharacterIntent>(
        (intent) => ExtendSelectionByCharacterIntent(
          forward: !intent.forward,
          collapseSelection: intent.collapseSelection,
        ),
      ),
      ExtendSelectionToNextWordBoundaryIntent:
          _FlipDirection<ExtendSelectionToNextWordBoundaryIntent>(
        (intent) => ExtendSelectionToNextWordBoundaryIntent(
          forward: !intent.forward,
          collapseSelection: intent.collapseSelection,
        ),
      ),
      ExtendSelectionToNextWordBoundaryOrCaretLocationIntent:
          _FlipDirection<ExtendSelectionToNextWordBoundaryOrCaretLocationIntent>(
        (intent) => ExtendSelectionToNextWordBoundaryOrCaretLocationIntent(
          forward: !intent.forward,
        ),
      ),
    };
