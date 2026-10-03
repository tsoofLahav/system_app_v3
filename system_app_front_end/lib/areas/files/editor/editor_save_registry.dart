/// Mounted object text editors participate in navigation/AI save barriers.
/// Payloads remain object data; they are never expanded into the file body.
class EditorSaveRegistry {
  static final _flushers = <Object, Future<void> Function()>{};
  static final _objectIds = <Object, int>{};
  static void register(
    Object owner,
    Future<void> Function() flush, {
    int? objectId,
  }) {
    if (objectId != null) _objectIds[owner] = objectId;
    _flushers[owner] = flush;
  }

  static void unregister(Object owner) {
    _flushers.remove(owner);
    _objectIds.remove(owner);
  }

  static Future<void> flushObject(int objectId) async {
    for (final entry in List.of(_flushers.entries)) {
      if (_objectIds[entry.key] == objectId) await entry.value();
    }
  }

  static Future<void> flushAll() async {
    for (final flush in List<Future<void> Function()>.from(_flushers.values)) {
      await flush();
    }
  }
}
