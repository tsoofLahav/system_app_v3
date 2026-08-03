import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/color_dialog.dart';
import '../../ui/dialog_field_style.dart';
import '../data/view_layout.dart';
import '../data/view_section_flags.dart';

/// Create or edit a view section (name, important flag icon, color).
Future<ViewSectionDef?> showViewSectionDialog({
  required BuildContext context,
  required AppState state,
  ViewSectionDef? section,
  String? viewLabel,
}) {
  return showAppDialog<ViewSectionDef>(
    context: context,
    builder: (ctx) => _ViewSectionDialog(
      state: state,
      section: section,
      viewLabel: viewLabel,
    ),
  );
}

/// Backward-compatible alias for edit.
Future<ViewSectionDef?> showEditViewSectionDialog({
  required BuildContext context,
  required AppState state,
  required ViewSectionDef section,
}) {
  return showViewSectionDialog(
    context: context,
    state: state,
    section: section,
  );
}

class _ViewSectionDialog extends StatefulWidget {
  const _ViewSectionDialog({
    required this.state,
    this.section,
    this.viewLabel,
  });

  final AppState state;
  final ViewSectionDef? section;
  final String? viewLabel;

  @override
  State<_ViewSectionDialog> createState() => _ViewSectionDialogState();
}

class _ViewSectionDialogState extends State<_ViewSectionDialog> {
  late final TextEditingController _name;
  late bool _important;
  String? _colorHex;

  bool get _isCreate => widget.section == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.section?.name ?? '');
    _important = sectionFlagIsImportant(widget.section?.flag);
    _colorHex = widget.section?.colorHex;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final picked = await showAppColorDialog(
      context: context,
      strings: widget.state.strings,
      selectedHex: _colorHex ?? AppColors.colorToHex(AppColors.primary),
    );
    if (picked == null || !mounted) return;
    setState(() => _colorHex = picked);
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final base = widget.section ?? ViewSectionDef(name: name);
    Navigator.pop(
      context,
      base.copyWith(
        name: name,
        flag: _important ? ViewSectionFlags.important : null,
        clearFlag: !_important,
        colorHex: _colorHex,
        clearColor: _colorHex == null || _colorHex!.isEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final title = _isCreate
        ? (widget.viewLabel == null
            ? s['addSection']
            : s.newSectionTitle(widget.viewLabel!))
        : s['editSection'];

    return AppAdaptiveDialogShell(
      title: Text(title),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isCreate ? s['add'] : s['save']),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogField(
            label: s['sectionName'],
            child: TextField(
              controller: _name,
              autofocus: true,
              decoration: DialogFieldStyle.decoration(),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Tooltip(
                message: _important
                    ? s['unmarkSectionImportant']
                    : s['markSectionImportant'],
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _important = !_important),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: AppIcon(
                      AppIcons.flag,
                      size: 22,
                      color: _important
                          ? AppColors.primary
                          : AppColors.textHint.withValues(alpha: 0.42),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s['sectionImportant'],
                  style: AppTypography.metaStyle.copyWith(
                    color: AppColors.text.withValues(alpha: 0.78),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AppIcon(AppIcons.colorWheel, size: 18),
            title: Text(s['sectionColor']),
            trailing: _colorHex == null
                ? Text(
                    s['noColor'],
                    style: TextStyle(color: AppColors.textHint),
                  )
                : Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.colorFromHex(_colorHex),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.noteBorder),
                    ),
                  ),
            onTap: _pickColor,
          ),
          if (_colorHex != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => setState(() => _colorHex = null),
                child: Text(s['clearSectionColor']),
              ),
            ),
        ],
      ),
    );
  }
}
