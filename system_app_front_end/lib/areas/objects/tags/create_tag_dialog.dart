import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/dialog_field_style.dart';
import '../../ux/create_topic/topic_color_dialog.dart';
import '../../ux/create_topic/topic_emoji_dialog.dart';
import '../../ux/topic/topic_appearance.dart';

class CreateTagResult {
  const CreateTagResult({
    required this.name,
    required this.icon,
    required this.color,
  });

  final String name;
  final String icon;
  final String color;
}

Future<CreateTagResult?> showCreateTagDialog({
  required BuildContext context,
  required AppState state,
}) {
  return showAppDialog<CreateTagResult>(
    context: context,
    builder: (_) => _CreateTagDialog(state: state),
  );
}

class _CreateTagDialog extends StatefulWidget {
  const _CreateTagDialog({required this.state});

  final AppState state;

  @override
  State<_CreateTagDialog> createState() => _CreateTagDialogState();
}

class _CreateTagDialogState extends State<_CreateTagDialog> {
  final _name = TextEditingController();
  late String _icon;
  late Color _pickerColor;

  String get _colorHex => TopicAppearance.hexFromColor(_pickerColor);

  @override
  void initState() {
    super.initState();
    _icon = TopicAppearance.defaultEmoji;
    _pickerColor = TopicAppearance.colorFromHex(TopicAppearance.defaultColor);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
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

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      CreateTagResult(name: name, icon: _icon, color: _colorHex),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    return AppAdaptiveDialogShell(
      title: Text(s['newTag']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        FilledButton(onPressed: _submit, child: Text(s['create'])),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogField(
            label: s['name'],
            child: TextField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: DialogFieldStyle.decoration(),
            ),
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
            preview: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: _pickerColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.noteBorder.withValues(alpha: 0.6),
                ),
              ),
            ),
            valueLabel: s['chooseColor'],
            onTap: _pickColor,
          ),
        ],
      ),
    );
  }
}
