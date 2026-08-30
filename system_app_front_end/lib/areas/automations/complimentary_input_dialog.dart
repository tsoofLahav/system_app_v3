import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../files/data/topic.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/dialog_field_style.dart';
import '../ux/topic/topic_appearance.dart';
import './automation.dart';

Future<bool> showComplimentaryInputDialog({
  required BuildContext context,
  required AppState state,
  required Automation automation,
}) async {
  final topics = await state.complimentaryInputTopics(automation.id);
  if (!context.mounted) return false;
  final saved = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => _ComplimentaryInputDialog(
      state: state,
      automation: automation,
      topics: topics,
    ),
  );
  return saved ?? false;
}

class _ComplimentaryInputDialog extends StatefulWidget {
  const _ComplimentaryInputDialog({
    required this.state,
    required this.automation,
    required this.topics,
  });

  final AppState state;
  final Automation automation;
  final List<Map<String, dynamic>> topics;

  @override
  State<_ComplimentaryInputDialog> createState() =>
      _ComplimentaryInputDialogState();
}

class _ComplimentaryInputDialogState extends State<_ComplimentaryInputDialog> {
  late final TextEditingController _text;
  final _answers = <int, String>{};
  var _index = 0;
  var _saving = false;

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
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _storeCurrent() {
    final topic = _currentTopic;
    if (topic != null && topic['id'] is int) {
      _answers[topic['id'] as int] = _text.text.trim();
    }
  }

  void _showIndex(int index) {
    _index = index;
    final topic = widget.topics[index];
    final id = topic['id'];
    _text.text = id is int ? (_answers[id] ?? '') : '';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  Future<void> _submit() async {
    _storeCurrent();
    setState(() => _saving = true);
    try {
      final body = _perTopic || widget.topics.length == 1
          ? {
              'by_topic': {
                for (final topic in widget.topics)
                  if (topic['id'] is int)
                    '${topic['id']}': _answers[topic['id'] as int] ?? '',
              },
            }
          : {'text': _text.text.trim()};
      await widget.state.submitComplimentaryInput(widget.automation.id, body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _next() {
    _storeCurrent();
    setState(() => _showIndex(_index + 1));
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
    final topic = _resolvedTopic;

    return AppAdaptiveDialogShell(
      title: Text(_titleLabel()),
      headerAccent: _headerAccent,
      headerAccentIsMain: topic?.isMain ?? false,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(s['cancel']),
        ),
        if (_perTopic && _index > 0)
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    _storeCurrent();
                    setState(() => _showIndex(_index - 1));
                  },
            child: Text(s['back']),
          ),
        FilledButton(
          onPressed: _saving ? null : (last ? _submit : _next),
          child: Text(last ? s['submitInput'] : s['next']),
        ),
      ],
      child: AppDialogField(
        label: s['userInputTitle'],
        child: TextField(
          controller: _text,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: DialogFieldStyle.decoration(),
        ),
      ),
    );
  }
}
