import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../ui/app_colors.dart';
import '../ui/app_typography.dart';
import '../ui/glass_surface.dart';

const compactUndoAutoClose = Duration(seconds: 8);

class CompactUndoChange {
  const CompactUndoChange({required this.op, required this.text});

  factory CompactUndoChange.fromJson(Map<String, dynamic> json) {
    return CompactUndoChange(
      op: json['op']?.toString() ?? 'change',
      text: json['text']?.toString() ?? '',
    );
  }

  final String op;
  final String text;
}

class CompactUndoCard {
  const CompactUndoCard({
    required this.fileId,
    required this.fileName,
    required this.topicId,
    required this.topicName,
    required this.oldDocumentJson,
    required this.changes,
  });

  factory CompactUndoCard.fromJson(Map<String, dynamic> json) {
    final raw = json['changes'];
    return CompactUndoCard(
      fileId: json['file_id'] as int? ?? 0,
      fileName: json['file_name']?.toString() ?? '',
      topicId: json['topic_id'] as int? ?? 0,
      topicName: json['topic_name']?.toString() ?? '',
      oldDocumentJson: json['old_document_json']?.toString() ?? '',
      changes: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => CompactUndoChange.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  final int fileId;
  final String fileName;
  final int topicId;
  final String topicName;
  final String oldDocumentJson;
  final List<CompactUndoChange> changes;
}

/// Collect undo cards from an agent run result (direct_apply only).
List<CompactUndoCard> undoCardsFromAgentResult(Map<dynamic, dynamic> result) {
  final changes = result['proposed_changes'];
  if (changes is! List) return const [];
  final cards = <CompactUndoCard>[];
  for (final c in changes) {
    if (c is! Map) continue;
    if (c['applied'] != true) continue;
    final undo = c['undo'];
    if (undo is! Map) continue;
    final card = CompactUndoCard.fromJson(Map<String, dynamic>.from(undo));
    if (card.fileId == 0 || card.oldDocumentJson.isEmpty) continue;
    cards.add(card);
  }
  return cards;
}

String compactUndoHeadline(AppStrings s, CompactUndoCard card) {
  return s.compactUndoInFile(card.fileName, card.topicName);
}

String compactUndoSummaryLine(AppStrings s, CompactUndoCard card) {
  final n = card.changes.length;
  if (n == 0) return s['aiAgentApplied'];
  if (n > 1) return s.compactUndoManyChanges(n);
  final c = card.changes.first;
  final quoted = '"${c.text}"';
  return switch (c.op) {
    'add' => s.compactUndoOneAdded(quoted),
    'remove' => s.compactUndoOneRemoved(quoted),
    _ => s.compactUndoOneEdited(quoted),
  };
}

String compactUndoDetailLine(AppStrings s, CompactUndoChange c) {
  final quoted = '"${c.text}"';
  return switch (c.op) {
    'add' => s.compactUndoOneAdded(quoted),
    'remove' => s.compactUndoOneRemoved(quoted),
    _ => s.compactUndoOneEdited(quoted),
  };
}

/// Show one toast per card; next opens when current closes (Undo / X / timeout).
Future<void> showCompactUndoQueue(
  BuildContext context,
  AppState state,
  List<CompactUndoCard> cards,
) async {
  for (final card in cards) {
    if (!context.mounted) return;
    await showCompactUndoToast(context, state, card);
  }
}

Future<void> showCompactUndoToast(
  BuildContext context,
  AppState state,
  CompactUndoCard card,
) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  final completer = Completer<void>();
  late OverlayEntry entry;

  void finish() {
    if (!completer.isCompleted) {
      entry.remove();
      completer.complete();
    }
  }

  entry = OverlayEntry(
    builder: (ctx) => _CompactUndoOverlay(
      card: card,
      strings: state.strings,
      onDismiss: finish,
      onUndo: () async {
        await state.undoDirectApply(
          fileId: card.fileId,
          oldDocumentJson: card.oldDocumentJson,
          topicId: card.topicId == 0 ? null : card.topicId,
        );
        finish();
      },
    ),
  );
  overlay.insert(entry);
  await completer.future;
}

class _CompactUndoOverlay extends StatefulWidget {
  const _CompactUndoOverlay({
    required this.card,
    required this.strings,
    required this.onDismiss,
    required this.onUndo,
  });

  final CompactUndoCard card;
  final AppStrings strings;
  final VoidCallback onDismiss;
  final Future<void> Function() onUndo;

  @override
  State<_CompactUndoOverlay> createState() => _CompactUndoOverlayState();
}

class _CompactUndoOverlayState extends State<_CompactUndoOverlay> {
  Timer? _timer;
  var _expanded = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(compactUndoAutoClose, () {
      if (!_busy) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _undo() async {
    if (_busy) return;
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      await widget.onUndo();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final card = widget.card;
    final many = card.changes.length > 1;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16 + bottom,
      child: Material(
        type: MaterialType.transparency,
        child: GlassSurface.styled(
          style: AppGlassStyle.floating,
          borderRadius: BorderRadius.circular(AppGlassStyle.floatingRadius),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            compactUndoHeadline(s, card),
                            style: AppTypography.metaStyle.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            compactUndoSummaryLine(s, card),
                            style: AppTypography.noteBodyStyle,
                            maxLines: _expanded ? null : 3,
                            overflow: _expanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: s['close'],
                      onPressed: _busy ? null : widget.onDismiss,
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
                if (many) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(
                        _expanded ? s['compactUndoHide'] : s['compactUndoShow'],
                      ),
                    ),
                  ),
                  if (_expanded)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 140),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: card.changes.length,
                        itemBuilder: (context, i) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              compactUndoDetailLine(s, card.changes[i]),
                              style: AppTypography.noteBodyStyle.copyWith(
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.tonal(
                    onPressed: _busy ? null : _undo,
                    child: Text(_busy ? s['aiRunning'] : s['undo']),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
