import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../core/app_state.dart';
import '../../core/models/topic.dart';
import '../../core/registry/file_registry.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import 'icon_category_picker.dart';

class CreateTopicResult {
  CreateTopicResult({
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    required this.selectedFileTypes,
  });

  final String name;
  final String type;
  final String icon;
  final String color;
  final List<String> selectedFileTypes;
}

class EditTopicResult {
  EditTopicResult({
    required this.name,
    required this.icon,
    required this.color,
  });

  final String name;
  final String icon;
  final String color;
}

class CreateTopicDialog extends StatefulWidget {
  const CreateTopicDialog({super.key, required this.state, this.topic});

  final AppState state;
  final Topic? topic;

  bool get isEdit => topic != null;

  @override
  State<CreateTopicDialog> createState() => _CreateTopicDialogState();
}

class _CreateTopicDialogState extends State<CreateTopicDialog> {
  final _nameController = TextEditingController();
  late String _type;
  late String _icon;
  late Color _pickerColor;
  late Set<String> _selectedFileTypes;

  String get _colorHex => TopicAppearance.hexFromColor(_pickerColor);

  @override
  void initState() {
    super.initState();
    final topic = widget.topic;
    if (topic != null) {
      _nameController.text = topic.name;
      _type = topic.type;
      _icon = topic.icon ?? TopicAppearance.defaultEmoji;
      _pickerColor = TopicAppearance.colorFromHex(topic.color);
      _selectedFileTypes = {};
    } else {
      _type = 'project';
      _icon = TopicAppearance.defaultEmoji;
      _pickerColor = TopicAppearance.colorFromHex(TopicAppearance.defaultColor);
      _selectedFileTypes = FileRegistry.recommendedForTopicType(
        _type,
      ).map((f) => f.type).toSet();
    }
  }

  void _onTypeChanged(String? value) {
    if (value == null) return;
    setState(() {
      _type = value;
      _selectedFileTypes = FileRegistry.recommendedForTopicType(
        _type,
      ).map((f) => f.type).toSet();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final files = FileRegistry.recommendedForTopicType(_type);
    final isEdit = widget.isEdit;

    return AppGlassDialog(
      width: 520,
      title: Text(isEdit ? s['editTopic'] : s['newTopic']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            if (isEdit) {
              Navigator.pop(
                context,
                EditTopicResult(name: name, icon: _icon, color: _colorHex),
              );
            } else {
              if (_selectedFileTypes.isEmpty) return;
              Navigator.pop(
                context,
                CreateTopicResult(
                  name: name,
                  type: _type,
                  icon: _icon,
                  color: _colorHex,
                  selectedFileTypes: _selectedFileTypes.toList(),
                ),
              );
            }
          },
          child: Text(isEdit ? s['save'] : s['create']),
        ),
      ],
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(labelText: s['name']),
                autofocus: true,
              ),
              if (!isEdit) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: InputDecoration(labelText: s['type']),
                  items: [
                    DropdownMenuItem(
                      value: 'project',
                      child: Text(s.topicTypeLabel('project')),
                    ),
                    DropdownMenuItem(
                      value: 'process',
                      child: Text(s.topicTypeLabel('process')),
                    ),
                    DropdownMenuItem(
                      value: 'area',
                      child: Text(s.topicTypeLabel('area')),
                    ),
                  ],
                  onChanged: _onTypeChanged,
                ),
              ],
              const SizedBox(height: 16),
              Text(s['emoji'], style: AppTypography.metaStyle),
              const SizedBox(height: 8),
              IconCategoryPicker(
                selectedId: _icon,
                searchHint: s['searchEmoji'],
                onSelected: (id) => setState(() => _icon = id),
              ),
              const SizedBox(height: 16),
              Text(s['color'], style: AppTypography.metaStyle),
              const SizedBox(height: 8),
              ColorPicker(
                pickerColor: _pickerColor,
                onColorChanged: (c) => setState(() => _pickerColor = c),
                colorPickerWidth: 280,
                pickerAreaHeightPercent: 0.7,
                enableAlpha: false,
                displayThumbColor: true,
                labelTypes: const [],
                portraitOnly: true,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TopicAppearance.presetColors.map((hex) {
                  final selected = _colorHex.toUpperCase() == hex.toUpperCase();
                  return GestureDetector(
                    onTap: () => setState(
                      () => _pickerColor = TopicAppearance.colorFromHex(hex),
                    ),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: TopicAppearance.colorFromHex(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? Colors.black54 : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (!isEdit) ...[
                const SizedBox(height: 16),
                Text(s['filesToInclude'], style: AppTypography.metaStyle),
                ...files.map(
                  (file) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      s.fileNameLabel(file.name),
                      style: AppTypography.noteBodyStyle,
                    ),
                    subtitle: Text(
                      s.fileTypeLabel(file.type),
                      style: AppTypography.metaStyle,
                    ),
                    value: _selectedFileTypes.contains(file.type),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedFileTypes.add(file.type);
                        } else {
                          _selectedFileTypes.remove(file.type);
                        }
                      });
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
