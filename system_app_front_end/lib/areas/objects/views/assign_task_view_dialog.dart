import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_field_style.dart';
import '../../ux/dialogs/dialog_choice_list.dart';
import '../data/app_view.dart';
import '../data/view_layout.dart';

var _assignTaskViewDialogOpen = false;

/// Pick a view, then a section. Does not change topic or home list.
Future<bool> showAssignTaskViewDialog({
  required BuildContext context,
  required AppState state,
  required List<int> taskIds,
}) async {
  if (taskIds.isEmpty) return false;
  if (_assignTaskViewDialogOpen) return false;
  _assignTaskViewDialogOpen = true;
  try {
    return await showAppDialog<bool>(
          context: context,
          builder: (_) => _AssignTaskViewDialog(state: state, taskIds: taskIds),
        ) ??
        false;
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
  var _applying = false;
  int? _selectedViewId;
  var _mixedViews = false;
  var _noView = false;
  String? _sectionName;
  String? _sectionFlag;
  var _uncategorized = true;
  var _sectionChosen = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    int? sharedView;
    String? sharedSection;
    String? sharedFlag;
    var mixedViews = false;
    var mixedSections = false;
    for (var i = 0; i < widget.taskIds.length; i++) {
      final rows = await state.loadTaskMemberships(widget.taskIds[i]);
      final viewId = rows.isEmpty ? null : rows.first.viewId;
      final section = rows.isEmpty ? null : rows.first.sectionName;
      final flag = rows.isEmpty ? null : rows.first.sectionFlag;
      if (i == 0) {
        sharedView = viewId;
        sharedSection = section;
        sharedFlag = flag;
      } else {
        if (viewId != sharedView) mixedViews = true;
        if (section != sharedSection) mixedSections = true;
      }
    }
    if (!mounted) return;
    setState(() {
      _mixedViews = mixedViews;
      _selectedViewId = mixedViews ? null : sharedView;
      _noView = !mixedViews && sharedView == null;
      if (!mixedViews && _selectedViewId != null) {
        final section = (sharedSection ?? '').trim();
        if (mixedSections || section.isEmpty) {
          _applyDefaultOrUncategorized(_viewFor(_selectedViewId));
        } else {
          _sectionName = section;
          _sectionFlag = sharedFlag;
          _uncategorized = false;
        }
      } else {
        _sectionName = null;
        _sectionFlag = null;
        _uncategorized = true;
      }
      _sectionChosen = !mixedViews && sharedView != null && !mixedSections;
      _loading = false;
    });
  }

  AppView? _viewFor(int? id) {
    if (id == null) return null;
    return state.userViews.where((v) => v.id == id).firstOrNull;
  }

  void _applyDefaultOrUncategorized(AppView? view) {
    if (view == null) {
      _sectionName = null;
      _sectionFlag = null;
      _uncategorized = true;
      return;
    }
    final def = ViewLayoutConfig.defaultSection(view.layoutConfig);
    _sectionName = def?.name;
    _sectionFlag = def?.flag;
    _uncategorized = def == null;
  }

  List<ViewSectionDef> get _sections {
    final view = _viewFor(_selectedViewId);
    if (view == null) return const [];
    return ViewLayoutConfig.sections(view.layoutConfig);
  }

  String get _viewLabel {
    if (_mixedViews && _selectedViewId == null) {
      return state.strings['mixedValues'];
    }
    final view = _viewFor(_selectedViewId);
    return view?.name ?? state.strings['noView'];
  }

  String get _sectionLabel {
    if (_uncategorized || (_sectionName ?? '').isEmpty) {
      return state.strings['uncategorized'];
    }
    return _sectionName!;
  }

  Future<void> _pickView() async {
    final s = state.strings;
    final items = <_ViewChoice>[
      const _ViewChoice(view: null),
      for (final v in state.userViews) _ViewChoice(view: v),
    ];
    final current = _selectedViewId == null
        ? 0
        : items.indexWhere((c) => c.view?.id == _selectedViewId);
    final picked = await showAppChoiceDialog<_ViewChoice>(
      context: context,
      title: s['viewField'],
      cancelLabel: s['cancel'],
      items: items,
      initialIndex: (current < 0 ? 0 : current).clamp(0, items.length - 1),
      itemBuilder: (context, item, _) =>
          DialogChoiceText(item.view?.name ?? s['noView']),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _mixedViews = false;
      _selectedViewId = picked.view?.id;
      _noView = picked.view == null;
      _sectionChosen = false;
      _applyDefaultOrUncategorized(picked.view);
    });
    if (picked.view != null) await _pickSection();
  }

  Future<void> _pickSection() async {
    if (_selectedViewId == null) return;
    final s = state.strings;
    final defs = _sections;
    final items = <_SectionChoice>[
      const _SectionChoice(),
      for (final d in defs) _SectionChoice(name: d.name, flag: d.flag),
    ];
    final current = _uncategorized || (_sectionName ?? '').isEmpty
        ? 0
        : items.indexWhere((c) => c.name == _sectionName);
    final picked = await showAppChoiceDialog<_SectionChoice>(
      context: context,
      title: s['sectionField'],
      cancelLabel: s['cancel'],
      items: items,
      initialIndex: (current < 0 ? 0 : current).clamp(0, items.length - 1),
      itemBuilder: (context, item, _) =>
          DialogChoiceText(_sectionChoiceLabel(defs, item)),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _sectionName = picked.name;
      _sectionFlag = picked.flag;
      _uncategorized = (picked.name ?? '').isEmpty;
      _sectionChosen = true;
    });
  }

  String _sectionChoiceLabel(List<ViewSectionDef> defs, _SectionChoice item) {
    final name = (item.name ?? '').trim();
    if (name.isEmpty) return state.strings['uncategorized'];
    final isDef = defs.any((d) => d.name == name && d.isDefault);
    return isDef ? state.strings.sectionWithDefault(name) : name;
  }

  bool get _canApply {
    if (_applying || _loading) return false;
    if (_mixedViews && _selectedViewId == null && !_noView) return false;
    if (!_noView && _selectedViewId != null && !_sectionChosen) return false;
    return true;
  }

  Future<void> _apply() async {
    if (!_canApply) return;
    setState(() => _applying = true);
    try {
      await state.setTaskViewPlacement(
        taskIds: widget.taskIds,
        viewId: _noView ? null : _selectedViewId,
        sectionName: _sectionName,
        sectionFlag: _sectionFlag,
        uncategorized: _uncategorized || _noView,
        sectionChosen: !_noView && _selectedViewId != null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final views = state.userViews;
    final sectionEnabled = _selectedViewId != null;

    return AppAdaptiveDialogShell(
      title: Text(s['assignTaskViewsTitle']),
      actions: [
        TextButton(
          onPressed: _applying ? null : () => Navigator.pop(context, false),
          child: Text(s['cancel']),
        ),
        TextButton(
          onPressed: _canApply ? _apply : null,
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
                else ...[
                  AppDialogPickerField(
                    label: s['viewField'],
                    preview: AppIcon(
                      AppIcons.layout,
                      size: 16,
                      color: AppColors.textHint,
                    ),
                    valueLabel: _viewLabel,
                    onTap: _pickView,
                  ),
                  const SizedBox(height: DialogFieldStyle.fieldGap),
                  IgnorePointer(
                    ignoring: !sectionEnabled,
                    child: Opacity(
                      opacity: sectionEnabled ? 1 : 0.45,
                      child: AppDialogPickerField(
                        label: s['sectionField'],
                        preview: AppIcon(
                          AppIcons.arrange,
                          size: 16,
                          color: AppColors.textHint,
                        ),
                        valueLabel: _sectionLabel,
                        onTap: _pickSection,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ViewChoice {
  const _ViewChoice({required this.view});
  final AppView? view;
}

class _SectionChoice {
  const _SectionChoice({this.name, this.flag});
  final String? name;
  final String? flag;
}
