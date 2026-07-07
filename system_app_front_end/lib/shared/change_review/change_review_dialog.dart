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

enum ChangeReviewMode { processUpdate, projectUpdate }

const _processDocumentOrder = {'plan': 0, 'tasks': 1};
const _projectDocumentOrder = {
  'plan': 0,
  'execution': 1,
  'tasks': 2,
  'doc': 3,
};

Map<String, int> _documentOrderFor(ChangeReviewMode mode) {
  return switch (mode) {
    ChangeReviewMode.projectUpdate => _projectDocumentOrder,
    ChangeReviewMode.processUpdate => _processDocumentOrder,
  };
}

Future<Map<String, bool>?> showChangeReviewDialog({
  required BuildContext context,
  required AppStrings strings,
  required ChangeSet changeSet,
  String? title,
  ChangeReviewMode reviewMode = ChangeReviewMode.processUpdate,
  List<PartReview> reviewParts = const [],
}) {
  return showDialog<Map<String, bool>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ChangeReviewDialog(
      strings: strings,
      changeSet: changeSet,
      title: title,
      reviewMode: reviewMode,
      reviewParts: reviewParts,
    ),
  );
}

class ChangeReviewDialog extends StatefulWidget {
  const ChangeReviewDialog({
    super.key,
    required this.strings,
    required this.changeSet,
    this.title,
    this.reviewMode = ChangeReviewMode.processUpdate,
    this.reviewParts = const [],
    this.embedded = false,
    this.onComplete,
    this.onCancel,
  });

  final AppStrings strings;
  final ChangeSet changeSet;
  final String? title;
  final ChangeReviewMode reviewMode;
  final List<PartReview> reviewParts;
  final bool embedded;
  final ValueChanged<Map<String, bool>>? onComplete;
  final VoidCallback? onCancel;

  @override
  State<ChangeReviewDialog> createState() => _ChangeReviewDialogState();
}

class _ChangeReviewDialogState extends State<ChangeReviewDialog> {
  late final List<ChangeDocument> _documents;
  late final List<PartReview> _reviewParts;
  late final bool _byPart;
  late int _documentPhase;
  final _decisions = <String, bool>{};
  final _changeKeys = <String, GlobalKey>{};
  final _scrollController = ScrollController();

  OverlayEntry? _suggestionOverlay;
  String? _activeChangeId;
  bool _awaitingHandoff = false;

  bool get _unifiedScroll => widget.embedded;

