import 'package:flutter/material.dart';
import 'dart:async';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../files/data/app_file.dart';
import '../files/data/topic.dart';
import '../files/data/topic_type.dart';
import '../production_agent/agent_run_defaults.dart';
import '../production_agent/ai_action.dart';
import '../production_agent/ai_action_edit_dialog.dart';
import '../ui/action_icons.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_colors.dart';
import '../ui/app_icons.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/app_typography.dart';
import '../ui/dialog_field_style.dart';
import '../ui/dialog_metrics.dart';
import '../ui/compact_calendar.dart';
import '../ui/time_picker_dialog.dart';
import '../ux/dialogs/dialog_choice_list.dart';
import '../ux/widgets/topic_emoji.dart';
import './automation.dart';
import './fill_file_snippet_dialog.dart';
import './schedule_format.dart';

/// Create or rewrite an automation: scope, when it fires, and what it does.
Future<bool> showAutomationBuilderDialog({
  required BuildContext context,
  required AppState state,
  Automation? automation,
  Map<String, dynamic>? initialScope,
}) async {
  final saved = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => _AutomationBuilderDialog(
      state: state,
      automation: automation,
      initialScope: initialScope,
    ),
  );
  return saved ?? false;
}

class _AutomationBuilderDialog extends StatefulWidget {
  const _AutomationBuilderDialog({
    required this.state,
    this.automation,
    this.initialScope,
  });

  final AppState state;
  final Automation? automation;
  final Map<String, dynamic>? initialScope;

  @override
  State<_AutomationBuilderDialog> createState() =>
      _AutomationBuilderDialogState();
}

class _AutomationBuilderDialogState extends State<_AutomationBuilderDialog> {
  late final TextEditingController _name;
  late final TextEditingController _nameHe;
  late String _scopeKind;
  int? _topicId;
  int? _topicTypeId;
  late AutomationSchedule _schedule;
  late List<Map<String, dynamic>> _steps;
  var _saving = false;
  var _addMenuOpen = false;
  List<AppFile> _templateFiles = const [];
  List<AppFile> _topicFiles = const [];

