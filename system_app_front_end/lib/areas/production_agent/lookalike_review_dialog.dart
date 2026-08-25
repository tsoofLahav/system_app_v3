import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/platform/app_form_factor.dart';
import '../files/editor/file_preview.dart';
import '../files/editor/read_only_document_view.dart';
import '../files/model/agent_text_blocks.dart';
import '../ui/app_colors.dart';
import '../ui/app_icons.dart';
import '../ui/app_typography.dart';
import '../ui/dialog_metrics.dart';
import '../ui/glass_surface.dart';
import '../ui/note_widgets.dart';
import './agent_message_snackbar.dart';
import './pending_review_service.dart';
import './review_marks.dart';

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

/// Side-by-side review of a pending proposal: the file as it is, the file as
/// the agent suggests it, and one bubble walking the changes between them.
class LookalikeReviewDialog {
  LookalikeReviewDialog._();

  static Future<bool?> show(
    BuildContext context, {
    required PendingReview pending,
    required AppStrings strings,
    required Future<void> Function(List<Map<String, String>> decisions) onFinish,
    required Future<void> Function() onDiscard,
    String? fileName,
    Color? topicAccent,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LookalikeReviewBody(
        pending: pending,
        strings: strings,
        onFinish: onFinish,
        onDiscard: onDiscard,
        fileName: fileName,
        topicAccent: topicAccent,
      ),
    );
  }
}

class _LookalikeReviewBody extends StatefulWidget {
  const _LookalikeReviewBody({
    required this.pending,
    required this.strings,
    required this.onFinish,
    required this.onDiscard,
    this.fileName,
    this.topicAccent,
  });

  final PendingReview pending;
  final AppStrings strings;
  final Future<void> Function(List<Map<String, String>> decisions) onFinish;
  final Future<void> Function() onDiscard;
  final String? fileName;
  final Color? topicAccent;

  @override
  State<_LookalikeReviewBody> createState() => _LookalikeReviewBodyState();
}

const _gutterWidth = 72.0;
const _bubbleHeight = 82.0;

class _LookalikeReviewBodyState extends State<_LookalikeReviewBody> {
  final Map<String, ReviewChoice> _choices = {};
  final _bodyKey = GlobalKey();
  final _oldScroll = ScrollController();
  final _newScroll = ScrollController();

  late final List<AgentBlock> _oldBlocks;
  late final List<AgentBlock> _newBlocks;
  late final Map<int, HunkMark> _oldMarks;
  late final Map<int, HunkMark> _newMarks;
  late final Map<int, String> _oldAnchorLines;
  late final Map<int, String> _newAnchorLines;
  late final Map<String, GlobalKey> _oldKeys;
  late final Map<String, GlobalKey> _newKeys;
  late final Map<int, String> _oldCompare;
  late final Map<int, String> _newCompare;

  String? _activeId;
  double? _bubbleTop;
  var _busy = false;
  var _phoneShowCurrent = true;

  /// Set when the last change is decided: the bubble steps aside and Finish
  /// takes over. Touching any change brings it back so a choice can be flipped.
  var _bubbleStoodDown = false;

  List<PendingReviewHunk> get _hunks => widget.pending.hunks;

