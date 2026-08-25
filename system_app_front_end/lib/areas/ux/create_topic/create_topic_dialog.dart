import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/topic.dart';
import '../topic/topic_appearance.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_icons.dart';
import '../../ui/dialog_field_style.dart';
import '../dialogs/dialog_choice_list.dart';
import './topic_color_dialog.dart';
import './topic_emoji_dialog.dart';

class CreateTopicResult {
  CreateTopicResult({
    required this.name,
    required this.topicTypeId,
    required this.icon,
    required this.color,
  });

  final String name;
  final int? topicTypeId;
  final String icon;
  final String color;
}

class EditTopicResult {
  EditTopicResult({
    required this.name,
    required this.icon,
    required this.color,
    required this.topicTypeId,
  });

  final String name;
  final String icon;
  final String color;
  final int? topicTypeId;
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
  int? _topicTypeId;
  late String _icon;
  late Color _pickerColor;

  String get _colorHex => TopicAppearance.hexFromColor(_pickerColor);

  @override
  void initState() {
    super.initState();
    final topic = widget.topic;
    if (topic != null) {
      _nameController.text = topic.name;
      _topicTypeId = topic.topicTypeId;
      _icon = topic.icon ?? TopicAppearance.defaultEmoji;
      _pickerColor = TopicAppearance.colorFromHex(topic.color);
    } else {
      _topicTypeId = widget.state.topicTypes.firstOrNull?.id;
      _icon = TopicAppearance.defaultEmoji;
      _pickerColor = TopicAppearance.colorFromHex(TopicAppearance.defaultColor);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _typeLabel(int? id) {
    final s = widget.state.strings;
    if (id == null) return s['untyped'];
    final type = widget.state.topicTypeById(id);
    return type == null
        ? s['untyped']
        : widget.state.topicTypeDisplayName(type);
  }

  Future<void> _pickType() async {
    final s = widget.state.strings;
    final types = widget.state.topicTypes;
    final rows = <({int? id, String label})>[
      (id: null, label: s['untyped']),
      for (final type in types)
        (id: type.id, label: widget.state.topicTypeDisplayName(type)),
    ];
    var initial = 0;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].id == _topicTypeId) {
        initial = i;
        break;
      }
    }
    final picked = await showAppChoiceDialog<({int? id, String label})>(
      context: context,
      title: s['type'],
      cancelLabel: s['cancel'],
      items: rows,
      initialIndex: initial,
      itemBuilder: (context, row, _) => DialogChoiceText(row.label),
    );
    if (picked == null || !mounted) return;
    setState(() => _topicTypeId = picked.id);
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (widget.isEdit) {
      Navigator.pop(
        context,
        EditTopicResult(
          name: name,
          icon: _icon,
          color: _colorHex,
          topicTypeId: _topicTypeId,
        ),
      );
    } else {
      Navigator.pop(
        context,
        CreateTopicResult(
          name: name,
          topicTypeId: _topicTypeId,
          icon: _icon,
          color: _colorHex,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final isEdit = widget.isEdit;

    return AppAdaptiveDialogShell(
      title: Text(isEdit ? s['editTopic'] : s['newTopic']),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogField(
            label: s['name'],
            child: TextField(
              controller: _nameController,
              decoration: DialogFieldStyle.decoration(),
              autofocus: !isEdit,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
          ),
          if ((!isEdit || widget.topic?.isMain != true) &&
              (widget.state.topicTypes.isNotEmpty || isEdit)) ...[
            const SizedBox(height: DialogFieldStyle.fieldGap),
            AppDialogPickerField(
              label: s['type'],
              preview: const AppIcon(AppIcons.bringFile, size: 16),
              valueLabel: _typeLabel(_topicTypeId),
              onTap: _pickType,
            ),
          ],
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
