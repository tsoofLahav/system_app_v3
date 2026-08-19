import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';
import '../archive/archive_topic_view.dart';
import '../bring_file/bring_file_picker_dialog.dart';
import '../create_topic/add_file_dialog.dart';
import '../sidebar/app_sidebar.dart';
import '../../objects/diagram/object_diagram_pane.dart';
import '../../objects/views/task_view_pane.dart';
import '../topic/topic_appearance.dart';
import '../topic/topic_view.dart';
import '../widgets/main_pane_loader.dart';
import '../../automations/automation_dialog.dart';
import '../../files/editor/document_editor_controller.dart';
import '../../files/editor/document_insert_bar.dart';
import '../../production_agent/ai_tool_bar.dart';
import './chrome_anchors.dart';
import './desktop_app_shell.dart';
import './app_bottom_bar.dart';
import './preferences_dialog.dart';

class PhoneAppShell extends StatefulWidget {
  const PhoneAppShell({super.key, required this.state});

  final AppState state;

  @override
  State<PhoneAppShell> createState() => _PhoneAppShellState();
}

class _PhoneAppShellState extends State<PhoneAppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final Widget _topicView = TopicView(
    key: const ValueKey('topic-canvas'),
    state: widget.state,
  );

  AppState get state => widget.state;

  String _title() {
    final s = state.strings;
    if (state.isDiagramMode) return s['diagram'];
    if (state.isArchiveMode) {
      final topic = state.selectedArchiveTopic;
      if (topic == null) return s['archive'];
      if (topic.isMain) return s['main'];
      return state.topicDisplayName(topic);
    }
    if (state.isViewMode && state.selectedViewType != null) {
      return state.viewLabel(state.selectedViewType!);
    }
    final topic = state.selectedTopic ?? state.selectedDetail?.topic;
    if (topic == null) return 'system_app';
    if (topic.isMain) return s['main'];
    return topic.name;
  }

  bool get _showAddFile =>
      !state.isViewMode &&
      !state.isDiagramMode &&
      !state.isArchiveMode &&
      state.selectedDetail != null &&
      !state.topicDetailStale;

  bool get _showBringFile =>
      _showAddFile && (state.selectedTopic?.isMain ?? false);

  Future<void> _addFile(BuildContext context) async {
    final topic = state.selectedTopic;
    if (topic == null) return;
    final result = await showAddFileDialog(
      context: context,
      state: state,
      topic: topic,
    );
    if (result == null) return;
    await state.addFile(topic: topic, name: result.name);
  }

  Future<void> _bringFile(BuildContext context) async {
    await showBringFilePicker(context: context, state: state);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      child: _topicView,
      builder: (context, topicView) {
        final diagramMode = state.isDiagramMode;
        final archiveMode = state.isArchiveMode;
        final useChromeBar = diagramMode || archiveMode;
        final bottomInset = useChromeBar
            ? AppBottomBarMetrics.scrollInset
            : MediaQuery.sizeOf(context).height * 0.1;
        final canvasTopic = archiveMode
            ? state.selectedArchiveTopic
            : (state.selectedDetail?.topic ?? state.selectedTopic);

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.canvasNeutralBottom,
          drawer: Drawer(
            width: MediaQuery.sizeOf(context).width * 0.86,
            backgroundColor: Colors.transparent,
            child: SafeArea(
              child: AppSidebar(
                state: state,
                isPhone: true,
              ),
            ),
          ),
          appBar: AppBar(
            backgroundColor: AppColors.canvasNeutralBottom.withValues(alpha: 0.92),
            elevation: 0,
            scrolledUnderElevation: 0.5,
            title: Text(
              _title(),
              style: AppTypography.noteTitleStyle.copyWith(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
            leading: IconButton(
              icon: const AppIcon(AppIcons.menu, size: 22),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            actions: [
              if (_showBringFile)
                IconButton(
                  tooltip: state.strings['bringFile'],
                  icon: const AppIcon(AppIcons.bringFile, size: 22),
                  onPressed: () => _bringFile(context),
                ),
              if (_showAddFile)
                IconButton(
                  tooltip: state.strings['addFile'],
                  icon: const AppIcon(AppIcons.add, size: 22),
                  onPressed: () => _addFile(context),
                ),
            ],
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: AppShellCanvas(
                  topicAccent: canvasTopic == null
                      ? null
                      : TopicAppearance.accentFor(canvasTopic),
                  isMainTopic: canvasTopic?.isMain ?? true,
                ),
              ),
              Positioned.fill(
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: !state.appReady
                        ? const MainPaneLoader()
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: state.isDiagramMode
                                ? ObjectDiagramPane(
                                    key: const ValueKey('diagram'),
                                    state: state,
                                  )
                                : state.isArchiveMode
                                ? ArchiveTopicView(
                                    key: ValueKey(
                                      'archive-${state.selectedArchiveTopic?.id}',
                                    ),
                                    state: state,
                                  )
                                : state.isViewMode && state.viewPaneReady
                                ? TaskViewPane(
                                    key: ValueKey(
                                      'view-${state.selectedViewType}',
                                    ),
                                    state: state,
                                  )
                                : topicView!,
                          ),
                  ),
                ),
              ),
              if (state.isViewMode && state.loading)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              if (!useChromeBar)
                ListenableBuilder(
                  listenable: DocumentEditorRegistry.notifier,
                  builder: (context, _) {
                    if (DocumentEditorRegistry.active == null) {
                      return const SizedBox.shrink();
                    }
                    return Positioned(
                      left: 0,
                      right: 0,
                      bottom: bottomInset,
                      child: DocumentInsertBar(state: state),
                    );
                  },
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: useChromeBar
                    ? AppBottomBar(state: state)
                    : SizedBox(
                        height: MediaQuery.sizeOf(context).height,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: _PhoneBottomToolsSheet(state: state),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PhoneBottomToolsSheet extends StatelessWidget {
  const _PhoneBottomToolsSheet({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final canAi = state.canUseAiTools;
    final maxSize = canAi ? 0.38 : 0.28;

    return DraggableScrollableSheet(
      initialChildSize: 0.09,
      minChildSize: 0.09,
      maxChildSize: maxSize,
      snap: true,
      snapSizes: [0.09, maxSize],
      builder: (context, scrollController) {
        return SafeArea(
          top: false,
          child: GlassSurface(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            tintOpacity: 0.88,
            elevation: 4,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.text.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                ListTile(
                  key: ChromeAnchors.preferencesButton,
                  leading: const AppIcon(AppIcons.preferences, size: 22),
                  title: Text(s['preferences']),
                  onTap: () =>
                      showPreferencesDialog(context: context, state: state),
                ),
                ListTile(
                  leading: const AppIcon(AppIcons.automations, size: 22),
                  title: Text(s['automations']),
                  onTap: () =>
                      showAutomationDialog(context: context, state: state),
                ),
                if (canAi) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('AI', style: AppTypography.metaStyle),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: AiToolBar(state: state),
                  ),
                  if (state.aiRunning)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.aiCyan.withValues(alpha: 0.85),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(s['aiRunning'], style: AppTypography.metaStyle),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
