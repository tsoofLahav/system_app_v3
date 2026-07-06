import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/ai_proposal.dart';
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
import '../../shared/widgets/main_pane_loader.dart';
import '../../shared/widgets/file_layout_board.dart';
import '../../shared/widgets/files_section_divider.dart';
import '../../shared/widgets/pane_reorder_canvas.dart';
import '../../shared/widgets/topic_emoji.dart';
import '../create_topic/add_file_dialog.dart';
import '../bring_file/bring_file_picker_dialog.dart';
import 'process_update_review_dialog.dart';

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
    final stale = state.topicDetailStale;

    if (detail == null && !stale) {
      return Center(child: Text(state.strings['selectTopic']));
    }

    final topic = stale
        ? (state.selectedTopic ?? detail?.topic)
        : (detail?.topic ?? state.selectedTopic);
    if (topic == null) {
      return Center(child: Text(state.strings['selectTopic']));
    }

    final filesTopic = stale ? topic : detail!.topic;
    final mainFiles = stale
        ? const <AppFile>[]
        : state.mainFilesFor(filesTopic, detail!.files);
    final secondaryFiles = stale
        ? const <AppFile>[]
        : state.secondaryFilesFor(filesTopic, detail!.files);
    final accent = TopicAppearance.colorFromHex(topic.color);
    final layoutId = state.layoutFor(topic);

    final canvasPadding = AppSpacing.canvasPadding.copyWith(
      top: AppSpacing.canvasPadding.top + AppTopicHeaderMetrics.scrollTopInset,
      bottom: AppSpacing.canvasPadding.bottom + AppBottomBarMetrics.scrollInset,
    );

    final broughtFile =
        !stale && topic.isMain && !state.paneDragMode ? state.broughtFile : null;
    final hasPrimaryContent = mainFiles.isNotEmpty || broughtFile != null;

    Widget filesContent;
    if (stale) {
      filesContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(
            color: accent.withValues(alpha: 0.7),
          ),
        ),
      );
    } else if (state.paneDragMode) {
      filesContent = mainFiles.isEmpty && secondaryFiles.isEmpty
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
            );
    } else {
      filesContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hasPrimaryContent && secondaryFiles.isEmpty)
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
            if (state.pendingAiProposals.isNotEmpty) ...[
              _AiProposalPanel(state: state),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (hasPrimaryContent)
              FileLayoutBoard(
                topic: topic,
                files: mainFiles,
                layoutId: layoutId,
                state: state,
                accent: accent,
                broughtFile: broughtFile,
                onDeleteFile: (f) => state.deleteFile(topic, f),
                slotHeight: FileLayouts.primarySlotHeight(
                  context,
                  canvasPaddingTop: canvasPadding.top,
                  canvasPaddingBottom: canvasPadding.bottom,
                  reservedAbove: state.pendingAiProposals.isNotEmpty ? 96 : 0,
                  reservedBelow: secondaryFiles.isNotEmpty
                      ? FileLayouts.secondarySectionReserve
                      : 0,
                ),
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
      );
    }

    return TopicCanvasBackground(
      accent: accent,
      isMain: topic.isMain,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: state.paneDragMode && !stale
                ? Padding(padding: canvasPadding, child: filesContent)
                : SingleChildScrollView(
                    key: PageStorageKey('topic-scroll-${topic.id}'),
                    padding: canvasPadding,
                    child: filesContent,
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
              addEnabled: !stale && detail != null,
              bringFileEnabled:
                  !stale && detail != null && topic.isMain && !state.paneDragMode,
              onAddFile: detail == null
                  ? () {}
                  : () => _addFile(context, topic, detail.files),
              onBringFile: detail == null
                  ? () {}
                  : () => _bringFile(context, state),
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

  Future<void> _bringFile(BuildContext context, AppState state) async {
    final entry = await showBringFilePickerDialog(context, state);
    if (entry == null) return;
    await state.bringFile(entry.topic, entry.file);
  }
}

class _AiProposalPanel extends StatelessWidget {
  const _AiProposalPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    return GlassSurface(
      borderRadius: BorderRadius.circular(16),
      tintOpacity: 0.42,
      tintColor: AppColors.aiCyan,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s['pendingSuggestions'], style: AppTypography.noteTitleStyle),
          const SizedBox(height: 8),
          for (final proposal in state.pendingAiProposals)
            _AiProposalRow(state: state, proposal: proposal),
        ],
      ),
    );
  }
}

class _AiProposalRow extends StatelessWidget {
  const _AiProposalRow({required this.state, required this.proposal});

  final AppState state;
  final AiProposal proposal;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;

    if (proposal.proposalType == 'process_refresh_skipped') {
      final message =
          proposal.payload['message']?.toString() ?? s['processRefreshSkipped'];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(message, style: AppTypography.noteBodyStyle)),
            TextButton(
              onPressed: () => state.rejectAiProposal(proposal),
              child: Text(s['dismiss']),
            ),
          ],
        ),
      );
    }

    if (proposal.proposalType == 'process_smart_update') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                s['processUpdateReview'],
                style: AppTypography.noteBodyStyle,
              ),
            ),
            TextButton(
              onPressed: () => state.rejectAiProposal(proposal),
              child: Text(s['reject']),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => showProcessUpdateReviewDialog(
                context: context,
                state: state,
                proposal: proposal,
              ),
              child: Text(s['processUpdateReview']),
            ),
          ],
        ),
      );
    }

    final source = proposal.payload['source_file_name']?.toString();
    final target = proposal.payload['target_file_name']?.toString();
    final suggestion =
        (proposal.payload['content'] as Map?)?['text']?.toString() ??
        (proposal.payload['content'] as Map?)?['suggestion']?.toString() ??
        proposal.proposalType;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (source != null || target != null)
            Text(
              [source, target].whereType<String>().join(' → '),
              style: AppTypography.metaStyle,
            ),
          Text(
            suggestion,
            style: AppTypography.noteBodyStyle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => state.rejectAiProposal(proposal),
                child: Text(s['reject']),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => state.approveAiProposal(proposal),
                child: Text(s['approve']),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopicHeader extends StatelessWidget {
  const _TopicHeader({
    required this.topic,
    required this.accent,
    required this.state,
    required this.onAddFile,
    required this.onBringFile,
    this.addEnabled = true,
    this.bringFileEnabled = false,
  });

  final Topic topic;
  final Color accent;
  final AppState state;
  final VoidCallback onAddFile;
  final VoidCallback onBringFile;
  final bool addEnabled;
  final bool bringFileEnabled;

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
                  if (isMain) ...[
                    Opacity(
                      opacity: bringFileEnabled ? 1 : 0.35,
                      child: GlassCircleButton(
                        tooltip: s['bringFile'],
                        icon: AppIcons.bringFile,
                        onPressed: bringFileEnabled ? onBringFile : () {},
                        size: AppTopicHeaderMetrics.addButtonSize,
                        iconSize: 15,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Opacity(
                    opacity: addEnabled ? 1 : 0.35,
                    child: GlassCircleButton(
                      tooltip: s['addFile'],
                      icon: AppIcons.add,
                      onPressed: addEnabled ? onAddFile : () {},
                      size: AppTopicHeaderMetrics.addButtonSize,
                      iconSize: 15,
                    ),
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
