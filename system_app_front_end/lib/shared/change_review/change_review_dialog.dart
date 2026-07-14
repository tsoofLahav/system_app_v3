import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/change_set.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';

const _calloutWidth = 280.0;
const _calloutHeight = 180.0;
const _calloutGap = 18.0;

const _documentOrder = {'plan': 0, 'execution': 1, 'tasks': 2};

Future<Map<String, bool>?> showChangeReviewDialog({
  required BuildContext context,
  required AppStrings strings,
  required ChangeSet changeSet,
  String? title,
}) {
  return showDialog<Map<String, bool>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ChangeReviewDialog(
      strings: strings,
      changeSet: changeSet,
      title: title,
    ),
  );
}

class ChangeReviewDialog extends StatefulWidget {
  const ChangeReviewDialog({
    super.key,
    required this.strings,
    required this.changeSet,
    this.title,
    this.isNewPart = false,
    this.embedded = false,
    this.onComplete,
    this.onCancel,
  });

  final AppStrings strings;
  final ChangeSet changeSet;
  final String? title;
  final bool isNewPart;
  final bool embedded;
  final ValueChanged<Map<String, bool>>? onComplete;
  final VoidCallback? onCancel;

  @override
  State<ChangeReviewDialog> createState() => _ChangeReviewDialogState();
}

class _ChangeReviewDialogState extends State<ChangeReviewDialog> {
  late final List<ChangeDocument> _documents;
  late int _documentPhase;
  final _decisions = <String, bool>{};
  final _unitKeys = <String, GlobalKey>{};
  final _changeKeys = <String, GlobalKey>{};
  final _scrollController = ScrollController();

  OverlayEntry? _suggestionOverlay;
  String? _activeChangeId;
  bool _awaitingHandoff = false;

  bool get _unifiedScroll => widget.embedded;

