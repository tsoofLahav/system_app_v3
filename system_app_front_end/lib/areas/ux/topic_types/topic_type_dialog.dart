import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/services/api_service.dart';
import '../../files/data/app_file.dart';
import '../../files/data/topic.dart';
import '../../files/data/topic_type.dart';
import '../../automations/automation.dart';
import '../../automations/automation_builder_dialog.dart';
import '../../production_agent/ai_action.dart';
import '../../production_agent/ai_action_edit_dialog.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/confirm_dialog.dart';
import '../../ui/dialog_field_style.dart';
import '../../ui/dialog_metrics.dart';
import '../shell/chrome_anchors.dart';
import '../widgets/app_context_menu.dart';
import '../widgets/topic_emoji.dart';

Future<void> showTopicTypesListDialog({
  required BuildContext context,
  required AppState state,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (_) => _TopicTypesListDialog(state: state),
  );
}

/// Name-only create. Config is in Preferences, not opened automatically.
Future<void> createTopicTypeFromDialog({
  required BuildContext context,
  required AppState state,
  bool showConfigHint = true,
}) async {
  final names = await showAppDialog<_TypeNames>(
    context: context,
    builder: (_) => _TopicTypeNameDialog(state: state),
  );
  if (names == null || !context.mounted) return;
  try {
    await state.createTopicType(name: names.name, nameHe: names.nameHe);
    if (!context.mounted || !showConfigHint) return;
    showTopicTypeConfigHint(context, state);
  } on ApiException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.message)),
    );
  }
}

Future<void> showTopicTypeDialog({
  required BuildContext context,
  required AppState state,
  required TopicType type,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (_) => _TopicTypeDialog(state: state, typeId: type.id),
  );
}

void showTopicTypeConfigHint(BuildContext context, AppState state) {
  final box = ChromeAnchors.preferencesButton.currentContext
      ?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;
  final anchor = box.localToGlobal(Offset(box.size.width / 2, 0));
  AppContextMenu.showHint(
    context: context,
    globalPosition: anchor,
    text: state.strings['topicTypeConfigHint'],
    isRtl: state.strings.isRtl,
  );
}

class _TypeNames {
  const _TypeNames({required this.name, required this.nameHe});

  final String name;
  final String nameHe;
}

class _TopicTypeNameDialog extends StatefulWidget {
  const _TopicTypeNameDialog({required this.state});

  final AppState state;

  @override
  State<_TopicTypeNameDialog> createState() => _TopicTypeNameDialogState();
}

