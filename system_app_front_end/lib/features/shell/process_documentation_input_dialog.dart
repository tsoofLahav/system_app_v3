import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/automation_companion_link.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';

Future<bool> showProcessDocumentationInputDialog({
  required BuildContext context,
  required AppState state,
  required List<AutomationCompanionLink> companions,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ProcessDocumentationInputDialog(
      state: state,
      companions: companions,
    ),
  );
  return result ?? false;
}

class ProcessDocumentationInputDialog extends StatefulWidget {
  const ProcessDocumentationInputDialog({
    super.key,
    required this.state,
    required this.companions,
  });

  final AppState state;
  final List<AutomationCompanionLink> companions;

  @override
  State<ProcessDocumentationInputDialog> createState() =>
      _ProcessDocumentationInputDialogState();
}

class _ProcessDocumentationInputDialogState
    extends State<ProcessDocumentationInputDialog> {
  late List<AutomationCompanionLink> _queue;
  late int _index;
  final _textController = TextEditingController();
  int? _grade;
  var _submitting = false;
  var _closing = false;
  Object? _error;

  AppStrings get _strings => widget.state.strings;

  @override
  void initState() {
    super.initState();
    _queue = List<AutomationCompanionLink>.from(widget.companions);
    _index = 0;
    _resetForm();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  AutomationCompanionLink get _current => _queue[_index];

  bool get _isSkippedCompanion =>
      _current.payload['skipped'] == true ||
      _current.payload['reason'] == 'missing_doc_file';

  void _resetForm() {
    _textController.clear();
    _grade = null;
    _error = null;
  }

  void _goToIndex(int next) {
    if (next < 0 || next >= _queue.length || next == _index) return;
    setState(() {
      _index = next;
      _resetForm();
    });
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
      _resetForm();
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
  }

  Future<void> _completeCurrent() async {
    await widget.state.completeAutomationCompanion(_current.id);
    await _advanceQueue();
  }

  Future<void> _skipCurrent() async {
    setState(() => _submitting = true);
    try {
      await _completeCurrent();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _saveCurrent() async {
    final topicId = _current.topicId;
    if (topicId == null) return;

    final text = _textController.text.trim();
    final grade = _grade;
    if (text.isEmpty || grade == null) {
      setState(() => _error = _strings['processDocumentationInputRequired']);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.state.submitProcessDocumentationInput(
        topicId: topicId,
        text: text,
        grade: grade,
        companionTaskId: _current.id,
      );
      await _advanceQueue();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString();
      setState(() {
        _error = message.contains('grade already exists')
            ? _strings['processDocumentationDuplicateGrade']
            : message;
        _submitting = false;
      });
      return;
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_closing || _queue.isEmpty) {
      return const SizedBox.shrink();
    }

    final companion = _current;
    final topicColor = TopicAppearance.colorFromHex(companion.topicColor);
    const frameRadius = 20.0;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
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
                    strings: _strings,
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
                  if (_isSkippedCompanion)
                    _buildSkippedBody()
                  else
                    _buildInputBody(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkippedBody() {
    final message = _current.payload['message']?.toString() ??
        _strings['processDocumentationMissingDoc'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: AppTypography.noteBodyStyle),
        const SizedBox(height: 12),
        _DialogActions(
          strings: _strings,
          submitting: _submitting,
          canSave: false,
          onCancel: () => Navigator.pop(context, false),
          onSkip: _skipCurrent,
          onSave: null,
        ),
      ],
    );
  }

  Widget _buildInputBody() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: AppColors.noteBorder.withValues(alpha: 0.68),
        width: 0.85,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _strings['processDocumentationInputLabel'],
          style: AppTypography.metaStyle,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _textController,
          minLines: 3,
          maxLines: 5,
          enabled: !_submitting,
          style: AppTypography.noteBodyStyle,
          decoration: InputDecoration(
            hintText: _strings['processDocumentationInputHint'],
            isDense: true,
            filled: false,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.54),
                width: 0.9,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _strings['processDocumentationGradeLabel'],
          style: AppTypography.metaStyle,
        ),
        const SizedBox(height: 6),
        _GradeSelector(
          value: _grade,
          enabled: !_submitting,
          onChanged: (value) => setState(() => _grade = value),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error.toString(),
            style: AppTypography.metaStyle.copyWith(
              color: AppColors.primary.withValues(alpha: 0.9),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _DialogActions(
          strings: _strings,
          submitting: _submitting,
          canSave: true,
          onCancel: () => Navigator.pop(context, false),
          onSkip: _skipCurrent,
          onSave: _saveCurrent,
        ),
      ],
    );
  }
}

class _GradeSelector extends StatelessWidget {
  const _GradeSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int? value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var grade = 1; grade <= 10; grade++)
          ChoiceChip(
            label: Text('$grade'),
            selected: value == grade,
            onSelected: enabled
                ? (selected) {
                    if (selected) onChanged(grade);
                  }
                : null,
            visualDensity: VisualDensity.compact,
            labelStyle: AppTypography.metaStyle,
          ),
      ],
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.strings,
    required this.submitting,
    required this.canSave,
    required this.onCancel,
    required this.onSkip,
    required this.onSave,
  });

  final AppStrings strings;
  final bool submitting;
  final bool canSave;
  final VoidCallback onCancel;
  final VoidCallback onSkip;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: submitting ? null : onCancel,
          child: Text(strings['cancel']),
        ),
        TextButton(
          onPressed: submitting ? null : onSkip,
          child: Text(strings['skip']),
        ),
        if (canSave)
          TextButton(
            onPressed: submitting || onSave == null ? null : onSave,
            child: submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(strings['save']),
          ),
      ],
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
              tooltip: strings['previousProcess'],
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
              tooltip: strings['nextProcess'],
              onPressed: onNext,
              icon: Icons.chevron_right,
              color: topicColor,
            ),
          ],
        ),
        if (total > 1) ...[
          const SizedBox(height: 2),
          Text(
            strings.processUpdateProgress(index + 1, total),
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