  @override
  void initState() {
    super.initState();
    _documents = [...widget.changeSet.documents]
      ..sort(
        (a, b) => (_documentOrder[a.key] ?? 99).compareTo(
          _documentOrder[b.key] ?? 99,
        ),
      );
    _documentPhase = 0;
    _scrollController.addListener(_markOverlayDirty);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _presentNextSuggestion(),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_markOverlayDirty);
    _removeSuggestionOverlay();
    _scrollController.dispose();
    super.dispose();
  }

  ChangeDocument get _activeDocument => _documents[_documentPhase];

  String get _dialogTitle {
    final s = widget.strings;
    return switch (_activeDocument.key) {
      'plan' => s['reviewPlan'],
      'execution' => s['reviewExecution'],
      'tasks' => s['reviewTasks'],
      _ => _activeDocument.title,
    };
  }

  bool get _allReviewed {
    if (!_unifiedScroll && _awaitingHandoff) return false;
    for (final document in _documents) {
      for (final change in _orderedChanges(document)) {
        if (!_decisions.containsKey(change.id)) return false;
      }
    }
    return true;
  }

  int get _pendingSuggestionCount {
    var count = 0;
    for (final document in _documents) {
      for (final change in _orderedChanges(document)) {
        if (!_decisions.containsKey(change.id)) count++;
      }
    }
    return count;
  }

  GlobalKey _keyForUnit(String unitId) =>
      _unitKeys.putIfAbsent(unitId, GlobalKey.new);

  GlobalKey _keyForChange(String changeId) =>
      _changeKeys.putIfAbsent(changeId, GlobalKey.new);

  List<ChangeItem> _orderedChanges(ChangeDocument document) =>
      [...document.changes];

  GlobalKey _anchorKeyForChange(ChangeItem change) {
    if (change.action == 'add_after') {
      return _keyForChange(change.id);
    }
    return _keyForUnit(change.unitId);
  }

  List<ChangeItem> _pendingChangesInScope() {
    if (_unifiedScroll) {
      return [
        for (final document in _documents)
          ..._orderedChanges(document).where(
            (change) => !_decisions.containsKey(change.id),
          ),
      ];
    }
    return _orderedChanges(_activeDocument)
        .where((change) => !_decisions.containsKey(change.id))
        .toList();
  }

  void _approveAllPending() {
    final pending = _pendingChangesInScope();
    if (pending.isEmpty) return;
    setState(() {
      for (final change in pending) {
        _decisions[change.id] = true;
      }
      _activeChangeId = null;
    });
    _removeSuggestionOverlay();
    _presentNextSuggestion();
  }

  ChangeItem? _nextPendingChangeInDocument(ChangeDocument document) {
    for (final change in _orderedChanges(document)) {
      if (!_decisions.containsKey(change.id)) return change;
    }
    return null;
  }

  ChangeItem? _nextPendingChangeGlobally() {
    for (final document in _documents) {
      final next = _nextPendingChangeInDocument(document);
      if (next != null) return next;
    }
    return null;
  }

  void _markOverlayDirty() {
    _suggestionOverlay?.markNeedsBuild();
  }

  void _removeSuggestionOverlay() {
    _suggestionOverlay?.remove();
    _suggestionOverlay = null;
  }

  void _presentNextSuggestion() {
    if (!mounted || (!_unifiedScroll && _awaitingHandoff)) return;

    _removeSuggestionOverlay();

    final next = _unifiedScroll
        ? _nextPendingChangeGlobally()
        : _nextPendingChangeInDocument(_activeDocument);
    if (next == null) {
      _onDocumentPhaseComplete();
      return;
    }

    setState(() => _activeChangeId = next.id);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _activeChangeId != next.id) return;
      if (!_unifiedScroll && _awaitingHandoff) return;

      final anchorKey = _anchorKeyForChange(next);
      final anchorContext = anchorKey.currentContext;
      if (anchorContext != null) {
        await Scrollable.ensureVisible(
          anchorContext,
          alignment: 0.35,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }

      if (!mounted || _activeChangeId != next.id) return;
      if (!_unifiedScroll && _awaitingHandoff) return;

      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (!mounted || _activeChangeId != next.id) return;
        if (!_unifiedScroll && _awaitingHandoff) return;
        _insertSuggestionOverlay(next);
      });
    });
  }

  void _insertSuggestionOverlay(ChangeItem change) {
    final overlay = Overlay.of(context, rootOverlay: true);

    _suggestionOverlay = OverlayEntry(
      builder: (overlayContext) => _SuggestionOverlay(
        anchorKey: _anchorKeyForChange(change),
        strings: widget.strings,
        change: change,
        onAccept: () => _resolveChange(change, accepted: true),
        onReject: () => _resolveChange(change, accepted: false),
      ),
    );

    overlay.insert(_suggestionOverlay!);
  }

  void _resolveChange(ChangeItem change, {required bool accepted}) {
    setState(() => _decisions[change.id] = accepted);
    _presentNextSuggestion();
  }

  void _onDocumentPhaseComplete() {
    _removeSuggestionOverlay();
    if (_unifiedScroll) {
      setState(() => _activeChangeId = null);
      return;
    }
    if (_documentPhase < _documents.length - 1) {
      setState(() {
        _activeChangeId = null;
        _awaitingHandoff = true;
      });
      return;
    }
    setState(() => _activeChangeId = null);
  }

  void _continueToNextDocument() {
    setState(() {
      _awaitingHandoff = false;
      _documentPhase += 1;
      _activeChangeId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _presentNextSuggestion(),
    );
  }

  void _cancelReview() {
    _removeSuggestionOverlay();
    if (widget.embedded) {
      widget.onCancel?.call();
      return;
    }
    Navigator.pop(context);
  }

  void _completeReview() {
    _removeSuggestionOverlay();
    if (widget.embedded) {
      widget.onComplete?.call(Map<String, bool>.from(_decisions));
      return;
    }
    Navigator.pop(context, _decisions);
  }

  String _sectionTitle(ChangeDocument document) {
    final s = widget.strings;
    return switch (document.key) {
      'plan' => s['reviewPlan'],
      'tasks' => s['reviewTasks'],
      _ => document.title,
    };
  }

  Widget _buildUnifiedDocuments() {
    final children = <Widget>[];

    for (var i = 0; i < _documents.length; i++) {
      final document = _documents[i];
      if (i > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(
              height: 1,
              thickness: 1,
              color: AppColors.noteBorder.withValues(alpha: 0.35),
            ),
          ),
        );
      }
      children.add(
        Text(
          _sectionTitle(document),
          style: AppTypography.metaStyle.copyWith(
            color: AppColors.noteMeta.withValues(alpha: 0.82),
          ),
        ),
      );
      children.add(const SizedBox(height: 8));
      children.add(
        _DocumentReview(
          document: document,
          decisions: _decisions,
          activeChangeId: _activeChangeId,
          isNewPart: widget.isNewPart,
          strings: widget.strings,
          keyForUnit: _keyForUnit,
          keyForChange: _keyForChange,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildPhasedDocument() {
    final s = widget.strings;
    final active = _activeDocument;
    final pendingCount = _orderedChanges(
      active,
    ).where((change) => !_decisions.containsKey(change.id)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_awaitingHandoff && pendingCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s['suggestedChange']} · $pendingCount',
                  style: AppTypography.metaStyle.copyWith(
                    color: AppColors.aiCyan.withValues(alpha: 0.9),
                  ),
                ),
                if (!widget.isNewPart) ...[
                  const SizedBox(height: 4),
                  Text(
                    s['reviewContextNote'],
                    style: AppTypography.metaStyle.copyWith(
                      color: AppColors.noteMeta.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
        _DocumentReview(
          document: active,
          decisions: _decisions,
          activeChangeId: _activeChangeId,
          isNewPart: widget.isNewPart,
          strings: widget.strings,
          keyForUnit: _keyForUnit,
          keyForChange: _keyForChange,
        ),
        if (_awaitingHandoff) ...[
          const SizedBox(height: 12),
          Text(
            s['planReviewComplete'],
            style: AppTypography.noteBodyStyle,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _continueToNextDocument,
              child: Text(s['continueToTasks']),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final pendingCount = _pendingSuggestionCount;

    final content = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 520,
        maxHeight: MediaQuery.sizeOf(context).height *
            (widget.embedded ? 0.55 : 0.75),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_unifiedScroll && pendingCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s['suggestedChange']} · $pendingCount',
                      style: AppTypography.metaStyle.copyWith(
                        color: AppColors.aiCyan.withValues(alpha: 0.9),
                      ),
                    ),
                    if (!widget.isNewPart) ...[
                      const SizedBox(height: 4),
                      Text(
                        s['reviewContextNote'],
                        style: AppTypography.metaStyle.copyWith(
                          color: AppColors.noteMeta.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (_unifiedScroll) _buildUnifiedDocuments() else _buildPhasedDocument(),
          ],
        ),
      ),
    );

    final finishLabel =
        widget.embedded ? s['finishUpdate'] : s['finishReview'];

    final actions = [
      TextButton(
        onPressed: _cancelReview,
        child: Text(s['cancel']),
      ),
      if (widget.isNewPart && _pendingChangesInScope().isNotEmpty)
        TextButton(
          onPressed: _approveAllPending,
          child: Text(s['approveAll']),
        ),
      TextButton(
        onPressed: _allReviewed ? _completeReview : null,
        child: Text(finishLabel),
      ),
    ];

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions,
          ),
        ],
      );
    }

    return AppGlassDialog(
      width: 560,
      title: Text(widget.title ?? _dialogTitle),
      actions: actions,
      child: content,
    );
  }
}

