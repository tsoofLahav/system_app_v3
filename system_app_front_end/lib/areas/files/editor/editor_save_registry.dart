/// Mounted object text editors participate in navigation/AI save barriers.
/// Payloads remain object data; they are never expanded into the file body.
class EditorSaveRegistry {
  static final _flushers = <Object, Future<void> Function()>{};
  static void register(Object owner, Future<void> Function() flush) {
    _flushers[owner] = flush;
  }

  static void unregister(Object owner) => _flushers.remove(owner);
  static Future<void> flushAll() async {
    for (final flush in List<Future<void> Function()>.from(_flushers.values)) {
      await flush();
    }
  }
}
