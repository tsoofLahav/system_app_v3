import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/ai_proposal.dart';
import '../../core/models/automation_companion_link.dart';
import '../../core/models/change_set.dart';
import '../../core/registry/topic_appearance.dart';
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
      if (mounted) Navigator.pop(context, true);
      return;
    }

    await _loadCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final s = _strings;
    final companion = _queue.isEmpty ? null : _current;
    final topicColor = TopicAppearance.colorFromHex(companion?.topicColor);
    final topicEmoji = TopicAppearance.emojiFromId(companion?.topicIcon);

    return AppGlassDialog(
      width: 600,
      title: Text(s['processUpdateReview']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s['cancel']),
        ),
      ],
      child: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (companion != null) ...[
              _ProcessHeader(
                strings: s,
                topicName: companion.displayTopicName,
                topicEmoji: topicEmoji,
                topicColor: topicColor,
                index: _index,
                total: _queue.length,
                onPrevious: _index > 0 ? () => _goToIndex(_index - 1) : null,
                onNext: _index < _queue.length - 1
                    ? () => _goToIndex(_index + 1)
                    : null,
              ),
              const SizedBox(height: 12),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
    required this.topicEmoji,
    required this.topicColor,
    required this.index,
    required this.total,
    this.onPrevious,
    this.onNext,
  });

  final AppStrings strings;
  final String topicName;
  final String topicEmoji;
  final Color topicColor;
  final int index;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: strings['previousProcess'],
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: topicColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: topicColor.withValues(alpha: 0.45)),
                ),
                child: Row(
                  children: [
                    Text(topicEmoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        topicName,
                        style: AppTypography.noteTitleStyle.copyWith(
                          color: topicColor.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: strings['nextProcess'],
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          strings.processUpdateProgress(index + 1, total),
          style: AppTypography.metaStyle,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