class _SuggestionOverlay extends StatelessWidget {
  const _SuggestionOverlay({
    required this.anchorKey,
    required this.strings,
    required this.change,
    required this.onAccept,
    required this.onReject,
  });

  final GlobalKey anchorKey;
  final AppStrings strings;
  final ChangeItem change;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final anchorBox =
        anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final anchorRect = anchorBox != null
        ? anchorBox.localToGlobal(Offset.zero) & anchorBox.size
        : null;

    if (anchorRect == null) {
      return const SizedBox.shrink();
    }

    final calloutOffset = _calloutOffset(anchorRect, screen);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: anchorRect.inflate(6),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.aiCyan.withValues(alpha: 0.75),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: calloutOffset.dx,
          top: calloutOffset.dy,
          child: _SuggestionCallout(
            strings: strings,
            change: change,
            onAccept: onAccept,
            onReject: onReject,
          ),
        ),
      ],
    );
  }

  Offset _calloutOffset(Rect anchor, Size screen) {
    final maxLeft = screen.width - _calloutWidth - 12;
    final maxTop = screen.height - _calloutHeight - 12;

    if (anchor.right + _calloutGap + _calloutWidth <= screen.width - 12) {
      final top = (anchor.center.dy - _calloutHeight / 2).clamp(12.0, maxTop);
      return Offset(anchor.right + _calloutGap, top);
    }

    if (anchor.left - _calloutGap - _calloutWidth >= 12) {
      final top = (anchor.center.dy - _calloutHeight / 2).clamp(12.0, maxTop);
      return Offset(anchor.left - _calloutGap - _calloutWidth, top);
    }

    final left = (anchor.center.dx - _calloutWidth / 2).clamp(12.0, maxLeft);
    final top = (anchor.bottom + _calloutGap).clamp(12.0, maxTop);
    return Offset(left, top);
  }
}

