import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../sidebar/app_sidebar.dart';
import '../task_view/task_view_pane.dart';
import '../topic/topic_view.dart';
import '../../design_system/glass_surface.dart';
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
            body: Row(
              children: [
                AppSidebar(state: state),
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: state.isViewMode && state.viewPaneReady
                              ? TaskViewPane(
                                  key: ValueKey('view-${state.selectedViewType}'),
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
                        Positioned(
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
                        child: const ChromeFloorShadow(),
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
              ],
            ),
          ),
        ),
      ),
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
