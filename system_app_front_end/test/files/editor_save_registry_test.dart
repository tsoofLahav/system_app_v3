import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/editor_save_registry.dart';

void main() {
  test('barrier awaits an object write and propagates its failure', () async {
    final owner = Object();
    final pending = Completer<void>();
    EditorSaveRegistry.register(owner, () => pending.future);
    try {
      final barrier = EditorSaveRegistry.flushAll();
      final checked = expectLater(barrier, throwsStateError);
      pending.completeError(StateError('offline'));
      await checked;
    } finally {
      EditorSaveRegistry.unregister(owner);
    }
    await EditorSaveRegistry.flushAll();
  });
}
