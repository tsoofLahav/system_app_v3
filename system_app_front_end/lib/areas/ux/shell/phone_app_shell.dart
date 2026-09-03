import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_state.dart';
import '../../ui/app_colors.dart';
import '../archive/archive_topic_view.dart';
import '../bring_file/bring_file_picker_dialog.dart';
import '../create_topic/add_file_dialog.dart';
import '../sidebar/app_sidebar.dart';
import '../../objects/diagram/object_diagram_pane.dart';
import '../../objects/views/task_view_pane.dart';
import '../topic/topic_appearance.dart';
import '../topic/topic_view.dart';
import '../topic_types/type_template_edit_bar.dart';
import '../widgets/main_pane_loader.dart';
import './app_bottom_bar.dart';
import './phone_edge_ombre.dart';
import './phone_top_bar.dart';
import '../../files/editor/document_editor_controller.dart';
import '../../files/rich_text/block_text_focus.dart';

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
      return s.archiveTopicHeadline(state.topicDisplayName(topic));
    }
    if (state.isViewMode && state.selectedViewType != null) {
      return state.viewLabel(state.selectedViewType!);
    }
    final topic = state.selectedTopic ?? state.selectedDetail?.topic;
    if (topic == null) return 'system_app';
    if (topic.isMain) return s['main'];
    return state.topicHeadline(topic);
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
        final archiveMode = state.isArchiveMode;
        final canvasTopic = archiveMode
            ? state.selectedArchiveTopic
            : (state.selectedDetail?.topic ?? state.selectedTopic);
        final accent = canvasTopic == null
            ? null
            : TopicAppearance.accentFor(canvasTopic);
        final isMain = canvasTopic?.isMain ?? true;
        final edge = AppColors.phoneEdgeColor(
          topicAccent: accent,
          isMainTopic: isMain,
          neutral: state.isViewMode || state.isDiagramMode,
        );
        final padding = MediaQuery.paddingOf(context);
        final topFadeStart = padding.top + AppBottomBarMetrics.phoneBarHeight;
        final bottomFadeStart =
            padding.bottom + AppBottomBarMetrics.phoneBarHeight;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor: AppColors.phoneCanvas,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: AppColors.phoneCanvas,
            resizeToAvoidBottomInset: true,
            drawer: Drawer(
              width:
                  (MediaQuery.sizeOf(context).width *
                          AppSidebarMetrics.phoneWidthFraction)
                      .clamp(200.0, AppSidebarMetrics.phoneMaxWidth),
              backgroundColor: Colors.transparent,
              child: AppSidebar(state: state, isPhone: true),
            ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
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
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: PhoneEdgeOmbre(atTop: true, edge: edge),
                ),
                Positioned(
                  top: topFadeStart,
                  left: 0,
                  right: 0,
                  height: AppBottomBarMetrics.phoneOmbreFade,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) {
                      if (BlockTextFocusRegistry.isInMenuSession) return;
                      DocumentEditorRegistry.dismissLiveMarkOnOutsideTap();
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: PhoneEdgeOmbre(atTop: false, edge: edge),
                ),
                Positioned(
                  bottom: bottomFadeStart,
                  left: 0,
                  right: 0,
                  height: AppBottomBarMetrics.phoneOmbreFade,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) {
                      if (BlockTextFocusRegistry.isInMenuSession) return;
                      DocumentEditorRegistry.dismissLiveMarkOnOutsideTap();
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                  ),
                ),
                Positioned(
                  top: padding.top + AppBottomBarMetrics.phoneFloatMargin,
                  left: 0,
                  right: 0,
                  child: PhoneTopBar(
                    state: state,
                    title: _title(),
                    onOpenMenu: () =>
                        _scaffoldKey.currentState?.openDrawer(),
                    showAddFile: _showAddFile,
                    showBringFile: _showBringFile,
                    onAddFile: () => _addFile(context),
                    onBringFile: () => _bringFile(context),
                  ),
                ),
                if (state.isEditingTypeTemplate)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom:
                        padding.bottom + AppBottomBarMetrics.phoneBarHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [TypeTemplateEditBar(state: state)],
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: padding.bottom,
                  child: PhoneBottomBar(state: state),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
