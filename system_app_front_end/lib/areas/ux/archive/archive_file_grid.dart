import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/app_file.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../topic/topic_appearance.dart';

class ArchiveFileGrid extends StatelessWidget {
  const ArchiveFileGrid({
    super.key,
    required this.files,
    required this.state,
    required this.selectedFileId,
    required this.onSelect,
    this.deleteMode = false,
    this.markedForDelete = const {},
    this.onToggleDelete,
    this.onContextMenu,
  });

  final List<AppFile> files;
  final AppState state;
  final int? selectedFileId;
  final ValueChanged<AppFile> onSelect;
  final bool deleteMode;
  final Set<int> markedForDelete;
  final ValueChanged<AppFile>? onToggleDelete;
  final void Function(AppFile file, Offset globalPosition)? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final topic = state.selectedArchiveTopic;
    final accent =
        topic == null ? null : TopicAppearance.accentFor(topic);
    final isMain = topic?.isMain ?? false;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 168,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final marked = markedForDelete.contains(file.id);
        final selected = !deleteMode && file.id == selectedFileId;
        final title = state.fileDisplayName(file.name);
        final decoration = accent != null
            ? AppColors.filePaneDecoration(
                accent,
                file.id,
                isMainTopic: isMain,
              )
            : BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppColors.noteTop,
                border: Border.all(
                  color: AppColors.noteBorder.withValues(alpha: 0.55),
                ),
              );

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: deleteMode
                ? () => onToggleDelete?.call(file)
                : () => onSelect(file),
            onSecondaryTapUp: deleteMode || onContextMenu == null
                ? null
                : (details) => onContextMenu!(file, details.globalPosition),
            onLongPress: deleteMode || onContextMenu == null
                ? null
                : () {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    onContextMenu!(
                      file,
                      box.localToGlobal(box.size.center(Offset.zero)),
                    );
                  },
            child: DecoratedBox(
              decoration: decoration.copyWith(
                border: Border.all(
                  color: marked
                      ? AppColors.primary.withValues(alpha: 0.72)
                      : selected
                          ? AppColors.primary.withValues(alpha: 0.55)
                          : AppColors.noteBorder.withValues(alpha: 0.45),
                  width: marked || selected ? 1.4 : 0.8,
                ),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: AppTypography.noteBodyStyle.copyWith(
                            fontWeight: marked || selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        if (file.archivedAt != null)
                          Text(
                            _archiveDateLabel(file.archivedAt!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.metaStyle.copyWith(
                              fontSize: 9,
                              color: AppColors.textHint.withValues(alpha: 0.85),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (deleteMode && marked)
                    PositionedDirectional(
                      top: 6,
                      end: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: AppIcon(
                            AppIcons.check,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _archiveDateLabel(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final local = parsed.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
