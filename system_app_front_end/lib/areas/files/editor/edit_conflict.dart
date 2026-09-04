import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../objects/data/object_embed.dart';
import '../../objects/data/table_payload.dart';
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

  /// Both sides changed — file body 3-ways (lookalike on leftover overlaps);
  /// embed payloads still ask keep-yours / use-agent.
  ask,
}

enum EditConflictChoice { keepYours, useAgent }

/// Object ids with unsaved embed edits (graph cells, info text, …).
///
/// The open file asks only when a dirty embed's inbound payload moved — typing
/// in object A while the agent edits object B is not a file conflict.
class UnsavedEmbedEdits {
  UnsavedEmbedEdits._();

  static final Set<int> _objectIds = {};
  static final Map<int, String> _baselines = {};

  /// After the file-level dialog chooses "keep yours", embeds persist local
  /// over an already-applied agent cache instead of asking a second time.
  static var takeLocalOverInbound = false;

  /// File body conflict is already asking — embeds must not open a second dialog.
  static var fileConflictPending = false;

  static void mark(int objectId, bool dirty, {String? baselineKey}) {
    if (dirty) {
      _objectIds.add(objectId);
      if (baselineKey != null) _baselines[objectId] = baselineKey;
    } else {
      _objectIds.remove(objectId);
      _baselines.remove(objectId);
    }
  }

  static bool isDirty(int objectId) => _objectIds.contains(objectId);

  /// True when the agent wrote a payload for an object the user is still editing.
  static bool anyDirtyConflictsWith(Iterable<ObjectEmbed> inbound) {
    for (final embed in inbound) {
      if (!_objectIds.contains(embed.id)) continue;
      final baseline = _baselines[embed.id];
      if (baseline == null || embedConflictKey(embed) != baseline) {
        return true;
      }
    }
    return false;
  }
}

/// Snapshot used to tell "agent touched this object" from "agent touched another".
String embedConflictKey(ObjectEmbed embed) {
  switch (embed.type) {
    case 'info':
      final info = embed.information ?? const {};
      final meta = info['metadata'];
      final rawSpans = meta is Map ? meta['spans'] : null;
      final spans = rawSpans is List ? rawSpans : const [];
      return jsonEncode({
        'title': info['title'] as String? ?? '',
        'body': info['body'] as String? ?? '',
        'spans': spans,
      });
    case 'table':
    case 'graph':
      return jsonEncode(TableObjectPayload.normalize(embed.payload));
    default:
      return jsonEncode(embed.payload ?? const {});
  }
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
              onPressed: () => Navigator.pop(ctx, EditConflictChoice.keepYours),
              child: Text(strings['editConflictKeepYours']),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, EditConflictChoice.useAgent),
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
