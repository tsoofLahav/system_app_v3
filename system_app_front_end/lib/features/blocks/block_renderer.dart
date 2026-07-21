import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import 'board_block_widget.dart';
import 'checklist_block_widget.dart';
import 'details_block_widget.dart';
import 'graph_block_widget.dart';
import 'header_block_widget.dart';
import 'image_block_widget.dart';
import 'points_list_block_widget.dart';
import 'summary_block_widget.dart';
import 'table_block_widget.dart';
import 'block_context_menu.dart';
import '../../features/shell/automation_abandon_dialog.dart';
import 'tasks_connected_editor.dart';
import 'task_block_widget.dart';
import 'text_block_widget.dart';

class BlockRenderer extends StatelessWidget {
  const BlockRenderer({
    super.key,
    required this.file,
    required this.block,
    required this.tasks,
    required this.state,
    this.topicAccent,
    this.isMainTopic = false,
    this.onBlockMenuAction,
    this.onTableCellSecondaryTapDown,
    this.blockIndex = 0,
  });

  final AppFile file;
  final Block block;
  final List<Task> tasks;
  final AppState state;
  final Color? topicAccent;
  final bool isMainTopic;
  final BlockMenuHandler? onBlockMenuAction;
  final TableCellSecondaryTapCallback? onTableCellSecondaryTapDown;
  final int blockIndex;

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
          onChanged: (c) => state.updateBlockContent(block, c, notify: true),
        );
      case 'header':
        return HeaderBlockWidget(
          block: block,
          hint: s['headerHint'],
          aiState: state,
          aiFileId: file.id,
          hasContentAbove: blockIndex > 0,
          onChanged: (c) => state.updateBlockContent(block, c, notify: true),
        );
      case 'summary':
        return SummaryBlockWidget(
          block: block,
          hint: s['summaryHint'],
          topicAccent: topicAccent,
          fileType: file.type,
          isMainTopic: isMainTopic,
          aiState: state,
          aiFileId: file.id,
          onChanged: (c) => state.updateBlockContent(block, c, notify: true),
        );
      case 'checklist':
        return ChecklistBlockWidget(
          block: block,
          aiState: state,
          aiFileId: file.id,
          onAddItem: (index) => state.addChecklistItem(block, index: index),
          onItemChanged: (i, text, done) =>
              state.updateChecklistItem(block, i, text, done),
          onRemoveItem: (i) => state.removeChecklistItem(block, i),
        );
      case 'task_list':
        return TasksConnectedEditor(
          file: file,
          listBlock: block,
          state: state,
          onBlockMenuAction: onBlockMenuAction,
        );
      case 'task':
        final fileBlocks = state.selectedDetail?.blocksByFileId[file.id] ?? [];
        Block? listBlock;
        for (final b in fileBlocks) {
          if (b.type == 'task_list') {
            listBlock = b;
            break;
          }
        }
        if (listBlock != null) return const SizedBox.shrink();

        final taskId = block.content['task_id'] as int?;
        Task? task;
        for (final t in tasks) {
          if (t.id == taskId) {
            task = t;
            break;
          }
        }
        if (task == null) return const SizedBox.shrink();
        return TaskBlockWidget(
          task: task,
          taskBlock: block,
          file: file,
          listBlock: block,
          state: state,
          onToggle: () => state.toggleTaskStatus(
            task!,
            confirmAbandonCompanionFlow: () =>
                showAutomationAbandonChangesDialog(
                  context: context,
                  state: state,
                ),
          ),
        );
      case 'image':
        final path = block.content['image_path'] as String? ?? '';
        if (path.isEmpty) return Text(s['noImage']);
        return ImageBlockWidget(
          block: block,
          maxWidth: 560,
          onChanged: (c) => state.updateBlockContent(block, c, notify: true),
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
          onChanged: (c) => state.updateBlockContent(block, c, notify: true),
          onCellSecondaryTapDown: onTableCellSecondaryTapDown,
        );
      case 'list':
        return PointsListBlockWidget(
          block: block,
          onChanged: (c) => state.updateBlockContent(block, c, notify: true),
        );
      case 'details':
        return DetailsBlockWidget(
          block: block,
          aiState: state,
          aiFileId: file.id,
          onChanged: (c) => state.updateBlockContent(block, c, notify: true),
        );
      case 'graph':
        return GraphBlockWidget(
          block: block,
          emptyLabel: s['graphPlaceholder'],
          duplicateDayMessage: s['graphDuplicateDay'],
          onChanged: (c) => state.updateBlockContent(block, c, notify: true),
        );
      case 'board':
        return BoardBlockWidget(
          block: block,
          addImageTooltip: s['boardAddImage'],
          aiImageTooltip: s['aiImage'],
          cropTooltip: s['boardCrop'],
          aiPromptTitle: s['boardAiPromptTitle'],
          aiPromptHint: s['boardAiPromptHint'],
          emptyHint: s['boardEmptyHint'],
          deleteImageLabel: s['boardDeleteImage'],
          cancelLabel: s['cancel'],
          submitLabel: s['aiImage'],
          copyImageLabel: s['boardCopyImage'],
          pasteImageLabel: s['boardPasteImage'],
          backgroundLabel: s['boardBackground'],
          backgroundCustomLabel: s['boardBackgroundCustom'],
          backgroundWhiteLabel: s['boardBgWhite'],
          backgroundLightGrayLabel: s['boardBgLightGray'],
          backgroundSkyLabel: s['boardBgSky'],
          backgroundCreamLabel: s['boardBgCream'],
          okLabel: s['ok'],
          isRtl: s.isRtl,
          aiRunning: state.aiRunning,
          uploadImage: (filename, bytes) =>
              state.uploadImageBytes(filename, bytes),
          onRunAiImage: (_) async {},
          onChanged: (c) => state.updateBlockContent(block, c, notify: true),
          onCommit: (c) => state.scheduleBlockSave(block, c),
        );
      default:
        return Text(s.unknownBlock(block.type));
    }
  }
}
