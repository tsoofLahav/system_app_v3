import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/app_state.dart';
import './automation.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/dialog_field_style.dart';
import '../ui/glass_surface.dart';
import '../production_agent/ai_tool_bar.dart';

Future<void> showAutomationDialog({
  required BuildContext context,
  required AppState state,
}) async {
  await showAppDialog<void>(
    context: context,
    builder: (ctx) => _AutomationDialog(state: state),
  );
}

class _AutomationDialog extends StatefulWidget {
  const _AutomationDialog({required this.state});

  final AppState state;

  @override
  State<_AutomationDialog> createState() => _AutomationDialogState();
}

class _AutomationDialogState extends State<_AutomationDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  var _creating = false;
  var _kind = _AutomationKind.manual;

  final _nameController = TextEditingController();
  final _promptController = TextEditingController();
  final _scheduleController = TextEditingController(text: '0 8 * * *');
  var _applyMode = 'review';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    widget.state.loadAutomations();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameController.dispose();
    _promptController.dispose();
    _scheduleController.dispose();
    super.dispose();
  }

  AppState get state => widget.state;

  Future<void> _create() async {
    final name = _nameController.text.trim();
    final prompt = _promptController.text.trim();
    if (name.isEmpty || prompt.isEmpty) return;

    setState(() => _creating = true);
    try {
      await state.createAutomation(
        name: name,
        prompt: prompt,
        applyMode: _applyMode,
        isScheduled: _kind == _AutomationKind.scheduled,
        schedule: _kind == _AutomationKind.scheduled
            ? _scheduleController.text.trim()
            : null,
      );
      if (!mounted) return;
      _nameController.clear();
      _promptController.clear();
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.strings['created'] ?? 'Created')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _runAutomation(Automation automation) async {
    try {
      await runSavedAgentAction(context, state, automation);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final manual = state.manualAiActions;
    final scheduled = state.scheduledAutomations;

    return AppGlassDialog(
      title: Text(s['automations']),
      width: 520,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s['close'])),
      ],
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              controller: _tabs,
              tabs: [
                Tab(text: s['aiActions']),
                Tab(text: s['scheduledAutomations']),
              ],
            ),
            const SizedBox(height: 12),
            _buildCreateForm(s),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _AutomationList(
                    emptyLabel: s['noAiActions'],
                    items: manual,
                    onRun: _runAutomation,
                    onDelete: (a) => state.deleteAutomation(a),
                  ),
                  _AutomationList(
                    emptyLabel: s['noAutomations'],
                    items: scheduled,
                    onRun: _runAutomation,
                    onDelete: (a) => state.deleteAutomation(a),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateForm(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _tabs.index == 0 ? s['createAiAction'] : s['createAutomation'],
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: DialogFieldStyle.decoration(hintText: s['automationName']),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _promptController,
          minLines: 2,
          maxLines: 4,
          decoration: DialogFieldStyle.decoration(hintText: s['automationPrompt']),
        ),
        if (_tabs.index == 1) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _scheduleController,
            decoration: DialogFieldStyle.decoration(
              hintText: s['scheduleCronHint'],
            ),
          ),
        ],
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _applyMode,
          decoration: DialogFieldStyle.decoration(hintText: s['applyMode']),
          items: [
            DropdownMenuItem(value: 'review', child: Text(s['applyModeReview'])),
            DropdownMenuItem(value: 'direct_apply', child: Text(s['applyModeDirect'])),
            DropdownMenuItem(value: 'notify_only', child: Text(s['applyModeNotify'])),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _applyMode = v);
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            onPressed: _creating ? null : () {
              _kind = _tabs.index == 0
                  ? _AutomationKind.manual
                  : _AutomationKind.scheduled;
              _create();
            },
            child: Text(_creating ? s['aiRunning'] : s['create']),
          ),
        ),
      ],
    );
  }
}

enum _AutomationKind { manual, scheduled }

class _AutomationList extends StatelessWidget {
  const _AutomationList({
    required this.emptyLabel,
    required this.items,
    required this.onRun,
    required this.onDelete,
  });

  final String emptyLabel;
  final List<Automation> items;
  final Future<void> Function(Automation) onRun;
  final Future<void> Function(Automation) onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(emptyLabel));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          dense: true,
          title: Text(item.name),
          subtitle: Text(
            item.prompt,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => onRun(item),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(item),
              ),
            ],
          ),
        );
      },
    );
  }
}