  AppState get state => widget.state;
  AppStrings get s => state.strings;
  bool get _isEdit => widget.automation != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.automation;
    _name = TextEditingController(text: existing?.name ?? '');
    _nameHe = TextEditingController(text: existing?.nameHe ?? '');
    _name.addListener(() => setState(() {}));
    _nameHe.addListener(() => setState(() {}));
    final scope = existing?.scope ?? widget.initialScope ?? _defaultScope();
    _scopeKind = AutomationScope.kindOf(scope);
    _topicId = scope['topic_id'] as int? ?? state.selectedTopic?.id;
    _topicTypeId =
        AutomationScope.typeIdOf(scope) ?? state.topicTypes.firstOrNull?.id;
    _schedule = AutomationSchedule.parse(existing?.schedule);
    _steps = [
      for (final step in existing?.steps ?? const <Map<String, dynamic>>[])
        Map<String, dynamic>.from(step),
    ];
    _loadTemplateFiles();
    _loadTopicFiles();
  }

  Map<String, dynamic> _defaultScope() {
    final topic = state.selectedTopic;
    return topic == null
        ? AutomationScope.everywhere()
        : AutomationScope.oneTopic(topic.id);
  }

  @override
  void dispose() {
    _name.dispose();
    _nameHe.dispose();
    super.dispose();
  }

  Map<String, dynamic> _scope() {
    return switch (_scopeKind) {
      AutomationScope.topic when _topicId != null => AutomationScope.oneTopic(
        _topicId!,
      ),
      AutomationScope.topicType when _topicTypeId != null =>
        AutomationScope.ofType(_topicTypeId!),
      _ => AutomationScope.everywhere(),
    };
  }

  bool get _canSave {
    if (_name.text.trim().isEmpty ||
        _nameHe.text.trim().isEmpty ||
        _steps.isEmpty) {
      return false;
    }
    if (_scopeKind == AutomationScope.topic && _topicId == null) return false;
    if (_scopeKind == AutomationScope.topicType && _topicTypeId == null) {
      return false;
    }
    return _steps.every(_stepIsReady);
  }

  bool _stepIsReady(Map<String, dynamic> step) {
    final kind = step['kind'] as String? ?? '';
    if (kind == StepKinds.ai) {
      final hasPrompt = (step['prompt'] as String? ?? '').trim().isNotEmpty;
      return hasPrompt || step['action_id'] != null;
    }
    if (kind == StepKinds.createFile) {
      final slot = (step['template_slot'] as String? ?? '').trim();
      if (slot.isNotEmpty && _scopeKind == AutomationScope.topicType) {
        return true;
      }
      if ((step['name'] as String? ?? '').trim().isEmpty) return false;
      final needsTopic = _scopeKind != AutomationScope.topic;
      return !needsTopic || step['topic_id'] != null;
    }
    if (kind == StepKinds.fillFile) {
      if ((step['document_json'] as String? ?? '').trim().isEmpty) return false;
      if (_scopeKind == AutomationScope.topicType) {
        return (step['template_slot'] as String? ?? '').trim().isNotEmpty;
      }
      if (_scopeKind == AutomationScope.topic) {
        return _asInt(step['file_id']) != null;
      }
      return _asInt(step['file_id']) != null ||
          (step['template_slot'] as String? ?? '').trim().isNotEmpty;
    }
    return StepKinds.all.contains(kind);
  }

  TopicType? get _scopedType => state.topicTypeById(_topicTypeId);

  Future<void> _loadTemplateFiles() async {
    final type = _scopedType;
    if (_scopeKind != AutomationScope.topicType ||
        type?.templateTopicId == null) {
      _templateFiles = const [];
      return;
    }
    try {
      final files = await state.templateFilesForType(type!);
      if (!mounted) return;
      setState(() => _templateFiles = files);
    } catch (_) {
      if (!mounted) return;
      setState(() => _templateFiles = const []);
    }
  }

  Future<void> _loadTopicFiles() async {
    if (_scopeKind != AutomationScope.topic || _topicId == null) {
      _topicFiles = const [];
      return;
    }
    try {
      final files = await state.filesForTopic(_topicId!);
      if (!mounted) return;
      setState(() => _topicFiles = files);
    } catch (_) {
      if (!mounted) return;
      setState(() => _topicFiles = const []);
    }
  }

  String _slotLabel(String? slot) {
    if (slot == null || slot.isEmpty) return s['pickTemplateSlot'];
    for (final file in _templateFiles) {
      if (file.templateSlot == slot) return file.name;
    }
    return slot;
  }

  String _fileLabel(int? id) {
    if (id == null) return s['pickTopicFile'];
    for (final file in _topicFiles) {
      if (file.id == id) return file.name;
    }
    return s['pickTopicFile'];
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await state.updateAutomation(widget.automation!, {
          'name': _name.text.trim(),
          'name_he': _nameHe.text.trim(),
          'scope': _scope(),
          'trigger': {'type': 'schedule'},
          'steps': _steps,
          'schedule': _schedule.toDsl(),
          'timezone': AutomationSchedule.defaultTimezone,
        });
      } else {
        await state.createAutomation(
          name: _name.text.trim(),
          nameHe: _nameHe.text.trim(),
          scope: _scope(),
          trigger: const {'type': 'schedule'},
          steps: _steps,
          schedule: _schedule.toDsl(),
          timezone: AutomationSchedule.defaultTimezone,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _appendStep(Map<String, dynamic> step) {
    setState(() {
      _addMenuOpen = false;
      _steps = [..._steps, step];
    });
  }

  Future<void> _addNewAiAction() async {
    setState(() => _addMenuOpen = false);
    final action = await showAiActionEditDialog(context: context, state: state);
    if (action == null || !mounted) return;
    _appendStep({
      'kind': StepKinds.ai,
      'action_id': action.id,
      'apply_mode': action.applyMode,
    });
  }

  Future<void> _addSavedAiAction() async {
    setState(() => _addMenuOpen = false);
    if (state.aiActions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s['noSavedActionsForStep'])));
      return;
    }
    final id = await _pickSavedAction(null);
    if (id == null || !mounted) return;
    AiAction? picked;
    for (final action in state.aiActions) {
      if (action.id == id) picked = action;
    }
    _appendStep({
      'kind': StepKinds.ai,
      'action_id': id,
      'apply_mode': picked?.applyMode ?? defaultAutomationApplyMode,
    });
  }

  void _addSystemStep(String kind) {
    final step = <String, dynamic>{'kind': kind};
    if (kind == StepKinds.createFile) {
      final slot = _templateFiles
          .map((f) => f.templateSlot)
          .whereType<String>()
          .firstOrNull;
      if (_scopeKind == AutomationScope.topicType && slot != null) {
        step['template_slot'] = slot;
      } else {
        step['name'] = 'Week of {date}';
      }
    }
    if (kind == StepKinds.fillFile) {
      unawaited(_addFillFileStep());
      return;
    }
    _appendStep(step);
  }

  Future<void> _addFillFileStep() async {
    setState(() => _addMenuOpen = false);
    await _loadTopicFiles();
    await _loadTemplateFiles();
    if (!mounted) return;
    final topic = _scratchHostTopic();
    if (topic == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s['fillFileNeedScope'])));
      return;
    }
    final content = await showFillFileSnippetDialog(
      context: context,
      state: state,
      topic: topic,
    );
    if (content == null || !mounted) return;
    final step = <String, dynamic>{
      'kind': StepKinds.fillFile,
      'document_json': content['document_json'],
      'objects': content['objects'] ?? const [],
    };
    if (_scopeKind == AutomationScope.topicType) {
      final slot = _templateFiles
          .map((f) => f.templateSlot)
          .whereType<String>()
          .firstOrNull;
      if (slot != null) step['template_slot'] = slot;
    } else if (_scopeKind == AutomationScope.topic) {
      final id = _topicFiles.firstOrNull?.id;
      if (id != null) step['file_id'] = id;
    }
    _appendStep(step);
  }

  Topic? _scratchHostTopic() {
    if (_scopeKind == AutomationScope.topic && _topicId != null) {
      return state.allTopics.where((t) => t.id == _topicId).firstOrNull;
    }
    if (_scopeKind == AutomationScope.topicType) {
      final templateId = _scopedType?.templateTopicId;
      if (templateId != null) {
        final template = state.allTopics
            .where((t) => t.id == templateId)
            .firstOrNull;
        if (template != null) return template;
      }
      return state.activeTopics
          .where((t) => t.topicTypeId == _topicTypeId)
          .firstOrNull;
    }
    return state.selectedTopic ?? state.activeTopics.firstOrNull;
  }

  String _stepLabel(String kind) => switch (kind) {
    StepKinds.ai => s['stepAi'],
    StepKinds.createFile => s['stepCreateFile'],
    StepKinds.unmarkTasks => s['stepUnmarkTasks'],
    StepKinds.archiveFiles => s['stepArchiveFiles'],
    StepKinds.fillFile => s['stepFillFile'],
    _ => kind,
  };

  String _stepFrameName(Map<String, dynamic> step) {
    final kind = step['kind'] as String? ?? '';
    if (kind == StepKinds.ai) {
      final id = step['action_id'] as int?;
      if (id != null) {
        for (final action in state.aiActions) {
          if (action.id == id) return state.aiActionDisplayName(action);
        }
      }
    }
    if (kind == StepKinds.createFile) {
      final slot = (step['template_slot'] as String? ?? '').trim();
      if (slot.isNotEmpty) return _slotLabel(slot);
      final name = (step['name'] as String? ?? '').trim();
      if (name.isNotEmpty) return name;
    }
    if (kind == StepKinds.fillFile) {
      final slot = (step['template_slot'] as String? ?? '').trim();
      if (slot.isNotEmpty) return _slotLabel(slot);
      final fileId = _asInt(step['file_id']);
      if (fileId != null) return _fileLabel(fileId);
    }
    return _stepLabel(kind);
  }

  IconData _stepFrameIcon(Map<String, dynamic> step) {
    final kind = step['kind'] as String? ?? '';
    if (kind == StepKinds.ai) {
      final id = step['action_id'] as int?;
      if (id != null) {
        for (final action in state.aiActions) {
          if (action.id == id) return actionIcon(action.icon);
        }
      }
      return AppIcons.ai;
    }
    if (kind == StepKinds.createFile) return AppIcons.addFile;
    if (kind == StepKinds.unmarkTasks) return AppIcons.unmarkTasks;
    if (kind == StepKinds.archiveFiles) return AppIcons.archiveFiles;
    if (kind == StepKinds.fillFile) return AppIcons.fillFile;
    return AppIcons.ai;
  }

  String _topicLabel(int? id) {
    if (id == null) return s['pickTopic'];
    for (final topic in state.activeTopics) {
      if (topic.id == id) return state.topicDisplayName(topic);
    }
    return s['pickTopic'];
  }

  Future<int?> _pickTopic({int? currentId}) async {
    final topics = state.activeTopics;
    var initial = 0;
    for (var i = 0; i < topics.length; i++) {
      if (topics[i].id == currentId) {
        initial = i;
        break;
      }
    }
    final picked = await showAppChoiceDialog(
      context: context,
      title: s['pickTopic'],
      cancelLabel: s['cancel'],
      items: topics,
      initialIndex: initial,
      itemBuilder: (context, topic, _) => DialogChoiceText(
        state.topicDisplayName(topic),
        leading: TopicEmoji(value: topic.icon, size: 18),
      ),
    );
    return picked?.id;
  }

  Future<int?> _pickTopicFile(int? currentId) async {
    final files = _topicFiles;
    if (files.isEmpty) return null;
    var initial = 0;
    for (var i = 0; i < files.length; i++) {
      if (files[i].id == currentId) {
        initial = i;
        break;
      }
    }
    final picked = await showAppChoiceDialog(
      context: context,
      title: s['pickTopicFile'],
      cancelLabel: s['cancel'],
      items: files,
      initialIndex: initial,
      itemBuilder: (context, file, _) => DialogChoiceText(file.name),
    );
    return picked?.id;
  }

  Future<Map<String, dynamic>?> _editFillSnippet(
    Map<String, dynamic> step,
  ) async {
    final topic = _scratchHostTopic();
    if (topic == null) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s['fillFileNeedScope'])));
      return null;
    }
    return showFillFileSnippetDialog(
      context: context,
      state: state,
      topic: topic,
      existing: {
        'document_json': step['document_json'],
        'objects': step['objects'] ?? const [],
      },
    );
  }

  String _typeScopeLabel() {
    final type = state.topicTypeById(_topicTypeId);
    if (type == null) return s['scopeTopicType'];
    return state.topicTypeDisplayName(type);
  }

  Future<int?> _pickTopicType() async {
    final types = state.topicTypes;
    var initial = 0;
    for (var i = 0; i < types.length; i++) {
      if (types[i].id == _topicTypeId) {
        initial = i;
        break;
      }
    }
    final picked = await showAppChoiceDialog(
      context: context,
      title: s['scopeTopicType'],
      cancelLabel: s['cancel'],
      items: types,
      initialIndex: initial,
      itemBuilder: (context, type, _) =>
          DialogChoiceText(state.topicTypeDisplayName(type)),
    );
    return picked?.id;
  }

  String _actionLabel(int? id) {
    if (id == null) return s['pickAiAction'];
    for (final action in state.aiActions) {
      if (action.id == id) return state.aiActionDisplayName(action);
    }
    return s['pickAiAction'];
  }

  Future<int?> _pickSavedAction(int? currentId) {
    return showAppDialog<int>(
      context: context,
      builder: (ctx) => AppAdaptiveDialogShell(
        title: Text(s['pickAiAction']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s['cancel']),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in state.aiActions)
              ListTile(
                dense: true,
                selected: action.id == currentId,
                leading: AppIcon(actionIcon(action.icon), size: 18),
                title: Text(state.aiActionDisplayName(action)),
                subtitle: Text(
                  action.prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(ctx, action.id),
              ),
          ],
        ),
      ),
    );
  }

  void _replaceStep(int index, Map<String, dynamic> step) {
    setState(() {
      _steps = [
        for (var i = 0; i < _steps.length; i++) i == index ? step : _steps[i],
      ];
    });
  }

  Future<void> _openStepEditor(int index) async {
    if (index < 0 || index >= _steps.length) return;
    final popped = await showAppDialog<_StepEditPop>(
      context: context,
      builder: (ctx) => _StepEditDialog(
        strings: s,
        step: Map<String, dynamic>.from(_steps[index]),
        scopeKind: _scopeKind,
        topicLabel: _topicLabel,
        actionLabel: _actionLabel,
        slotLabel: _slotLabel,
        fileLabel: _fileLabel,
        templateFiles: _templateFiles,
        topicFiles: _topicFiles,
        onPickTopic: _pickTopic,
        onPickAction: _pickSavedAction,
        onPickFile: _pickTopicFile,
        onEditSnippet: _editFillSnippet,
        aiActions: state.aiActions,
      ),
    );
    if (popped == null || !mounted) return;
    if (popped.op == 'delete') {
      setState(() {
        _steps = [
          for (var i = 0; i < _steps.length; i++)
            if (i != index) _steps[i],
        ];
      });
      return;
    }
    _replaceStep(index, popped.step);
  }

  String _whenCaption() {
    final dayKey = AutomationSchedule.weekdayKeys[_schedule.weekday]!;
    if (_schedule.kind == 'weekly') return s.weeklyScheduleCaption(dayKey);
    if (_schedule.kind == 'monthly') {
      return s.monthlyScheduleCaption(_schedule.placement, dayKey);
    }
    return '';
  }

  Widget _compactTime() {
    return AppCompactTimePicker(
      title: s['time'],
      value: timeOfDayFromHmm(_schedule.time),
      onChanged: (picked) {
        setState(
          () => _schedule = _schedule.copyWith(time: hmmFromTimeOfDay(picked)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppAdaptiveDialogShell(
      title: Text(
        _isEdit
            ? s.editAutomationTitle(widget.automation!.name)
            : s['createAutomation'],
      ),
      width: AppDialogMetrics.extraWideWidth,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(s['cancel']),
        ),
        FilledButton(
          onPressed: _canSave && !_saving ? _save : null,
          child: Text(s['save']),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BuilderSection(
            label: s['builderSectionBasics'],
            child: _basicsFields(),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          _BuilderSection(label: s['builderSectionWhen'], child: _whenFields()),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          _BuilderSection(label: s['automationSteps'], child: _stepsStrip()),
        ],
      ),
    );
  }

  Widget _basicsFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogField(
          label: s['nameEnglish'],
          child: TextField(
            controller: _name,
            decoration: DialogFieldStyle.decoration(),
          ),
        ),
        const SizedBox(height: DialogFieldStyle.fieldGap),
        AppDialogField(
          label: s['nameHebrew'],
          child: TextField(
            controller: _nameHe,
            textDirection: TextDirection.rtl,
            decoration: DialogFieldStyle.decoration(),
          ),
        ),
        const SizedBox(height: DialogFieldStyle.fieldGap),
        AppDialogChoiceField<String>(
          label: s['automationScopeKind'],
          options: [
            AppSegmentedOption(
              value: AutomationScope.all,
              label: s['scopeAll'],
            ),
            AppSegmentedOption(
              value: AutomationScope.topic,
              label: s['scopeOneTopic'],
            ),
            AppSegmentedOption(
              value: AutomationScope.topicType,
              label: s['scopeTopicType'],
            ),
          ],
          selected: _scopeKind,
          onSelected: (kind) {
            setState(() {
              _scopeKind = kind;
              if (kind != AutomationScope.topicType) {
                _templateFiles = const [];
              }
              if (kind != AutomationScope.topic) {
                _topicFiles = const [];
              }
            });
            _loadTemplateFiles();
            _loadTopicFiles();
          },
        ),
        if (_scopeKind == AutomationScope.topic) ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogPickerField(
            label: s['pickTopic'],
            preview: const AppIcon(AppIcons.bringFile, size: 16),
            valueLabel: _topicLabel(_topicId),
            onTap: () async {
              final id = await _pickTopic(currentId: _topicId);
              if (id == null) return;
              setState(() => _topicId = id);
              await _loadTopicFiles();
            },
          ),
        ],
        if (_scopeKind == AutomationScope.topicType) ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogPickerField(
            label: s['scopeTopicType'],
            preview: const AppIcon(AppIcons.bringFile, size: 16),
            valueLabel: _typeScopeLabel(),
            onTap: () async {
              final id = await _pickTopicType();
              if (id == null) return;
              setState(() => _topicTypeId = id);
              await _loadTemplateFiles();
            },
          ),
        ],
        const SizedBox(height: DialogFieldStyle.fieldGap),
        AppDialogChoiceField<String>(
          label: s['schedule'],
          options: [
            AppSegmentedOption(value: 'daily', label: s['onceADay']),
            AppSegmentedOption(value: 'weekly', label: s['onceAWeek']),
            AppSegmentedOption(value: 'monthly', label: s['onceAMonth']),
          ],
          selected: _schedule.kind,
          onSelected: (kind) =>
              setState(() => _schedule = _schedule.copyWith(kind: kind)),
        ),
      ],
    );
  }

  Widget _whenFields() {
    final time = _compactTime();
    if (_schedule.kind == 'daily') return time;
    return Row(
      children: [
        Expanded(
          child: AppCompactCalendar(
            title: s['chooseDay'],
            weekdayLabels: s.narrowWeekdaysSundayFirst,
            formatMonth: s.monthYear,
            isMarked: _schedule.marksDate,
            caption: _whenCaption(),
            onDaySelected: (date) {
              setState(() => _schedule = _schedule.applyingDate(date));
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: time),
      ],
    );
  }

  Widget _stepsStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_steps.isEmpty)
          Text(s['addStepHint'], style: AppTypography.metaStyle),
        SizedBox(
          height: 88,
          child: Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    buildDefaultDragHandles: false,
                    itemCount: _steps.length,
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        color: AppColors.noteTop.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(10),
                        child: child,
                      );
                    },
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final next = [..._steps];
                        next.insert(newIndex, next.removeAt(oldIndex));
                        _steps = next;
                      });
                    },
                    itemBuilder: (context, index) {
                      final step = _steps[index];
                      return ReorderableDelayedDragStartListener(
                        key: ObjectKey(step),
                        index: index,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: _StepFrame(
                            icon: _stepFrameIcon(step),
                            name: _stepFrameName(step),
                            deleteTooltip: s['delete'],
                            onTap: () => _openStepEditor(index),
                            onDelete: () => setState(() {
                              _steps = [
                                for (var i = 0; i < _steps.length; i++)
                                  if (i != index) _steps[i],
                              ];
                            }),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: s['addStep'],
                onPressed: () => setState(() => _addMenuOpen = !_addMenuOpen),
                icon: const AppIcon(AppIcons.add, size: 18),
              ),
            ],
          ),
        ),
        if (_addMenuOpen) ...[
          const SizedBox(height: DialogFieldStyle.labelGap),
          _AddStepMenu(
            strings: s,
            onNewAi: _addNewAiAction,
            onSavedAi: _addSavedAiAction,
            onSystem: _addSystemStep,
          ),
        ],
      ],
    );
  }
}

