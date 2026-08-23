import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../files/data/app_file.dart';
import '../../files/data/topic.dart';
import './topic_appearance.dart';
import './topic_header.dart';
import './phone_topic_view.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../layout/file_layout_board.dart';
import '../layout/file_layouts.dart';
import '../shell/app_bottom_bar.dart';
import '../widgets/main_pane_loader.dart';
import '../create_topic/add_file_dialog.dart';

/// The topic canvas. Desktop draws the files the layout has room for.
/// Phone draws every file in order, one at a time ([PhoneTopicView]).
/// On Home, visiting files from other topics sit in that same order.
///
/// Listens to [AppState] itself and only rebuilds when the open topic / files /
/// layout / language change — not on every `notifyListeners` (AI actions,
/// automations, embed payload patches). A parent [ListenableBuilder] around
/// this widget remounts Super Editor mid-keystroke and desyncs
/// [HardwareKeyboard].
class TopicView extends StatefulWidget {
  const TopicView({super.key, required this.state});

  final AppState state;

  @override
  State<TopicView> createState() => _TopicViewState();
}

class _TopicViewState extends State<TopicView> {
  AppState get state => widget.state;
  late Object _signature;

  @override
  void initState() {
    super.initState();
    _signature = _canvasSignature(state);
    state.addListener(_onState);
  }

  @override
  void didUpdateWidget(covariant TopicView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_onState);
      _signature = _canvasSignature(state);
      state.addListener(_onState);
    }
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    final next = _canvasSignature(state);
    if (next == _signature || !mounted) return;
    setState(() => _signature = next);
  }

  /// What the canvas actually paints — not embed payloads, AI actions, etc.
  static Object _canvasSignature(AppState s) {
    final topic = s.selectedDetail?.topic ?? s.selectedTopic;
    final files = s.selectedDetail?.files;
    return Object.hash(
      s.loading,
      s.error,
      s.topicDetailStale,
      s.language,
      topic?.id,
      topic?.name,
      topic?.icon,
      topic?.color,
      topic?.fileLayout,
      topic?.isMain,
      Object.hashAll([
        for (final file in files ?? const <AppFile>[])
          Object.hash(file.id, file.name, file.orderIndex),
      ]),
      Object.hashAll([
        for (final file in topic == null
            ? const <AppFile>[]
            : s.orderedFilesFor(topic, files ?? const <AppFile>[]))
          Object.hash(file.id, file.name, file.topicId),
      ]),
    );
  }

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

    if (isPhoneLayout) {
      return PhoneTopicView(
        state: state,
        topic: topic,
        files: state.orderedFilesFor(topic, detail!.files),
      );
    }

    final shown = state.shownFilesFor(topic, detail!.files);
    final accent = TopicAppearance.accentFor(topic);

    // The header floats over the files, so the canvas reserves its height at
    // the top and the bottom bar's at the bottom. Files begin right under the
    // header — a topic reads from its first file down, never from the middle.
    final canvasPadding = AppSpacing.canvasPadding.copyWith(
      top: AppSpacing.canvasPadding.top + AppTopicHeaderMetrics.scrollTopInset,
      bottom:
          AppSpacing.canvasPadding.bottom + AppBottomBarMetrics.scrollInset,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            key: PageStorageKey('topic-scroll-${topic.id}'),
            padding: canvasPadding,
            child: shown.isEmpty
                ? _EmptyTopic(state: state)
                : _board(context, topic, shown, canvasPadding),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: TopicHeader(
            topic: topic,
            accent: accent,
            state: state,
            onAddFile: () => _addFile(context, topic),
          ),
        ),
      ],
    );
  }

  Widget _board(
    BuildContext context,
    Topic topic,
    List<AppFile> shown,
    EdgeInsets canvasPadding,
  ) {
    return FileLayoutBoard(
      topic: topic,
      files: shown,
      layoutId: state.layoutFor(topic),
      state: state,
      onDeleteFile: state.deleteFile,
      slotHeight: FileLayouts.primarySlotHeight(
        context,
        canvasPaddingTop: canvasPadding.top,
        canvasPaddingBottom: canvasPadding.bottom,
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

/// A topic with nothing in it yet. The header already carries the `+`, so this
/// says where to look rather than offering a second button.
class _EmptyTopic extends StatelessWidget {
  const _EmptyTopic({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Center(
        child: Text(
          state.strings['topicNoFiles'],
          textAlign: TextAlign.center,
          style: AppTypography.metaStyle,
        ),
      ),
    );
  }
}
