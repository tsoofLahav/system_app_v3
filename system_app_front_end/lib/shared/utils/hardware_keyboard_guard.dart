import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter seeds [HardwareKeyboard] from the engine on startup / hot restart
/// (`syncKeyboardState`). The next [KeyDownEvent] for those keys then asserts
/// `physical key is already pressed` and loops.
///
/// Do **not** call [HardwareKeyboard.clearState] — that also wipes key
/// handlers (shortcuts, link clicks). Synthesize KeyUp instead.
///
/// See [`NOTES.md` § Editor keyboard safety](../../../NOTES.md#editor-keyboard-safety).

var _guardInstalled = false;

/// True when Flutter's HardwareKeyboard pressed-key map disagrees with the
/// event just delivered (the looping debug assertion).
bool isHardwareKeyboardDesync(Object exception) {
  final text = exception.toString();
  return text.contains('physical key is already pressed') ||
      text.contains('physical key is not pressed');
}

/// Drops every key Flutter currently thinks is down.
///
/// Safe while the loading pane is on screen — the user cannot type yet.
void releaseTrackedHardwareKeys() {
  final keyboard = HardwareKeyboard.instance;
  final snapshot = <PhysicalKeyboardKey, LogicalKeyboardKey>{
    for (final physical in keyboard.physicalKeysPressed)
      if (keyboard.lookUpLayout(physical) != null)
        physical: keyboard.lookUpLayout(physical)!,
  };
  if (snapshot.isEmpty) return;
  for (final entry in snapshot.entries) {
    try {
      keyboard.handleKeyEvent(
        KeyUpEvent(
          physicalKey: entry.key,
          logicalKey: entry.value,
          timeStamp: Duration.zero,
          synthesized: true,
        ),
      );
    } catch (_) {}
  }
}

/// Wait until Flutter's own startup sync has run, then drop the seeded keys.
///
/// Binding attaches the real key handler only after `syncKeyboardState`
/// completes — we sync+release twice so a late seed cannot survive into the
/// editor.
Future<void> settleHardwareKeyboardForLaunch() async {
  Future<void> once() async {
    try {
      await HardwareKeyboard.instance.syncKeyboardState();
    } catch (_) {}
    releaseTrackedHardwareKeys();
  }

  await once();
  await Future<void>.delayed(Duration.zero);
  await once();
}

/// Catch the assertion if a seed still leaks, so one bad KeyDown cannot loop.
///
/// Call once from `main` after [WidgetsFlutterBinding.ensureInitialized].
void installHardwareKeyboardGuard() {
  if (_guardInstalled) return;
  _guardInstalled = true;
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (isHardwareKeyboardDesync(details.exception) &&
        details.exception.toString().contains('already pressed')) {
      releaseTrackedHardwareKeys();
    }
    (previous ?? FlutterError.presentError)(details);
  };
}