class _TopicTypeNameDialogState extends State<_TopicTypeNameDialog> {
  late final TextEditingController _name;
  late final TextEditingController _nameHe;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _nameHe = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _nameHe.dispose();
    super.dispose();
  }

  bool get _ready =>
      _name.text.trim().isNotEmpty && _nameHe.text.trim().isNotEmpty;

  void _submit() {
    if (!_ready) return;
    Navigator.pop(
      context,
      _TypeNames(name: _name.text.trim(), nameHe: _nameHe.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    return AppAdaptiveDialogShell(
      title: Text(s['newTopicType']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([_name, _nameHe]),
          builder: (context, _) {
            return FilledButton(
              onPressed: _ready ? _submit : null,
              child: Text(s['create']),
            );
          },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogField(
            label: s['nameEnglish'],
            child: TextField(
              controller: _name,
              autofocus: true,
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
        ],
      ),
    );
  }
}

class _TopicTypesListDialog extends StatefulWidget {
  const _TopicTypesListDialog({required this.state});

  final AppState state;

  @override
  State<_TopicTypesListDialog> createState() => _TopicTypesListDialogState();
}

class _TopicTypesListDialogState extends State<_TopicTypesListDialog> {
  AppState get state => widget.state;

  Future<void> _create() async {
    await createTopicTypeFromDialog(
      context: context,
      state: state,
      showConfigHint: false,
    );
    if (mounted) setState(() {});
  }

  Future<void> _open(TopicType type) async {
    await showTopicTypeDialog(context: context, state: state, type: type);
    if (mounted) setState(() {});
  }

  Future<void> _delete(TopicType type) async {
    final s = state.strings;
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: s['deleteTopicTypeTitle'],
      message: s.deleteTopicTypeMessage(state.topicTypeDisplayName(type)),
      confirmLabel: s['delete'],
      cancelLabel: s['cancel'],
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await state.deleteTopicType(type);
      if (mounted) setState(() {});
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.isEmpty ? s['typeInUse'] : error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final types = state.topicTypes;

    return AppAdaptiveDialogShell(
      title: Text(s['topicTypes']),
      width: AppDialogMetrics.wideWidth,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['close']),
        ),
        FilledButton(onPressed: _create, child: Text(s['newTopicType'])),
      ],
      child: SizedBox(
        height: 260,
        child: types.isEmpty
            ? Center(
                child: Text(
                  s['noTopicTypes'],
                  textAlign: TextAlign.center,
                  style: AppTypography.metaStyle,
                ),
              )
            : ListView.separated(
                itemCount: types.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final type = types[index];
                  return ListTile(
                    dense: true,
                    title: Text(state.topicTypeDisplayName(type)),
                    onTap: () => _open(type),
                    trailing: IconButton(
                      tooltip: s['delete'],
                      icon: const AppIcon(AppIcons.trash, size: 16),
                      onPressed: () => _delete(type),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _TopicTypeDialog extends StatefulWidget {
  const _TopicTypeDialog({required this.state, required this.typeId});

  final AppState state;
  final int typeId;

  @override
  State<_TopicTypeDialog> createState() => _TopicTypeDialogState();
}

class _TopicTypeDialogState extends State<_TopicTypeDialog> {
  AppState get state => widget.state;
  late final TextEditingController _name;
  late final TextEditingController _nameHe;
  List<AppFile> _templateFiles = const [];
  Topic? _templateTopic;
  var _loadingFiles = false;

  TopicType? get _type => state.topicTypeById(widget.typeId);

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _type?.name ?? '');
    _nameHe = TextEditingController(text: _type?.nameHe ?? '');
    state.loadAutomations();
    state.loadAiActions();
    _loadTemplate();
  }

  @override
  void dispose() {
    _name.dispose();
    _nameHe.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    final type = _type;
    final templateId = type?.templateTopicId;
    if (templateId == null) {
      setState(() {
        _templateFiles = const [];
        _templateTopic = null;
      });
      return;
    }
    setState(() => _loadingFiles = true);
    try {
      Topic? topic;
      for (final row in state.allTopics) {
        if (row.id == templateId) topic = row;
      }
      topic ??= await state.loadTopic(templateId);
      final files = await state.filesForTopic(templateId);
      if (!mounted) return;
      setState(() {
        _templateTopic = topic;
        _templateFiles = files;
        _loadingFiles = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFiles = false);
    }
  }

  Future<void> _saveAndClose() async {
    final type = _type;
    final name = _name.text.trim();
    final nameHe = _nameHe.text.trim();
    if (type == null) return;
    if (name.isEmpty || nameHe.isEmpty) return;
    if (name != type.name || nameHe != type.nameHe) {
      try {
        await state.updateTopicType(type, {
          'name': name,
          'name_he': nameHe,
        });
      } on ApiException catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
        return;
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickTemplate() async {
    final type = _type;
    if (type == null) return;
    final s = state.strings;
    final candidates = state.topicsOfType(type.id);
    final picked = await showAppDialog<int?>(
      context: context,
      builder: (ctx) => AppAdaptiveDialogShell(
        title: Text(s['pickTemplate']),
        width: AppDialogMetrics.wideWidth,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s['cancel']),
          ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                dense: true,
                title: Text(s['noTemplate']),
                onTap: () => Navigator.pop(ctx, -1),
              ),
              for (final topic in candidates)
                ListTile(
                  dense: true,
                  selected: topic.id == type.templateTopicId,
                  leading: TopicEmoji(value: topic.icon, size: 18),
                  title: Text(state.topicDisplayName(topic)),
                  onTap: () => Navigator.pop(ctx, topic.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await state.updateTopicType(type, {
      'template_topic_id': picked < 0 ? null : picked,
    });
    await _loadTemplate();
  }

  Future<void> _addExistingAction() async {
    final type = _type;
    if (type == null) return;
    final s = state.strings;
    final globals = [
      for (final action in state.aiActions)
        if (action.topicTypeId == null) action,
    ];
    if (globals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s['noGlobalActionsToAdd'])),
      );
      return;
    }
    final id = await showAppDialog<int>(
      context: context,
      builder: (ctx) => AppAdaptiveDialogShell(
        title: Text(s['addExistingAction']),
        width: AppDialogMetrics.wideWidth,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s['cancel']),
          ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final action in globals)
                ListTile(
                  dense: true,
                  title: Text(action.name),
                  onTap: () => Navigator.pop(ctx, action.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (id == null || !mounted) return;
    AiAction? picked;
    for (final action in state.aiActions) {
      if (action.id == id) picked = action;
    }
    if (picked == null) return;
    await state.updateAiAction(picked, {'topic_type_id': type.id});
    if (mounted) setState(() {});
  }

  Future<void> _createAction() async {
    final type = _type;
    if (type == null) return;
    final saved = await showAiActionEditDialog(
      context: context,
      state: state,
      initialTopicTypeId: type.id,
    );
    if (saved != null && mounted) setState(() {});
  }

  Future<void> _createAutomation() async {
    final type = _type;
    if (type == null) return;
    final saved = await showAutomationBuilderDialog(
      context: context,
      state: state,
      initialScope: AutomationScope.ofType(type.id),
    );
    if (saved && mounted) setState(() {});
  }

  Future<void> _editAutomation(Automation automation) async {
    final saved = await showAutomationBuilderDialog(
      context: context,
      state: state,
      automation: automation,
    );
    if (saved && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final type = _type;
    if (type == null) {
      return AppAdaptiveDialogShell(
        title: Text(s['topicType']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s['close']),
          ),
        ],
        child: Text(s['noTopicTypes'], style: AppTypography.metaStyle),
      );
    }

    final actions = state.aiActionsForType(type.id);
    final automations = state.automationsForType(type.id);
    final templateLabel = _templateTopic == null
        ? s['noTemplate']
        : state.topicDisplayName(_templateTopic!);

    return AppAdaptiveDialogShell(
      title: Text(s['editTopicType']),
      width: AppDialogMetrics.wideWidth,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['close']),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([_name, _nameHe]),
          builder: (context, _) {
            final ready =
                _name.text.trim().isNotEmpty && _nameHe.text.trim().isNotEmpty;
            return FilledButton(
              onPressed: ready ? _saveAndClose : null,
              child: Text(s['save']),
            );
          },
        ),
      ],
      child: Column(
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
          _TypeSection(
            label: s['template'],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppDialogPickerField(
                  label: s['templateTopic'],
                  preview: const AppIcon(AppIcons.bringFile, size: 16),
                  valueLabel: templateLabel,
                  onTap: _pickTemplate,
                ),
                if (_templateTopic?.isArchived == true) ...[
                  const SizedBox(height: 6),
                  Text(s['templateArchived'], style: AppTypography.metaStyle),
                ],
                if (_loadingFiles) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ] else if (_templateFiles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(s['templateFiles'], style: DialogFieldStyle.labelStyle),
                  for (final file in _templateFiles)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(file.name, style: AppTypography.metaStyle),
                    ),
                ] else if (type.templateTopicId != null) ...[
                  const SizedBox(height: 6),
                  Text(s['noTemplateFiles'], style: AppTypography.metaStyle),
                ],
              ],
            ),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          _TypeSection(
            label: s['typeAiActions'],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (actions.isEmpty)
                  Text(s['noTypeActions'], style: AppTypography.metaStyle)
                else
                  for (final action in actions)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(action.name),
                      onTap: () async {
                        await showAiActionEditDialog(
                          context: context,
                          state: state,
                          action: action,
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _addExistingAction,
                        child: Text(s['addExistingAction']),
                      ),
                      TextButton(
                        onPressed: _createAction,
                        child: Text(s['createAiAction']),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DialogFieldStyle.fieldGap),
          _TypeSection(
            label: s['typeAutomations'],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (automations.isEmpty)
                  Text(s['noTypeAutomations'], style: AppTypography.metaStyle)
                else
                  for (final automation in automations)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(automation.name),
                      onTap: () => _editAutomation(automation),
                    ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: _createAutomation,
                    child: Text(s['createAutomation']),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeSection extends StatelessWidget {
  const _TypeSection({required this.label, required this.child});

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