  @override
  void initState() {
    super.initState();
    _reviewParts = [...widget.reviewParts];
    _byPart =
        widget.reviewMode == ChangeReviewMode.projectUpdate &&
        _reviewParts.isNotEmpty;
    final documentOrder = _documentOrderFor(widget.reviewMode);
    _documents = [...widget.changeSet.documents]
      ..sort(
        (a, b) => (documentOrder[a.key] ?? 99).compareTo(
          documentOrder[b.key] ?? 99,
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

  PartReview get _activePart => _reviewParts[_documentPhase];

  String get _dialogTitle {
    final s = widget.strings;
    if (_byPart) {
      final part = _activePart;
      return part.partName.trim().isEmpty
          ? (widget.title ?? s['projectUpdateReview'])
          : part.partName;
    }
    return switch (_activeDocument.key) {
      'plan' => s['reviewPlan'],
      'execution' => s['reviewExecution'],
      'tasks' => s['reviewTasks'],
      'doc' => s['reviewDocumentation'],
      _ => _activeDocument.title,
    };
  }

  String get _handoffCompleteMessage {
    final s = widget.strings;
    if (_byPart) {
      return s['partReviewComplete'];
    }
    return switch (_activeDocument.key) {
      'plan' => s['planReviewComplete'],
      'execution' => s['executionReviewComplete'],
      'tasks' => s['tasksReviewComplete'],
      _ => s['planReviewComplete'],
    };
  }

  String get _continueToNextLabel {
    final s = widget.strings;
    if (_documentPhase >= (_byPart ? _reviewParts.length : _documents.length) - 1) {
      return s['finishReview'];
    }
    if (_byPart) {
      return s['continueToNextPart'];
    }
    final nextKey = _documents[_documentPhase + 1].key;
    return switch (nextKey) {
      'execution' => s['continueToExecution'],
      'tasks' => s['continueToTasks'],
      'doc' => s['continueToDocumentation'],
      _ => s['continueToTasks'],
    };
  }

  bool get _allReviewed {
    if (!_unifiedScroll && _awaitingHandoff) return false;
    if (_byPart) {
      for (final part in _reviewParts) {
        for (final document in part.documents) {
          if (document.reviewBundle) {
            if (_documentHasPending(document)) return false;
            continue;
          }
          for (final change in _orderedChanges(document)) {
            if (!_decisions.containsKey(change.id)) return false;
          }
        }
      }
      return true;
    }
    for (final document in _documents) {
      for (final change in _orderedChanges(document)) {
        if (!_decisions.containsKey(change.id)) return false;
      }
    }
    return true;
  }

  int get _pendingSuggestionCount {
    var count = 0;
    if (_byPart) {
      for (final part in _reviewParts) {
        for (final document in part.documents) {
          if (document.reviewBundle) {
            if (_documentHasPending(document)) count++;
            continue;
          }
          for (final change in _orderedChanges(document)) {
            if (!_decisions.containsKey(change.id)) count++;
          }
        }
      }
      return count;
    }
    for (final document in _documents) {
      for (final change in _orderedChanges(document)) {
        if (!_decisions.containsKey(change.id)) count++;
      }
    }
    return count;
  }

  GlobalKey _keyForChange(String changeId) =>
      _changeKeys.putIfAbsent(changeId, GlobalKey.new);

  List<ChangeItem> _orderedChanges(ChangeDocument document) {
    final byUnit = <String, List<ChangeItem>>{};
    for (final change in document.changes) {
      byUnit.putIfAbsent(change.unitId, () => []).add(change);
    }
    final items = <ChangeItem>[];
    for (final unit in document.units) {
      items.addAll(byUnit[unit.id] ?? const []);
    }
    return items;
  }

  int _pendingCountInPart(PartReview part) {
    var count = 0;
    for (final document in part.documents) {
      if (_documentHasPending(document)) count++;
    }
    return count;
  }

  String? _partActionLabel(PartReview part) {
    final s = widget.strings;
    return switch ((part.action ?? '').toLowerCase()) {
      'create' => s['reviewPartCreate'],
      'update' => s['reviewPartUpdate'],
      'remove' => s['reviewPartRemove'],
      _ => null,
    };
  }

  ChangeItem? _nextPendingChangeInPart(PartReview part) {
    for (final document in part.documents) {
      if (!_documentHasPending(document)) continue;
      if (document.reviewBundle) {
        return document.changes.first;
      }
      final next = _nextPendingChangeInDocument(document);
      if (next != null) return next;
    }
    return null;
  }

  ChangeItem? _nextPendingChangeInDocument(ChangeDocument document) {
    for (final change in _orderedChanges(document)) {
      if (!_decisions.containsKey(change.id)) return change;
    }
    return null;
  }

  ChangeItem? _nextPendingChangeGlobally() {
    if (_byPart) {
      for (final part in _reviewParts) {
        for (final document in part.documents) {
          if (document.reviewBundle) {
            if (_documentHasPending(document)) {
              return document.changes.first;
            }
            continue;
          }
          for (final change in _orderedChanges(document)) {
            if (!_decisions.containsKey(change.id)) return change;
          }
        }
      }
      return null;
    }
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
        : (_byPart
              ? _nextPendingChangeInPart(_activePart)
              : _nextPendingChangeInDocument(_activeDocument));
    if (next == null) {
      _onDocumentPhaseComplete();
      return;
    }

    setState(() => _activeChangeId = next.id);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _activeChangeId != next.id) return;
      if (!_unifiedScroll && _awaitingHandoff) return;

      final anchorKey = _keyForChange(next.id);
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
        anchorKey: _keyForChange(change.id),
        strings: widget.strings,
        change: change,
        partAction: _partActionForChange(change),
        reviewBundle: _bundledChangesFor(change) != null,
        onAccept: () => _resolveChange(change, accepted: true),
        onReject: () => _resolveChange(change, accepted: false),
      ),
    );

    overlay.insert(_suggestionOverlay!);
  }

  void _resolveChange(ChangeItem change, {required bool accepted}) {
    final bundled = _bundledChangesFor(change);
    if (bundled != null) {
      for (final item in bundled) {
        _decisions[item.id] = accepted;
      }
    } else {
      _decisions[change.id] = accepted;
    }
    setState(() {});
    _presentNextSuggestion();
  }