class _BuilderSection extends StatelessWidget {
  const _BuilderSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppColors.noteTop.withValues(alpha: 0.55),
        border: Border.all(
          color: AppColors.noteBorder.withValues(alpha: 0.68),
          width: 0.85,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: DialogFieldStyle.labelStyle),
            const SizedBox(height: DialogFieldStyle.fieldGap),
            child,
          ],
        ),
      ),
    );
  }
}

class _StepFrame extends StatelessWidget {
  const _StepFrame({
    required this.icon,
    required this.name,
    required this.deleteTooltip,
    required this.onTap,
    required this.onDelete,
  });

  final IconData icon;
  final String name;
  final String deleteTooltip;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.canvasNeutralTop.withValues(alpha: 0.72),
              border: Border.all(
                color: AppColors.noteBorder.withValues(alpha: 0.68),
                width: 0.85,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon(icon, size: 20),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTypography.metaStyle.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: IconButton(
                    tooltip: deleteTooltip,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    onPressed: onDelete,
                    icon: const AppIcon(AppIcons.close, size: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddStepMenu extends StatelessWidget {
  const _AddStepMenu({
    required this.strings,
    required this.onNewAi,
    required this.onSavedAi,
    required this.onSystem,
  });

  final AppStrings strings;
  final VoidCallback onNewAi;
  final VoidCallback onSavedAi;
  final ValueChanged<String> onSystem;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AddStepRow(
          icon: AppIcons.ai,
          label: s['createAiAction'],
          onTap: onNewAi,
        ),
        _AddStepRow(
          icon: AppIcons.ai,
          label: s['stepAiSaved'],
          onTap: onSavedAi,
        ),
        _AddStepRow(
          icon: AppIcons.addFile,
          label: s['stepCreateFile'],
          onTap: () => onSystem(StepKinds.createFile),
        ),
        _AddStepRow(
          icon: AppIcons.unmarkTasks,
          label: s['stepUnmarkTasks'],
          onTap: () => onSystem(StepKinds.unmarkTasks),
        ),
        _AddStepRow(
          icon: AppIcons.archiveFiles,
          label: s['stepArchiveFiles'],
          onTap: () => onSystem(StepKinds.archiveFiles),
        ),
        _AddStepRow(
          icon: AppIcons.fillFile,
          label: s['stepFillFile'],
          onTap: () => onSystem(StepKinds.fillFile),
        ),
      ],
    );
  }
}

class _AddStepRow extends StatelessWidget {
  const _AddStepRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      leading: AppIcon(icon, size: 16),
      title: Text(label, style: AppTypography.metaStyle),
      onTap: onTap,
    );
  }
}

