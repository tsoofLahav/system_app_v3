import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/part.dart';
import '../../design_system/app_typography.dart';

class PartNameDialog extends StatefulWidget {
  const PartNameDialog({super.key, required this.strings});

  final AppStrings strings;

  static Future<String?> show(BuildContext context, AppStrings strings) {
    return showDialog<String>(
      context: context,
      builder: (context) => PartNameDialog(strings: strings),
    );
  }

  @override
  State<PartNameDialog> createState() => _PartNameDialogState();
}

class _PartNameDialogState extends State<PartNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(s['addNewPart']),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: s['partName']),
        style: AppTypography.noteBodyStyle,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(s['create']),
        ),
      ],
    );
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }
}

class ExistingPartPickerDialog extends StatelessWidget {
  const ExistingPartPickerDialog({
    super.key,
    required this.strings,
    required this.parts,
  });

  final AppStrings strings;
  final List<Part> parts;

  static Future<Part?> show(
    BuildContext context, {
    required AppStrings strings,
    required List<Part> parts,
  }) {
    return showDialog<Part>(
      context: context,
      builder: (context) =>
          ExistingPartPickerDialog(strings: strings, parts: parts),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return AlertDialog(
      title: Text(s['addExistingPart']),
      content: SizedBox(
        width: 280,
        child: parts.isEmpty
            ? Text(s['noPartsAvailable'], style: AppTypography.noteBodyStyle)
            : ListView.builder(
                shrinkWrap: true,
                itemCount: parts.length,
                itemBuilder: (context, index) {
                  final part = parts[index];
                  return ListTile(
                    title: Text(part.name, style: AppTypography.noteBodyStyle),
                    onTap: () => Navigator.pop(context, part),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
      ],
    );
  }
}