  @override
  void initState() {
    super.initState();
    _oldBlocks = parseAgentTextBlocks(widget.pending.oldAgentText);
    _newBlocks = parseAgentTextBlocks(widget.pending.newAgentText);
    _oldMarks = hunkMarksByLine(_hunks, oldSide: true);
    _newMarks = hunkMarksByLine(_hunks, oldSide: false);
    _oldAnchorLines = _anchorLines(_oldBlocks, oldSide: true);
    _newAnchorLines = _anchorLines(_newBlocks, oldSide: false);
    _oldKeys = {for (final h in _hunks) h.id: GlobalKey()};
    _newKeys = {for (final h in _hunks) h.id: GlobalKey()};
    final (oldCompare, newCompare) = _compareLines();
    _oldCompare = oldCompare;
    _newCompare = newCompare;
    _activeId = _hunks.isEmpty ? null : _hunks.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncToActive());
  }

  @override
  void dispose() {
    _oldScroll.dispose();
    _newScroll.dispose();
    super.dispose();
  }

  /// Where each hunk's bubble anchor lives on one side.
  ///
  /// A hunk can start on a line that is never drawn on its own — a `DONE:`
  /// header, a closing fence, a blank line inside an embed — so the anchor
  /// snaps to the first drawn element inside the hunk, else the one above it.
  Map<int, String> _anchorLines(List<AgentBlock> blocks, {required bool oldSide}) {
    final drawn = _drawnLines(blocks);
    final anchors = <int, String>{};
    for (final hunk in _hunks) {
      final start = oldSide ? hunk.oldIndex0 : hunk.newIndex0;
      final end = oldSide ? hunk.oldIndexEnd : hunk.newIndexEnd;
      if (start >= end) continue;
      var line = drawn.firstWhere(
        (l) => l >= start && l < end,
        orElse: () => -1,
      );
      if (line < 0) {
        line = drawn.lastWhere((l) => l <= start, orElse: () => -1);
      }
      if (line < 0) continue;
      anchors.putIfAbsent(line, () => hunk.id);
    }
    return anchors;
  }

  /// Ascending start lines of everything the read-only view draws.
  List<int> _drawnLines(List<AgentBlock> blocks) {
    final lines = <int>{};
    for (final block in blocks) {
      lines.add(block.lineStart);
      switch (block) {
        case AgentListBlock():
          lines.addAll(block.items.map((i) => i.line));
        case AgentTaskListBlock():
          lines.addAll(block.tasks.map((t) => t.line));
        case AgentTableBlock():
          lines.addAll(block.rows.map((r) => r.line));
        case AgentInfoBlock():
          if (block.titleLine >= 0) lines.add(block.titleLine);
          lines.addAll(block.bodyLines.map((b) => b.line));
        case _:
          break;
      }
    }
    return lines.toList()..sort();
  }

  /// Counterpart text per line, so a changed line can carry word marks.
  ///
  /// Table and graph rows are left out: they are split into cells before they
  /// are drawn, and the row tint already says which row moved.
  (Map<int, String>, Map<int, String>) _compareLines() {
    final rowLines = <int>{
      for (final block in [..._oldBlocks, ..._newBlocks])
        if (block is AgentTableBlock)
          for (final row in block.rows) row.line
        else if (block is AgentGraphBlock)
          for (var l = block.lineStart; l <= block.lineEnd; l++) l,
    };
    final oldCompare = <int, String>{};
    final newCompare = <int, String>{};
    for (final hunk in _hunks) {
      if (hunk.op != 'change') continue;
      final pairs = hunk.oldLines.length < hunk.newLines.length
          ? hunk.oldLines.length
          : hunk.newLines.length;
      for (var k = 0; k < pairs; k++) {
        final oldLine = hunk.oldIndex0 + k;
        final newLine = hunk.newIndex0 + k;
        if (!rowLines.contains(oldLine)) {
          oldCompare[oldLine] = _stripLeadMarker(hunk.newLines[k]);
        }
        if (!rowLines.contains(newLine)) {
          newCompare[newLine] = _stripLeadMarker(hunk.oldLines[k]);
        }
      }
    }
    return (oldCompare, newCompare);
  }

  LineDecoration _decorate(int lineStart, int lineEnd, {required bool oldSide}) {
    final anchorId =
        (oldSide ? _oldAnchorLines : _newAnchorLines)[lineStart];
    final anchorKey =
        anchorId == null ? null : (oldSide ? _oldKeys : _newKeys)[anchorId];
    final compare =
        lineStart == lineEnd ? (oldSide ? _oldCompare : _newCompare)[lineStart] : null;
    final spanFor = compare == null
        ? null
        : (String text) =>
            wordDiffSpan(text, compare, highlightRemoved: oldSide);

    final mark = markForRange(
      oldSide ? _oldMarks : _newMarks,
      lineStart,
      lineEnd,
    );
    if (mark == null) {
      if (anchorKey == null && spanFor == null) return LineDecoration.none;
      return LineDecoration(
        anchorKey: anchorKey,
        spanFor: spanFor,
        onTap: anchorId == null ? null : () => _activate(anchorId),
      );
    }
    return decorationForChange(
      mark: mark,
      state: changeStateFor(
        hunkId: mark.hunkId,
        activeHunkId: _activeId,
        choices: _choices,
      ),
      oldSide: oldSide,
      anchorKey: anchorKey,
      onTap: () => _activate(mark.hunkId),
      spanFor: spanFor,
    );
  }

  void _activate(String hunkId) {
    if (_activeId == hunkId && !_bubbleStoodDown) return;
    setState(() {
      _activeId = hunkId;
      _bubbleStoodDown = false;
    });
    _syncToActive();
  }

  void _decide(ReviewChoice choice) {
    final active = _activeId;
    if (active == null) return;
    setState(() {
      _choices[active] = choice;
      _activeId = nextUndecidedHunkId(_hunks, _choices, fromId: active) ?? active;
      _bubbleStoodDown = _allDecided;
    });
    _syncToActive();
  }

  /// Move the bubble by [delta] changes, decided or not.
  void _step(int delta) {
    if (_hunks.isEmpty) return;
    final at = _hunks.indexWhere((h) => h.id == _activeId);
    final next = (at < 0 ? 0 : at + delta).clamp(0, _hunks.length - 1);
    _activate(_hunks[next].id);
  }

  Future<void> _syncToActive() async {
    final id = _activeId;
    if (id == null) return;
    await Future.wait([
      _revealIn(_oldKeys[id]),
      _revealIn(_newKeys[id]),
    ]);
    if (mounted) _placeBubble();
  }

  Future<void> _revealIn(GlobalKey? key) async {
    final ctx = key?.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.4,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Park the bubble beside the active change, in the gutter's own space.
  void _placeBubble() {
    final id = _activeId;
    final body = _bodyKey.currentContext?.findRenderObject();
    if (id == null || body is! RenderBox || !body.hasSize) return;
    final anchor = (_newKeys[id]?.currentContext ??
            _oldKeys[id]?.currentContext)
        ?.findRenderObject();
    final limit = (body.size.height - _bubbleHeight).clamp(0.0, double.infinity);
    // With nothing to measure the bubble still shows, centred — the reviewer
    // must always be able to accept or reject.
    if (anchor is! RenderBox || !anchor.hasSize) {
      final centred = limit / 2;
      if (_bubbleTop != centred) setState(() => _bubbleTop = centred);
      return;
    }
    final dy = anchor.localToGlobal(Offset.zero, ancestor: body).dy;
    final top =
        (dy + anchor.size.height / 2 - _bubbleHeight / 2).clamp(0.0, limit);
    if (_bubbleTop != top) setState(() => _bubbleTop = top);
  }

  bool get _allDecided => pendingHunksFullyDecided(
        _hunks.map((h) => h.id),
        {
          for (final e in _choices.entries)
            e.key: e.value == ReviewChoice.accept ? 'accept' : 'reject',
        },
      );

  Future<void> _finish() async {
    if (!_allDecided || _busy) return;
    setState(() => _busy = true);
    try {
      final decisions = [
        for (final h in _hunks)
          {
            'hunk_id': h.id,
            'choice':
                _choices[h.id] == ReviewChoice.accept ? 'accept' : 'reject',
          },
      ];
      await widget.onFinish(decisions);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAgentMessageSnackBar(context, '$e');
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
      showAgentMessageSnackBar(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final size = MediaQuery.sizeOf(context);
    final phone = isPhoneLayout;
    final inset = phone
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 12)
        : AppDialogMetrics.windowInset;

    // No text fields live here, so raw key handling is safe (see NOTES.md).
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            _decide(ReviewChoice.accept),
        const SingleActivator(LogicalKeyboardKey.backspace): () =>
            _decide(ReviewChoice.reject),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _step(-1),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: inset,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: phone ? double.infinity : 1040,
              maxHeight: phone
                  ? size.height - inset.vertical
                  : (size.height - inset.vertical < 720
                      ? size.height - inset.vertical
                      : 720),
            ),
            child: GlassSurface.styled(
              style: AppGlassStyle.dialog,
              borderRadius: BorderRadius.circular(AppGlassStyle.dialogRadius),
              padding: phone
                  ? const EdgeInsets.fromLTRB(10, 10, 10, 8)
                  : AppDialogMetrics.padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(s),
                  const SizedBox(height: AppDialogMetrics.titleGap),
                  if (phone) ...[
                    _phoneSideToggle(s),
                    const SizedBox(height: 8),
                  ],
                  Expanded(child: phone ? _phonePane(s) : _panes(s)),
                  if (phone) ...[
                    const SizedBox(height: 8),
                    _phoneHunkBar(s),
                  ],
                  const SizedBox(height: AppDialogMetrics.actionsGap),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : _discard,
                        child: Text(s['reviewDiscard']),
                      ),
                      const SizedBox(width: 8),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: _allDecided && !_busy
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.45),
                                    blurRadius: 16,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : const [],
                        ),
                        child: FilledButton(
                          onPressed: _allDecided && !_busy ? _finish : null,
                          child: Text(
                            _busy ? s['reviewSaving'] : s['reviewFinish'],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneSideToggle(AppStrings s) {
    return SegmentedButton<bool>(
      segments: [
        ButtonSegment(value: true, label: Text(s['reviewPaneCurrent'])),
        ButtonSegment(value: false, label: Text(s['reviewPaneSuggested'])),
      ],
      selected: {_phoneShowCurrent},
      onSelectionChanged: (next) {
        setState(() => _phoneShowCurrent = next.first);
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncToActive());
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          AppTypography.metaStyle.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _phonePane(AppStrings s) {
    if (_hunks.isEmpty) {
      return Center(
        child: Text(s['reviewNoChanges'], style: AppTypography.metaStyle),
      );
    }
    return _pane(
      label: '',
      blocks: _phoneShowCurrent ? _oldBlocks : _newBlocks,
      controller: _phoneShowCurrent ? _oldScroll : _newScroll,
      oldSide: _phoneShowCurrent,
    );
  }

  Widget _phoneHunkBar(AppStrings s) {
    if (_hunks.isEmpty || _activeId == null) {
      return const SizedBox.shrink();
    }
    final index = _hunks.indexWhere((h) => h.id == _activeId) + 1;
    return Row(
      children: [
        Text(
          s.reviewCounter(index, _hunks.length),
          style: AppTypography.metaStyle,
        ),
        const Spacer(),
        _bubbleButton(
          tooltip: s['reviewAccept'],
          icon: AppIcons.check,
          color: AppColors.primary,
          selected: _choices[_activeId] == ReviewChoice.accept,
          onTap: () => _decide(ReviewChoice.accept),
        ),
        const SizedBox(width: 8),
        _bubbleButton(
          tooltip: s['reviewReject'],
          icon: AppIcons.close,
          color: AppColors.textHint,
          selected: _choices[_activeId] == ReviewChoice.reject,
          onTap: () => _decide(ReviewChoice.reject),
        ),
      ],
    );
  }

  Widget _header(AppStrings s) {
    final decided = _choices.length;
    return Row(
      children: [
        Text(
          s['reviewChanges'],
          style: AppTypography.noteTitleStyle.copyWith(
            fontSize: 13.5,
            color: AppColors.text.withValues(alpha: 0.94),
          ),
        ),
        if ((widget.fileName ?? '').isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.fileName!,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.metaStyle,
            ),
          ),
        ],
        const Spacer(),
        Text(
          s.reviewDecidedCount(decided, _hunks.length),
          style: AppTypography.metaStyle,
        ),
      ],
    );
  }

  Widget _panes(AppStrings s) {
    if (_hunks.isEmpty) {
      return Center(child: Text(s['reviewNoChanges'], style: AppTypography.metaStyle));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _placeBubble();
        });
        return false;
      },
      child: Stack(
        key: _bodyKey,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _pane(
                  label: s['reviewPaneCurrent'],
                  blocks: _oldBlocks,
                  controller: _oldScroll,
                  oldSide: true,
                ),
              ),
              const SizedBox(width: _gutterWidth),
              Expanded(
                child: _pane(
                  label: s['reviewPaneSuggested'],
                  blocks: _newBlocks,
                  controller: _newScroll,
                  oldSide: false,
                ),
              ),
            ],
          ),
          _bubble(s),
        ],
      ),
    );
  }

  Widget _pane({
    required String label,
    required List<AgentBlock> blocks,
    required ScrollController controller,
    required bool oldSide,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              label,
              style: AppTypography.metaStyle.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.text.withValues(alpha: 0.75),
              ),
            ),
          ),
        Expanded(
          child: NoteCard(
            topicAccent: widget.topicAccent,
            fileId: widget.topicAccent == null ? null : widget.pending.fileId,
            child: SingleChildScrollView(
              controller: controller,
              padding: AppSpacing.notePadding,
              child: FilePreview(
                blocks: blocks,
                decorate: (start, end) =>
                    _decorate(start, end, oldSide: oldSide),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubble(AppStrings s) {
    final top = _bubbleTop;
    if (top == null || _activeId == null || _bubbleStoodDown) {
      return const SizedBox.shrink();
    }
    final index = _hunks.indexWhere((h) => h.id == _activeId) + 1;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      top: top,
      left: 0,
      right: 0,
      height: _bubbleHeight,
      child: Center(
        child: SizedBox(
          width: _gutterWidth - 4,
          child: GlassSurface.styled(
            style: AppGlassStyle.floating,
            borderRadius: BorderRadius.circular(AppGlassStyle.floatingRadius),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.reviewCounter(index, _hunks.length),
                  style: AppTypography.metaStyle.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _bubbleButton(
                      tooltip: s['reviewAccept'],
                      icon: AppIcons.check,
                      color: AppColors.primary,
                      selected: _choices[_activeId] == ReviewChoice.accept,
                      onTap: () => _decide(ReviewChoice.accept),
                    ),
                    const SizedBox(width: 4),
                    _bubbleButton(
                      tooltip: s['reviewReject'],
                      icon: AppIcons.close,
                      color: AppColors.textHint,
                      selected: _choices[_activeId] == ReviewChoice.reject,
                      onTap: () => _decide(ReviewChoice.reject),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubbleButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: selected ? 0.22 : 0.10),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, size: 15, color: color),
          ),
        ),
      ),
    );
  }
}

/// Drop a leading list or task marker so word marks compare like with like.
String _stripLeadMarker(String line) {
  return line.replaceFirst(
    RegExp(r'^\s*(?:-\s*\[[ xX]\]\s*|[-*]\s+|\d+[.)]\s+)'),
    '',
  );
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
        dp[i][j] = dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
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