class _StepEditPop {
  const _StepEditPop(this.op, this.step);

  final String op;
  final Map<String, dynamic> step;
}

class _StepEditDialog extends StatefulWidget {
  const _StepEditDialog({
    required this.strings,
    required this.step,
    required this.scopeKind,
    required this.topicLabel,
    required this.actionLabel,
    required this.slotLabel,
    required this.fileLabel,
    required this.templateFiles,
    required this.topicFiles,
    required this.onPickTopic,
    required this.onPickAction,
    required this.onPickFile,
    required this.onEditSnippet,
    required this.aiActions,
  });

  final AppStrings strings;
  final Map<String, dynamic> step;
  final String scopeKind;
  final String Function(int? id) topicLabel;
  final String Function(int? id) actionLabel;
  final String Function(String? slot) slotLabel;
  final String Function(int? id) fileLabel;
  final List<AppFile> templateFiles;
  final List<AppFile> topicFiles;
  final Future<int?> Function({int? currentId}) onPickTopic;
  final Future<int?> Function(int? currentId) onPickAction;
  final Future<int?> Function(int? currentId) onPickFile;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic> step)
  onEditSnippet;
  final List<AiAction> aiActions;

  @override
  State<_StepEditDialog> createState() => _StepEditDialogState();
}

class _StepEditDialogState extends State<_StepEditDialog> {
  late Map<String, dynamic> _step;

