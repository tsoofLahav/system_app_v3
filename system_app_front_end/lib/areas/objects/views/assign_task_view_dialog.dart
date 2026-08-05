import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_field_style.dart';
import '../data/app_view.dart';

/// Pick exactly one view for a task (replaces any previous view).
Future<void> showAssignTaskViewDialog({
  required BuildContext context,
  required AppState state,
  required int taskId,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (_) => _AssignTaskViewDialog(state: state, taskId: taskId),
  );
}

class _AssignTaskViewDialog extends StatefulWidget {
  const _AssignTaskViewDialog({
    required this.state,
    required this.taskId,
  });

  final AppState state;
  final int taskId;

  @override
  State<_AssignTaskViewDialog> createState() => _AssignTaskViewDialogState();
}

class _AssignTaskViewDialogState extends State<_AssignTaskViewDialog> {
  var _loading = true;
  int? _selectedViewId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await widget.state.loadTaskMemberships(widget.taskId);
    if (!mounted) return;
    setState(() {
      _selectedViewId = rows.isEmpty ? null : rows.first.viewId;
      _loading = false;
    });
  }

  Future<void> _select(AppView? view) async {
    final nextId = view?.id;
    if (nextId == _selectedViewId) return;
    final previous = _selectedViewId;
    setState(() => _selectedViewId = nextId);
    try {
      await widget.state.setTaskView(widget.taskId, nextId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _selectedViewId = previous);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final views = widget.state.userViews;

    return AppAdaptiveDialogShell(
      title: Text(s['assignTaskViews']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['ok']),
        ),
      ],
      child: _loading
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s['chooseViewHint'],
                  style: AppTypography.metaStyle.copyWith(
                    color: AppColors.textHint,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: DialogFieldStyle.fieldGap),
                if (views.isEmpty)
                  Text(s['noViewsYet'], style: AppTypography.noteBodyStyle)
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        _ViewChoiceTile(
                          label: s['noView'],
                          selected: _selectedViewId == null,
                          onTap: () => _select(null),
                        ),
                        for (final view in views)
                          _ViewChoiceTile(
                            label: view.name,
                            selected: _selectedViewId == view.id,
                            onTap: () => _select(view),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ViewChoiceTile extends StatelessWidget {
  const _ViewChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: AppTypography.noteBodyStyle),
      trailing: selected
          ? AppIcon(
              AppIcons.check,
              size: 18,
              color: AppColors.primary,
            )
          : const SizedBox(width: 18),
      onTap: onTap,
    );
  }
}
