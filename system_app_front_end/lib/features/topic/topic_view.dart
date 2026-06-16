import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/topic.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/file_layouts.dart';
import '../../design_system/glass_surface.dart';
import '../../design_system/note_widgets.dart';
import '../shell/app_bottom_bar.dart';
import '../../shared/widgets/file_layout_board.dart';
import '../../shared/widgets/files_section_divider.dart';
import '../../shared/widgets/pane_reorder_canvas.dart';
import '../../shared/widgets/topic_emoji.dart';
import '../create_topic/add_file_dialog.dart';

class TopicView extends StatelessWidget {
  const TopicView({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.selectedDetail == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.selectedDetail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => state.initialize(),
              child: Text(state.strings['retry']),
            ),
          ],
        ),
      );
    }

    final detail = state.selectedDetail;
    if (detail == null) {
      return Center(child: Text(state.strings['selectTopic']));
    }

    final topic = detail.topic;
    final mainFiles = state.mainFilesFor(topic, detail.files);
    final secondaryFiles = state.secondaryFilesFor(topic, detail.files);
    final accent = TopicAppearance.colorFromHex(topic.color);
    final layoutId = state.layoutFor(topic);

    final canvasPadding = AppSpacing.canvasPadding.copyWith(
      top: AppSpacing.canvasPadding.top + AppTopicHeaderMetrics.scrollTopInset,
      bottom: AppSpacing.canvasPadding.bottom + AppBottomBarMetrics.scrollInset,
    );

    return TopicCanvasBackground(
      accent: accent,
      isMain: topic.isMain,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: state.paneDragMode
                ? Padding(
                    padding: canvasPadding,
                    child: mainFiles.isEmpty && secondaryFiles.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                state.strings['noFilesYet'],
                                style: AppTypography.noteBodyStyle,
                              ),
                            ),
                          )
                        : PaneReorderCanvas(
                            topic: topic,
                            mainFiles: mainFiles,
                            secondaryFiles: secondaryFiles,
                            state: state,
                            accent: accent,
                            onDeleteFile: (f) => state.deleteFile(topic, f),
                            onReorderError: (message) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text(message)));
                            },
                          ),
                  )
                : SingleChildScrollView(
                    padding: canvasPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (mainFiles.isEmpty && secondaryFiles.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                state.strings['noFilesYet'],
                                style: AppTypography.noteBodyStyle,
                              ),
                            ),
                          )
                        else ...[
                          if (mainFiles.isNotEmpty)
                            FileLayoutBoard(
                              topic: topic,
                              files: mainFiles,
                              layoutId: layoutId,
                              state: state,
                              accent: accent,
                              onDeleteFile: (f) => state.deleteFile(topic, f),
                            ),
                          if (secondaryFiles.isNotEmpty) ...[
                            FilesSectionDivider(
                              collapsed: !state.moreFilesExpanded,
                              onTap: state.toggleMoreFiles,
                            ),
                            if (state.moreFilesExpanded)
                              FileLayoutBoard(
                                topic: topic,
                                files: secondaryFiles,
                                layoutId: FileLayouts.grid,
                                state: state,
                                accent: accent,
                                onDeleteFile: (f) => state.deleteFile(topic, f),
                              ),
                          ],
                        ],
                      ],
                    ),
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopicHeader(
              topic: topic,
              accent: accent,
              state: state,
              onAddFile: () => _addFile(context, topic, detail.files),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addFile(
    BuildContext context,
    Topic topic,
    List<AppFile> files,
  ) async {
    final result = await showDialog<AddFileResult>(
      context: context,
      builder: (_) => AddFileDialog(
        state: state,
        topic: topic,
        existingTypes: files.map((f) => f.type).toList(growable: false),
      ),
    );
    if (result == null) return;
    await state.addFile(topic: topic, type: result.type, name: result.name);
  }
}

class _TopicHeader extends StatelessWidget {
  const _TopicHeader({
    required this.topic,
    required this.accent,
    required this.state,
    required this.onAddFile,
  });

  final Topic topic;
  final Color accent;
  final AppState state;
  final VoidCallback onAddFile;

  @override
  Widget build(BuildContext context) {
    final isMain = topic.isMain;
    final s = state.strings;
    final veilTint = Color.alphaBlend(
      (isMain ? AppColors.text : accent).withValues(
        alpha: isMain ? 0.02 : 0.08,
      ),
      Colors.white,
    );

    return SizedBox(
      height: AppTopicHeaderMetrics.scrollTopInset,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      veilTint.withValues(alpha: 0.86),
                      veilTint.withValues(alpha: 0.52),
                      veilTint.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.58, 1],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppTopicHeaderMetrics.horizontalMargin,
              AppTopicHeaderMetrics.floatMargin,
              AppTopicHeaderMetrics.horizontalMargin,
              0,
            ),
            child: SizedBox(
              height: AppTopicHeaderMetrics.headerHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!isMain) ...[
                    TopicEmoji(value: topic.icon, size: 16),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      _headerTitle(state, topic),
                      style: AppTypography.noteTitleStyle.copyWith(
                        fontSize: 15,
                        height: 1.2,
                        color: AppColors.text.withValues(alpha: 0.94),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppTopicHeaderMetrics.headerGap),
                  GlassCircleButton(
                    tooltip: s['addFile'],
                    icon: AppIcons.add,
                    onPressed: onAddFile,
                    size: AppTopicHeaderMetrics.addButtonSize,
                    iconSize: 15,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _headerTitle(AppState state, Topic topic) {
    final name = state.topicDisplayName(topic);
    if (!state.paneDragMode) return name;
    return '$name - ${state.strings['reorderMode']}';
  }
}