  List<ChangeItem>? _bundledChangesFor(ChangeItem change) {
    if (_byPart) {
      for (final part in _reviewParts) {
        for (final document in part.documents) {
          if (!document.reviewBundle) continue;
          if (document.changes.any((item) => item.id == change.id)) {
            return document.changes;
          }
        }
      }
      return null;
    }
    for (final document in _documents) {
      if (!document.reviewBundle) continue;
      if (document.changes.any((item) => item.id == change.id)) {
        return document.changes;
      }
    }
    return null;
  }

  bool _documentHasPending(ChangeDocument document) {
    if (document.changes.isEmpty) return false;
    return document.changes.any((item) => !_decisions.containsKey(item.id));
  }

  String? _partActionForChange(ChangeItem change) {
    if (!_byPart) return null;
    for (final part in _reviewParts) {
      for (final document in part.documents) {
        if (document.changes.any((item) => item.id == change.id)) {
          return part.action;
        }
      }
    }
    return null;
  }

  void _onDocumentPhaseComplete() {
    _removeSuggestionOverlay();
    if (_unifiedScroll) {
      setState(() => _activeChangeId = null);
      return;
    }
    if (_documentPhase < (_byPart ? _reviewParts.length : _documents.length) - 1) {
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
      'execution' => s['reviewExecution'],
      'tasks' => s['reviewTasks'],
      'doc' => s['reviewDocumentation'],
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
          keyForChange: _keyForChange,
          groupByParts:
              widget.reviewMode == ChangeReviewMode.projectUpdate &&
              document.key != 'doc',
          appendOnlyDoc:
              widget.reviewMode == ChangeReviewMode.projectUpdate &&
              document.key == 'doc',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildPhasedPartReview() {
    final s = widget.strings;
    final part = _activePart;
    var pendingCount = 0;
    for (final document in part.documents) {
      pendingCount += _orderedChanges(document)
          .where((change) => !_decisions.containsKey(change.id))
          .length;
    }

    final children = <Widget>[];
    final actionLabel = _partActionLabel(part);
    if (actionLabel != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            actionLabel,
            style: AppTypography.metaStyle.copyWith(
              color: AppColors.text.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }
    if (!_awaitingHandoff && pendingCount > 0) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '${s['suggestedChange']} · $pendingCount',
            style: AppTypography.metaStyle.copyWith(
              color: AppColors.aiCyan.withValues(alpha: 0.9),
            ),
          ),
        ),
      );
    }

    final subdocs = [
      if (part.plan != null) part.plan!,
      if (part.execution != null) part.execution!,
      if (part.tasks != null) part.tasks!,
    ];

    for (var i = 0; i < subdocs.length; i++) {
      final document = subdocs[i];
      if (i > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
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
          style: AppTypography.blockHeaderStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      );
      children.add(const SizedBox(height: 8));
      children.add(
        _DocumentReview(
          document: document,
          decisions: _decisions,
          activeChangeId: _activeChangeId,
          keyForChange: _keyForChange,
          groupByParts: false,
          partAction: part.action,
        ),
      );
    }

    if (_awaitingHandoff) {
      children.addAll([
        const SizedBox(height: 12),
        Text(_handoffCompleteMessage, style: AppTypography.noteBodyStyle),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _continueToNextDocument,
            child: Text(_continueToNextLabel),
          ),
        ),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildPhasedDocument() {
    final s = widget.strings;
    if (_byPart) {
      return _buildPhasedPartReview();
    }
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
            child: Text(
              '${s['suggestedChange']} · $pendingCount',
              style: AppTypography.metaStyle.copyWith(
                color: AppColors.aiCyan.withValues(alpha: 0.9),
              ),
            ),
          ),
        _DocumentReview(
          document: active,
          decisions: _decisions,
          activeChangeId: _activeChangeId,
          keyForChange: _keyForChange,
          groupByParts:
              widget.reviewMode == ChangeReviewMode.projectUpdate &&
              active.key != 'doc',
          appendOnlyDoc:
              widget.reviewMode == ChangeReviewMode.projectUpdate &&
              active.key == 'doc',
        ),
        if (_awaitingHandoff) ...[
          const SizedBox(height: 12),
          Text(
            _handoffCompleteMessage,
            style: AppTypography.noteBodyStyle,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _continueToNextDocument,
              child: Text(_continueToNextLabel),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final pendingCount = _byPart && !_unifiedScroll
        ? _pendingCountInPart(_activePart)
        : _pendingSuggestionCount;

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
                child: Text(
                  '${s['suggestedChange']} · $pendingCount',
                  style: AppTypography.metaStyle.copyWith(
                    color: AppColors.aiCyan.withValues(alpha: 0.9),
                  ),
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
    this.partAction,
    this.reviewBundle = false,
    required this.onAccept,
    required this.onReject,
  });

  final GlobalKey anchorKey;
  final AppStrings strings;
  final ChangeItem change;
  final String? partAction;
  final bool reviewBundle;
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
            partAction: partAction,
            reviewBundle: reviewBundle,
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
    required this.keyForChange,
    this.groupByParts = false,
    this.appendOnlyDoc = false,
    this.partAction,
  });

