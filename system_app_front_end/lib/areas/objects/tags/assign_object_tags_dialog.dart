import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/models/tag.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ux/topic/topic_appearance.dart';
import '../data/object_embed.dart';

Future<void> showAssignObjectTagsDialog({
  required BuildContext context,
  required AppState state,
  required ObjectEmbed embed,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (_) => _AssignObjectTagsDialog(state: state, embed: embed),
  );
}

class _AssignObjectTagsDialog extends StatefulWidget {
  const _AssignObjectTagsDialog({
    required this.state,
    required this.embed,
  });

  final AppState state;
  final ObjectEmbed embed;

  @override
  State<_AssignObjectTagsDialog> createState() =>
      _AssignObjectTagsDialogState();
}

class _AssignObjectTagsDialogState extends State<_AssignObjectTagsDialog> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {for (final t in widget.embed.tags) t.id};
  }

  Future<void> _toggle(AppTag tag) async {
    setState(() {
      if (_selected.contains(tag.id)) {
        _selected.remove(tag.id);
      } else {
        _selected.add(tag.id);
      }
    });
    await widget.state.setObjectTags(widget.embed, _selected.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final tags = widget.state.objectTags;

    return AppAdaptiveDialogShell(
      title: Text(s['addTag']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['ok']),
        ),
      ],
      child: tags.isEmpty
          ? Text(s['noTagsYet'], style: AppTypography.noteBodyStyle)
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final tag in tags)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Text(
                        tag.icon?.isNotEmpty == true
                            ? tag.icon!
                            : TopicAppearance.defaultEmoji,
                        style: const TextStyle(fontSize: 18),
                      ),
                      title: Text(tag.name, style: AppTypography.noteBodyStyle),
                      trailing: Icon(
                        _selected.contains(tag.id)
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        color: _selected.contains(tag.id)
                            ? AppColors.primary
                            : AppColors.textHint,
                        size: 22,
                      ),
                      onTap: () => unawaited(_toggle(tag)),
                    ),
                ],
              ),
            ),
    );
  }
}