class _DocumentReview extends StatelessWidget {
  const _DocumentReview({
    required this.document,
    required this.decisions,
    required this.activeChangeId,
    required this.isNewPart,
    required this.strings,
    required this.keyForUnit,
    required this.keyForChange,
  });

  final ChangeDocument document;
  final Map<String, bool> decisions;
  final String? activeChangeId;
  final bool isNewPart;
  final AppStrings strings;
  final GlobalKey Function(String unitId) keyForUnit;
  final GlobalKey Function(String changeId) keyForChange;

  @override
  Widget build(BuildContext context) {
    if (document.units.isEmpty && document.changes.isEmpty) {
      return Text('…', style: AppTypography.noteBodyStyle);
    }
    return isNewPart ? _buildNewPartReview() : _buildExistingPartReview();
  }

  Widget _buildNewPartReview() {
    final addAfterByAnchor = document.addAfterChangesByAnchorId;
    final children = <Widget>[];

    void renderAddAfterChain(String anchorId) {
      for (final change in addAfterByAnchor[anchorId] ?? const <ChangeItem>[]) {
        final decision = _decisionFor(change);
        if (decision == true) {
          children.add(
            _AddedUnitRow(
              text: change.newText,
              rowKey: keyForChange(change.id),
            ),
          );
        } else {
          children.add(
            _ProposedChangeRow(
              change: change,
              decision: decision,
              isActive: change.id == activeChangeId,
              rowKey: keyForChange(change.id),
            ),
          );
        }
        final nextAnchor = change.proposedUnitId;
        if (nextAnchor != null && nextAnchor.isNotEmpty) {
          renderAddAfterChain(nextAnchor);
        }
      }
    }

    for (final unit in document.units) {
      renderAddAfterChain(unit.id);
    }

    if (children.isEmpty) {
      return Text('…', style: AppTypography.noteBodyStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildExistingPartReview() {
    final changesByUnit = document.changesByUnitId;
    final addAfterByAnchor = document.addAfterChangesByAnchorId;
    final children = <Widget>[];

    void renderAddAfterChain(String anchorId) {
      for (final change in addAfterByAnchor[anchorId] ?? const <ChangeItem>[]) {
        final decision = _decisionFor(change);
        if (decision == true) {
          children.add(
            _AddedUnitRow(
              text: change.newText,
              rowKey: keyForChange(change.id),
              prefix: '+ ',
            ),
          );
        } else {
          children.add(
            _ExistingAdditionRow(
              strings: strings,
              change: change,
              decision: decision,
              isActive: change.id == activeChangeId,
              rowKey: keyForChange(change.id),
            ),
          );
        }
        final nextAnchor = change.proposedUnitId;
        if (nextAnchor != null && nextAnchor.isNotEmpty) {
          renderAddAfterChain(nextAnchor);
        }
      }
    }

    for (final unit in document.units) {
      final change = changesByUnit[unit.id];
      if (_shouldShowUnit(unit, change)) {
        children.add(
          _UnitRow(
            unit: unit,
            change: change,
            decision: _decisionFor(change),
            isActive: change?.id == activeChangeId,
            contextOnly: change == null,
            unitKey: keyForUnit(unit.id),
          ),
        );
      }
      renderAddAfterChain(unit.id);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  bool? _decisionFor(ChangeItem? change) {
    if (change == null) return null;
    if (!decisions.containsKey(change.id)) return null;
    return decisions[change.id];
  }

  bool _shouldShowUnit(ChangeUnit unit, ChangeItem? change) {
    if (change?.action == 'remove' && decisions[change!.id] == true) {
      return false;
    }
    if (unit.text.trim().isEmpty && change == null) {
      return false;
    }
    return true;
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.unit,
    required this.change,
    required this.decision,
    required this.isActive,
    required this.unitKey,
    this.contextOnly = false,
  });

  final ChangeUnit unit;
  final ChangeItem? change;
  final bool? decision;
  final bool isActive;
  final GlobalKey unitKey;
  final bool contextOnly;

  @override
  Widget build(BuildContext context) {
    final displayText = _displayText();
    final isPending = !contextOnly && change != null && decision == null;
    final isAccepted = !contextOnly && decision == true;

    Widget text = Text(
      displayText,
      style: AppTypography.noteBodyStyle.copyWith(
        color: contextOnly
            ? AppColors.noteMeta.withValues(alpha: 0.88)
            : isAccepted
                ? AppColors.aiCyan.withValues(alpha: 0.95)
                : null,
        decoration: change?.action == 'remove' && isPending
            ? TextDecoration.lineThrough
            : null,
      ),
    );

    if (unit.kind == 'list_item') {
      text = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: AppTypography.noteBodyStyle),
          Expanded(child: text),
        ],
      );
    } else if (unit.kind == 'task') {
      text = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.noteBorder.withValues(alpha: 0.55),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: text,
        ),
      );
    }

