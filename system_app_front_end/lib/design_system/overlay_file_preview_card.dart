import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import '../core/models/app_file.dart';
import '../core/models/topic.dart';
import '../features/bring_file/bring_file_preview.dart';
import '../features/bring_file/overlay_file_content_preview.dart';
import 'app_typography.dart';
import 'glass_surface.dart';
import 'overlay_dialog_style.dart';

/// Frosted file preview card shared by bring-file and arrange overlays.
class OverlayFilePreviewCard extends StatelessWidget {
  const OverlayFilePreviewCard({
    super.key,
    required this.file,
    required this.topic,
    required this.fileName,
    required this.accent,
    required this.preview,
    required this.previewsLoaded,
    required this.strings,
    this.topicLabel,
    this.padding = const EdgeInsets.all(14),
    this.titleFontSize = 14,
    this.tintOpacity = OverlayDialogStyle.fileCardTintOpacity,
    this.emphasized = false,
    this.onTap,
    this.onSecondaryTapDown,
  });

  final AppFile file;
  final Topic topic;
  final String fileName;
  final Color accent;
  final OverlayFilePreviewData? preview;
  final bool previewsLoaded;
  final AppStrings strings;
  final String? topicLabel;
  final EdgeInsets padding;
  final double titleFontSize;
  final double tintOpacity;
  final bool emphasized;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

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
            Expanded(
              child: OverlayFileContentPreview(
                preview: preview,
                loaded: previewsLoaded,
                strings: strings,
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null && onSecondaryTapDown == null) return child;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onSecondaryTapDown: onSecondaryTapDown,
        child: child,
      ),
    );
  }
}
