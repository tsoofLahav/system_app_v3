import 'dart:async';
import 'dart:convert';
import '../../../core/services/api_service.dart';
import '../data/task.dart';

bool sameTaskValue(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

Map<String, dynamic> taskSaveFields(Task task) => {
  'title': task.title,
  'title_spans': task.titleSpans,
  'status': task.status,
  'due_date': task.dueDate,
};

Task applyTaskFields(Task task, Map<String, dynamic> patch, {int? revision}) =>
    task.copyWith(
      title: patch['title'] as String?,
      titleSpans: (patch['title_spans'] as List?)?.cast<Map<String, dynamic>>(),
      status: patch['status'] as String?,
      dueDate: patch['due_date'] as String?,
      clearDueDate: patch.containsKey('due_date') && patch['due_date'] == null,
      revision: revision,
    );

class PendingTaskOrder {
  PendingTaskOrder(this.write, this.rebase);
  final Future<void> Function() write;
  final void Function() rebase;
}

class TaskOrderConflict implements Exception {
  TaskOrderConflict(this.key);
  final String key;
}

class TaskSaveConflict implements Exception {
  TaskSaveConflict(this.taskId);
  final int taskId;
}

/// Session-owned drafts. Acknowledgements remove only the values actually sent;
/// typing/clicks during the request remain queued. Failures retain the draft.
class TaskSaveQueue {
  TaskSaveQueue({
    required Task baseline,
    required this.read,
    required this.write,
    required this.publish,
  }) : _baseline = baseline;

  Task _baseline;
  final Future<Task> Function() read;
  final Future<Task> Function(Map<String, dynamic> patch, int revision) write;
  final void Function(Task draft, Set<String> fields) publish;
  final Map<String, dynamic> _pending = {};
  final Set<String> _ownedFields = {};
  Future<void>? _running;
  bool _uncertain = false;
  Map<String, dynamic> _lastSent = {};
  Object? error;

  bool get dirty => _pending.isNotEmpty;
  bool get saving => _running != null;
  Task get draft => applyTaskFields(_baseline, _pending);

  void observe(Task remote) {
    if (dirty || saving || remote.revision < _baseline.revision) return;
    _baseline = remote;
  }

  Future<void> edit(Map<String, dynamic> patch) {
    _ownedFields.addAll(patch.keys);
    _pending.addAll(patch);
    publish(draft, Set.of(_ownedFields));
    return flush();
  }

  Future<void> flush() {
    if (_running != null) return _running!;
    if (!dirty) return Future.value();
    final completion = Completer<void>();
    _running = completion.future;
    () async {
      try {
        while (dirty) {
          if (_uncertain || _baseline.revision == 0) {
            await _reconcile(await read());
            _uncertain = false;
            if (!dirty) break;
          }
          final sent = Map<String, dynamic>.of(_pending);
          Task saved;
          try {
            _lastSent = sent;
            saved = await write(sent, _baseline.revision);
          } on ApiException catch (e) {
            if (e.statusCode != 409) rethrow;
            await _reconcile(await read());
            // One safe rebase for non-overlapping changes, never an endless loop.
            if (!dirty) break;
            final retry = Map<String, dynamic>.of(_pending);
            _lastSent = retry;
            saved = await write(retry, _baseline.revision);
            _acknowledge(saved, retry);
            continue;
          } on TimeoutException {
            _uncertain = true;
            await _reconcile(await read());
            if (dirty) rethrow;
            break;
          }
          _acknowledge(saved, sent);
        }
        error = null;
        _ownedFields.clear();
        completion.complete();
      } catch (e, stack) {
        _uncertain = true;
        error = e;
        completion.completeError(e, stack);
      } finally {
        _running = null;
      }
    }();
    return completion.future;
  }

  Future<void> _reconcile(Task remote) async {
    final base = taskSaveFields(_baseline), current = taskSaveFields(remote);
    for (final entry in _pending.entries.toList()) {
      if (sameTaskValue(current[entry.key], entry.value)) {
        _pending.remove(entry.key);
      } else if (!sameTaskValue(current[entry.key], base[entry.key]) &&
          !(_lastSent.containsKey(entry.key) &&
              sameTaskValue(current[entry.key], _lastSent[entry.key]))) {
        throw TaskSaveConflict(remote.id);
      }
    }
    _baseline = remote;
    publish(draft, Set.of(_ownedFields));
  }

  void _acknowledge(Task saved, Map<String, dynamic> sent) {
    for (final entry in sent.entries) {
      if (sameTaskValue(_pending[entry.key], entry.value))
        _pending.remove(entry.key);
    }
    _baseline = saved;
    _uncertain = false;
    publish(draft, Set.of(_ownedFields));
  }

  /// Explicit user decision after a conflict; still uses the latest revision.
  Future<void> resolve({required bool keepLocal}) async {
    if (saving) await _running;
    final remote = await read();
    _baseline = remote;
    if (!keepLocal) _pending.clear();
    _uncertain = false;
    error = null;
    publish(draft, Set.of(_ownedFields));
    if (!dirty) _ownedFields.clear();
    await flush();
  }
}
