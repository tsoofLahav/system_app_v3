import 'package:flutter/material.dart';

import '../ui/app_colors.dart';
import '../ui/app_typography.dart';
import './change_review_dialog.dart';
import './pending_review_service.dart';

enum _HunkChoice { accept, reject }

final _fenceLineRe = RegExp(
  r'^\s*\[(TASK_LIST|INFO|TABLE|GRAPH|IMAGE|EMBED|SPACER)\b',
);

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

/// Aligned side-by-side row for the PR-style viewer.
class DiffViewRow {
  const DiffViewRow({
    this.oldText,
    this.newText,
    this.hunkId,
    this.op,
    this.hunkStart = false,
  });

  final String? oldText;
  final String? newText;
  final String? hunkId;
  final String? op;
  final bool hunkStart;

  bool get isChange => hunkId != null;
}

/// Build PR-style aligned rows from full texts + contiguous hunks.
List<DiffViewRow> buildSideBySideRows({
  required String oldText,
  required String newText,
  required List<PendingReviewHunk> hunks,
}) {
  List<String> splitlines(String t) {
    if (t.isEmpty) return [];
    final parts = t.split('\n');
    if (t.endsWith('\n') && parts.isNotEmpty && parts.last.isEmpty) {
      return parts.sublist(0, parts.length - 1);
    }
    return parts;
  }

  final old = splitlines(oldText);
  final neu = splitlines(newText);
  final rows = <DiffViewRow>[];
  var oi = 0;
  var ni = 0;

  for (final hunk in hunks) {
    final oldStart = hunk.oldIndex0;
    final newStart = hunk.newIndex0;
    while (oi < oldStart && ni < newStart && oi < old.length && ni < neu.length) {
      rows.add(DiffViewRow(oldText: old[oi], newText: neu[ni]));
      oi++;
      ni++;
    }
    // Drain any leftover equal on one side (should not happen with valid hunks).
    while (oi < oldStart && oi < old.length) {
      rows.add(DiffViewRow(oldText: old[oi], newText: null));
      oi++;
    }
    while (ni < newStart && ni < neu.length) {
      rows.add(DiffViewRow(oldText: null, newText: neu[ni]));
      ni++;
    }

    final oldSlice = old.sublist(
      hunk.oldIndex0.clamp(0, old.length),
      hunk.oldIndexEnd.clamp(0, old.length),
    );
    final newSlice = neu.sublist(
      hunk.newIndex0.clamp(0, neu.length),
      hunk.newIndexEnd.clamp(0, neu.length),
    );

    if (hunk.op == 'add') {
      for (var i = 0; i < newSlice.length; i++) {
        rows.add(
          DiffViewRow(
            oldText: null,
            newText: newSlice[i],
            hunkId: hunk.id,
            op: hunk.op,
            hunkStart: i == 0,
          ),
        );
      }
      ni = hunk.newIndexEnd;
    } else if (hunk.op == 'remove') {
      for (var i = 0; i < oldSlice.length; i++) {
        rows.add(
          DiffViewRow(
            oldText: oldSlice[i],
            newText: null,
            hunkId: hunk.id,
            op: hunk.op,
            hunkStart: i == 0,
          ),
        );
      }
      oi = hunk.oldIndexEnd;
    } else {
      final n = oldSlice.length > newSlice.length
          ? oldSlice.length
          : newSlice.length;
      for (var i = 0; i < n; i++) {
        rows.add(
          DiffViewRow(
            oldText: i < oldSlice.length ? oldSlice[i] : null,
            newText: i < newSlice.length ? newSlice[i] : null,
            hunkId: hunk.id,
            op: hunk.op,
            hunkStart: i == 0,
          ),
        );
      }
      oi = hunk.oldIndexEnd;
      ni = hunk.newIndexEnd;
    }
  }

  while (oi < old.length && ni < neu.length) {
    rows.add(DiffViewRow(oldText: old[oi], newText: neu[ni]));
    oi++;
    ni++;
  }
  while (oi < old.length) {
    rows.add(DiffViewRow(oldText: old[oi], newText: null));
    oi++;
  }
  while (ni < neu.length) {
    rows.add(DiffViewRow(oldText: null, newText: neu[ni]));
    ni++;
  }

  return rows;
}

/// Lookalike full-file side-by-side review. Every hunk must be decided.
class LookalikeReviewDialog {
  LookalikeReviewDialog._();

