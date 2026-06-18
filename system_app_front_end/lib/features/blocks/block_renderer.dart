import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import 'checklist_block_widget.dart';
import 'graph_placeholder_block_widget.dart';
import 'header_block_widget.dart';
import 'points_list_block_widget.dart';
import 'summary_block_widget.dart';
import 'table_block_widget.dart';
import 'task_block_widget.dart';
import 'text_block_widget.dart';

class BlockRenderer extends StatelessWidget {
  const BlockRenderer({
    super.key,
    required this.file,
    required this.block,
    required this.tasks,
    required this.state,
  });

  final AppFile file;
  final Block block;
  final List<Task> tasks;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;

    switch (block.type) {
      case 'text':
        return TextBlockWidget(
          block: block,
          hint: s['writeHere'],
          aiState: state,
          aiFileId: file.id,
          autofocus: state.pendingFocusBlockId == block.id,
          onAutofocused: () => state.clearBlockFocus(block.id),
          onChanged: (c) => state.updateBlockContent(block, c),
        );
      case 'header':
        return HeaderBlockWidget(
          block: block,
          hint: s['headerHint'],
          aiState: state,
          aiFileId: file.id,
          onChanged: (c) => state.updateBlockContent(block, c),
        );
      case 'summary':
        return SummaryBlockWidget(
          block: block,
          hint: s['summaryHint'],
          aiState: state,
          aiFileId: file.id,
          onChanged: (c) => state.updateBlockContent(block, c),
        );
      case 'checklist':
        return ChecklistBlockWidget(
          block: block,
          aiState: state,
          aiFileId: file.id,
          onAddItem: (index) => state.addChecklistItem(block, index: index),
          onItemChanged: (i, text, done) =>
              state.updateChecklistItem(block, i, text, done),
        );
      case 'task_list':
        return const SizedBox.shrink();
      case 'task':
        final taskId = block.content['task_id'] as int?;
        Task? task;
        for (final t in tasks) {
          if (t.id == taskId) {
            task = t;
            break;
          }
        }
        if (task == null) return const SizedBox.shrink();
        final resolvedTask = task;
        return TaskBlockWidget(
          task: resolvedTask,
          state: state,
          onToggle: () => state.toggleTaskStatus(resolvedTask),
        );
      case 'image':
        final path = block.content['image_path'] as String? ?? '';
        if (path.isEmpty) return Text(s['noImage']);
        final url = path.startsWith('http')
            ? path
            : '${ApiConfig.baseUrl}$path';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Image.network(url, height: 180, fit: BoxFit.cover),
        );
      case 'measurement':
        return ListTile(
          dense: true,
          title: Text(block.content['label']?.toString() ?? s['measurement']),
          trailing: Text(
            '${block.content['value'] ?? ''} ${block.content['unit'] ?? ''}',
          ),
        );
      case 'table':
        return TableBlockWidget(
          block: block,
          addRowLabel: s['addRow'],
          addColumnLabel: s['addColumn'],
          onChanged: (c) => state.updateBlockContent(block, c, notify: true),
        );
      case 'list':
        return PointsListBlockWidget(
          block: block,
          onChanged: (c) => state.updateBlockContent(block, c, notify: true),
        );
      case 'graph':
        return GraphPlaceholderBlockWidget(label: s['graphPlaceholder']);
      default:
        return Text(s.unknownBlock(block.type));
    }
  }
}
