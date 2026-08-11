/// Visual ←/→ caret motion in Super Editor — part of the [RTL solution](RTL.md).
///
/// SE maps arrowLeft → upstream (string offset−−). In Hebrew that walks the
/// wrong way on screen. Mirror [rtl_caret_motion.dart]: when the caret node's
/// resolved direction is RTL, swap left↔right for character and word moves.
///
/// Not flipped (same gap as FormattedTextField): Cmd+arrow / line / Home / End.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import './paragraph_text_direction.dart';

/// True when the extent node's text resolves to RTL (first strong / ambient).
bool isSuperEditorCaretRtl(
  SuperEditorContext editContext,
  TextDirection ambient,
) {
  final selection = editContext.composer.selection;
  if (selection == null) return ambient == TextDirection.rtl;
  final node = editContext.document.getNodeById(selection.extent.nodeId);
  if (node is! TextNode) return ambient == TextDirection.rtl;
  final dir =
      detectParagraphTextDirection(node.text.toPlainText()) ?? ambient;
  return dir == TextDirection.rtl;
}

/// Keyboard action: visual ←/→ when the caret paragraph is RTL.
///
/// Runs ahead of SE's [moveLeftAndRightWithArrowKeys] (plugin actions prepend).
ExecutionInstruction moveVisuallyLeftAndRightWithArrowKeys({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
  required TextDirection ambient,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  const arrowKeys = [
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  ];
  if (!arrowKeys.contains(keyEvent.logicalKey)) {
    return ExecutionInstruction.continueExecution;
  }

  if (!isSuperEditorCaretRtl(editContext, ambient)) {
    return ExecutionInstruction.continueExecution;
  }

  if (kIsWeb && editContext.composer.composingRegion.value != null) {
    return ExecutionInstruction.blocked;
  }

  if (defaultTargetPlatform == TargetPlatform.windows &&
      HardwareKeyboard.instance.isAltPressed) {
    return ExecutionInstruction.continueExecution;
  }

  final isApple = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // Cmd+arrow = line — leave unflipped (RTL.md known gap).
  if (isApple && HardwareKeyboard.instance.isMetaPressed) {
    return ExecutionInstruction.continueExecution;
  }

  MovementModifier? movementModifier;
  if ((defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux) &&
      HardwareKeyboard.instance.isControlPressed) {
    movementModifier = MovementModifier.word;
  } else if (isApple && HardwareKeyboard.instance.isAltPressed) {
    movementModifier = MovementModifier.word;
  }

  // Visual left in RTL = logical downstream.
  final visualLeft = keyEvent.logicalKey == LogicalKeyboardKey.arrowLeft;
  final didMove = visualLeft
      ? editContext.commonOps.moveCaretDownstream(
          expand: HardwareKeyboard.instance.isShiftPressed,
          movementModifier: movementModifier,
        )
      : editContext.commonOps.moveCaretUpstream(
          expand: HardwareKeyboard.instance.isShiftPressed,
          movementModifier: movementModifier,
        );

  return didMove
      ? ExecutionInstruction.haltExecution
      : ExecutionInstruction.continueExecution;
}

/// Selector names whose left/right pair should swap under RTL.
const _horizontalSelectorPairs = <String, String>{
  MacOsSelectors.moveLeft: MacOsSelectors.moveRight,
  MacOsSelectors.moveRight: MacOsSelectors.moveLeft,
  MacOsSelectors.moveBackward: MacOsSelectors.moveForward,
  MacOsSelectors.moveForward: MacOsSelectors.moveBackward,
  MacOsSelectors.moveWordLeft: MacOsSelectors.moveWordRight,
  MacOsSelectors.moveWordRight: MacOsSelectors.moveWordLeft,
  MacOsSelectors.moveLeftAndModifySelection:
      MacOsSelectors.moveRightAndModifySelection,
  MacOsSelectors.moveRightAndModifySelection:
      MacOsSelectors.moveLeftAndModifySelection,
  MacOsSelectors.moveWordLeftAndModifySelection:
      MacOsSelectors.moveWordRightAndModifySelection,
  MacOsSelectors.moveWordRightAndModifySelection:
      MacOsSelectors.moveWordLeftAndModifySelection,
};

/// Wraps [base] so horizontal left/right selectors are visual when the caret
/// paragraph is RTL. Line / Home / End selectors stay logical.
Map<String, SuperEditorSelectorHandler> withVisualHorizontalSelectors({
  required Map<String, SuperEditorSelectorHandler> base,
  required TextDirection ambient,
}) {
  final out = Map<String, SuperEditorSelectorHandler>.from(base);
  for (final entry in _horizontalSelectorPairs.entries) {
    final leftName = entry.key;
    final rightName = entry.value;
    final original = base[leftName];
    final swapped = base[rightName];
    if (original == null || swapped == null) continue;
    out[leftName] = (ctx) {
      if (isSuperEditorCaretRtl(ctx, ambient)) {
        swapped(ctx);
      } else {
        original(ctx);
      }
    };
  }
  return out;
}

/// Plugin that installs the visual ←/→ keyboard action.
class SuperEditorVisualCaretPlugin extends SuperEditorPlugin {
  SuperEditorVisualCaretPlugin({required this.ambient});

  /// Updated each build from [Directionality.of].
  TextDirection ambient;

  @override
  List<SuperEditorKeyboardAction> get keyboardActions => [
        ({required editContext, required keyEvent}) =>
            moveVisuallyLeftAndRightWithArrowKeys(
              editContext: editContext,
              keyEvent: keyEvent,
              ambient: ambient,
            ),
      ];
}
