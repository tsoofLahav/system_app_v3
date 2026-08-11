import 'package:flutter/material.dart';

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
    widget.state.shortcutRebuildListenable.addListener(_onBindingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureShellFocus());
  }

  @override
  void didUpdateWidget(covariant AppShortcutsScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.shortcutRebuildListenable.removeListener(_onBindingsChanged);
      widget.state.shortcutRebuildListenable.addListener(_onBindingsChanged);
    }
  }

  @override
  void dispose() {
    widget.state.shortcutRebuildListenable.removeListener(_onBindingsChanged);
    _shellFocusNode.dispose();
    super.dispose();
  }

  void _onBindingsChanged() {
    if (mounted) setState(() {});
  }

  void _ensureShellFocus() {
    if (!_shellFocusNode.hasFocus && _shellFocusNode.canRequestFocus) {
      _shellFocusNode.requestFocus();
    }
  }

  Map<ShortcutActivator, Intent> _shortcutMap() {
    final out = <ShortcutActivator, Intent>{};
    for (final action in kShortcutCatalog) {
      // Only wire actions the dispatcher knows; others stay catalog-only.
      if (!_dispatchableIds.contains(action.id)) continue;
      final binding = widget.state.shortcutBindings.bindingFor(action.id);
      if (!binding.isValid) continue;
      out[binding.toActivator()] = AppShortcutIntent(action.id);
    }
    return out;
  }

  static const _dispatchableIds = {
    ShortcutActionIds.addTopic,
    ShortcutActionIds.addView,
    ShortcutActionIds.addFile,
    ShortcutActionIds.assignTaskView,
    ShortcutActionIds.aiConsult,
    ShortcutActionIds.insertInfo,
    ShortcutActionIds.insertTaskList,
    ShortcutActionIds.insertTable,
    ShortcutActionIds.insertGraph,
    ShortcutActionIds.insertImage,
  };

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _shellFocusNode,
      child: Shortcuts(
        shortcuts: _shortcutMap(),
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

String? shortcutTooltipSuffix(AppState state, String actionId) {
  final binding = state.shortcutBindings.bindingFor(actionId);
  if (!binding.isValid) return null;
  return binding.displayLabel();
}
