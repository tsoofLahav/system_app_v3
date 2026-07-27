/// Making the caret follow the arrow key on screen in right-to-left text.
///
/// A Flutter text field moves the caret **through the string**, so in Hebrew the
/// left arrow walks backwards on screen and the right arrow forwards — the
/// opposite of where the keys point.
///
/// Rather than intercept key events, this reconfigures the editor: it overrides
/// the motion *intents* the text field dispatches and flips their direction, so
/// Flutter still performs the move itself. Key repeat, selection extension,
/// grapheme clusters and platform differences all keep working, because none of
/// that is reimplemented here.
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
/// Only horizontal intents are flipped. Vertical movement and the document
/// boundary intents (Cmd+Up/Down) are unaffected by text direction.
///
/// Wrap a text field in `Actions(actions: rtlCaretMotionActions(), child: ...)`
/// **only when the direction is RTL** — in LTR the editor's own behavior is
/// already correct.
Map<Type, Action<Intent>> rtlCaretMotionActions() => <Type, Action<Intent>>{
      // Left / Right, with or without Shift.
      ExtendSelectionByCharacterIntent:
          _FlipDirection<ExtendSelectionByCharacterIntent>(
        (intent) => ExtendSelectionByCharacterIntent(
          forward: !intent.forward,
          collapseSelection: intent.collapseSelection,
        ),
      ),
      // Alt+Left / Alt+Right word jumps.
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
