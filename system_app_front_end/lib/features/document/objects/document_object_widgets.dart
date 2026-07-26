import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/models/app_file.dart';
import '../../../core/models/object_embed.dart';
import '../../../core/models/task.dart';
import '../../../design_system/app_typography.dart';
import '../../../shared/widgets/task_row.dart';
import '../document_model.dart';
import '../nodes/paragraph_node_widget.dart';

class TaskListObjectWidget extends StatefulWidget {
  const TaskListObjectWidget({
    super.key,
    required this.node,
    required this.embed,
    required this.file,
    required this.state,
    required this.onRefresh,
  });

  final ObjectNode node;
  final ObjectEmbed embed;
  final AppFile file;
  final AppState state;
  final VoidCallback onRefresh;

  @override
  State<TaskListObjectWidget> createState() => _TaskListObjectWidgetState();
}

class _TaskListObjectWidgetState extends State<TaskListObjectWidget> {
  List<Task> get _tasks => widget.embed.tasks ?? const [];

  List<Task> get _active => _tasks.where((t) => !t.isDone).toList()
    ..sort((a, b) => a.listOrderIndex.compareTo(b.listOrderIndex));

  List<Task> get _done => _tasks.where((t) => t.isDone).toList()
    ..sort((a, b) => a.listOrderIndex.compareTo(b.listOrderIndex));

  Future<void> _createAtEnd(String title) async {
    if (widget.embed.taskListId == null) return;
    await widget.state.createTaskInList(
      widget.embed.taskListId!,
      title: title.isEmpty ? 'New task' : title,
    );
    widget.onRefresh();
  }

  Future<void> _reorder(List<Task> zoneTasks, int oldIndex, int newIndex) async {
    if (widget.embed.taskListId == null) return;
    if (newIndex > oldIndex) newIndex--;
    final items = List<Task>.from(zoneTasks);
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    final otherZone = zoneTasks == _active ? _done : _active;
    final orderedIds = [
      if (zoneTasks == _active) ...items.map((t) => t.id),
      if (zoneTasks == _active) ...otherZone.map((t) => t.id),
      if (zoneTasks == _done) ...otherZone.map((t) => t.id),
      if (zoneTasks == _done) ...items.map((t) => t.id),
    ];
    await widget.state.reorderTasksInList(widget.embed.taskListId!, orderedIds);
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tasks', style: AppTypography.metaStyle),
            const SizedBox(height: 4),
            _TaskZone(
              label: 'Active',
              tasks: _active,
              state: widget.state,
              file: widget.file,
              embed: widget.embed,
              onRefresh: widget.onRefresh,
              onReorder: (o, n) => _reorder(_active, o, n),
            ),
            _TaskZone(
              label: 'Done',
              tasks: _done,
              state: widget.state,
              file: widget.file,
              embed: widget.embed,
              onRefresh: widget.onRefresh,
              onReorder: (o, n) => _reorder(_done, o, n),
            ),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Add task…',
                isDense: true,
                border: InputBorder.none,
              ),
              onSubmitted: _createAtEnd,
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskZone extends StatelessWidget {
  const _TaskZone({
    required this.label,
    required this.tasks,
    required this.state,
    required this.file,
    required this.embed,
    required this.onRefresh,
    required this.onReorder,
  });

  final String label;
  final List<Task> tasks;
  final AppState state;
  final AppFile file;
  final ObjectEmbed embed;
  final VoidCallback onRefresh;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTypography.metaStyle),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tasks.length,
          onReorder: onReorder,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return ReorderableDragStartListener(
              key: ValueKey(task.id),
              index: index,
              child: TaskRow(
                task: task,
                state: state,
                onToggle: () async {
                  await state.toggleTaskStatus(task);
                  onRefresh();
                },
                onTitleChanged: (title) async {
                  await state.updateTaskTitle(task, title);
                  onRefresh();
                },
                onDelete: () async {
                  await state.deleteTask(task);
                  onRefresh();
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class InfoObjectWidget extends StatefulWidget {
  const InfoObjectWidget({
    super.key,
    required this.node,
    required this.embed,
    required this.state,
    required this.onRefresh,
  });

  final ObjectNode node;
  final ObjectEmbed embed;
  final AppState state;
  final VoidCallback onRefresh;

  @override
  State<InfoObjectWidget> createState() => _InfoObjectWidgetState();
}

class _InfoObjectWidgetState extends State<InfoObjectWidget> {
  late TextEditingController _titleController;
  ParagraphNode? _bodyNode;

  @override
  void initState() {
    super.initState();
    final info = widget.embed.information ?? const {};
    _titleController = TextEditingController(text: info['title'] as String? ?? '');
    final meta = info['metadata'];
    final spans = meta is Map ? meta['spans'] : null;
    _bodyNode = ParagraphNode(
      id: '${widget.node.id}_body',
      text: info['body'] as String? ?? '',
      spans: spans is List
          ? [
              for (final s in spans)
                if (s is Map<String, dynamic>) TextSpanMark.fromJson(s),
            ]
          : const [],
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.embed.informationId == null || _bodyNode == null) return;
    await widget.state.updateInfoObject(
      widget.embed,
      title: _titleController.text,
      body: _bodyNode!.text,
      spans: _bodyNode!.spans.map((s) => s.toJson()).toList(),
    );
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final links = widget.embed.links ?? const [];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            style: AppTypography.noteTitleStyle,
            decoration: const InputDecoration(
              hintText: 'Info title',
              border: InputBorder.none,
              isDense: true,
            ),
            onEditingComplete: _save,
          ),
          if (_bodyNode != null)
            ParagraphNodeWidget(
              node: _bodyNode!,
              state: widget.state,
              onChanged: (node) {
                setState(() => _bodyNode = node);
                _save();
              },
            ),
          if (links.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Links', style: AppTypography.metaStyle),
            for (final link in links)
              Text(
                '${link['target_type']} #${link['target_id']}',
                style: AppTypography.metaStyle,
              ),
          ],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () async {
                await widget.state.addInfoLink(widget.embed, 'info', widget.embed.id);
                widget.onRefresh();
              },
              child: const Text('Add link'),
            ),
          ),
        ],
      ),
    );
  }
}
