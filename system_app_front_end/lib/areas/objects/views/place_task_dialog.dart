import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/topic.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/confirm_dialog.dart';
import '../../ui/dialog_field_style.dart';
import '../../ui/dialog_metrics.dart';
import '../../ux/dialogs/dialog_choice_list.dart';
import '../data/task.dart';

var _placeTaskTopicListDialogOpen = false;

/// Topic + list only. Does not change view or section.
Future<void> showPlaceTaskTopicListDialog({
  required BuildContext context,
  required AppState state,
  required List<Task> tasks,
}) async {
  if (tasks.isEmpty) return;
  if (_placeTaskTopicListDialogOpen) return;
  _placeTaskTopicListDialogOpen = true;
  try {
    await showAppDialog<void>(
      context: context,
      builder: (_) => _PlaceTaskTopicListDialog(state: state, tasks: tasks),
    );
  } finally {
    _placeTaskTopicListDialogOpen = false;
  }
}

class _PlaceTaskTopicListDialog extends StatefulWidget {
  const _PlaceTaskTopicListDialog({required this.state, required this.tasks});

  final AppState state;
  final List<Task> tasks;

  @override
  State<_PlaceTaskTopicListDialog> createState() =>
      _PlaceTaskTopicListDialogState();
}

class _PlaceTaskTopicListDialogState extends State<_PlaceTaskTopicListDialog> {
  Topic? _topic;
  var _noTopic = false;
  int? _listId;
  var _noList = false;
  var _listsLoading = false;
  List<TopicTaskList> _lists = const [];
  var _applying = false;

  AppState get state => widget.state;
  Task get _seed => widget.tasks.first;

  @override
  void initState() {
    super.initState();
    _seedFromTask(_seed);
    final topic = _topic;
    if (topic != null) {
      unawaited(_loadLists(topic.id));
    }
  }

  void _seedFromTask(Task task) {
    final topicId = task.topicId ??
        (task.topicKey != null
            ? int.tryParse(task.topicKey!.replaceFirst('topic_', ''))
            : null);
    _topic = topicId == null
        ? null
        : state.activeTopics.where((t) => t.id == topicId).firstOrNull;
    _noTopic = _topic == null;
    _listId = task.taskListId;
    _noList = task.taskListId == null;
  }

