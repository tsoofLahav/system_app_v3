import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/topic.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/dialog_field_style.dart';
import '../../ui/glass_surface.dart';

class AddFileResult {
  const AddFileResult({required this.name, required this.isEssence});

  final String name;
  final bool isEssence;
}

Future<AddFileResult?> showAddFileDialog({
  required BuildContext context,
  required AppState state,
  required Topic topic,
}) {
  return showAppDialog<AddFileResult>(
    context: context,
    builder: (_) => _AddFileDialog(state: state, topic: topic),
  );
}

class _AddFileDialog extends StatefulWidget {
  const _AddFileDialog({required this.state, required this.topic});

  final AppState state;
  final Topic topic;

  @override
  State<_AddFileDialog> createState() => _AddFileDialogState();
}

class _AddFileDialogState extends State<_AddFileDialog> {
  final _nameController = TextEditingController(text: 'Document');
  var _isEssence = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  int get _essenceCount {
    final files = widget.state.selectedDetail?.files ?? const [];
    return widget.state.mainFilesFor(widget.topic, files).length;
  }

  bool get _canAddEssence => _essenceCount < 3;

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (_isEssence && !_canAddEssence) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.state.strings['essenceMaxReached'])),
      );
      return;
    }
    Navigator.pop(
      context,
      AddFileResult(name: name, isEssence: _isEssence),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;

    return AppGlassDialog(
      title: Text(s['addFile']),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s['cancel'])),
        FilledButton(onPressed: _submit, child: Text(s['create'])),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: DialogFieldStyle.decoration(hintText: s['fileName']),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(s['additionalFile'])),
              ButtonSegment(
                value: true,
                label: Text(s['essenceFile']),
                enabled: _canAddEssence,
              ),
            ],
            selected: {_isEssence},
            onSelectionChanged: (selected) {
              setState(() => _isEssence = selected.first);
            },
          ),
          if (!_canAddEssence)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                s['essenceMaxReached'],
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
