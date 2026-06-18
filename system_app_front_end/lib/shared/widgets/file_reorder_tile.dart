import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';

const fileReorderTileHeight = 88.0;
const fileReorderTileMaxWidth = 360.0;

/// Draggable card that looks like a file pane cut off at the bottom.
class FileReorderTile extends StatelessWidget {
  const FileReorderTile({
    super.key,
    required this.file,
    required this.blocks,
    required this.tasks,
    required this.state,
    required this.accent,
    required this.dimmed,
  });

  final AppFile file;
  final List<Block> blocks;
  final List<Task> tasks;
  final AppState state;
  final Color accent;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: dimmed ? 0.5 : 1,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GlassSurface.styled(
          style: AppGlassStyle.floating,
          borderRadius: BorderRadius.circular(AppGlassStyle.floatingRadius),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppGlassStyle.floatingRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.fileDisplayName(file.name),
                        style: AppTypography.noteTitleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ClipRect(
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: _FileContentPreview(
                              file: file,
                              blocks: blocks,
                              tasks: tasks,
                              state: state,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 28,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.noteTop.withValues(alpha: 0),
                          AppColors.noteTop.withValues(alpha: 0.55),
                          AppColors.noteTop.withValues(alpha: 0.88),
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
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

class _FileContentPreview extends StatelessWidget {
  const _FileContentPreview({
    required this.file,
    required this.blocks,
    required this.tasks,
    required this.state,
  });

  final AppFile file;
  final List<Block> blocks;
  final List<Task> tasks;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;

    if (blocks.isEmpty && file.type != 'tasks') {
      return Text(
        s['writeHere'],
        style: AppTypography.noteBodyStyle.copyWith(color: AppColors.noteHint),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _PreviewBlock(
              file: file,
              block: block,
              tasks: tasks,
              state: state,
            ),
          ),
        if (file.type == 'tasks' && tasks.isNotEmpty)
          for (final task in tasks.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• ${task.title}',
                style: AppTypography.noteBodyStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
      ],
    );
  }
}

class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({
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
      case 'header':
        return Text(
          block.text.isEmpty ? s['headerHint'] : block.text,
          style: AppTypography.blockHeaderStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case 'summary':
        return Text(
          block.text.isEmpty ? s['summaryHint'] : block.text,
          style: AppTypography.noteBodyStyle.copyWith(
            fontStyle: FontStyle.italic,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      case 'text':
        return Text(
          block.text.isEmpty ? s['writeHere'] : block.text,
          style: AppTypography.noteBodyStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      case 'checklist':
        final items = List<Map<String, dynamic>>.from(
          block.content['items'] as List<dynamic>? ?? [],
        );
        if (items.isEmpty) return const SizedBox.shrink();
        final item = items.first;
        return Text(
          '${item['done'] == true ? '☑' : '☐'} ${item['text'] ?? ''}',
          style: AppTypography.noteBodyStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case 'image':
        final path = block.content['image_path'] as String? ?? '';
        if (path.isEmpty) {
          return Text(s['noImage'], style: AppTypography.metaStyle);
        }
        final url = path.startsWith('http')
            ? path
            : '${ApiConfig.baseUrl}$path';
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            url,
            height: 36,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Text(s['noImage'], style: AppTypography.metaStyle),
          ),
        );
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
        return Text(
          '• ${task.title}',
          style: AppTypography.noteBodyStyle.copyWith(
            decoration: task.isDone ? TextDecoration.lineThrough : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case 'measurement':
        return Text(
          '${block.content['label'] ?? s['measurement']}: '
          '${block.content['value'] ?? ''} ${block.content['unit'] ?? ''}',
          style: AppTypography.noteBodyStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case 'table':
        return Text(
          s.tableRows(block.content['rows']?.length ?? 0),
          style: AppTypography.noteBodyStyle,
        );
      case 'list':
        final items = block.content['items'] as List<dynamic>? ?? [];
        final first = items.isEmpty ? '' : items.first;
        final text = first is Map
            ? first['text']?.toString() ?? ''
            : first.toString();
        return Text(
          text.isEmpty ? s['addPoint'] : '• $text',
          style: AppTypography.noteBodyStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case 'graph':
        return Text(
          s['graphPlaceholder'],
          style: AppTypography.metaStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case 'task_list':
        return const SizedBox.shrink();
      default:
        return Text(
          s.unknownBlock(block.type),
          style: AppTypography.metaStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
    }
  }
}