    if (isPending && isActive) {
      text = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.aiCyan.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.aiCyan.withValues(alpha: 0.65)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: text,
        ),
      );
    } else if (isPending) {
      text = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.aiCyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.aiCyan.withValues(alpha: 0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: text,
        ),
      );
    } else if (isAccepted && change != null) {
      text = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.aiCyan.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: text,
        ),
      );
    }

    return Padding(
      key: unitKey,
      padding: const EdgeInsets.only(bottom: 12),
      child: text,
    );
  }

  String _displayText() {
    final raw = unit.text.trim().isEmpty ? '…' : unit.text;
    if (change == null) return raw;
    if (decision == true && change!.action == 'replace') {
      return change!.newText.trim().isEmpty ? '…' : change!.newText;
    }
    return raw;
  }
}

class _ExistingAdditionRow extends StatelessWidget {
  const _ExistingAdditionRow({
    required this.strings,
    required this.change,
    required this.decision,
    required this.isActive,
    required this.rowKey,
  });

  final AppStrings strings;
  final ChangeItem change;
  final bool? decision;
  final bool isActive;
  final GlobalKey rowKey;

  @override
  Widget build(BuildContext context) {
    final displayText =
        change.newText.trim().isEmpty ? '…' : change.newText;
    final isPending = decision == null;
    final isRejected = decision == false;

    Widget text = Text(
      displayText,
      style: AppTypography.noteBodyStyle.copyWith(
        color: isRejected
            ? AppColors.text.withValues(alpha: 0.45)
            : AppColors.aiCyan.withValues(alpha: 0.95),
        decoration: isRejected ? TextDecoration.lineThrough : null,
      ),
    );

    text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings['suggestedNewPoint'],
          style: AppTypography.metaStyle.copyWith(
            color: AppColors.aiCyan.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('+ ', style: AppTypography.noteBodyStyle),
            Expanded(child: text),
          ],
        ),
      ],
    );

    if (isPending && isActive) {
      text = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.aiCyan.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.aiCyan.withValues(alpha: 0.65)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: text,
        ),
      );
    } else if (isPending) {
      text = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.aiCyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.aiCyan.withValues(alpha: 0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: text,
        ),
      );
    }

    return Padding(
      key: rowKey,
      padding: const EdgeInsets.only(left: 12, bottom: 12),
      child: text,
    );
  }
}

