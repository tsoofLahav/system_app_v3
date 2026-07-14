import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/ai_proposal.dart';
import '../../core/models/automation_companion_link.dart';
import '../../core/models/change_set.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../../shared/change_review/change_review_dialog.dart';
import '../../shared/change_review/part_change_review_dialog.dart';

Future<bool> showProjectUpdateBatchDialog({
  required BuildContext context,
  required AppState state,
  required List<AutomationCompanionLink> companions,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ProjectUpdateBatchDialog(
      state: state,
      companions: companions,
    ),
  );
  return result ?? false;
}

class ProjectUpdateBatchDialog extends StatefulWidget {
  const ProjectUpdateBatchDialog({
    super.key,
    required this.state,
    required this.companions,
  });

  final AppState state;
  final List<AutomationCompanionLink> companions;

  @override
  State<ProjectUpdateBatchDialog> createState() =>
      _ProjectUpdateBatchDialogState();
}

class _ProjectUpdateBatchDialogState extends State<ProjectUpdateBatchDialog> {
  late List<AutomationCompanionLink> _queue;
  late int _index;
  AiProposal? _proposal;
  var _loading = true;
  var _closing = false;
  Object? _error;

  AppStrings get _strings => widget.state.strings;

  @override
  void initState() {
    super.initState();
    _queue = List<AutomationCompanionLink>.from(widget.companions);
    _index = 0;
    _loadCurrent();
  }

  AutomationCompanionLink get _current => _queue[_index];