  AppStrings get s => widget.strings;

  @override
  void initState() {
    super.initState();
    _step = Map<String, dynamic>.from(widget.step);
  }

  String get _kind => _step['kind'] as String? ?? '';

  String _title() => switch (_kind) {
    StepKinds.ai => s['stepAi'],
    StepKinds.createFile => s['stepCreateFile'],
    StepKinds.unmarkTasks => s['stepUnmarkTasks'],
    StepKinds.archiveFiles => s['stepArchiveFiles'],
    StepKinds.fillFile => s['stepFillFile'],
    _ => _kind,
  };

  void _pop(String op) => Navigator.pop(context, _StepEditPop(op, _step));

  @override
  Widget build(BuildContext context) {
    return AppAdaptiveDialogShell(
      title: Text(_title()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        FilledButton(onPressed: () => _pop('save'), child: Text(s['save'])),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Spacer(),
              IconButton(
                tooltip: s['delete'],
                onPressed: () => _pop('delete'),
                icon: const AppIcon(AppIcons.trash, size: 16),
              ),
            ],
          ),
          if (_kind == StepKinds.ai) _aiFields(),
          if (_kind == StepKinds.createFile) _createFileFields(),
          if (_kind == StepKinds.archiveFiles) _archiveFields(),
          if (_kind == StepKinds.fillFile) _fillFileFields(),
          if (_kind == StepKinds.unmarkTasks)
            Text(s['unmarkAllInScope'], style: AppTypography.metaStyle),
        ],
      ),
    );
  }

  Widget _aiFields() {
    final usingSaved = _step['action_id'] != null;
    final actions = widget.aiActions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (usingSaved)
          actions.isEmpty
              ? Text(s['noSavedActionsForStep'], style: AppTypography.metaStyle)
              : AppDialogPickerField(
                  label: s['pickAiAction'],
                  preview: const AppIcon(AppIcons.ai, size: 16),
                  valueLabel: widget.actionLabel(_step['action_id'] as int?),
                  onTap: () async {
                    final id = await widget.onPickAction(
                      _step['action_id'] as int?,
                    );
                    if (id == null) return;
                    setState(() => _step['action_id'] = id);
                  },
                )
        else
          AppDialogField(
            label: s['automationPrompt'],
            child: _KeepTextField(
              value: _step['prompt'] as String? ?? '',
              minLines: 2,
              maxLines: 4,
              onChanged: (value) => _step['prompt'] = value,
            ),
          ),
        const SizedBox(height: DialogFieldStyle.fieldGap),
        AppDialogChoiceField<String>(
          label: s['applyMode'],
          options: [
            AppSegmentedOption(value: 'review', label: s['applyModeReview']),
            AppSegmentedOption(
              value: 'direct_apply',
              label: s['applyModeDirect'],
            ),
          ],
          selected:
              (_step['apply_mode'] as String?) ?? defaultAutomationApplyMode,
          onSelected: (mode) => setState(() => _step['apply_mode'] = mode),
        ),
      ],
    );
  }

  Widget _createFileFields() {
    final slots = [
      for (final file in widget.templateFiles)
        if (file.templateSlot != null) file,
    ];
    final useSlot =
        widget.scopeKind == AutomationScope.topicType && slots.isNotEmpty;
    final slotMode = (_step['template_slot'] as String? ?? '').isNotEmpty;
    final needsTopic = widget.scopeKind != AutomationScope.topic && !slotMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (useSlot) ...[
          AppDialogChoiceField<bool>(
            label: s['stepCreateFile'],
            options: [
              AppSegmentedOption(value: true, label: s['createFromSlot']),
              AppSegmentedOption(value: false, label: s['createNamedFile']),
            ],
            selected: slotMode,
            onSelected: (fromSlot) {
              setState(() {
                if (fromSlot) {
                  _step.remove('name');
                  _step.remove('topic_id');
                  _step['template_slot'] = slots.first.templateSlot;
                } else {
                  _step.remove('template_slot');
                  _step['name'] = 'Week of {date}';
                }
              });
            },
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
        ],
        if (useSlot && slotMode)
          AppDialogPickerField(
            label: s['templateSlot'],
            preview: const AppIcon(AppIcons.addFile, size: 16),
            valueLabel: widget.slotLabel(_step['template_slot'] as String?),
            onTap: () async {
              final picked = await _pickSlot(_step['template_slot'] as String?);
              if (picked == null) return;
              setState(() => _step['template_slot'] = picked);
            },
          )
        else ...[
          AppDialogField(
            label: s['fileNamePattern'],
            hint: s['fileNamePatternHint'],
            child: _KeepTextField(
              value: _step['name'] as String? ?? '',
              onChanged: (value) => _step['name'] = value,
            ),
          ),
          if (needsTopic) ...[
            const SizedBox(height: DialogFieldStyle.fieldGap),
            AppDialogPickerField(
              label: s['pickTopic'],
              preview: const AppIcon(AppIcons.bringFile, size: 16),
              valueLabel: widget.topicLabel(_step['topic_id'] as int?),
              onTap: () async {
                final id = await widget.onPickTopic(
                  currentId: _step['topic_id'] as int?,
                );
                if (id == null) return;
                setState(() => _step['topic_id'] = id);
              },
            ),
          ],
        ],
      ],
    );
  }

  Widget _archiveFields() {
    final slots = [
      for (final file in widget.templateFiles)
        if (file.templateSlot != null) file,
    ];
    final useSlot =
        widget.scopeKind == AutomationScope.topicType && slots.isNotEmpty;
    final useFile =
        widget.scopeKind == AutomationScope.topic &&
        widget.topicFiles.isNotEmpty;
    final days = _step['older_than_days'];
    final slot = _step['template_slot'] as String?;
    final fileId = _firstFileId(_step);
    final selected = fileId != null && useFile
        ? 'file'
        : (slot != null && slot.isNotEmpty && useSlot
              ? 'slot'
              : (days == null ? 'all' : 'older'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogChoiceField<String>(
          label: s['archiveAllOrSlot'],
          options: [
            AppSegmentedOption(value: 'all', label: s['archiveAllInScope']),
            if (useFile)
              AppSegmentedOption(value: 'file', label: s['archiveThisFile']),
            if (useSlot)
              AppSegmentedOption(value: 'slot', label: s['archiveBySlot']),
            AppSegmentedOption(value: 'older', label: s['archiveOlderThan']),
          ],
          selected: selected,
          onSelected: (mode) {
            setState(() {
              _step.remove('older_than_days');
              _step.remove('template_slot');
              _step.remove('file_ids');
              if (mode == 'older') _step['older_than_days'] = 30;
              if (mode == 'slot') {
                _step['template_slot'] = slots.first.templateSlot;
              }
              if (mode == 'file') {
                _step['file_ids'] = [widget.topicFiles.first.id];
              }
            });
          },
        ),
        if (selected == 'older' && days != null) ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogField(
            label: s['days'],
            child: _KeepTextField(
              value: '$days',
              keyboardType: TextInputType.number,
              onChanged: (value) {
                final parsed = int.tryParse(value.trim());
                if (parsed == null || parsed <= 0) return;
                _step['older_than_days'] = parsed;
              },
            ),
          ),
        ],
        if (selected == 'slot' && slot != null && slot.isNotEmpty) ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogPickerField(
            label: s['templateSlot'],
            preview: const AppIcon(AppIcons.archiveFiles, size: 16),
            valueLabel: widget.slotLabel(slot),
            onTap: () async {
              final picked = await _pickSlot(slot);
              if (picked == null) return;
              setState(() => _step['template_slot'] = picked);
            },
          ),
        ],
        if (selected == 'file') ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogPickerField(
            label: s['pickTopicFile'],
            preview: const AppIcon(AppIcons.archiveFiles, size: 16),
            valueLabel: widget.fileLabel(fileId),
            onTap: () async {
              final picked = await widget.onPickFile(fileId);
              if (picked == null) return;
              setState(() => _step['file_ids'] = [picked]);
            },
          ),
        ],
      ],
    );
  }

  Widget _fillFileFields() {
    final slots = [
      for (final file in widget.templateFiles)
        if (file.templateSlot != null) file,
    ];
    final useSlot =
        widget.scopeKind == AutomationScope.topicType && slots.isNotEmpty;
    final useFile = widget.scopeKind == AutomationScope.topic;
    final fileId = _asInt(_step['file_id']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogPickerField(
          label: s['editFillFileContent'],
          preview: const AppIcon(AppIcons.fillFile, size: 16),
          valueLabel: s['editFillFileContent'],
          onTap: () async {
            final next = await widget.onEditSnippet(_step);
            if (next == null) return;
            setState(() {
              _step['document_json'] = next['document_json'];
              _step['objects'] = next['objects'] ?? const [];
            });
          },
        ),
        if (useSlot) ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogPickerField(
            label: s['templateSlot'],
            preview: const AppIcon(AppIcons.fillFile, size: 16),
            valueLabel: widget.slotLabel(_step['template_slot'] as String?),
            onTap: () async {
              final picked = await _pickSlot(_step['template_slot'] as String?);
              if (picked == null) return;
              setState(() {
                _step.remove('file_id');
                _step['template_slot'] = picked;
              });
            },
          ),
        ] else if (useFile) ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          widget.topicFiles.isEmpty
              ? Text(s['noTemplateFiles'], style: AppTypography.metaStyle)
              : AppDialogPickerField(
                  label: s['pickTopicFile'],
                  preview: const AppIcon(AppIcons.fillFile, size: 16),
                  valueLabel: widget.fileLabel(fileId),
                  onTap: () async {
                    final picked = await widget.onPickFile(fileId);
                    if (picked == null) return;
                    setState(() {
                      _step.remove('template_slot');
                      _step['file_id'] = picked;
                    });
                  },
                ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: DialogFieldStyle.fieldGap),
            child: Text(s['fillFileNeedScope'], style: AppTypography.metaStyle),
          ),
      ],
    );
  }

  Future<String?> _pickSlot(String? current) {
    final files = [
      for (final file in widget.templateFiles)
        if (file.templateSlot != null) file,
    ];
    var initial = 0;
    for (var i = 0; i < files.length; i++) {
      if (files[i].templateSlot == current) {
        initial = i;
        break;
      }
    }
    return showAppChoiceDialog(
      context: context,
      title: s['pickTemplateSlot'],
      cancelLabel: s['cancel'],
      items: files,
      initialIndex: initial,
      itemBuilder: (context, file, _) => DialogChoiceText(file.name),
    ).then((file) => file?.templateSlot);
  }
}

/// A text field that keeps its own controller so typing does not rebuild it
/// out from under the caret.
class _KeepTextField extends StatefulWidget {
  const _KeepTextField({
    required this.value,
    required this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  State<_KeepTextField> createState() => _KeepTextFieldState();
}

class _KeepTextFieldState extends State<_KeepTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_KeepTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      decoration: DialogFieldStyle.decoration(),
      onChanged: widget.onChanged,
    );
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse('$value');
}

int? _firstFileId(Map<String, dynamic> step) {
  final raw = step['file_ids'];
  if (raw is! List || raw.isEmpty) return null;
  return _asInt(raw.first);
}
