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

const _documentOrder = {'plan': 0, 'tasks': 1};

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
    this.embedded = false,
    this.onComplete,
    this.onCancel,
  });

  final AppStrings strings;
  final ChangeSet changeSet;
  final String? title;
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
  final _scrollController = ScrollController();

  OverlayEntry? _suggestionOverlay;
  String? _activeChangeId;
  bool _awaitingHandoff = false;

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
      'tasks' => s['reviewTasks'],
      _ => _activeDocument.title,
    };
  }

  bool get _allReviewed {
    if (_awaitingHandoff) return false;
    for (final document in _documents) {
      for (final change in _orderedChanges(document)) {
        if (!_decisions.containsKey(change.id)) return false;
      }
    }
    return true;
  }

  GlobalKey _keyForUnit(String unitId) =>
      _unitKeys.putIfAbsent(unitId, GlobalKey.new);

  List<ChangeItem> _orderedChanges(ChangeDocument document) {
    final byUnit = document.changesByUnitId;
    final items = <ChangeItem>[];
    for (final unit in document.units) {
      final change = byUnit[unit.id];
      if (change != null) items.add(change);
    }
    return items;
  }

  ChangeItem? _nextPendingChange(ChangeDocument document) {
    for (final change in _orderedChanges(document)) {
      if (!_decisions.containsKey(change.id)) return change;
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
    if (!mounted || _awaitingHandoff) return;

    _removeSuggestionOverlay();

    final next = _nextPendingChange(_activeDocument);
    if (next == null) {
      _onDocumentPhaseComplete();
      return;
    }

    setState(() => _activeChangeId = next.id);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _activeChangeId != next.id || _awaitingHandoff) return;

      final anchorKey = _keyForUnit(next.unitId);
      final anchorContext = anchorKey.currentContext;
      if (anchorContext != null) {
        await Scrollable.ensureVisible(
          anchorContext,
          alignment: 0.35,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }

      if (!mounted || _activeChangeId != next.id || _awaitingHandoff) return;

      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (!mounted || _activeChangeId != next.id || _awaitingHandoff) return;
        _insertSuggestionOverlay(next);
      });
    });
  }

  void _insertSuggestionOverlay(ChangeItem change) {
    final overlay = Overlay.of(context, rootOverlay: true);

    _suggestionOverlay = OverlayEntry(
      builder: (overlayContext) => _SuggestionOverlay(
        anchorKey: _keyForUnit(change.unitId),
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

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final active = _activeDocument;
    final pendingCount = _orderedChanges(
      active,
    ).where((change) => !_decisions.containsKey(change.id)).length;

    final content = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 520,
        maxHeight: MediaQuery.sizeOf(context).height * (widget.embedded ? 0.55 : 0.75),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
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
              keyForUnit: _keyForUnit,
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
        ),
      ),
    );

    final actions = [
      TextButton(
        onPressed: _cancelReview,
        child: Text(s['cancel']),
      ),
      TextButton(
        onPressed: _allReviewed ? _completeReview : null,
        child: Text(s['finishReview']),
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
    required this.keyForUnit,
  });

  final ChangeDocument document;
  final Map<String, bool> decisions;
  final String? activeChangeId;
  final GlobalKey Function(String unitId) keyForUnit;

  @override
  Widget build(BuildContext context) {
    final changesByUnit = document.changesByUnitId;
    if (document.units.isEmpty) {
      return Text('…', style: AppTypography.noteBodyStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final unit in document.units) ...[
          if (_shouldShowUnit(unit, changesByUnit[unit.id]))
            _UnitRow(
              unit: unit,
              change: changesByUnit[unit.id],
              decision: _decisionFor(changesByUnit[unit.id]),
              isActive: changesByUnit[unit.id]?.id == activeChangeId,
              unitKey: keyForUnit(unit.id),
            ),
          if (_shouldShowAddition(unit, changesByUnit[unit.id]))
            _AddedUnitRow(text: changesByUnit[unit.id]!.newText),
        ],
      ],
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
    return true;
  }

  bool _shouldShowAddition(ChangeUnit unit, ChangeItem? change) {
    return change?.action == 'add_after' && decisions[change!.id] == true;
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.unit,
    required this.change,
    required this.decision,
    required this.isActive,
    required this.unitKey,
  });

  final ChangeUnit unit;
  final ChangeItem? change;
  final bool? decision;
  final bool isActive;
  final GlobalKey unitKey;

  @override
  Widget build(BuildContext context) {
    final displayText = _displayText();
    final isPending = change != null && decision == null;
    final isAccepted = decision == true;

    Widget text = Text(
      displayText,
      style: AppTypography.noteBodyStyle.copyWith(
        color: isAccepted ? AppColors.aiCyan.withValues(alpha: 0.95) : null,
      ),
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

class _AddedUnitRow extends StatelessWidget {
  const _AddedUnitRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.aiCyan.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            text.trim().isEmpty ? '…' : text,
            style: AppTypography.noteBodyStyle.copyWith(
              color: AppColors.aiCyan.withValues(alpha: 0.95),
            ),
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
              Text(strings['suggestedChange'], style: AppTypography.metaStyle),
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
