import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One frame later — default for Shift+Enter object enter/leave handoffs.
///
/// Prefer this over [runAfterKeystroke] when the key does not delete structure
/// mid-KeyDown. Waiting for keys to clear can stall up to 500ms.
void runNextFrame(VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) => action());
}

/// Runs [action] only after the current keystroke has fully settled.
///
/// Flutter's [HardwareKeyboard] asserts if a new [KeyDownEvent] arrives while
/// it still thinks that physical key is pressed. That desync happens when we
/// **unfocus / move caret / rebuild the editor mid-KeyDown** (Backspace that
/// deletes a structure, etc.): the field dies before the matching KeyUp is
/// delivered cleanly.
///
/// Use for destructive structure changes. For Shift+Enter focus handoff, use
/// [runNextFrame] instead.
///
/// See [`FLUENT_TEXT.md`](FLUENT_TEXT.md) § "Keystroke handoff".
void runAfterKeystroke(VoidCallback action) {
  var finished = false;

  void finish() {
    if (finished) return;
    finished = true;
    // One more frame so Focus/IME finish the KeyUp path before we hand off.
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  }

  void armWhenKeysClear() {
    if (HardwareKeyboard.instance.logicalKeysPressed.isEmpty) {
      finish();
      return;
    }

    late final KeyEventCallback handler;
    handler = (KeyEvent event) {
      if (HardwareKeyboard.instance.logicalKeysPressed.isEmpty) {
        HardwareKeyboard.instance.removeHandler(handler);
        finish();
      }
      return false;
    };
    HardwareKeyboard.instance.addHandler(handler);

    // Lost KeyUp (hot reload / platform glitch) — don't hang forever.
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      HardwareKeyboard.instance.removeHandler(handler);
      finish();
    });
  }

  // Let the current KeyDown finish dispatching first.
  WidgetsBinding.instance.addPostFrameCallback((_) => armWhenKeysClear());
}
