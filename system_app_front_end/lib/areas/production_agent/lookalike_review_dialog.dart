import 'package:flutter/material.dart';

import '../ui/app_colors.dart';
import '../ui/app_typography.dart';
import './change_review_dialog.dart';
import './pending_review_service.dart';

enum _HunkChoice { accept, reject }

/// True when every hunk has accept or reject (empty list counts as decided).
bool pendingHunksFullyDecided(
  Iterable<String> hunkIds,
  Map<String, String> choices,
) {
  return hunkIds.every((id) {
    final c = choices[id];
    return c == 'accept' || c == 'reject';
  });
}

/// Lookalike per-hunk review. Every hunk must be accepted or rejected.
class LookalikeReviewDialog {
  LookalikeReviewDialog._();

  static Future<bool?> show(
    BuildContext context, {
    required PendingReview pending,
    required Future<void> Function(List<Map<String, String>> decisions) onFinish,
    required Future<void> Function() onDiscard,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LookalikeReviewBody(
        pending: pending,
        onFinish: onFinish,
        onDiscard: onDiscard,
      ),
    );
  }
}

class _LookalikeReviewBody extends StatefulWidget {
  const _LookalikeReviewBody({
    required this.pending,
    required this.onFinish,
    required this.onDiscard,
  });

  final PendingReview pending;
  final Future<void> Function(List<Map<String, String>> decisions) onFinish;
  final Future<void> Function() onDiscard;

  @override
  State<_LookalikeReviewBody> createState() => _LookalikeReviewBodyState();
}

class _LookalikeReviewBodyState extends State<_LookalikeReviewBody> {
  final Map<String, _HunkChoice> _choices = {};
  var _busy = false;

  bool get _allDecided => pendingHunksFullyDecided(
        widget.pending.hunks.map((h) => h.id),
        {
          for (final e in _choices.entries)
            e.key: e.value == _HunkChoice.accept ? 'accept' : 'reject',
        },
      );

  Future<void> _finish() async {
    if (!_allDecided || _busy) return;
    setState(() => _busy = true);
    try {
      final decisions = [
        for (final h in widget.pending.hunks)
          {
            'hunk_id': h.id,
            'choice': _choices[h.id] == _HunkChoice.accept ? 'accept' : 'reject',
          },
      ];
      await widget.onFinish(decisions);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _discard() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onDiscard();
      if (mounted) Navigator.pop(context, false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hunks = widget.pending.hunks;
    return ChangeReviewDialogShell(
      title: 'Review changes',
      actions: [
        TextButton(
          onPressed: _busy ? null : _discard,
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: _allDecided && !_busy ? _finish : null,
          child: Text(_busy ? 'Saving…' : 'Finish'),
        ),
      ],
      child: hunks.isEmpty
          ? const Text('No line changes to review.')
          : ListView.separated(
              itemCount: hunks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final hunk = hunks[index];
                final choice = _choices[hunk.id];
                return _HunkCard(
                  hunk: hunk,
                  choice: choice,
                  onAccept: () => setState(() => _choices[hunk.id] = _HunkChoice.accept),
                  onReject: () => setState(() => _choices[hunk.id] = _HunkChoice.reject),
                );
              },
            ),
    );
  }
}

class _HunkCard extends StatelessWidget {
  const _HunkCard({
    required this.hunk,
    required this.choice,
    required this.onAccept,
    required this.onReject,
  });

  final PendingReviewHunk hunk;
  final _HunkChoice? choice;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final opLabel = switch (hunk.op) {
      'add' => 'Added',
      'remove' => 'Removed',
      _ => 'Changed',
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.noteTop,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: choice == null
              ? AppColors.noteBorder
              : (choice == _HunkChoice.accept
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.textHint.withValues(alpha: 0.5)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  opLabel,
                  style: AppTypography.metaStyle.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onReject,
                  child: Text(
                    'Reject',
                    style: TextStyle(
                      color: choice == _HunkChoice.reject
                          ? AppColors.primary
                          : AppColors.textHint,
                    ),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (hunk.oldLines.isNotEmpty)
              _LineBlock(
                label: 'Before',
                lines: hunk.oldLines,
                background: AppColors.destructive.withValues(alpha: 0.08),
                compareTo: hunk.op == 'change' ? hunk.newLines : null,
                showAsOld: true,
              ),
            if (hunk.newLines.isNotEmpty) ...[
              if (hunk.oldLines.isNotEmpty) const SizedBox(height: 6),
              _LineBlock(
                label: 'After',
                lines: hunk.newLines,
                background: AppColors.primary.withValues(alpha: 0.08),
                compareTo: hunk.op == 'change' ? hunk.oldLines : null,
                showAsOld: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineBlock extends StatelessWidget {
  const _LineBlock({
    required this.label,
    required this.lines,
    required this.background,
    this.compareTo,
    required this.showAsOld,
  });

  final String label;
  final List<String> lines;
  final Color background;
  final List<String>? compareTo;
  final bool showAsOld;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: AppTypography.metaStyle),
            const SizedBox(height: 4),
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text.rich(
                  _wordDiffSpan(
                    lines[i],
                    compareTo != null && i < compareTo!.length
                        ? compareTo![i]
                        : null,
                    highlightRemoved: showAsOld,
                  ),
                  style: AppTypography.noteBodyStyle.copyWith(
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

TextSpan _wordDiffSpan(
  String line,
  String? other, {
  required bool highlightRemoved,
}) {
  if (other == null || other.isEmpty) {
    return TextSpan(text: line.isEmpty ? '·' : line);
  }
  final a = line.split(RegExp(r'(\s+)'));
  final b = other.split(RegExp(r'(\s+)'));
  // Simple LCS-ish mark: tokens in this line not in other get emphasis.
  final otherSet = b.toSet();
  final spans = <TextSpan>[];
  for (final token in a) {
    if (token.isEmpty) continue;
    final changed = token.trim().isNotEmpty && !otherSet.contains(token);
    spans.add(
      TextSpan(
        text: token,
        style: changed
            ? TextStyle(
                backgroundColor: highlightRemoved
                    ? AppColors.destructive.withValues(alpha: 0.25)
                    : AppColors.primary.withValues(alpha: 0.25),
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
    );
  }
  return TextSpan(children: spans);
}
