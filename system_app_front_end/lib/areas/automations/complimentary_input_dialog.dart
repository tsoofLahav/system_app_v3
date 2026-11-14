import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../files/data/topic.dart';
import '../files/editor/editor_key_handoff.dart';
import '../files/rich_text/dialog_formatted_field.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_colors.dart';
import '../ui/dialog_field_style.dart';
import '../ux/topic/topic_appearance.dart';
import './automation.dart';

/// Keep in sync with `COMPLIMENTARY_INPUT_MAX_CHARS` in section_windows.py.
const complimentaryInputMaxChars = 12000;

/// Collects per-topic answers and pops immediately. The caller starts the run.
Future<Map<String, dynamic>?> showComplimentaryInputDialog({
  required BuildContext context,
  required AppState state,
  required Automation automation,
}) async {
  final Map<String, dynamic> fields;
  try {
    fields = await state.complimentaryInputFields(automation.id);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
    return null;
  }
  if (!context.mounted) return null;
  final steps = (fields['steps'] as List).cast<Map<String, dynamic>>();
  if (steps.isEmpty) return null;
  return showAppDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => _ComplimentaryInputDialog(
      state: state,
      topics: (fields['topics'] as List).cast<Map<String, dynamic>>(),
      steps: steps,
      stepsVersion: fields['steps_version'] as String,
    ),
  );
}

class _ComplimentaryInputDialog extends StatefulWidget {
  const _ComplimentaryInputDialog({
    required this.state,
    required this.topics,
    required this.steps,
    required this.stepsVersion,
  });

  final AppState state;
  final List<Map<String, dynamic>> topics;
  final List<Map<String, dynamic>> steps;
  final String stepsVersion;

  @override
  State<_ComplimentaryInputDialog> createState() =>
      _ComplimentaryInputDialogState();
}

class _ComplimentaryInputDialogState extends State<_ComplimentaryInputDialog> {
  late final List<TextEditingController> _controllers;
  final _firstFocus = FocusNode();
  final _answers = <int, List<String>>{};
  var _index = 0;
  var _closing = false;

  bool get _perTopic => widget.topics.length > 1;

  Map<String, dynamic>? get _currentTopic =>
      widget.topics.isEmpty ? null : widget.topics[_index];

  Topic? get _resolvedTopic {
    final id = _currentTopic?['id'];
    if (id is! int) return null;
    for (final topic in widget.state.allTopics) {
      if (topic.id == id) return topic;
    }
    return null;
  }

  bool get _overLimit => _controllers.any(
    (controller) => controller.text.trim().length > complimentaryInputMaxChars,
  );

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final _ in widget.steps)
        TextEditingController()..addListener(_onTextChanged),
    ];
    runWhenKeyboardIdle(() {
      if (mounted) _firstFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_onTextChanged);
      controller.dispose();
    }
    _firstFocus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _storeCurrent() {
    _answers[_index] = [
      for (final controller in _controllers) controller.text.trim(),
    ];
  }

  void _showIndex(int index) {
    final currentIndex = _index;
    runWhenKeyboardIdle(() {
      if (!mounted || _closing || _overLimit || _index != currentIndex) return;
      _storeCurrent();
      setState(() => _index = index);
      final answers = _answers[index];
      for (final (field, controller) in _controllers.indexed) {
        final text = answers?[field] ?? '';
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      _firstFocus.requestFocus();
    });
  }

  Map<String, dynamic> _body() => {
    'steps_version': widget.stepsVersion,
    'by_step': {
      for (final (field, step) in widget.steps.indexed)
        '${step['position']}': widget.topics.isEmpty
            ? {'text': _answers[0]![field]}
            : {
                'by_topic': {
                  for (final (page, topic) in widget.topics.indexed)
                    '${topic['id']}': _answers[page]![field],
                },
              },
    },
  };

  void _finish() {
    if (_closing || _overLimit) return;
    _closing = true;
    runWhenKeyboardIdle(() {
      if (!mounted) return;
      _storeCurrent();
      Navigator.pop(context, _body());
    });
  }

  String _titleLabel() {
    final s = widget.state.strings;
    final topic = _resolvedTopic;
    if (topic != null) {
      return s.userInputForTopic(widget.state.topicDisplayName(topic));
    }
    final name = '${_currentTopic?['name'] ?? ''}'.trim();
    if (name.isNotEmpty) return s.userInputForTopic(name);
    return s['userInputTitle'];
  }

  Color? get _headerAccent {
    final topic = _resolvedTopic;
    if (topic != null) return TopicAppearance.accentFor(topic);
    final hex = '${_currentTopic?['color'] ?? ''}'.trim();
    if (hex.isEmpty) return null;
    return TopicAppearance.colorFromHex(hex);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final last = !_perTopic || _index >= widget.topics.length - 1;
    final over = _overLimit;

    return AppAdaptiveDialogShell(
      title: Text(_titleLabel()),
      headerAccent: _headerAccent,
      headerAccentIsMain: false,
      headerAccentTintAlpha: AppColors.topicDialogVeilAlpha,
      actions: [
        TextButton(
          onPressed: _closing ? null : () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        if (_perTopic && _index > 0)
          TextButton(
            onPressed: _closing ? null : () => _showIndex(_index - 1),
            child: Text(s['back']),
          ),
        FilledButton(
          onPressed: _closing || over
              ? null
              : (last ? _finish : () => _showIndex(_index + 1)),
          child: Text(last ? s['submitInput'] : s['next']),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, step) in widget.steps.indexed) ...[
            if (index > 0) const SizedBox(height: 16),
            _buildField(index, step, last: last),
          ],
        ],
      ),
    );
  }

  Widget _buildField(
    int index,
    Map<String, dynamic> step, {
    required bool last,
  }) {
    final s = widget.state.strings;
    final controller = _controllers[index];
    final count = controller.text.trim().length;
    final over = count > complimentaryInputMaxChars;
    final name = (step[s.isRtl ? 'name_he' : 'name'] as String?)?.trim();
    final fallbackName = (step['name'] as String?)?.trim();
    final position = step['position'];
    final label = name != null && name.isNotEmpty
        ? name
        : (fallbackName != null && fallbackName.isNotEmpty
              ? fallbackName
              : (s.isRtl ? 'פעולת AI $position' : 'AI step $position'));
    final prompt = (step['prompt'] as String?)?.trim() ?? '';

    return AppDialogField(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prompt.isNotEmpty) ...[Text(prompt), const SizedBox(height: 8)],
          DialogFormattedField(
            controller: controller,
            focusNode: index == 0 ? _firstFocus : null,
            strings: s,
            minLines: 3,
            maxLines: 12,
            onEnter: widget.steps.length == 1
                ? () {
                    if (_closing || _overLimit) return;
                    if (last) {
                      _finish();
                    } else {
                      _showIndex(_index + 1);
                    }
                  }
                : null,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              over
                  ? s.userInputOverLimit(complimentaryInputMaxChars)
                  : s.userInputCharCount(count, complimentaryInputMaxChars),
              style: DialogFieldStyle.labelStyle.copyWith(
                color: over ? AppColors.destructive : AppColors.textHint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
