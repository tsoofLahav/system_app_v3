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

Future<bool> showProcessUpdateBatchDialog({
  required BuildContext context,
  required AppState state,
  required List<AutomationCompanionLink> companions,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ProcessUpdateBatchDialog(
      state: state,
      companions: companions,
    ),
  );
  return result ?? false;
}

class ProcessUpdateBatchDialog extends StatefulWidget {
  const ProcessUpdateBatchDialog({
    super.key,
    required this.state,
    required this.companions,
  });

  final AppState state;
  final List<AutomationCompanionLink> companions;

  @override
  State<ProcessUpdateBatchDialog> createState() =>
      _ProcessUpdateBatchDialogState();
}

class _ProcessUpdateBatchDialogState extends State<ProcessUpdateBatchDialog> {
  late List<AutomationCompanionLink> _queue;
  late int _index;
  AiProposal? _proposal;
  var _loading = true;
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

  Future<void> _finishCurrent({Map<String, bool>? decisions}) async {
    final companion = _current;
    final proposal = _proposal;
    if (proposal == null) return;

    if (proposal.proposalType == 'process_refresh_skipped') {
      await widget.state.rejectAiProposal(
        proposal,
        companionTaskId: companion.id,
      );
    } else if (decisions != null) {
      await widget.state.finalizeProcessUpdate(
        proposal,
        decisions,
        companionTaskId: companion.id,
      );
    }

    if (!mounted) return;

    setState(() {
      _queue.removeAt(_index);
      if (_queue.isEmpty) {
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

  @override
  Widget build(BuildContext context) {
    final s = _strings;
    final companion = _queue.isEmpty ? null : _current;
    final topicColor = TopicAppearance.colorFromHex(companion?.topicColor);

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: GlassSurface.styled(
          style: AppGlassStyle.dialog,
          borderRadius: BorderRadius.circular(AppGlassStyle.dialogRadius),
          border: Border(
            top: BorderSide(color: topicColor.withValues(alpha: 0.72), width: 2.5),
            left: BorderSide(
              color: topicColor.withValues(alpha: 0.22),
              width: 1,
            ),
            right: BorderSide(
              color: topicColor.withValues(alpha: 0.22),
              width: 1,
            ),
            bottom: BorderSide(
              color: AppColors.noteBorder.withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (companion != null)
                _ProcessHeader(
                  strings: s,
                  topicName: companion.displayTopicName,
                  topicColor: topicColor,
                  index: _index,
                  total: _queue.length,
                  onPrevious: _index > 0 ? () => _goToIndex(_index - 1) : null,
                  onNext: _index < _queue.length - 1
                      ? () => _goToIndex(_index + 1)
                      : null,
                ),
              const SizedBox(height: 14),
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
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(s['cancel']),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewBody(AiProposal proposal) {
    if (proposal.proposalType == 'process_refresh_skipped') {
      final message = proposal.payload['message']?.toString() ??
          _strings['processRefreshSkipped'];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: AppTypography.noteBodyStyle),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              onPressed: () => _finishCurrent(),
              child: Text(_strings['finishReview']),
            ),
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

    return ChangeReviewDialog(
      key: ValueKey(_current.id),
      strings: _strings,
      changeSet: ChangeSet.fromJson(raw),
      embedded: true,
      onCancel: () => Navigator.pop(context, false),
      onComplete: (decisions) => _finishCurrent(decisions: decisions),
    );
  }
}

class _ProcessHeader extends StatelessWidget {
  const _ProcessHeader({
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
      fontSize: 13,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: topicColor.withValues(alpha: 0.88),
    );

    return Column(
      children: [
        Row(
          children: [
            _NavButton(
              tooltip: strings['previousProcess'],
              onPressed: onPrevious,
              icon: Icons.chevron_left,
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
              tooltip: strings['nextProcess'],
              onPressed: onNext,
              icon: Icons.chevron_right,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          strings.processUpdateProgress(index + 1, total),
          style: AppTypography.metaStyle.copyWith(
            fontSize: 11,
            color: AppColors.noteMeta.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
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
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      color: AppColors.text.withValues(alpha: onPressed == null ? 0.25 : 0.55),
      icon: Icon(icon),
    );
  }
}
