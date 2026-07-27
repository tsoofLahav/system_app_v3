import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_state.dart';
import './shortcut_catalog.dart';
import './shortcut_dispatcher.dart';

class AppShortcutIntent extends Intent {
  const AppShortcutIntent(this.actionId);

  final String actionId;
}

class AppShortcutsScope extends StatefulWidget {
  const AppShortcutsScope({
    super.key,
    required this.state,
    required this.child,
  });

  final AppState state;
  final Widget child;

  @override
  State<AppShortcutsScope> createState() => _AppShortcutsScopeState();
}

class _AppShortcutsScopeState extends State<AppShortcutsScope> {
  final _shellFocusNode = FocusNode(debugLabel: 'appShortcuts');

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureShellFocus());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _shellFocusNode.dispose();
    super.dispose();
  }

  void _ensureShellFocus() {
    if (!_shellFocusNode.hasFocus && _shellFocusNode.canRequestFocus) {
      _shellFocusNode.requestFocus();
    }
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
          const AppShortcutIntent(ShortcutActionIds.addTopic),
    };

    return Focus(
      focusNode: _shellFocusNode,
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: {
            AppShortcutIntent: CallbackAction<AppShortcutIntent>(
              onInvoke: (intent) {
                dispatchShortcutAction(context, widget.state, intent.actionId);
                return null;
              },
            ),
          },
          child: widget.child,
        ),
      ),
    );
  }
}

String? shortcutTooltipSuffix(AppState state, String actionId) => null;
