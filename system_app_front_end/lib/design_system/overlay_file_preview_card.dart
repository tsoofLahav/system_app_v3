import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import 'app_colors.dart';
import 'app_typography.dart';
import 'glass_surface.dart';
import 'overlay_dialog_style.dart';

/// Frosted file preview card shared by bring-file and arrange overlays.
class OverlayFilePreviewCard extends StatelessWidget {
  const OverlayFilePreviewCard({
    super.key,
    required this.fileName,
    required this.accent,
    required this.previewLines,
    required this.previewsLoaded,
    required this.strings,
    this.topicLabel,
    this.padding = const EdgeInsets.all(14),
    this.titleFontSize = 14,
    this.tintOpacity = OverlayDialogStyle.fileCardTintOpacity,
    this.emphasized = false,
    this.onTap,
  });

  final String fileName;
  final Color accent;
  final List<String> previewLines;
  final bool previewsLoaded;
  final AppStrings strings;
  final String? topicLabel;
  final EdgeInsets padding;
  final double titleFontSize;
  final double tintOpacity;
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(OverlayDialogStyle.fileCardBorderRadius),
        boxShadow: OverlayDialogStyle.fileCardShadow,
      ),
      child: GlassSurface(
        borderRadius:
            BorderRadius.circular(OverlayDialogStyle.fileCardBorderRadius),
        tintColor: accent,
        tintOpacity: tintOpacity,
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (topicLabel != null) ...[
              Text(
                topicLabel!,
                style: AppTypography.metaStyle.copyWith(
                  color: accent.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
            ],
            Text(
              fileName,
              style: AppTypography.noteTitleStyle.copyWith(
                fontSize: titleFontSize,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: topicLabel != null ? 10 : 8),
            Expanded(child: _PreviewBody(
              previewLines: previewLines,
              previewsLoaded: previewsLoaded,
              strings: strings,
            )),
          ],
        ),
      ),
    );

    if (onTap == null) return child;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({
    required this.previewLines,
    required this.previewsLoaded,
    required this.strings,
  });

  final List<String> previewLines;
  final bool previewsLoaded;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    if (!previewsLoaded) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          strings['bringFilePreviewLoading'],
          style: AppTypography.metaStyle.copyWith(
            color: AppColors.noteHint.withValues(alpha: 0.8),
            fontSize: 11,
          ),
        ),
      );
    }
    if (previewLines.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          strings['bringFilePreviewEmpty'],
          style: AppTypography.metaStyle.copyWith(
            color: AppColors.noteHint.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: previewLines.length,
      separatorBuilder: (_, index) => const SizedBox(height: 5),
      itemBuilder: (context, index) {
        final line = previewLines[index];
        final isTask = line.startsWith('• ');
        return Text(
          line,
          style: AppTypography.noteBodyStyle.copyWith(
            fontSize: 11,
            height: 1.35,
            color: AppColors.text.withValues(alpha: isTask ? 0.72 : 0.78),
          ),
          maxLines: isTask ? 1 : 2,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