  static Future<bool?> show(
    BuildContext context, {
    required PendingReview pending,
    required Future<void> Function(List<Map<String, String>> decisions)
        onFinish,
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
  late final List<DiffViewRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = buildSideBySideRows(
      oldText: widget.pending.oldAgentText,
      newText: widget.pending.newAgentText,
      hunks: widget.pending.hunks,
    );
  }

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
            'choice':
                _choices[h.id] == _HunkChoice.accept ? 'accept' : 'reject',
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
    return ChangeReviewDialogShell(
      title: 'Review changes',
      maxWidth: 960,
      maxHeight: 640,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Current',
                  style: AppTypography.metaStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Suggested',
                  style: AppTypography.metaStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.noteTop,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.noteBorder),
              ),
              child: ListView.builder(
                itemCount: _rows.length,
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  return _DiffRowWidget(
                    row: row,
                    choice: row.hunkId == null ? null : _choices[row.hunkId],
                    onAccept: row.hunkId == null
                        ? null
                        : () => setState(
                              () => _choices[row.hunkId!] = _HunkChoice.accept,
                            ),
                    onReject: row.hunkId == null
                        ? null
                        : () => setState(
                              () => _choices[row.hunkId!] = _HunkChoice.reject,
                            ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffRowWidget extends StatelessWidget {
  const _DiffRowWidget({
    required this.row,
    required this.choice,
    required this.onAccept,
    required this.onReject,
  });

  final DiffViewRow row;
  final _HunkChoice? choice;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  Color? _sideColor({required bool isOld}) {
    if (row.hunkId == null) return null;
    final op = row.op;
    if (op == 'add') {
      return isOld ? null : AppColors.primary.withValues(alpha: 0.10);
    }
    if (op == 'remove') {
      return isOld ? AppColors.destructive.withValues(alpha: 0.10) : null;
    }
    // change
    if (isOld) return AppColors.destructive.withValues(alpha: 0.10);
    return AppColors.primary.withValues(alpha: 0.10);
  }

  @override
  Widget build(BuildContext context) {
    final showControls = row.hunkStart && row.hunkId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showControls)
          Container(
            color: AppColors.noteBottom.withValues(alpha: 0.85),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Text(
                  switch (row.op) {
                    'add' => 'Added',
                    'remove' => 'Removed',
                    _ => 'Changed',
                  },
                  style: AppTypography.metaStyle.copyWith(
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
          ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _LineCell(
                  text: row.oldText,
                  background: _sideColor(isOld: true),
                  compareTo: row.op == 'change' ? row.newText : null,
                  highlightRemoved: true,
                  decided: choice,
                ),
              ),
              Container(width: 1, color: AppColors.noteBorder),
              Expanded(
                child: _LineCell(
                  text: row.newText,
                  background: _sideColor(isOld: false),
                  compareTo: row.op == 'change' ? row.oldText : null,
                  highlightRemoved: false,
                  decided: choice,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineCell extends StatelessWidget {
  const _LineCell({
    required this.text,
    required this.background,
    required this.compareTo,
    required this.highlightRemoved,
    required this.decided,
  });

  final String? text;
  final Color? background;
  final String? compareTo;
  final bool highlightRemoved;
  final _HunkChoice? decided;

  @override
  Widget build(BuildContext context) {
    final borderColor = decided == null
        ? null
        : (decided == _HunkChoice.accept
            ? AppColors.primary.withValues(alpha: 0.35)
            : AppColors.textHint.withValues(alpha: 0.35));
    final line = text;
    final isFence = line != null && _fenceLineRe.hasMatch(line);

    Widget body;
    if (line == null) {
      body = const SizedBox(height: 18);
    } else if (isFence) {
      body = _FenceChrome(line: line);
    } else {
      body = Text.rich(
        wordDiffSpan(
          line,
          compareTo,
          highlightRemoved: highlightRemoved,
        ),
        style: AppTypography.noteBodyStyle.copyWith(height: 1.45),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: borderColor == null
            ? null
            : Border(
                left: BorderSide(color: borderColor, width: 2),
              ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: body,
      ),
    );
  }
}

class _FenceChrome extends StatelessWidget {
  const _FenceChrome({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.noteBottom.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.noteBorder.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          line,
          style: AppTypography.metaStyle.copyWith(
            color: AppColors.text,
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

/// Word-level marks using a simple LCS on whitespace-separated tokens.
TextSpan wordDiffSpan(
  String line,
  String? other, {
  required bool highlightRemoved,
}) {
  if (other == null) {
    return TextSpan(text: line.isEmpty ? ' ' : line);
  }
  final a = _tokenize(line);
  final b = _tokenize(other);
  final matchedA = _lcsMatchedIndices(a, b);
  final spans = <TextSpan>[];
  for (var i = 0; i < a.length; i++) {
    final token = a[i];
    final changed = !matchedA.contains(i) && token.trim().isNotEmpty;
    spans.add(
      TextSpan(
        text: token,
        style: changed
            ? TextStyle(
                backgroundColor: highlightRemoved
                    ? AppColors.destructive.withValues(alpha: 0.28)
                    : AppColors.primary.withValues(alpha: 0.28),
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
    );
  }
  if (spans.isEmpty) return const TextSpan(text: ' ');
  return TextSpan(children: spans);
}

List<String> _tokenize(String line) {
  // Keep whitespace tokens so layout stays readable.
  return line.split(RegExp(r'(?<=\s)|(?=\s)'));
}

Set<int> _lcsMatchedIndices(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  if (n == 0 || m == 0) return {};
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      if (a[i] == b[j]) {
        dp[i][j] = dp[i + 1][j + 1] + 1;
      } else {
        dp[i][j] =
            dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
      }
    }
  }
  final matched = <int>{};
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      matched.add(i);
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return matched;
}
