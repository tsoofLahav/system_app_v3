import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/color_dialog.dart';
import '../../ui/dialog_field_style.dart';
import '../data/view_layout.dart';
import '../data/view_section_flags.dart';

Future<ViewSectionDef?> showEditViewSectionDialog({
  required BuildContext context,
  required AppState state,
  required ViewSectionDef section,
}) {
  return showAppDialog<ViewSectionDef>(
    context: context,
    builder: (ctx) => _EditViewSectionDialog(state: state, section: section),
  );
}

class _EditViewSectionDialog extends StatefulWidget {
  const _EditViewSectionDialog({
    required this.state,
    required this.section,
  });

  final AppState state;
  final ViewSectionDef section;

  @override
  State<_EditViewSectionDialog> createState() => _EditViewSectionDialogState();
}

class _EditViewSectionDialogState extends State<_EditViewSectionDialog> {
  late final TextEditingController _name;
  late bool _important;
  String? _colorHex;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.section.name);
    _important = sectionFlagIsImportant(widget.section.flag);
    _colorHex = widget.section.colorHex;
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

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    return AppAdaptiveDialogShell(
      title: Text(s['editSection']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              widget.section.copyWith(
                name: name,
                flag: _important ? ViewSectionFlags.important : null,
                clearFlag: !_important,
                colorHex: _colorHex,
                clearColor: _colorHex == null || _colorHex!.isEmpty,
              ),
            );
          },
          child: Text(s['save']),
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
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(s['markSectionImportant']),
            value: _important,
            onChanged: (v) => setState(() => _important = v),
          ),
          const SizedBox(height: 4),
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
