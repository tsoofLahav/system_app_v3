import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';

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
  });

  final List<AppFile> files;
  final AppState state;
  final int? selectedFileId;
  final ValueChanged<AppFile> onSelect;
  final bool deleteMode;
  final Set<int> markedForDelete;
  final ValueChanged<AppFile>? onToggleDelete;

  @override
  Widget build(BuildContext context) {
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
        final typeLabel = state.strings.fileTypeLabel(file.type);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: deleteMode
                ? () => onToggleDelete?.call(file)
                : () => onSelect(file),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: marked
                    ? AppColors.primary.withValues(alpha: 0.16)
                    : selected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.noteTop,
                border: Border.all(
                  color: marked
                      ? AppColors.primary.withValues(alpha: 0.72)
                      : selected
                      ? AppColors.primary.withValues(alpha: 0.55)
                      : AppColors.noteBorder.withValues(alpha: 0.55),
                  width: marked || selected ? 1.2 : 0.8,
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
                        Text(
                          typeLabel,
                          textAlign: TextAlign.start,
                          style: AppTypography.metaStyle.copyWith(
                            color: AppColors.textHint,
                          ),
                        ),
                        if (file.archivedAt != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            file.archivedAt!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.start,
                            style: AppTypography.metaStyle.copyWith(
                              fontSize: 9,
                              color: AppColors.textHint.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
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
                          child: Icon(
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
