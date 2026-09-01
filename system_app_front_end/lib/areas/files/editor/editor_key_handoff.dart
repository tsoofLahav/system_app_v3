import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// True while Flutter is tracking at least one physical key as down.
///
/// The HardwareKeyboard assertions are about **physical** keys, not logical.
bool hardwareKeysAreDown() =>
    HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty;

/// One frame later — layout / IME wiring after the tree has already settled.
///
/// Do **not** use this to mutate a focused editor while a key may still be
/// down. That is [runWhenKeyboardIdle]. Chrome that must not wait for KeyUp
/// (cycle files) runs immediately, not here.
void runNextFrame(VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) => action());
  // A post-frame callback does not schedule a frame. Enter/Esc with no
  // pointer motion would otherwise sit until the next unrelated paint.
  WidgetsBinding.instance.scheduleFrame();
}

/// The one gate for anything that can remount, unfocus, [FocusNode.requestFocus],
/// dispose, or notify a focused editor.
///
/// Flutter asserts when a KeyDown/KeyUp arrives and its pressed-key map
/// disagrees — usually because the focused [TextField] / [FocusNode] died or
/// focus moved **while a physical key was still down**.
///
/// - No physical key down → runs [action] now.
/// - A key is down → waits until every physical key is up, then one frame,
///   then [action]. If KeyUp is lost, waits at most 500ms.
///
/// Phone IME reports no physical keys, so this runs immediately. Do not remount
/// a [TextField] on IME; this helper cannot catch that.
///
/// **Every** path that can cause that desync must go through this function.
/// Exceptions: cycle-files chrome; layout-only [runNextFrame] IME wiring after
/// keys are already idle. Launch leftover keys:
/// `shared/utils/hardware_keyboard_guard.dart`.
void runWhenKeyboardIdle(VoidCallback action) {
  if (!hardwareKeysAreDown()) {
    action();
    return;
  }
  // Finish the current KeyDown dispatch before we arm the KeyUp wait.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!hardwareKeysAreDown()) {
      action();
      return;
    }
    _runAfterPhysicalKeysClear(action);
  });
  WidgetsBinding.instance.scheduleFrame();
}

/// Completes when [runWhenKeyboardIdle] would run its callback.
Future<void> whenKeyboardIdle() {
  if (!hardwareKeysAreDown()) return Future<void>.value();
  final ready = Completer<void>();
  runWhenKeyboardIdle(ready.complete);
  return ready.future;
}

/// Same as [runWhenKeyboardIdle]. Prefer that name in new code.
void runAfterKeystroke(VoidCallback action) => runWhenKeyboardIdle(action);

void _runAfterPhysicalKeysClear(VoidCallback action) {
  var finished = false;
  late final KeyEventCallback handler;
  Timer? timeout;

  void finish() {
    if (finished) return;
    finished = true;
    timeout?.cancel();
    HardwareKeyboard.instance.removeHandler(handler);
    runNextFrame(action);
  }

  handler = (KeyEvent event) {
    if (!hardwareKeysAreDown()) finish();
    return false;
  };
  HardwareKeyboard.instance.addHandler(handler);

  // Lost KeyUp (hot reload / platform glitch) — don't hang forever.
  timeout = Timer(const Duration(milliseconds: 500), finish);
}
