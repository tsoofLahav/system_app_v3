import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../../core/app_state.dart';
import '../../files/data/topic.dart';
import '../topic/topic_appearance.dart';
import '../../ui/dialog_field_style.dart';
import '../../ui/glass_surface.dart';
import './icon_category_picker.dart';

class CreateTopicResult {
  CreateTopicResult({
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
  });

  final String name;
  final String type;
  final String icon;
  final String color;
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

  String get _colorHex => TopicAppearance.hexFromColor(_pickerColor);

  @override
  void initState() {
    super.initState();
    final topic = widget.topic;
    if (topic != null) {
      _nameController.text = topic.name;
      _type = topic.primaryTag ?? 'project';
      _icon = topic.icon ?? TopicAppearance.defaultEmoji;
      _pickerColor = TopicAppearance.colorFromHex(topic.color);
    } else {
      _type = 'project';
      _icon = TopicAppearance.defaultEmoji;
      _pickerColor = TopicAppearance.colorFromHex(TopicAppearance.defaultColor);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final isEdit = widget.isEdit;

    return AppGlassDialog(
      title: Text(isEdit ? s['editTopic'] : s['newTopic']),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s['cancel'])),
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
              Navigator.pop(
                context,
                CreateTopicResult(
                  name: name,
                  type: _type,
                  icon: _icon,
                  color: _colorHex,
                ),
              );
            }
          },
          child: Text(isEdit ? s['save'] : s['create']),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: DialogFieldStyle.decoration(hintText: s['topicName']),
              autofocus: !isEdit,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: ['project', 'process', 'area', 'other'].map((type) {
                final selected = _type == type;
                return ChoiceChip(
                  label: Text(s.topicTypeLabel(type)),
                  selected: selected,
                  onSelected: isEdit
                      ? null
                      : (v) {
                          if (v) setState(() => _type = type);
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            IconCategoryPicker(
              selectedId: _icon,
              onSelected: (icon) => setState(() => _icon = icon),
            ),
            const SizedBox(height: 12),
            BlockPicker(
              pickerColor: _pickerColor,
              onColorChanged: (c) => setState(() => _pickerColor = c),
            ),
          ],
        ),
      ),
    );
  }
}
