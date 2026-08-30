import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/dialog_field_style.dart';
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
  late final Map<int, TextEditingController> _byTopic;
  late final TextEditingController _single;
  var _saving = false;

  bool get _perTopic => widget.topics.length > 1;

  @override
  void initState() {
    super.initState();
    _single = TextEditingController();
    _byTopic = {
      for (final topic in widget.topics)
        if (topic['id'] is int)
          topic['id'] as int: TextEditingController(),
    };
  }

  @override
  void dispose() {
    _single.dispose();
    for (final controller in _byTopic.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final body = _perTopic
          ? {
              'by_topic': {
                for (final entry in _byTopic.entries)
                  '${entry.key}': entry.value.text.trim(),
              },
            }
          : {'text': _single.text.trim()};
      await widget.state.submitComplimentaryInput(widget.automation.id, body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    return AppAdaptiveDialogShell(
      title: Text(s['userInputTitle']),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(s['cancel']),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(s['submitInput']),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_perTopic)
            for (final topic in widget.topics) ...[
              AppDialogField(
                label: s.userInputForTopic('${topic['name'] ?? ''}'),
                child: TextField(
                  controller: _byTopic[topic['id'] as int?],
                  minLines: 2,
                  maxLines: 4,
                  decoration: DialogFieldStyle.decoration(),
                ),
              ),
              const SizedBox(height: DialogFieldStyle.fieldGap),
            ]
          else
            AppDialogField(
              label: s['userInputTitle'],
              child: TextField(
                controller: _single,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                decoration: DialogFieldStyle.decoration(),
              ),
            ),
        ],
      ),
    );
  }
}
