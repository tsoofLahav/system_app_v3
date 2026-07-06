import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../core/app_state.dart';
import '../../core/models/topic.dart';
import '../../core/registry/file_registry.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
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

  InputDecoration _fieldDecoration({String? hintText}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: AppColors.noteBorder.withValues(alpha: 0.68),
        width: 0.85,
      ),
    );
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.54),
          width: 0.9,
        ),
      ),
      border: border,
    );
  }

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

  Future<void> _chooseEmoji() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        width: 420,
        title: Text(widget.state.strings['chooseEmoji']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(widget.state.strings['cancel']),
          ),
        ],
        child: IconCategoryPicker(
          selectedId: _icon,
          searchHint: widget.state.strings['searchEmoji'],
          onSelected: (id) => Navigator.pop(ctx, id),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _icon = picked);
  }

  Future<void> _chooseCustomColor() async {
    var draft = _pickerColor;
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        width: 420,
        title: Text(widget.state.strings['chooseColor']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(widget.state.strings['cancel']),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, draft),
            child: Text(widget.state.strings['choose']),
          ),
        ],
        child: ColorPicker(
          pickerColor: draft,
          onColorChanged: (c) => draft = c,
          colorPickerWidth: 280,
          pickerAreaHeightPercent: 0.7,
          enableAlpha: false,
          displayThumbColor: true,
          labelTypes: const [],
          portraitOnly: true,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _pickerColor = picked);
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
      width: 360,
      title: Text(isEdit ? s['editTopic'] : s['newTopic']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        OutlinedButton(
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
              const SizedBox(height: 6),
              Text(s['name'], style: AppTypography.metaStyle),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                decoration: _fieldDecoration(hintText: '...'),
                autofocus: true,
              ),
              if (!isEdit) ...[
                const SizedBox(height: 12),
                Text(s['type'], style: AppTypography.metaStyle),
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: _fieldDecoration(),
                      dropdownColor: AppColors.noteTop.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(14),
                      elevation: 6,
                      menuMaxHeight: 280,
                      itemHeight: null,
                      style: AppTypography.noteBodyStyle.copyWith(
                        color: AppColors.text.withValues(alpha: 0.92),
                        fontSize: 12,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'project',
                          child: _DialogDropdownItem(
                            s.topicTypeLabel('project'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'process',
                          child: _DialogDropdownItem(
                            s.topicTypeLabel('process'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'area',
                          child: _DialogDropdownItem(s.topicTypeLabel('area')),
                        ),
                      ],
                      onChanged: _onTypeChanged,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(s['emoji'], style: AppTypography.metaStyle),
              const SizedBox(height: 6),
              _ChooserSummaryRow(
                selected: _EmojiPreview(icon: _icon),
                action: _ChooserIconButton(
                  onPressed: _chooseEmoji,
                  icon: AppIcons.smiley,
                ),
              ),
              const SizedBox(height: 12),
              Text(s['color'], style: AppTypography.metaStyle),
              const SizedBox(height: 6),
              _ChooserSummaryRow(
                selected: _ColorDot(
                  color: _pickerColor,
                  selected: true,
                  size: 20,
                ),
                action: _ChooserIconButton(
                  onPressed: _chooseCustomColor,
                  icon: AppIcons.colorWheel,
                ),
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
                    child: _ColorDot(
                      color: TopicAppearance.colorFromHex(hex),
                      selected: selected,
                      size: 20,
                    ),
                  );
                }).toList(),
              ),
              if (!isEdit) ...[
                const SizedBox(height: 12),
                Text(s['filesToInclude'], style: AppTypography.metaStyle),
                const SizedBox(height: 8),
                ...files.map(
                  (file) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Transform.scale(
                          scale: 0.86,
                          child: Checkbox(
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            value: _selectedFileTypes.contains(file.type),
                            checkColor: AppColors.text,
                            fillColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.selected)) {
                                return AppColors.primary.withValues(
                                  alpha: 0.10,
                                );
                              }
                              return Colors.transparent;
                            }),
                            overlayColor: WidgetStateProperty.all(
                              AppColors.primary.withValues(alpha: 0.08),
                            ),
                            side: BorderSide(
                              color: AppColors.text.withValues(alpha: 0.54),
                              width: 0.85,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
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
                        const SizedBox(width: 8),
                        Text(
                          s.fileNameLabel(file.name),
                          style: AppTypography.noteBodyStyle,
                        ),
                      ],
                    ),
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

class _ChooserSummaryRow extends StatelessWidget {
  const _ChooserSummaryRow({required this.selected, required this.action});

  final Widget selected;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          _SelectedValueFrame(child: selected),
          const Spacer(),
          Directionality(
            textDirection: Directionality.of(context),
            child: action,
          ),
          const SizedBox(width: 56),
        ],
      ),
    );
  }
}

class _DialogDropdownItem extends StatelessWidget {
  const _DialogDropdownItem(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(label),
    );
  }
}

class _SelectedValueFrame extends StatelessWidget {
  const _SelectedValueFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
        ),
      ),
      child: child,
    );
  }
}

class _ChooserIconButton extends StatelessWidget {
  const _ChooserIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: onPressed,
      icon: AppIcon(icon, size: 22, color: AppColors.primary),
    );
  }
}

class _EmojiPreview extends StatelessWidget {
  const _EmojiPreview({required this.icon});

  final String icon;

  @override
  Widget build(BuildContext context) {
    return Text(
      TopicAppearance.emojiFromId(icon),
      style: const TextStyle(fontSize: 21),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    this.size = 24,
  });

  final Color color;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? Colors.black54 : Colors.transparent,
          width: 2,
        ),
      ),
    );
  }
}