  final ChangeDocument document;
  final Map<String, bool> decisions;
  final String? activeChangeId;
  final GlobalKey Function(String changeId) keyForChange;
  final bool groupByParts;
  final bool appendOnlyDoc;
  final String? partAction;

  @override
  Widget build(BuildContext context) {
    if (appendOnlyDoc) {
      return _DocAppendOnlyReview(
        document: document,
        decisions: decisions,
        activeChangeId: activeChangeId,
        keyForChange: keyForChange,
      );
    }
    if (groupByParts) {
      return _PartGroupedDocumentReview(
        document: document,
        decisions: decisions,
        activeChangeId: activeChangeId,
        keyForChange: keyForChange,
      );
    }
    if (document.reviewBundle) {
      final action = (partAction ?? '').toLowerCase();
      if (action == 'create') {
        return _BundledCreateDocumentReview(
          document: document,
          decisions: decisions,
          activeChangeId: activeChangeId,
          keyForChange: keyForChange,
        );
      }
      if (action == 'remove') {
        return _BundledRemoveDocumentReview(
          document: document,
          decisions: decisions,
          activeChangeId: activeChangeId,
          keyForChange: keyForChange,
        );
      }
    }

    final changesByUnit = _changesByUnitId(document.changes);
    if (document.units.isEmpty) {
      return Text('…', style: AppTypography.noteBodyStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final unit in document.units) ...[
          ..._rowsForUnit(
            unit: unit,
            changes: changesByUnit[unit.id] ?? const [],
            decisions: decisions,
            activeChangeId: activeChangeId,
            keyForChange: keyForChange,
          ),
        ],
      ],
    );
  }

  static bool shouldShowUnit(
    ChangeUnit unit,
    ChangeItem? change,
    Map<String, bool> decisions,
  ) {
    if (change?.action == 'remove' && decisions[change!.id] == true) {
      return false;
    }
    return true;
  }

  static bool shouldShowAddition(
    ChangeUnit unit,
    ChangeItem change,
    Map<String, bool> decisions,
  ) {
    if (decisions[change.id] != true) return false;
    return change.action == 'add_after' || change.action == 'add_row';
  }
}

Map<String, List<ChangeItem>> _changesByUnitId(List<ChangeItem> changes) {
  final map = <String, List<ChangeItem>>{};
  for (final change in changes) {
    map.putIfAbsent(change.unitId, () => []).add(change);
  }
  return map;
}

List<Widget> _rowsForUnit({
  required ChangeUnit unit,
  required List<ChangeItem> changes,
  required Map<String, bool> decisions,
  required String? activeChangeId,
  required GlobalKey Function(String changeId) keyForChange,
  bool isContext = false,
}) {
  final rows = <Widget>[];
  if (changes.isEmpty) {
    rows.add(
      _UnitRow(
        unit: unit,
        change: null,
        decision: null,
        isActive: false,
        unitKey: null,
        emphasizeHeader: unit.kind == 'header',
        isContext: isContext,
      ),
    );
    return rows;
  }

  final hasReplaceOrRemove = changes.any(
    (change) => change.action == 'replace' || change.action == 'remove',
  );
  if (hasReplaceOrRemove) {
    final primary = changes.firstWhere(
      (change) => change.action == 'replace' || change.action == 'remove',
      orElse: () => changes.first,
    );
    if (_DocumentReview.shouldShowUnit(unit, primary, decisions)) {
      rows.add(
        _UnitRow(
          unit: unit,
          change: primary,
          decision: _decisionFor(primary, decisions),
          isActive: primary.id == activeChangeId,
          unitKey: keyForChange(primary.id),
          emphasizeHeader: unit.kind == 'header',
          isContext: isContext,
        ),
      );
    }
  } else {
    final hasPendingAdd = changes.any(
      (change) =>
          _showPendingAddition(change, decisions) &&
          (change.action == 'add_after' || change.action == 'add_row'),
    );
    if (hasPendingAdd && unit.text.trim().isNotEmpty) {
      rows.add(
        _UnitRow(
          unit: unit,
          change: null,
          decision: null,
          isActive: false,
          unitKey: null,
          emphasizeHeader: unit.kind == 'header',
          isContext: true,
        ),
      );
    } else if (isContext) {
      rows.add(
        _UnitRow(
          unit: unit,
          change: null,
          decision: null,
          isActive: false,
          unitKey: null,
          emphasizeHeader: unit.kind == 'header',
          isContext: true,
        ),
      );
    }
  }

  for (final change in changes) {
    if (_DocumentReview.shouldShowAddition(unit, change, decisions)) {
      rows.add(
        _AddedUnitRow(
          text: change.newText,
          isHeader: change.newUnitKind == 'header',
        ),
      );
    } else if (_showPendingAddition(change, decisions) &&
        (change.action == 'add_after' || change.action == 'add_row')) {
      rows.add(
        _PendingAdditionRow(
          text: change.newText,
          isHeader: change.newUnitKind == 'header',
          unitKey: keyForChange(change.id),
          isActive: change.id == activeChangeId,
        ),
      );
    }
  }
  return rows;
}