  Future<void> _loadCurrent() async {
    setState(() {
      _loading = true;
      _error = null;
      _proposal = null;
    });
    try {
      final proposalId = _current.proposalId;
      if (proposalId == null) {
        throw StateError('missing proposal_id');
      }
      final proposal = await widget.state.fetchAiProposal(proposalId);
      if (!mounted) return;
      setState(() {
        _proposal = proposal;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _goToIndex(int next) {
    if (next < 0 || next >= _queue.length || next == _index) return;
    setState(() => _index = next);
    _loadCurrent();
  }

  Future<void> _closeWhenDone() async {
    if (widget.state.selectedViewType != null) {
      await widget.state.refreshCurrentView();
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _advanceQueue() async {
    if (!mounted || _closing) return;

    if (_queue.isEmpty) {
      await _closeWhenDone();
      return;
    }

    setState(() {
      _queue.removeAt(_index);
      if (_queue.isEmpty) {
        _closing = true;
        return;
      }
      if (_index >= _queue.length) {
        _index = _queue.length - 1;
      }
    });

    if (_queue.isEmpty) {
      await _closeWhenDone();
      return;
    }

    await _loadCurrent();
  }

  Future<void> _finishCurrent({Map<String, bool>? decisions}) async {
    final companion = _current;
    final proposal = _proposal;
    if (proposal == null) return;

    if (proposal.proposalType == 'project_update_skipped') {
      await widget.state.rejectAiProposal(
        proposal,
        companionTaskId: companion.id,
      );
    } else if (decisions != null) {
      final updated = await widget.state.finalizeProjectUpdate(
        proposal,
        decisions,
        companionTaskId: companion.id,
      );
      _maybeShowDocRowsSnackBar(updated);
    }

    await _advanceQueue();
  }

  void _maybeShowDocRowsSnackBar(AiProposal proposal) {
    final count = proposal.payload['doc_rows_added'];
    if (count is! int || count <= 0 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_strings.docRowsAdded(count))),
    );
  }

  Future<void> _skipCurrent() async {
    final companion = _current;
    final proposal = _proposal;
    if (proposal == null) return;

    await widget.state.rejectAiProposal(
      proposal,
      companionTaskId: companion.id,
    );

    await _advanceQueue();
  }

  @override
  Widget build(BuildContext context) {
    if (_closing || _queue.isEmpty) {
      return const SizedBox.shrink();
    }

    final s = _strings;
    final companion = _current;
    final topicColor = TopicAppearance.colorFromHex(companion.topicColor);
    const frameRadius = 20.0;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(frameRadius),
            border: Border.all(
              color: topicColor.withValues(alpha: 0.34),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(frameRadius - 1),
            child: GlassSurface.styled(
              style: AppGlassStyle.dialog,
              borderRadius: BorderRadius.circular(frameRadius - 1),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopicFrameHeader(
                    strings: s,
                    topicName: companion.displayTopicName,
                    topicColor: topicColor,
                    index: _index,
                    total: _queue.length,
                    onPrevious:
                        _index > 0 ? () => _goToIndex(_index - 1) : null,
                    onNext: _index < _queue.length - 1
                        ? () => _goToIndex(_index + 1)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        s['automationRunFailed'],
                        style: AppTypography.noteBodyStyle,
                      ),
                    )
                  else if (_proposal != null)
                    _buildReviewBody(_proposal!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewBody(AiProposal proposal) {
    if (proposal.proposalType == 'project_update_skipped') {
      final message = proposal.payload['message']?.toString() ??
          _strings['projectUpdateSkipped'];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: AppTypography.noteBodyStyle),
          const SizedBox(height: 8),
          _ReviewActions(
            strings: _strings,
            canFinish: true,
            onCancel: _skipCurrent,
            onFinish: _finishCurrent,
          ),
        ],
      );
    }

    final raw = proposal.payload['change_set'];
    if (raw is! Map<String, dynamic>) {
      return Text(
        _strings['automationRunFailed'],
        style: AppTypography.noteBodyStyle,
      );
    }

    final changeSet = ChangeSet.fromJson(raw);
    if (changeSet.isPartBased) {
      final parts = changeSet.parts ?? const [];
      if (parts.isEmpty) {
        return Text(
          _strings['automationRunFailed'],
          style: AppTypography.noteBodyStyle,
        );
      }
      return SizedBox(
        height: 520,
        child: PartChangeReviewDialog(
          key: ValueKey(_current.id),
          strings: _strings,
          parts: parts,
          embedded: true,
          onCancel: _skipCurrent,
          onComplete: (decisions) async {
            await _finishCurrent(decisions: decisions);
          },
        ),
      );
    }

    return ChangeReviewDialog(
      key: ValueKey(_current.id),
      strings: _strings,
      changeSet: changeSet,
      embedded: true,
      onCancel: _skipCurrent,
      onComplete: (decisions) async {
        await _finishCurrent(decisions: decisions);
      },
    );
  }
}

class _TopicFrameHeader extends StatelessWidget {
  const _TopicFrameHeader({
    required this.strings,
    required this.topicName,
    required this.topicColor,
    required this.index,
    required this.total,
    this.onPrevious,
    this.onNext,
  });

  final AppStrings strings;
  final String topicName;
  final Color topicColor;
  final int index;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final titleStyle = AppTypography.metaStyle.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.15,
      color: topicColor.withValues(alpha: 0.9),
    );

    return Column(
      children: [
        Row(
          children: [
            _NavButton(
              tooltip: strings['previousProject'],
              onPressed: onPrevious,
              icon: Icons.chevron_left,
              color: topicColor,
            ),
            Expanded(
              child: Text(
                topicName,
                style: titleStyle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _NavButton(
              tooltip: strings['nextProject'],
              onPressed: onNext,
              icon: Icons.chevron_right,
              color: topicColor,
            ),
          ],
        ),
        if (total > 1) ...[
          const SizedBox(height: 2),
          Text(
            strings.projectUpdateProgress(index + 1, total),
            style: AppTypography.metaStyle.copyWith(
              fontSize: 10.5,
              color: AppColors.noteMeta.withValues(alpha: 0.62),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _ReviewActions extends StatelessWidget {
  const _ReviewActions({
    required this.strings,
    required this.canFinish,
    required this.onCancel,
    required this.onFinish,
  });

  final AppStrings strings;
  final bool canFinish;
  final VoidCallback onCancel;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: onCancel,
          child: Text(strings['cancel']),
        ),
        TextButton(
          onPressed: canFinish ? onFinish : null,
          child: Text(strings['finishUpdate']),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    required this.color,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      color: color.withValues(alpha: onPressed == null ? 0.28 : 0.72),
      icon: Icon(icon),
    );
  }
}
