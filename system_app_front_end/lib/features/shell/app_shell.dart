import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/platform/app_form_factor.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import 'desktop_app_shell.dart';
import 'phone_app_shell.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final body = isPhoneLayout
        ? PhoneAppShell(state: state)
        : DesktopAppShell(state: state);

    return AppShortcutsScope(
      state: state,
      child: _AutomationNoticeHost(state: state, child: body),
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
