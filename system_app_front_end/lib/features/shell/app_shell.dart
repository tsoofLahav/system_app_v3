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
        child: Scaffold(
          body: Row(
            children: [
              AppSidebar(state: state),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: state.isViewMode
                          ? TaskViewPane(state: state)
                          : TopicView(state: state),
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
    );
  }
}

class _GoHomeIntent extends Intent {
  const _GoHomeIntent();
}
