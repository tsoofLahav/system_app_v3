import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/app_file.dart';
import '../../core/models/part.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';

class PartNameDialog extends StatefulWidget {
  const PartNameDialog({
    super.key,
    required this.strings,
    this.title,
    this.initialName,
    this.submitLabel,
  });

  final AppStrings strings;
  final String? title;
  final String? initialName;
  final String? submitLabel;

  static Future<String?> show(
    BuildContext context,
    AppStrings strings, {
    String? title,
    String? initialName,
    String? submitLabel,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => PartNameDialog(
        strings: strings,
        title: title,
        initialName: initialName,
        submitLabel: submitLabel,
      ),
    );
  }

  @override
  State<PartNameDialog> createState() => _PartNameDialogState();
}

class _PartNameDialogState extends State<PartNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(widget.title ?? s['addNewPart']),
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
          child: Text(widget.submitLabel ?? s['create']),
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

class ExistingPartPickerDialog extends StatefulWidget {
  const ExistingPartPickerDialog({
    super.key,
    required this.strings,
    required this.state,
    required this.file,
  });

  final AppStrings strings;
  final AppState state;
  final AppFile file;

  static Future<Part?> show(
    BuildContext context, {
    required AppStrings strings,
    required AppState state,
    required AppFile file,
  }) {
    return showDialog<Part>(
      context: context,
      builder: (context) => ExistingPartPickerDialog(
        strings: strings,
        state: state,
        file: file,
      ),
    );
  }

  @override
  State<ExistingPartPickerDialog> createState() =>
      _ExistingPartPickerDialogState();
}

class _ExistingPartPickerDialogState extends State<ExistingPartPickerDialog> {
  late List<Part> _parts;
  late Set<int> _placedPartIds;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _parts = widget.state.partsForFile(widget.file);
    _placedPartIds = widget.state.partIdsPlacedInFile(widget.file);
  }

  Future<void> _refresh() async {
    _reload();
    setState(() {});
  }

  Future<void> _renamePart(Part part) async {
    final name = await PartNameDialog.show(
      context,
      widget.strings,
      title: widget.strings['editPart'],
      initialName: part.name,
      submitLabel: widget.strings['save'],
    );
    if (name == null || name == part.name) return;
    await widget.state.renamePart(part.id, name);
    await _refresh();
  }

  Future<void> _deletePart(Part part) async {
    final s = widget.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        title: Text(s['deletePart']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s['cancel']),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s['delete']),
          ),
        ],
        child: Text(s.deletePartMessage(part.name)),
      ),
    );
    if (ok != true) return;
    await widget.state.archivePart(part.id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(s['addExistingPart']),
      content: SizedBox(
        width: 340,
        child: _parts.isEmpty
            ? Text(s['noPartsAvailable'], style: AppTypography.noteBodyStyle)
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _parts.length,
                itemBuilder: (context, index) {
                  final part = _parts[index];
                  final placed = _placedPartIds.contains(part.id);
                  return ListTile(
                    title: Text(
                      part.name,
                      style: AppTypography.noteBodyStyle,
                    ),
                    subtitle: placed
                        ? Text(
                            s['partAlreadyInFile'],
                            style: AppTypography.metaStyle,
                          )
                        : null,
                    enabled: !placed,
                    onTap: placed ? null : () => Navigator.pop(context, part),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: s['editPart'],
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _renamePart(part),
                        ),
                        IconButton(
                          tooltip: s['deletePart'],
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _deletePart(part),
                        ),
                      ],
                    ),
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
