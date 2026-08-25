import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_metrics.dart';

/// What to do with an inbound (agent / reload) edit vs live local state.
enum RemoteEditDecision {
  /// Already in sync, or inbound is just the last baseline (unsaved local).
  ignore,

  /// User did not change this content — take the inbound copy.
  takeRemote,

  /// Both sides changed — ask which version to keep.
  ask,
}

enum EditConflictChoice { keepYours, useAgent }

/// Object ids with unsaved embed edits (graph cells, info text, …).
///
/// The open file uses this so a document reload cannot throw away a dirty
/// graph without asking. Not a substitute for [decideRemoteEdit].
class UnsavedEmbedEdits {
  UnsavedEmbedEdits._();

  static final Set<int> _objectIds = {};

  /// After the file-level dialog chooses "keep yours", embeds persist local
  /// over an already-applied agent cache instead of asking a second time.
  static var takeLocalOverInbound = false;

  /// File body conflict is already asking — embeds must not open a second dialog.
  static var fileConflictPending = false;

  static void mark(int objectId, bool dirty) {
    if (dirty) {
      _objectIds.add(objectId);
    } else {
      _objectIds.remove(objectId);
    }
  }

  static bool anyOf(Iterable<int> objectIds) =>
      objectIds.any(_objectIds.contains);
}

RemoteEditDecision decideRemoteEdit({
  required bool localDirty,
  required bool inboundEqualsLocal,
  required bool inboundEqualsBaseline,
}) {
  if (inboundEqualsLocal) return RemoteEditDecision.ignore;
  if (inboundEqualsBaseline) return RemoteEditDecision.ignore;
  if (!localDirty) return RemoteEditDecision.takeRemote;
  return RemoteEditDecision.ask;
}

bool jsonEquals(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

/// Must choose — barrier dismiss would silently pick a side.
Future<EditConflictChoice> showEditConflictDialog({
  required BuildContext context,
  required AppStrings strings,
}) async {
  final answer = await showAppDialog<EditConflictChoice>(
    context: context,
    isDismissible: false,
    builder: (ctx) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            Navigator.pop(ctx, EditConflictChoice.useAgent),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            Navigator.pop(ctx, EditConflictChoice.useAgent),
      },
      child: Focus(
        autofocus: true,
        child: AppAdaptiveDialogShell(
          title: Text(strings['editConflictTitle']),
          width: AppDialogMetrics.maxWidth,
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, EditConflictChoice.keepYours),
              child: Text(strings['editConflictKeepYours']),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, EditConflictChoice.useAgent),
              child: Text(strings['editConflictUseAgent']),
            ),
          ],
          child: Text(
            strings['editConflictBody'],
            style: AppTypography.noteBodyStyle.copyWith(
              fontSize: 12,
              color: AppColors.text.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    ),
  );
  return answer ?? EditConflictChoice.useAgent;
}
