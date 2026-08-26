import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_field_style.dart';
import '../../ux/dialogs/dialog_choice_list.dart';
import '../data/app_view.dart';

var _assignTaskViewDialogOpen = false;

/// Pick exactly one view for the given tasks (replaces any previous view).
Future<void> showAssignTaskViewDialog({
  required BuildContext context,
  required AppState state,
  required List<int> taskIds,
}) async {
  if (taskIds.isEmpty) return;
  if (_assignTaskViewDialogOpen) return;
  _assignTaskViewDialogOpen = true;
  try {
    await showAppDialog<void>(
      context: context,
      builder: (_) => _AssignTaskViewDialog(state: state, taskIds: taskIds),
    );
  } finally {
    _assignTaskViewDialogOpen = false;
  }
}

class _AssignTaskViewDialog extends StatefulWidget {
  const _AssignTaskViewDialog({required this.state, required this.taskIds});

  final AppState state;
  final List<int> taskIds;

  @override
  State<_AssignTaskViewDialog> createState() => _AssignTaskViewDialogState();
}

class _AssignTaskViewDialogState extends State<_AssignTaskViewDialog> {
  var _loading = true;
  int? _selectedViewId;
  var _mixed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    int? shared;
    var mixed = false;
    for (var i = 0; i < widget.taskIds.length; i++) {
      final rows = await widget.state.loadTaskMemberships(widget.taskIds[i]);
      final viewId = rows.isEmpty ? null : rows.first.viewId;
      if (i == 0) {
        shared = viewId;
      } else if (viewId != shared) {
        mixed = true;
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _mixed = mixed;
      _selectedViewId = mixed ? null : shared;
      _loading = false;
    });
  }

  List<AppView?> get _choices => [null, ...widget.state.userViews];

  int get _initialIndex {
    if (_mixed) return 0;
    final id = _selectedViewId;
    if (id == null) return 0;
    final i = widget.state.userViews.indexWhere((v) => v.id == id);
    return i < 0 ? 0 : i + 1;
  }

  Future<void> _select(AppView? view) async {
    final nextId = view?.id;
    if (!_mixed && nextId == _selectedViewId) return;
    final previous = _selectedViewId;
    final wasMixed = _mixed;
    setState(() {
      _selectedViewId = nextId;
      _mixed = false;
    });
    try {
      await widget.state.setTaskViews(widget.taskIds, nextId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectedViewId = previous;
        _mixed = wasMixed;
      });
    }
  }

  String _label(AppView? view) {
    return view?.name ?? widget.state.strings['noView'];
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
                  DialogChoiceList(
                    itemCount: _choices.length,
                    initialIndex: _initialIndex,
                    maxHeight: 280,
                    onTap: (i) => _select(_choices[i]),
                    onActivate: (i) async {
                      await _select(_choices[i]);
                      if (context.mounted) Navigator.pop(context);
                    },
                    itemBuilder: (context, i, _) {
                      final view = _choices[i];
                      final selected = !_mixed && view?.id == _selectedViewId;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _label(view),
                                style: AppTypography.noteBodyStyle,
                              ),
                            ),
                            selected
                                ? AppIcon(
                                    AppIcons.check,
                                    size: 18,
                                    color: AppColors.primary,
                                  )
                                : const SizedBox(width: 18),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}
