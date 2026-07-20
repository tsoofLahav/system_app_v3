import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/topic.dart';
import '../../core/registry/file_registry.dart';
import '../../design_system/adaptive_dialog.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';

Future<AddFileResult?> showAddFileDialog({
  required BuildContext context,
  required AppState state,
  required Topic topic,
  required List<String> existingTypes,
}) {
  return showAppDialog<AddFileResult>(
    context: context,
    builder: (_) => AddFileDialog(
      state: state,
      topic: topic,
      existingTypes: existingTypes,
    ),
  );
}

class AddFileResult {
  AddFileResult({required this.type, required this.name});
  final String type;
  final String name;
}

class AddFileDialog extends StatefulWidget {
  const AddFileDialog({
    super.key,
    required this.state,
    required this.topic,
    required this.existingTypes,
  });

  final AppState state;
  final Topic topic;
  final List<String> existingTypes;

  @override
  State<AddFileDialog> createState() => _AddFileDialogState();
}

class _AddFileDialogState extends State<AddFileDialog> {
  late final List<RecommendedFile> _options;
  late String _type;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _options = FileRegistry.allowedFilesForTopic(
      topicType: widget.topic.type,
      isMainTopic: widget.topic.isMain,
      existingTypes: widget.existingTypes,
    );
    _type = _options.first.type;
    _nameController = TextEditingController(
      text: FileRegistry.defaultNameForType(
        _type,
        isMainTopic: widget.topic.isMain,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;

    if (_options.isEmpty) {
      return AppAdaptiveDialogShell(
        title: Text(s['addFile']),
        width: 480,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s['ok']),
          ),
        ],
        child: Text(s['allFilesExist']),
      );
    }

    return AppAdaptiveDialogShell(
      title: Text(s['addFile']),
      width: 480,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, AddFileResult(type: _type, name: name));
          },
          child: Text(s['add']),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: InputDecoration(labelText: s['type']),
                dropdownColor: AppColors.noteTop.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(14),
                elevation: 6,
                menuMaxHeight: 280,
                itemHeight: null,
                style: AppTypography.noteBodyStyle.copyWith(
                  color: AppColors.text.withValues(alpha: 0.92),
                  fontSize: 12,
                ),
                items: _options
                    .map(
                      (o) => DropdownMenuItem(
                        value: o.type,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(s.fileTypeOption(o.name, o.type)),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _type = value;
                    _nameController.text = FileRegistry.defaultNameForType(
                      _type,
                      isMainTopic: widget.topic.isMain,
                    );
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: s['name']),
          ),
        ],
      ),
    );
  }
}
