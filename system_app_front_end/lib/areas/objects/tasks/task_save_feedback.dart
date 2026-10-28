import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/app_state.dart';
import 'task_save_queue.dart';

Future<void> showTaskSaveError(
  BuildContext context,
  AppState state,
  Object error,
  Future<void> Function() retry,
) async {
  if (!context.mounted) return;
  final s = state.strings;
  if (error is TaskSaveConflict || error is TaskOrderConflict) {
    final keep = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s['taskSaveConflict']),
        content: Text(s['taskSaveConflictBody']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s['taskUseServer']),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s['taskKeepMine']),
          ),
        ],
      ),
    );
    if (keep == null) return;
    try {
      if (error is TaskSaveConflict) {
        await state.resolveTaskSave(error.taskId, keepLocal: keep);
      } else if (error is TaskOrderConflict) {
        await state.resolveOrderSave(error.key, keepLocal: keep);
      }
    } catch (next) {
      if (context.mounted) await showTaskSaveError(context, state, next, retry);
    }
    return;
  }
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(s['taskSaveFailed']),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: s['retry'],
        onPressed: () async {
          try {
            await retry();
          } catch (next) {
            if (context.mounted)
              await showTaskSaveError(context, state, next, retry);
          }
        },
      ),
    ),
  );
}

Future<void> navigateAfterTaskSaves(
  BuildContext context,
  AppState state,
  Future<void> Function() navigate,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? saving;
  final timer = Timer(const Duration(milliseconds: 300), () {
    if (!context.mounted) return;
    saving = messenger?.showSnackBar(
      SnackBar(
        duration: const Duration(minutes: 2),
        content: Text(state.strings['taskSaving']),
      ),
    );
  });
  Object? failure;
  try {
    await navigate();
  } catch (e) {
    failure = e;
  } finally {
    timer.cancel();
    saving?.close();
  }
  if (failure != null && context.mounted) {
    await showTaskSaveError(
      context,
      state,
      failure,
      () => navigateAfterTaskSaves(context, state, navigate),
    );
  }
}
