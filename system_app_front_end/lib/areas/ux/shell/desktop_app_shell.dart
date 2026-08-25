import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/app_colors.dart';
import '../../ui/glass_surface.dart';
import '../archive/archive_topic_view.dart';
import '../sidebar/app_sidebar.dart';
import '../../objects/diagram/object_diagram_pane.dart';
import '../../objects/views/task_view_pane.dart';
import '../topic/topic_appearance.dart';
import '../topic/topic_view.dart';
import '../widgets/main_pane_loader.dart';
import './app_bottom_bar.dart';

class DesktopAppShell extends StatefulWidget {
  const DesktopAppShell({super.key, required this.state});

  final AppState state;

  @override
  State<DesktopAppShell> createState() => _DesktopAppShellState();
}

class _DesktopAppShellState extends State<DesktopAppShell> {
  var _sidebarWidth = AppSidebarMetrics.defaultWidth;
  late final Widget _topicView = TopicView(
    key: const ValueKey('topic-canvas'),
    state: widget.state,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      // Same [TopicView] instance across AppState notifies so Super Editor is
      // not rebuilt mid-keystroke (HardwareKeyboard "already pressed").
      child: _topicView,
      builder: (context, topicView) {
        final state = widget.state;
        final contentInset = AppSidebarMetrics.contentInset(_sidebarWidth);
        final topic = state.isArchiveMode
            ? state.selectedArchiveTopic
            : (state.selectedDetail?.topic ?? state.selectedTopic);
        final neutralCanvas = state.isViewMode || state.isDiagramMode;
        final accent = (topic == null || neutralCanvas)
            ? null
            : TopicAppearance.accentFor(topic);
        final isMain = neutralCanvas || (topic?.isMain ?? true);

        return Scaffold(
          backgroundColor: AppColors.canvasNeutralBottom,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: AppShellCanvas(topicAccent: accent, isMainTopic: isMain),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(start: contentInset),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: !state.appReady
                            ? const MainPaneLoader()
                            : AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                switchInCurve: Curves.easeOut,
                                switchOutCurve: Curves.easeIn,
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
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AppBottomBar(state: state),
                      ),
                    ],
                  ),
                ),
              ),
              PositionedDirectional(
                start: AppSidebarMetrics.outerStart,
                top: AppSidebarMetrics.outerVertical,
                bottom: AppSidebarMetrics.outerVertical,
                child: AppSidebar(
                  state: state,
                  width: _sidebarWidth,
                  onWidthChanged: (width) {
                    if (_sidebarWidth == width) return;
                    setState(() => _sidebarWidth = width);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Full-window canvas shared by desktop and phone shells.
///
/// The topic wash is painted here, edge to edge, so it continues behind the
/// sidebar. Sidebar glass and the bottom bar sit above it in the shell stack.
class AppShellCanvas extends StatelessWidget {
  const AppShellCanvas({
    super.key,
    this.topicAccent,
    this.isMainTopic = true,
  });

  final Color? topicAccent;
  final bool isMainTopic;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.neutralCanvasGradient,
          ),
        ),
        if (topicAccent != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 220,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.topicTopVeil(
                    accent: topicAccent!,
                    isMainTopic: isMainTopic,
                  ),
                ),
              ),
            ),
          ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ChromeFloorShadow(),
        ),
      ],
    );
  }
}
