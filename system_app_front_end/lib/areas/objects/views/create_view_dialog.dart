import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../data/app_view.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/dialog_field_style.dart';

/// Name-only create / rename dialog for a user task view.
Future<String?> showCreateViewDialog({
  required BuildContext context,
  required AppState state,
  AppView? view,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (_) => _CreateViewDialog(state: state, view: view),
  );
}

class _CreateViewDialog extends StatefulWidget {
  const _CreateViewDialog({required this.state, this.view});

  final AppState state;
  final AppView? view;

  bool get isEdit => view != null;

  @override
  State<_CreateViewDialog> createState() => _CreateViewDialogState();
}

class _CreateViewDialogState extends State<_CreateViewDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.view?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final isEdit = widget.isEdit;
    return AppAdaptiveDialogShell(
      title: Text(isEdit ? s['editView'] : s['newView']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEdit ? s['save'] : s['create']),
        ),
      ],
      child: AppDialogField(
        label: s['name'],
        child: TextField(
          controller: _nameController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: DialogFieldStyle.decoration(hintText: s['newViewHint']),
        ),
      ),
    );
  }
}
