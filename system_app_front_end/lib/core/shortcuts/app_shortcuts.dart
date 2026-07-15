import 'package:flutter/material.dart';

import '../../features/blocks/block_text_focus.dart';
import '../app_state.dart';
import 'shortcut_catalog.dart';
import 'shortcut_dispatcher.dart';

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
  late final Listenable _shortcutListenable;

  @override
  void initState() {
    super.initState();
    _shortcutListenable = Listenable.merge([
      widget.state.shortcutRebuildListenable,
      BlockTextFocusRegistry.focusListenable,
    ]);
  }

  @override
  void dispose() {
    _shellFocusNode.dispose();
    super.dispose();
  }

  void _ensureShellFocus() {
    if (!_shellFocusNode.hasFocus && _shellFocusNode.canRequestFocus) {
      _shellFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _shortcutListenable,
      builder: (context, _) {
        final shortcuts = <ShortcutActivator, Intent>{};
        for (final action in kShortcutCatalog) {
          if (!ShortcutDispatcher.canInvoke(widget.state, action.id)) continue;
          final binding = widget.state.shortcutBindings.bindingFor(action.id);
          if (!binding.isValid) continue;
          shortcuts[binding.toActivator()] = AppShortcutIntent(action.id);
        }

        return Shortcuts(
          shortcuts: shortcuts,
          child: Actions(
            actions: {
              AppShortcutIntent: CallbackAction<AppShortcutIntent>(
                onInvoke: (intent) {
                  ShortcutDispatcher.invoke(
                    context,
                    widget.state,
                    intent.actionId,
                  );
                  return intent;
                },
              ),
            },
            child: Focus(
              focusNode: _shellFocusNode,
              autofocus: true,
              skipTraversal: true,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final primary = FocusManager.instance.primaryFocus;
                    if (primary == null || !primary.hasFocus) {
                      _ensureShellFocus();
                    }
                  });
                },
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}

String? shortcutTooltipSuffix(AppState state, String actionId) {
  final binding = state.shortcutBindings.bindingFor(actionId);
  if (!binding.isValid) return null;
  return binding.displayLabel();
}
