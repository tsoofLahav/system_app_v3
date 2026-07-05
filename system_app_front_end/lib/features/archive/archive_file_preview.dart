import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../core/models/topic.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/note_widgets.dart';
import '../../features/blocks/block_renderer.dart';

class ArchiveFilePreview extends StatelessWidget {
  const ArchiveFilePreview({
    super.key,
    required this.topic,
    required this.file,
    required this.blocks,
    required this.tasksByBlockId,
    required this.state,
    required this.height,
  });

  final Topic topic;
  final AppFile file;
  final List<Block> blocks;
  final Map<int, List<Task>> tasksByBlockId;
  final AppState state;
  final double height;

  @override
  Widget build(BuildContext context) {
    final accent = TopicAppearance.colorFromHex(topic.color);
    final title = state.fileDisplayName(file.name);
    final archivedAt = file.archivedAt;

    return SizedBox(
      height: height,
      child: NoteCard(
        topicAccent: accent,
        fileType: file.type,
        isMainTopic: topic.isMain,
        child: Padding(
          padding: AppSpacing.notePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: AppTypography.noteTitleStyle),
                  ),
                  if (archivedAt != null)
                    Text(
                      _formatArchivedDate(archivedAt),
                      style: AppTypography.metaStyle.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: AbsorbPointer(
                    child: blocks.isEmpty
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final block in blocks)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.blockGap,
                                  ),
                                  child: BlockRenderer(
                                    file: file,
                                    block: block,
                                    tasks: tasksByBlockId[block.id] ?? const [],
                                    state: state,
                                    topicAccent: accent,
                                    isMainTopic: topic.isMain,
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatArchivedDate(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
