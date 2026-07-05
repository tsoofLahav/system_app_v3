import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../archive/archive_topic_view.dart';
import '../sidebar/app_sidebar.dart';
import '../task_view/task_view_pane.dart';
import '../topic/topic_view.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/glass_surface.dart';
import '../../shared/widgets/main_pane_loader.dart';
import 'app_bottom_bar.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyH):
            const _GoHomeIntent(),
      },
      child: Actions(
        actions: {
          _GoHomeIntent: CallbackAction<_GoHomeIntent>(
            onInvoke: (_) {
              state.goHome();
              return null;
            },
          ),
        },
        child: _AutomationNoticeHost(
          state: state,
          child: Scaffold(
            backgroundColor: AppColors.canvasNeutralBottom,
            body: _AppShellBody(state: state),
          ),
        ),
      ),
    );
  }
}

class _AppShellBody extends StatefulWidget {
  const _AppShellBody({required this.state});

  final AppState state;

  @override
  State<_AppShellBody> createState() => _AppShellBodyState();
}

class _AppShellBodyState extends State<_AppShellBody> {
  var _sidebarWidth = AppSidebarMetrics.defaultWidth;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final contentInset = AppSidebarMetrics.contentInset(_sidebarWidth);

    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(child: _AppCanvas()),
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
    );
  }
}

class _AutomationNoticeHost extends StatefulWidget {
  const _AutomationNoticeHost({required this.state, required this.child});

  final AppState state;
  final Widget child;

  @override
  State<_AutomationNoticeHost> createState() => _AutomationNoticeHostState();
}

class _AutomationNoticeHostState extends State<_AutomationNoticeHost> {
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(covariant _AutomationNoticeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_onStateChanged);
      widget.state.addListener(_onStateChanged);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    final notice = widget.state.takeAutomationNotice();
    if (notice == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(notice)),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _GoHomeIntent extends Intent {
  const _GoHomeIntent();
}

/// Single full-window canvas: gradient + ambient floor shadow stay in sync
/// everywhere, including behind the floating sidebar.
class _AppCanvas extends StatelessWidget {
  const _AppCanvas();

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
