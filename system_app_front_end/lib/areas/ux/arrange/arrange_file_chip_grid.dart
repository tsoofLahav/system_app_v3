import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../files/data/app_file.dart';
import '../../files/data/topic.dart';
import '../../files/editor/file_preview.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/overlay_file_preview_card.dart';

/// Payload for an arrange-grid drag: which file, and where it started.
class ArrangeFileDrag {
  const ArrangeFileDrag({required this.fileId, required this.fromIndex});

  final int fileId;
  final int fromIndex;
}

/// Final index of a file dropped onto the gap *before* [insertIndex].
int arrangeChipDest({required int from, required int insertIndex}) {
  var dest = insertIndex;
  if (from < insertIndex) dest -= 1;
  return dest;
}

/// Final index for a drop on a wrap's trailing gap, ending at [wrapEnd].
int arrangeTrailingDest({required int wrapEnd}) => wrapEnd - 1;

/// Preview cards in one or two wraps, with a full-width cut after the layout's
/// on-screen slots. Dragging a card onto a gap calls [onMove].
class ArrangeFileChipGrid extends StatelessWidget {
  const ArrangeFileChipGrid({
    super.key,
    required this.files,
    required this.shownCount,
    required this.onScreenLabel,
    required this.offScreenLabel,
    required this.displayNameFor,
    required this.topicFor,
    required this.accentFor,
    required this.loadAgentText,
    required this.strings,
    required this.onMove,
  });

  static const cardWidth = 200.0;
  static const cardHeight = 232.0;
  static const _previewScale = 0.62;

  final List<AppFile> files;
  final int shownCount;
  final String onScreenLabel;
  final String offScreenLabel;
  final String Function(AppFile file) displayNameFor;
  final Topic Function(AppFile file) topicFor;
  final Color Function(AppFile file) accentFor;
  final Future<String> Function(int fileId) loadAgentText;
  final AppStrings strings;
  final void Function(int from, int to) onMove;

  bool get _showCut => shownCount > 0 && shownCount < files.length;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();

    if (!_showCut) {
      return _wrap(start: 0, end: files.length);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _sectionLabel(onScreenLabel),
        _wrap(start: 0, end: shownCount),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SizedBox(
            width: double.infinity,
            child: Divider(
              height: 1,
              color: AppColors.textHint.withValues(alpha: 0.35),
            ),
          ),
        ),
        _sectionLabel(offScreenLabel),
        _wrap(start: shownCount, end: files.length),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypography.metaStyle.copyWith(
          color: AppColors.textHint,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _wrap({required int start, required int end}) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = start; i < end; i++)
          KeyedSubtree(
            key: ValueKey(files[i].id),
            child: _cardSlot(files[i], i),
          ),
        _trailingGap(end),
      ],
    );
  }

  Widget _cardSlot(AppFile file, int index) {
    return FilePreviewLoader(
      fileId: file.id,
      loadAgentText: loadAgentText,
      builder: (context, agentText) {
        Widget preview() => _scaledPreview(agentText);
        return DragTarget<ArrangeFileDrag>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (details) {
            final dest = arrangeChipDest(
              from: details.data.fromIndex,
              insertIndex: index,
            );
            onMove(details.data.fromIndex, dest);
          },
          builder: (context, candidate, rejected) {
            final hot = candidate.isNotEmpty;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _insertBar(visible: hot),
                Draggable<ArrangeFileDrag>(
                  data: ArrangeFileDrag(fileId: file.id, fromIndex: index),
                  feedback: Material(
                    color: Colors.transparent,
                    child: Transform.scale(
                      scale: 0.96,
                      child: _card(
                        file,
                        preview: preview(),
                        emphasized: index == 0,
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.28,
                    child: _card(
                      file,
                      preview: preview(),
                      emphasized: index == 0,
                    ),
                  ),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: _card(
                      file,
                      preview: preview(),
                      emphasized: index == 0,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _trailingGap(int wrapEnd) {
    return DragTarget<ArrangeFileDrag>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final dest = arrangeTrailingDest(wrapEnd: wrapEnd);
        if (dest < 0) return;
        onMove(details.data.fromIndex, dest);
      },
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return SizedBox(
          width: hot ? 18 : 12,
          height: cardHeight,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _insertBar(visible: hot),
          ),
        );
      },
    );
  }

  Widget _insertBar({required bool visible}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: visible ? 3 : 0,
      height: visible ? cardHeight * 0.72 : 0,
      margin: EdgeInsetsDirectional.only(end: visible ? 6 : 0),
      decoration: BoxDecoration(
        color: AppColors.glassTint.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _scaledPreview(String? agentText) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / _previewScale;
        final height = constraints.maxHeight / _previewScale;
        return ClipRect(
          child: OverflowBox(
            alignment: AlignmentDirectional.topStart,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: Transform.scale(
              scale: _previewScale,
              alignment: AlignmentDirectional.topStart,
              child: SizedBox(
                width: width,
                height: height,
                child: FilePreview(
                  agentText: agentText,
                  mode: FilePreviewMode.clipped,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _card(
    AppFile file, {
    required Widget preview,
    required bool emphasized,
  }) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: OverlayFilePreviewCard(
        file: file,
        topic: topicFor(file),
        fileName: displayNameFor(file),
        accent: accentFor(file),
        preview: preview,
        strings: strings,
        padding: const EdgeInsets.all(12),
        titleFontSize: 13,
        emphasized: emphasized,
      ),
    );
  }
}
