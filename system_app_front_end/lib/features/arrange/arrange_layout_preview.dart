import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/app_file.dart';
import '../../core/models/topic.dart';
import '../../design_system/file_layouts.dart';
import '../../design_system/overlay_file_preview_card.dart';
import '../bring_file/bring_file_preview.dart';

/// Layout-shaped arrangement of compact preview cards for the arrange overlay.
class ArrangeLayoutPreview extends StatelessWidget {
  const ArrangeLayoutPreview({
    super.key,
    required this.files,
    required this.layoutId,
    required this.topic,
    required this.accent,
    required this.fileNameFor,
    required this.onFileTap,
    this.onFileSecondaryTap,
    required this.previewsByFileId,
    required this.previewsLoaded,
    required this.strings,
  });

  final List<AppFile> files;
  final String layoutId;
  final Topic topic;
  final Color accent;
  final String Function(AppFile file) fileNameFor;
  final void Function(AppFile file) onFileTap;
  final void Function(AppFile file)? onFileSecondaryTap;
  final Map<int, OverlayFilePreviewData> previewsByFileId;
  final bool previewsLoaded;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final slots = [
          for (var i = 0; i < files.length; i++)
            OverlayFilePreviewCard(
              file: files[i],
              topic: topic,
              fileName: fileNameFor(files[i]),
              accent: accent,
              preview:
                  previewsByFileId[files[i].id] ?? OverlayFilePreviewData.empty,
              previewsLoaded: previewsLoaded,
              strings: strings,
              padding: const EdgeInsets.all(12),
              titleFontSize: 13,
              emphasized: i == 0,
              onTap: () => onFileTap(files[i]),
              onSecondaryTapDown: onFileSecondaryTap == null
                  ? null
                  : (_) => onFileSecondaryTap!(files[i]),
            ),
        ];

        final layout = FileLayouts.byId(layoutId);
        final fixedCapacity = FileLayouts.fixedCapacityFor(layoutId);
        final primaryCount = fixedCapacity != null
            ? fixedCapacity.clamp(0, slots.length)
            : slots.length;
        final primarySlots = List.generate(primaryCount, (i) => slots[i]);

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: _buildLayout(
            layoutId: layout.id,
            slots: primarySlots,
            constraints: constraints,
          ),
        );
      },
    );
  }

  Widget _buildLayout({
    required String layoutId,
    required List<Widget> slots,
    required BoxConstraints constraints,
  }) {
    final gap = AppLayoutSpacing.gap;
    final h = constraints.maxHeight;
    final w = constraints.maxWidth;

    switch (layoutId) {
      case FileLayouts.single:
        return slots.isEmpty
            ? const SizedBox.shrink()
            : SizedBox(height: h, child: slots.first);
      case FileLayouts.split:
        return SizedBox(
          height: h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < slots.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: slots[i]),
              ],
            ],
          ),
        );
      case FileLayouts.heroLeft:
        return SizedBox(
          height: h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: _slotAt(slots, 0)),
              SizedBox(width: gap),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Expanded(child: _slotAt(slots, 1)),
                    SizedBox(height: gap),
                    Expanded(child: _slotAt(slots, 2)),
                  ],
                ),
              ),
            ],
          ),
        );
      case FileLayouts.heroRight:
        return SizedBox(
          height: h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Expanded(child: _slotAt(slots, 0)),
                    SizedBox(height: gap),
                    Expanded(child: _slotAt(slots, 1)),
                  ],
                ),
              ),
              SizedBox(width: gap),
              Expanded(flex: 3, child: _slotAt(slots, 2)),
            ],
          ),
        );
      case FileLayouts.row:
        return SizedBox(
          height: h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < slots.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: slots[i]),
              ],
            ],
          ),
        );
      case FileLayouts.grid:
      default:
        final cols = w >= 460 ? 2 : 1;
        final rows = (slots.length / cols).ceil().clamp(1, 3);
        final cellW = (w - gap * (cols - 1)) / cols;
        final cellH = (h - gap * (rows - 1)) / rows;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final slot in slots)
              SizedBox(width: cellW, height: cellH, child: slot),
          ],
        );
    }
  }

  Widget _slotAt(List<Widget> slots, int index) {
    if (index < slots.length) return slots[index];
    return const SizedBox.shrink();
  }
}