bool? _decisionFor(ChangeItem? change, Map<String, bool> decisions) {
  if (change == null) return null;
  if (!decisions.containsKey(change.id)) return null;
  return decisions[change.id];
}

bool _showPendingAddition(ChangeItem change, Map<String, bool> decisions) {
  if (decisions.containsKey(change.id)) return false;
  return change.action == 'add_after' || change.action == 'add_row';
}

class _DocAppendOnlyReview extends StatelessWidget {
  const _DocAppendOnlyReview({
    required this.document,
    required this.decisions,
    required this.activeChangeId,
    required this.keyForChange,
  });

  final ChangeDocument document;
  final Map<String, bool> decisions;
  final String? activeChangeId;
  final GlobalKey Function(String changeId) keyForChange;

  @override
  Widget build(BuildContext context) {
    final changesByUnit = _changesByUnitId(document.changes);
    final anchorIds = changesByUnit.keys.toSet();
    final children = <Widget>[];

    for (final unit in document.units) {
      final unitChanges = changesByUnit[unit.id] ?? const [];
      final isAnchorOnly = anchorIds.contains(unit.id) && unitChanges.isNotEmpty;
      if (isAnchorOnly && unit.text.trim().isEmpty) continue;

      children.addAll(
        _rowsForUnit(
          unit: unit,
          changes: const [],
          decisions: decisions,
          activeChangeId: activeChangeId,
          keyForChange: keyForChange,
          isContext: true,
        ),
      );
    }

    for (final change in document.changes) {
      if (change.action != 'add_row') continue;
      final anchor = document.units
          .where((unit) => unit.id == change.unitId)
          .firstOrNull;
      if (anchor == null) continue;
      if (_DocumentReview.shouldShowAddition(anchor, change, decisions)) {
        children.add(
          _AddedUnitRow(
            text: change.newText,
          ),
        );
      } else if (_showPendingAddition(change, decisions)) {
        children.add(
          _PendingAdditionRow(
            text: change.newText,
            unitKey: keyForChange(change.id),
            isActive: change.id == activeChangeId,
          ),
        );
      }
    }

    if (children.isEmpty) {
      return Text('…', style: AppTypography.noteBodyStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _PartGroupedDocumentReview extends StatelessWidget {
  const _PartGroupedDocumentReview({
    required this.document,
    required this.decisions,
    required this.activeChangeId,
    required this.keyForChange,
  });

  final ChangeDocument document;
  final Map<String, bool> decisions;
  final String? activeChangeId;
  final GlobalKey Function(String changeId) keyForChange;

  @override
  Widget build(BuildContext context) {
    final sections = _partSectionsWithChanges(document, decisions);
    if (sections.isEmpty) {
      return Text('…', style: AppTypography.noteBodyStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(
                height: 1,
                thickness: 1,
                color: AppColors.noteBorder.withValues(alpha: 0.45),
              ),
            ),
          if (sections[i].showTitle)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PartSectionTitle(title: sections[i].title),
            ),
          for (final entry in sections[i].entries) ...[
            ..._rowsForUnit(
              unit: entry.unit,
              changes: entry.changes,
              decisions: decisions,
              activeChangeId: activeChangeId,
              keyForChange: keyForChange,
              isContext: entry.isContext,
            ),
          ],
        ],
      ],
    );
  }
}

class _PartSectionView {
  const _PartSectionView({
    required this.title,
    required this.entries,
    this.showTitle = true,
  });