class _ProposedChangeRow extends StatelessWidget {
  const _ProposedChangeRow({
    required this.change,
    required this.decision,
    required this.isActive,
    required this.rowKey,
  });

  final ChangeItem change;
  final bool? decision;
  final bool isActive;
  final GlobalKey rowKey;

  @override
  Widget build(BuildContext context) {
    final displayText =
        change.newText.trim().isEmpty ? '…' : change.newText;
    final isPending = decision == null;
    final isRejected = decision == false;

    Widget text = Text(
      displayText,
      style: AppTypography.noteBodyStyle.copyWith(
        color: isRejected
            ? AppColors.text.withValues(alpha: 0.45)
            : null,
        decoration: isRejected ? TextDecoration.lineThrough : null,
      ),
    );

    if (change.action == 'add_after') {
      text = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: AppTypography.noteBodyStyle),
          Expanded(child: text),
        ],
      );
    }

    if (isPending && isActive) {
      text = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.aiCyan.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.aiCyan.withValues(alpha: 0.65)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: text,
        ),
      );
    } else if (isPending) {
      text = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.aiCyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.aiCyan.withValues(alpha: 0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: text,
        ),
      );
    }

    return Padding(
      key: rowKey,
      padding: const EdgeInsets.only(left: 12, bottom: 12),
      child: text,
    );
  }
}

class _AddedUnitRow extends StatelessWidget {
  const _AddedUnitRow({required this.text, this.rowKey, this.prefix = '• '});

  final String text;
  final Key? rowKey;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: rowKey,
      padding: const EdgeInsets.only(left: 12, bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.aiCyan.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(prefix, style: AppTypography.noteBodyStyle),
              Expanded(
                child: Text(
                  text.trim().isEmpty ? '…' : text,
                  style: AppTypography.noteBodyStyle.copyWith(
                    color: AppColors.aiCyan.withValues(alpha: 0.95),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionCallout extends StatelessWidget {
  const _SuggestionCallout({
    required this.strings,
    required this.change,
    required this.onAccept,
    required this.onReject,
  });

  final AppStrings strings;
  final ChangeItem change;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final suggestionText = switch (change.action) {
      'remove' => strings['delete'],
      _ => change.newText.trim().isEmpty ? '…' : change.newText,
    };
    final suggestionLabel = switch (change.action) {
      'replace' => strings['replaceWith'],
      'add_after' => strings['suggestedNewPoint'],
      'remove' => strings['delete'],
      _ => strings['suggestedChange'],
    };

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(14),
        blurSigma: 18,
        tintOpacity: 0.9,
        tintColor: const Color(0xFFDDF6F2),
        elevation: 10,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        child: SizedBox(
          width: _calloutWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(suggestionLabel, style: AppTypography.metaStyle),
              const SizedBox(height: 8),
              Text(suggestionText, style: AppTypography.noteBodyStyle),
              if (change.reason != null && change.reason!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(change.reason!, style: AppTypography.metaStyle),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _CalloutActionButton(
                    icon: Icons.close_rounded,
                    tooltip: strings['reject'],
                    onPressed: onReject,
                  ),
                  const SizedBox(width: 6),
                  _CalloutActionButton(
                    icon: Icons.check_rounded,
                    tooltip: strings['approve'],
                    highlighted: true,
                    onPressed: onAccept,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalloutActionButton extends StatelessWidget {
  const _CalloutActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.highlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted
        ? AppColors.aiCyan
        : AppColors.text.withValues(alpha: 0.72);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: highlighted
                ? AppColors.aiCyan.withValues(alpha: 0.14)
                : AppColors.noteTop.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlighted
                  ? AppColors.aiCyan.withValues(alpha: 0.55)
                  : AppColors.noteBorder.withValues(alpha: 0.7),
            ),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
