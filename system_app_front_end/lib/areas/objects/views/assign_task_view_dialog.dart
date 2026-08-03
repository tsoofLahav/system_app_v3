import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../data/app_view.dart';

/// Small checklist of views for one task — tap to assign / unassign.
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
  final _assigned = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await widget.state.loadTaskMemberships(widget.taskId);
    if (!mounted) return;
    setState(() {
      _assigned
        ..clear()
        ..addAll([for (final m in rows) m.viewId]);
      _loading = false;
    });
  }

  Future<void> _toggle(AppView view) async {
    final on = _assigned.contains(view.id);
    setState(() {
      if (on) {
        _assigned.remove(view.id);
      } else {
        _assigned.add(view.id);
      }
    });
    try {
      if (on) {
        await widget.state.removeTaskFromView(widget.taskId, view.id);
      } else {
        await widget.state.assignTaskToView(widget.taskId, view.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (on) {
          _assigned.add(view.id);
        } else {
          _assigned.remove(view.id);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final views = widget.state.userViews;

    return AppAdaptiveDialogShell(
      title: Text(s['assignTaskViews']),
      width: 360,
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
          : views.isEmpty
              ? Text(s['noViewsYet'], style: AppTypography.noteBodyStyle)
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final view in views)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(view.name, style: AppTypography.noteBodyStyle),
                          trailing: Icon(
                            _assigned.contains(view.id)
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            color: _assigned.contains(view.id)
                                ? AppColors.primary
                                : AppColors.textHint,
                            size: 22,
                          ),
                          onTap: () => _toggle(view),
                        ),
                    ],
                  ),
                ),
    );
  }
}