  final String title;
  final List<_PartEntryView> entries;
  final bool showTitle;
}

class _PartEntryView {
  const _PartEntryView({
    required this.unit,
    required this.changes,
    this.isContext = false,
  });

  final ChangeUnit unit;
  final List<ChangeItem> changes;
  final bool isContext;
}

bool _partHasChanges(
  List<ChangeUnit> units,
  Map<String, List<ChangeItem>> changesByUnit,
) {
  for (final unit in units) {
    final changes = changesByUnit[unit.id] ?? const [];
    if (changes.isNotEmpty) return true;
  }
  return false;
}

List<_PartSectionView> _partSectionsWithChanges(
  ChangeDocument document,
  Map<String, bool> decisions,
) {
  final changesByUnit = _changesByUnitId(document.changes);
  final partOrder = <String>[];
  final partUnits = <String, List<ChangeUnit>>{};
  var currentPart = '';
  for (final unit in document.units) {
    if (unit.kind == 'header') {
      currentPart = unit.text.trim();
      partOrder.add(currentPart);
      partUnits.putIfAbsent(currentPart, () => []).add(unit);
      continue;
    }
    if (!partUnits.containsKey(currentPart)) {
      partOrder.add(currentPart);
      partUnits[currentPart] = [];
    }
    partUnits[currentPart]!.add(unit);
  }

  final sections = <_PartSectionView>[];
  final consumedChangeIds = <String>{};
  final deferredAnchorIds = <String>{};

  for (final partName in partOrder) {
    final units = partUnits[partName] ?? const [];
    if (!_partHasChanges(units, changesByUnit)) continue;

    var onlyDeferredHeader = true;
    for (final unit in units) {
      for (final change in changesByUnit[unit.id] ?? const []) {
        if (change.action == 'add_after' &&
            change.newUnitKind == 'header' &&
            change.newText.trim().isNotEmpty &&
            change.newText.trim() != partName.trim()) {
          if (decisions[change.id] != false) {
            deferredAnchorIds.add(unit.id);
          }
          continue;
        }
        onlyDeferredHeader = false;
      }
    }
    if (onlyDeferredHeader && deferredAnchorIds.isNotEmpty) {
      continue;
    }

    final entries = <_PartEntryView>[];
    for (final unit in units) {
      final changes = changesByUnit[unit.id] ?? const [];
      final keptChanges = <ChangeItem>[];

      for (final change in changes) {
        if (change.action == 'add_after' &&
            change.newUnitKind == 'header' &&
            change.newText.trim().isNotEmpty &&
            change.newText.trim() != partName.trim()) {
          continue;
        }
        keptChanges.add(change);
        consumedChangeIds.add(change.id);
      }

      entries.add(
        _PartEntryView(
          unit: unit,
          changes: keptChanges,
          isContext: keptChanges.isEmpty,
        ),
      );
    }

    if (entries.isEmpty) continue;
    final title = partName.trim().isEmpty ? '…' : partName.trim();
    sections.add(
      _PartSectionView(
        title: title,
        entries: entries,
        showTitle: !entries.any((entry) => entry.unit.kind == 'header'),
      ),
    );
  }

  final deferredSections = _deferredNewPartSections(
    document,
    decisions,
    consumedChangeIds,
    deferredAnchorIds,
  );
  sections.addAll(deferredSections);

  return sections;
}

List<_PartSectionView> _deferredNewPartSections(
  ChangeDocument document,
  Map<String, bool> decisions,
  Set<String> consumedChangeIds,
  Set<String> deferredAnchorIds,
) {
  final sections = <_PartSectionView>[];
  final byAnchor = <String, List<ChangeItem>>{};
  for (final change in document.changes) {
    if (consumedChangeIds.contains(change.id)) continue;
    if (change.action != 'add_after') continue;
    if (decisions[change.id] == false) continue;
    if (!deferredAnchorIds.contains(change.unitId)) continue;
    byAnchor.putIfAbsent(change.unitId, () => []).add(change);
  }

  for (final entry in byAnchor.entries) {
    final anchorId = entry.key;
    final changes = entry.value;
    if (changes.isEmpty) continue;

    final headerChange = changes
        .where((change) => change.newUnitKind == 'header')
        .firstOrNull;
    final title = headerChange?.newText.trim().isNotEmpty == true
        ? headerChange!.newText.trim()
        : '…';

    final anchor = document.units
        .where((unit) => unit.id == anchorId)
        .firstOrNull;
    if (anchor == null) continue;

    final partEntries = <_PartEntryView>[];
    for (final change in changes) {
      partEntries.add(
        _PartEntryView(
          unit: anchor,
          changes: [change],
          isContext: false,
        ),
      );
    }

    if (partEntries.isEmpty) continue;
    sections.add(
      _PartSectionView(title: title, entries: partEntries, showTitle: true),
    );
  }

  return sections;
}

class _PartSectionTitle extends StatelessWidget {
  const _PartSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.blockHeaderStyle.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.unit,
    required this.change,
    required this.decision,
    required this.isActive,
    required this.unitKey,
    this.emphasizeHeader = false,
    this.isContext = false,
  });

  final ChangeUnit unit;
  final ChangeItem? change;
  final bool? decision;
  final bool isActive;
  final GlobalKey? unitKey;
  final bool emphasizeHeader;
  final bool isContext;

  @override
  Widget build(BuildContext context) {
    final displayText = _displayText();
    final isPending = change != null && decision == null;
    final isAccepted = decision == true;
    final isHeader = emphasizeHeader || unit.kind == 'header';

    Widget text = Text(
      displayText,
      style: (isHeader ? AppTypography.blockHeaderStyle : AppTypography.noteBodyStyle)
          .copyWith(
        color: isContext
            ? AppColors.textHint.withValues(alpha: 0.85)
            : isAccepted
            ? AppColors.aiCyan.withValues(alpha: 0.95)
            : isHeader
            ? AppColors.text
            : null,
        fontWeight: isHeader ? FontWeight.w600 : null,
        decoration: isPending && change?.action == 'replace'
            ? TextDecoration.lineThrough
            : null,
        decorationColor: isPending && change?.action == 'replace'
            ? AppColors.textHint.withValues(alpha: 0.7)
            : null,
      ),
    );

    if (isContext) {
      return Padding(
        key: unitKey,
        padding: const EdgeInsets.only(bottom: 10),
        child: text,
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

class _PendingAdditionRow extends StatelessWidget {
  const _PendingAdditionRow({
    required this.text,
    required this.unitKey,
    required this.isActive,
    this.isHeader = false,
  });

  final String text;
  final GlobalKey unitKey;
  final bool isActive;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    final display = text.trim().isEmpty ? '…' : text;
    Widget content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 8),
          child: Text(
            '+',
            style: AppTypography.blockHeaderStyle.copyWith(
              color: AppColors.aiCyan.withValues(alpha: 0.95),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            display,
            style: (isHeader
                    ? AppTypography.blockHeaderStyle
                    : AppTypography.noteBodyStyle)
                .copyWith(
              color: AppColors.aiCyan.withValues(alpha: 0.95),
              fontWeight: isHeader ? FontWeight.w600 : null,
            ),
          ),
        ),
      ],
    );

    final decoration = BoxDecoration(
      color: AppColors.aiCyan.withValues(alpha: isActive ? 0.16 : 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: AppColors.aiCyan.withValues(alpha: isActive ? 0.65 : 0.35),
      ),
    );

    return Padding(
      key: unitKey,
      padding: EdgeInsets.only(left: isHeader ? 0 : 12, bottom: 12),
      child: DecoratedBox(
        decoration: decoration,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: content,
        ),
      ),
    );
  }
}

