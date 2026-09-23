import 'dart:async';

/// Coalesces object autosave/flush requests and identifies our own cache echo.
/// A pending snapshot is not a server baseline: failure must not acknowledge it.
class ObjectSaveQueue {
  Future<void>? _running;
  String? _pendingKey;

  bool isLocalEcho(String key) => _pendingKey == key;

  Future<void> flush({
    required bool Function() needsSave,
    required String Function() capture,
    required Future<void> Function(String snapshot) write,
    required void Function(String snapshot) acknowledge,
  }) {
    if (_running != null) return _running!;
    final done = Completer<void>();
    _running = done.future;
    () async {
      try {
        while (needsSave()) {
          final snapshot = capture();
          // Register before write: the optimistic cache can notify immediately.
          _pendingKey = snapshot;
          await write(snapshot);
          acknowledge(snapshot);
          _pendingKey = null;
        }
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        _pendingKey = null;
        _running = null;
      }
    }();
    return done.future;
  }
}
