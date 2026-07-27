import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/topic.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/dialog_field_style.dart';
import '../../ui/glass_surface.dart';

/// Only a name. How prominent the file is comes from where it sits in the
/// topic's order, which the user changes by arranging — not from a choice made
/// once at creation.
class AddFileResult {
  const AddFileResult({required this.name});

  final String name;
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

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, AddFileResult(name: name));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;

    return AppGlassDialog(
      title: Text(s['addFile']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        FilledButton(onPressed: _submit, child: Text(s['create'])),
      ],
      child: TextField(
        controller: _nameController,
        autofocus: true,
        decoration: DialogFieldStyle.decoration(hintText: s['fileName']),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}
