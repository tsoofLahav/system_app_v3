import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../data/app_view.dart';
import '../data/view_layout.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_segmented_toggle.dart';
import '../../ui/dialog_field_style.dart';

class CreateViewResult {
  const CreateViewResult({required this.name, required this.cadence});

  final String name;
  final String cadence;
}

/// Name + repeating / one-time for a user task view.
Future<CreateViewResult?> showCreateViewDialog({
  required BuildContext context,
  required AppState state,
  AppView? view,
}) {
  return showAppDialog<CreateViewResult>(
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
  late String _cadence;

  @override
  void initState() {
    super.initState();
    final view = widget.view;
    _nameController = TextEditingController(text: view?.name ?? '');
    _cadence = view == null
        ? ViewSectionCadence.routine
        : ViewLayoutConfig.cadence(view.layoutConfig);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, CreateViewResult(name: name, cadence: _cadence));
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogField(
            label: s['name'],
            child: TextField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: DialogFieldStyle.decoration(hintText: s['newViewHint']),
            ),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogChoiceField<String>(
            label: s['viewCadence'],
            options: [
              AppSegmentedOption(
                value: ViewSectionCadence.routine,
                label: s['viewCadenceRepeating'],
              ),
              AppSegmentedOption(
                value: ViewSectionCadence.oneTime,
                label: s['viewCadenceOneTime'],
              ),
            ],
            selected: _cadence,
            onSelected: (value) => setState(() => _cadence = value),
          ),
        ],
      ),
    );
  }
}