class _AddedUnitRow extends StatelessWidget {
  const _AddedUnitRow({
    required this.text,
    this.isHeader = false,
  });

  final String text;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    final display = text.trim().isEmpty ? '…' : text;
    return Padding(
      padding: EdgeInsets.only(left: isHeader ? 0 : 12, bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.aiCyan.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 8),
                child: Text(
                  '+',
                  style: AppTypography.metaStyle.copyWith(
                    color: AppColors.aiCyan.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  display,
                  style: (isHeader
                          ? AppTypography.metaStyle
                          : AppTypography.noteBodyStyle)
                      .copyWith(
                    color: AppColors.aiCyan.withValues(alpha: 0.95),
                    fontWeight: isHeader ? FontWeight.w600 : null,
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
    this.partAction,
    this.reviewBundle = false,
    required this.onAccept,
    required this.onReject,
  });

  final AppStrings strings;
  final ChangeItem change;
  final String? partAction;
  final bool reviewBundle;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final action = (partAction ?? '').toLowerCase();
    final isBundledCreate = reviewBundle && action == 'create';
    final isBundledRemove = reviewBundle && action == 'remove';
    final isAddition =
        !isBundledCreate &&
        (change.action == 'add_after' || change.action == 'add_row');
    final isReplace = change.action == 'replace';
    final suggestionText = switch (change.action) {
      'remove' => strings['delete'],
      'add_after' || 'add_row' => '',
      _ => change.newText.trim().isEmpty ? '…' : change.newText,
    };
    final title = isBundledCreate
        ? strings['reviewApproveNewSection']
        : isBundledRemove
        ? strings['reviewConfirmRemoveSection']
        : isAddition
        ? strings['reviewAddLine']
        : isReplace
        ? strings['suggestedChange']
        : strings['suggestedChange'];

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(14),
        blurSigma: 18,
        tintOpacity: 0.9,
        tintColor: isBundledRemove
            ? const Color(0xFFF8E8E8)
            : const Color(0xFFDDF6F2),
        elevation: 10,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        child: SizedBox(
          width: _calloutWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppTypography.metaStyle),
              const SizedBox(height: 8),
              if (isBundledCreate || isBundledRemove)
                const SizedBox.shrink()
              else if (isAddition)
                Text(
                  '+',
                  style: AppTypography.blockHeaderStyle.copyWith(
                    color: AppColors.aiCyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 28,
                  ),
                )
              else
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

class _BundledCreateDocumentReview extends StatelessWidget {
  const _BundledCreateDocumentReview({
    required this.document,
    required this.decisions,
    required this.activeChangeId,
    required this.keyForChange,
  });

  final ChangeDocument document;
  final Map<String, bool> decisions;
  final String? activeChangeId;
  final GlobalKey Function(String changeId) keyForChange;

  @override
  Widget build(BuildContext context) {
    final anchorChange = document.changes.isNotEmpty ? document.changes.first : null;
    final isPending = anchorChange != null && !decisions.containsKey(anchorChange.id);
    final isAccepted = anchorChange != null && decisions[anchorChange.id] == true;
    final isRejected = anchorChange != null && decisions[anchorChange.id] == false;

    if (document.units.isEmpty) {
      return Text('…', style: AppTypography.noteBodyStyle);
    }

    return DecoratedBox(
      key: anchorChange == null ? null : keyForChange(anchorChange.id),
      decoration: BoxDecoration(
        color: isPending && anchorChange.id == activeChangeId
            ? AppColors.aiCyan.withValues(alpha: 0.12)
            : isAccepted
            ? AppColors.aiCyan.withValues(alpha: 0.08)
            : isRejected
            ? AppColors.noteTop.withValues(alpha: 0.5)
            : AppColors.aiCyan.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPending && anchorChange.id == activeChangeId
              ? AppColors.aiCyan.withValues(alpha: 0.65)
              : isAccepted
              ? AppColors.aiCyan.withValues(alpha: 0.45)
              : AppColors.noteBorder.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final unit in document.units)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  unit.text.trim().isEmpty ? '…' : unit.text,
                  style: AppTypography.noteBodyStyle.copyWith(
                    color: isRejected
                        ? AppColors.textHint.withValues(alpha: 0.7)
                        : AppColors.aiCyan.withValues(alpha: 0.95),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BundledRemoveDocumentReview extends StatelessWidget {
  const _BundledRemoveDocumentReview({
    required this.document,
    required this.decisions,
    required this.activeChangeId,
    required this.keyForChange,
  });

  final ChangeDocument document;
  final Map<String, bool> decisions;
  final String? activeChangeId;
  final GlobalKey Function(String changeId) keyForChange;

  @override
  Widget build(BuildContext context) {
    final anchorChange = document.changes.isNotEmpty ? document.changes.first : null;
    final isPending = anchorChange != null && !decisions.containsKey(anchorChange.id);

    if (document.units.isEmpty) {
      return Text('…', style: AppTypography.noteBodyStyle);
    }

    return DecoratedBox(
      key: anchorChange == null ? null : keyForChange(anchorChange.id),
      decoration: BoxDecoration(
        color: isPending && anchorChange.id == activeChangeId
            ? const Color(0x26D64545)
            : const Color(0x14D64545),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPending && anchorChange.id == activeChangeId
              ? const Color(0x99D64545)
              : AppColors.noteBorder.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final unit in document.units)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  unit.text.trim().isEmpty ? '…' : unit.text,
                  style: AppTypography.noteBodyStyle.copyWith(
                    decoration: TextDecoration.lineThrough,
                    decorationColor: AppColors.textHint.withValues(alpha: 0.75),
                    color: AppColors.textHint.withValues(alpha: 0.85),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
