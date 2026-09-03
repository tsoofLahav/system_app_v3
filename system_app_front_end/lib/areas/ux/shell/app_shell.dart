import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../automations/leftover_clear_dialog.dart';
import '../shortcuts/app_shortcuts.dart';
import './desktop_app_shell.dart';
import './dismiss_focus_on_outside_tap.dart';
import './phone_app_shell.dart';

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
      child: DismissFocusOnOutsideTap(
        child: _AutomationNoticeHost(
          state: state,
          child: _SectionWindowHost(state: state, child: body),
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

class _SectionWindowHost extends StatefulWidget {
  const _SectionWindowHost({required this.state, required this.child});

  final AppState state;
  final Widget child;

  @override
  State<_SectionWindowHost> createState() => _SectionWindowHostState();
}

class _SectionWindowHostState extends State<_SectionWindowHost> {
  var _showing = false;
  final _seen = <int>{};

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  @override
  void didUpdateWidget(covariant _SectionWindowHost oldWidget) {
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
    _maybeShow();
  }

  Future<void> _maybeShow() async {
    if (!mounted || _showing || !widget.state.appReady) return;
    final currentIds = {
      for (final window in widget.state.pendingClearWindows) window.id,
    };
    _seen.removeWhere((id) => !currentIds.contains(id));
    final pending = [
      for (final window in widget.state.pendingClearWindows)
        if (!_seen.contains(window.id)) window,
    ];
    if (pending.isEmpty) return;
    _showing = true;
    try {
      for (final window in pending) {
        if (!mounted) return;
        _seen.add(window.id);
        await showLeftoverClearDialog(
          context: context,
          state: widget.state,
          window: window,
        );
      }
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
