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

/// Collects per-topic answers and pops immediately. The caller starts the run.
Future<Map<String, dynamic>?> showComplimentaryInputDialog({
  required BuildContext context,
  required AppState state,
  required Automation automation,
}) async {
  final topics = await state.complimentaryInputTopics(automation.id);
  if (!context.mounted) return null;
  return showAppDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => _ComplimentaryInputDialog(state: state, topics: topics),
  );
}

class _ComplimentaryInputDialog extends StatefulWidget {
  const _ComplimentaryInputDialog({required this.state, required this.topics});

  final AppState state;
  final List<Map<String, dynamic>> topics;

  @override
  State<_ComplimentaryInputDialog> createState() =>
      _ComplimentaryInputDialogState();
}

class _ComplimentaryInputDialogState extends State<_ComplimentaryInputDialog> {
  late final TextEditingController _text;
  late final FocusNode _focus;
  final _answers = <int, String>{};
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

  @override
  void initState() {
    super.initState();
    _text = TextEditingController();
    _focus = FocusNode();
    _focusField();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _storeCurrent() {
    final topic = _currentTopic;
    if (topic != null && topic['id'] is int) {
      _answers[topic['id'] as int] = _text.text.trim();
    }
  }

  void _focusField() {
    runWhenKeyboardIdle(() {
      if (!mounted) return;
      _focus.requestFocus();
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    });
  }

  void _showIndex(int index) {
    _index = index;
    final topic = widget.topics[index];
    final id = topic['id'];
    _text.text = id is int ? (_answers[id] ?? '') : '';
    _focusField();
  }

  Map<String, dynamic> _body() {
    if (_perTopic || widget.topics.length == 1) {
      return {
        'by_topic': {
          for (final topic in widget.topics)
            if (topic['id'] is int)
              '${topic['id']}': _answers[topic['id'] as int] ?? '',
        },
      };
    }
    return {'text': _text.text.trim()};
  }

  void _finish() {
    if (_closing) return;
    _closing = true;
    _storeCurrent();
    Navigator.pop(context, _body());
  }

  void _next() {
    _storeCurrent();
    setState(() => _showIndex(_index + 1));
  }

  void _advanceFromEnter() {
    final last = !_perTopic || _index >= widget.topics.length - 1;
    if (last) {
      _finish();
    } else {
      _next();
    }
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
            onPressed: _closing
                ? null
                : () {
                    _storeCurrent();
                    setState(() => _showIndex(_index - 1));
                  },
            child: Text(s['back']),
          ),
        FilledButton(
          onPressed: _closing ? null : (last ? _finish : _next),
          child: Text(last ? s['submitInput'] : s['next']),
        ),
      ],
      child: AppDialogField(
        label: s['userInputTitle'],
        child: DialogFormattedField(
          controller: _text,
          focusNode: _focus,
          strings: s,
          minLines: 3,
          maxLines: 8,
          onEnter: _advanceFromEnter,
        ),
      ),
    );
  }
}
