import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/topic.dart';
import '../../core/registry/file_registry.dart';
import '../../design_system/glass_surface.dart';

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
      return AppGlassDialog(
        title: Text(s['addFile']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s['ok']),
          ),
        ],
        child: Text(s['allFilesExist']),
      );
    }

    return AppGlassDialog(
      title: Text(s['addFile']),
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
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: InputDecoration(labelText: s['type']),
            items: _options
                .map(
                  (o) => DropdownMenuItem(
                    value: o.type,
                    child: Text(s.fileTypeOption(o.name, o.type)),
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
