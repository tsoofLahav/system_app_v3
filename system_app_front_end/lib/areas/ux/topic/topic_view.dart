import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../files/data/app_file.dart';
import '../../files/data/topic.dart';
import './topic_appearance.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../layout/file_layout_board.dart';
import '../layout/file_layouts.dart';
import '../shell/app_bottom_bar.dart';
import '../widgets/main_pane_loader.dart';
import '../create_topic/add_file_dialog.dart';
import '../../files/editor/document_pane.dart';

/// The topic canvas: the files the topic's layout has room for, and nothing
/// else. Files past the last slot are reached by arranging the topic.
class TopicView extends StatelessWidget {
  const TopicView({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.loading &&
        state.selectedDetail == null &&
        state.selectedTopic == null) {
      return const MainPaneLoader();
    }

    if (state.error != null &&
        state.selectedDetail == null &&
        state.selectedTopic == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => state.initialize(),
              child: Text(state.strings['retry']),
            ),
          ],
        ),
      );
    }

    final detail = state.selectedDetail;
    if (detail == null && !state.topicDetailStale) {
      return Center(child: Text(state.strings['selectTopic']));
    }

    final topic = detail?.topic ?? state.selectedTopic;
    if (topic == null) {
      return Center(child: Text(state.strings['selectTopic']));
    }

    if (state.topicDetailStale) {
      return const MainPaneLoader();
    }

    final shown = state.shownFilesFor(topic, detail!.files);
    final accent = TopicAppearance.accentFor(topic);

    return SingleChildScrollView(
      key: PageStorageKey('topic-scroll-${topic.id}'),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppBottomBarMetrics.scrollInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  state.topicDisplayName(topic),
                  style: AppTypography.pageTitleStyle,
                ),
              ),
              TextButton.icon(
                onPressed: () => _addFile(context, topic),
                icon: const AppIcon(AppIcons.addFile, size: 18),
                label: Text(state.strings['addFile']),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (shown.isEmpty)
            Center(
              child: OutlinedButton.icon(
                onPressed: () => _addFile(context, topic),
                icon: const AppIcon(AppIcons.addFile, size: 18),
                label: Text(state.strings['addFile']),
              ),
            )
          else
            _board(context, topic, shown, accent),
        ],
      ),
    );
  }

  Widget _board(
    BuildContext context,
    Topic topic,
    List<AppFile> shown,
    Color accent,
  ) {
    // Two files cannot sit side by side on a phone, so there the shape
    // collapses to one file per row. Which files appear is still the layout's
    // answer, so a file hidden on desktop stays hidden here.
    if (isPhoneLayout) {
      final height = FileLayouts.phoneSlotHeight(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final file in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: AppLayoutSpacing.gap),
              child: SizedBox(
                height: height,
                child: DocumentPane(
                  key: ValueKey(file.id),
                  topic: topic,
                  file: file,
                  state: state,
                  accent: accent,
                  onDelete: () => state.deleteFile(file),
                ),
              ),
            ),
        ],
      );
    }

    return FileLayoutBoard(
      topic: topic,
      files: shown,
      layoutId: state.layoutFor(topic),
      state: state,
      accent: accent,
      onDeleteFile: state.deleteFile,
      slotHeight: FileLayouts.primarySlotHeight(
        context,
        canvasPaddingTop: AppSpacing.lg + AppTopicHeaderMetrics.headerHeight,
        canvasPaddingBottom: AppBottomBarMetrics.scrollInset,
      ),
    );
  }

  Future<void> _addFile(BuildContext context, Topic topic) async {
    final result = await showAddFileDialog(
      context: context,
      state: state,
      topic: topic,
    );
    if (result == null) return;
    await state.addFile(topic: topic, name: result.name);
  }
}