  Future<void> _loadLists(int topicId) async {
    setState(() => _listsLoading = true);
    try {
      final lists = await state.listTaskListsForTopic(topicId);
      if (!mounted) return;
      setState(() {
        _lists = lists;
        _listsLoading = false;
        if (_listId != null && !lists.any((l) => l.id == _listId)) {
          _listId = null;
          _noList = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lists = const [];
        _listsLoading = false;
      });
    }
  }

  String get _topicLabel {
    if (_noTopic || _topic == null) return state.strings['noTopic'];
    return state.topicDisplayName(_topic!);
  }

  String get _listLabel {
    if (_noList || _listId == null) return state.strings['noList'];
    for (final list in _lists) {
      if (list.id == _listId) {
        final title = list.title.trim();
        return title.isEmpty ? state.strings['untitledTaskList'] : title;
      }
    }
    return state.strings['noList'];
  }

  Future<void> _pickTopic() async {
    final next = await _showSearchableTopicDialog(
      context: context,
      state: state,
      selected: _noTopic ? null : _topic,
    );
    if (!mounted || next == null) return;
    final topic = next.topic;
    setState(() {
      _topic = topic;
      _noTopic = topic == null;
      if (topic == null) {
        _listId = null;
        _noList = true;
        _lists = const [];
      }
    });
    if (topic != null) await _loadLists(topic.id);
  }

  Future<void> _pickList() async {
    if (_noTopic || _topic == null) return;
    final s = state.strings;
    final items = <_ListChoice>[
      const _ListChoice(id: null),
      for (final list in _lists) _ListChoice(id: list.id, title: list.title),
    ];
    final current = _noList || _listId == null
        ? 0
        : items.indexWhere((c) => c.id == _listId);
    final picked = await showAppChoiceDialog<_ListChoice>(
      context: context,
      title: s['listField'],
      cancelLabel: s['cancel'],
      items: items,
      initialIndex: (current < 0 ? 0 : current).clamp(0, items.length - 1),
      itemBuilder: (context, item, _) => DialogChoiceText(
        item.id == null
            ? s['noList']
            : (item.title.trim().isEmpty ? s['untitledTaskList'] : item.title),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _listId = picked.id;
      _noList = picked.id == null;
    });
  }

  int? _topicIdOf(Task task) {
    if (task.topicId != null) return task.topicId;
    final key = task.topicKey;
    if (key == null || key.isEmpty) return null;
    return int.tryParse(key.replaceFirst('topic_', ''));
  }

  bool get _wouldLeaveHomeList {
    final nextTopicId = _noTopic ? null : _topic?.id;
    final topicChanged = widget.tasks.any((t) => _topicIdOf(t) != nextTopicId);
    final listChanged = widget.tasks.any((t) {
      if (_noList || _noTopic) return t.taskListId != null;
      return t.taskListId != _listId;
    });
    if (!topicChanged && !listChanged) return false;
    return widget.tasks.any((t) => t.taskListId != null);
  }

  Future<void> _apply() async {
    if (_applying) return;
    if (_wouldLeaveHomeList) {
      final s = state.strings;
      final nextTopicId = _noTopic ? null : _topic?.id;
      final forTopic = widget.tasks.any((t) => _topicIdOf(t) != nextTopicId);
      final ok = await showAppConfirmDialog(
        context: context,
        title: s['leaveHomeListTitle'],
        message: forTopic
            ? s['leaveHomeListForTopicBody']
            : s['leaveHomeListForListBody'],
        confirmLabel: s['leaveHomeListConfirm'],
        cancelLabel: s['cancel'],
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _applying = true);
    try {
      await state.setTaskTopicAndList(
        taskIds: [for (final t in widget.tasks) t.id],
        topicKey: _noTopic || _topic == null ? null : 'topic_${_topic!.id}',
        noTopic: _noTopic || _topic == null,
        taskListId: _listId,
        noList: _noList || _noTopic,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final listEnabled = !_noTopic && _topic != null && !_listsLoading;

    return AppAdaptiveDialogShell(
      title: Text(s['placeTopicListTitle']),
      width: AppDialogMetrics.wideWidth,
      actions: [
        TextButton(
          onPressed: _applying ? null : () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        TextButton(
          onPressed: _applying ? null : _apply,
          child: Text(s['ok']),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppDialogPickerField(
            label: s['topicField'],
            preview: AppIcon(AppIcons.search, size: 16, color: AppColors.textHint),
            valueLabel: _topicLabel,
            onTap: _pickTopic,
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          IgnorePointer(
            ignoring: !listEnabled,
            child: Opacity(
              opacity: listEnabled ? 1 : 0.45,
              child: AppDialogPickerField(
                label: s['listField'],
                preview: AppIcon(
                  AppIcons.unmarkTasks,
                  size: 16,
                  color: AppColors.textHint,
                ),
                valueLabel: _listsLoading ? '…' : _listLabel,
                onTap: _pickList,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListChoice {
  const _ListChoice({required this.id, this.title = ''});
  final int? id;
  final String title;
}

class _TopicPick {
  const _TopicPick({this.topic});
  final Topic? topic;
}

Future<_TopicPick?> _showSearchableTopicDialog({
  required BuildContext context,
  required AppState state,
  Topic? selected,
}) {
  return showAppDialog<_TopicPick>(
    context: context,
    builder: (ctx) => _SearchableTopicDialog(state: state, selected: selected),
  );
}

class _SearchableTopicDialog extends StatefulWidget {
  const _SearchableTopicDialog({required this.state, this.selected});

  final AppState state;
  final Topic? selected;

  @override
  State<_SearchableTopicDialog> createState() => _SearchableTopicDialogState();
}

class _SearchableTopicDialogState extends State<_SearchableTopicDialog> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<_TopicPick> get _choices {
    final s = widget.state.strings;
    final q = _query.text.trim().toLowerCase();
    final topics = [
      for (final t in widget.state.activeTopics)
        if (q.isEmpty ||
            widget.state.topicDisplayName(t).toLowerCase().contains(q) ||
            t.name.toLowerCase().contains(q))
          _TopicPick(topic: t),
    ];
    final noTopicLabel = s['noTopic'].toLowerCase();
    final includeNone = q.isEmpty || noTopicLabel.contains(q);
    return [if (includeNone) const _TopicPick(), ...topics];
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final choices = _choices;
    var initial = 0;
    final selectedId = widget.selected?.id;
    if (selectedId != null) {
      final i = choices.indexWhere((c) => c.topic?.id == selectedId);
      if (i >= 0) initial = i;
    }
    return AppAdaptiveDialogShell(
      title: Text(s['topicField']),
      width: AppDialogMetrics.wideWidth,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppDialogField(
            label: s['searchTopics'],
            child: TextField(
              controller: _query,
              autofocus: true,
              style: AppTypography.noteBodyStyle.copyWith(fontSize: 12),
              decoration: DialogFieldStyle.decoration(),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          if (choices.isEmpty)
            Text(s['noTopic'], style: AppTypography.noteBodyStyle)
          else
            DialogChoiceList(
              itemCount: choices.length,
              initialIndex: initial.clamp(0, choices.length - 1),
              maxHeight: 240,
              onActivate: (i) => Navigator.pop(context, choices[i]),
              itemBuilder: (context, i, _) => DialogChoiceText(
                choices[i].topic == null
                    ? s['noTopic']
                    : widget.state.topicDisplayName(choices[i].topic!),
              ),
            ),
        ],
      ),
    );
  }
}
