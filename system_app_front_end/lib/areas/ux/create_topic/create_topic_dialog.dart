import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/topic.dart';
import '../topic/topic_appearance.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_segmented_toggle.dart';
import '../../ui/dialog_field_style.dart';
import './topic_color_dialog.dart';
import './topic_emoji_dialog.dart';

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

    return AppAdaptiveDialogShell(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogField(
            label: s['name'],
            child: TextField(
              controller: _nameController,
              decoration: DialogFieldStyle.decoration(),
              autofocus: !isEdit,
            ),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogChoiceField<String>(
            label: s['type'],
            // A topic's type decides where it files itself in the sidebar, so
            // it is settled once, at creation.
            enabled: !isEdit,
            options: [
              for (final type in const ['project', 'process', 'area', 'other'])
                AppSegmentedOption(value: type, label: s.topicTypeLabel(type)),
            ],
            selected: _type,
            onSelected: (type) => setState(() => _type = type),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogPickerField(
            label: s['emoji'],
            preview: Text(_icon, style: const TextStyle(fontSize: 15)),
            valueLabel: s['chooseEmoji'],
            onTap: _pickEmoji,
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogPickerField(
            label: s['color'],
            preview: _ColorDot(color: _pickerColor),
            valueLabel: s['chooseColor'],
            onTap: _pickColor,
          ),
        ],
      ),
    );
  }

  Future<void> _pickEmoji() async {
    final picked = await showTopicEmojiDialog(
      context: context,
      strings: widget.state.strings,
      selected: _icon,
    );
    if (picked == null || !mounted) return;
    setState(() => _icon = picked);
  }

  Future<void> _pickColor() async {
    final picked = await showTopicColorDialog(
      context: context,
      strings: widget.state.strings,
      selectedHex: _colorHex,
    );
    if (picked == null || !mounted) return;
    setState(() => _pickerColor = TopicAppearance.colorFromHex(picked));
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.7),
          width: 0.8,
        ),
      ),
    );
  }
}
