import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/glass_surface.dart';
import '../archive/archive_topic_view.dart';
import '../sidebar/app_sidebar.dart';
import '../task_view/task_view_pane.dart';
import '../topic/topic_view.dart';
import '../../shared/widgets/main_pane_loader.dart';
import 'app_bottom_bar.dart';

class DesktopAppShell extends StatefulWidget {
  const DesktopAppShell({super.key, required this.state});

  final AppState state;

  @override
  State<DesktopAppShell> createState() => _DesktopAppShellState();
}

class _DesktopAppShellState extends State<DesktopAppShell> {
  var _sidebarWidth = AppSidebarMetrics.defaultWidth;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final contentInset = AppSidebarMetrics.contentInset(_sidebarWidth);

    return Scaffold(
      backgroundColor: AppColors.canvasNeutralBottom,
      body: Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(child: AppShellCanvas()),
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
                          child: state.isArchiveMode
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
                              : TopicView(
                                  key: ValueKey(
                                    'topic-${state.selectedDetail?.topic.id ?? 'none'}',
                                  ),
                                  state: state,
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
  }
}

/// Full-window canvas shared by desktop and phone shells.
class AppShellCanvas extends StatelessWidget {
  const AppShellCanvas({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: const [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.neutralCanvasGradient,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ChromeFloorShadow(),
        ),
      ],
    );
  }
}
