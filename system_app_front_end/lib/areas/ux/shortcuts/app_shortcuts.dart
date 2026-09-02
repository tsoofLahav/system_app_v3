import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_state.dart';
import '../../files/editor/document_editor_controller.dart';
import './shortcut_bindings_store.dart';
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
  final _dispatchedThisFrame = <String>{};
  String? _pressedActionId;

  @override
  void initState() {
    super.initState();
    widget.state.shortcutRebuildListenable.addListener(_onBindingsChanged);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
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
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
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

  /// Steal catalog keys before Super Editor / text fields handle them, and
  /// fire even when no text field has focus.
  bool _onHardwareKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is KeyUpEvent) {
      _pressedActionId = null;
      return false;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final actionId =
        widget.state.shortcutBindings.actionIdMatchingHardware(event);
    if (actionId == null) return false;
    final action = shortcutActionById(actionId);
    if (action == null) return false;

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      // A dialog sits above the shell. Insert / text / list still apply to
      // the focused editor inside that dialog (fill-file snippet, prompts).
      if (!_allowedBehindModal(action)) return false;
    }

    final sizeRepeat = action.textAction == 'text:size_up' ||
        action.textAction == 'text:size_down';
    if (event is KeyRepeatEvent && !sizeRepeat) return false;

    if (action.context == ShortcutContextRequirement.textFocus &&
        !shortcutHasTextFocus()) {
      return false;
    }
    if (action.context == ShortcutContextRequirement.insertObject &&
        DocumentEditorRegistry.active == null) {
      return false;
    }
    if (action.context == ShortcutContextRequirement.emojiPalette &&
        !emojiPaletteAvailable(widget.state)) {
      return false;
    }

    _dispatchOnce(actionId, allowRepeat: event is KeyRepeatEvent && sizeRepeat);
    return true;
  }

  bool _allowedBehindModal(ShortcutAction action) {
    switch (action.context) {
      case ShortcutContextRequirement.insertObject:
      case ShortcutContextRequirement.emojiPalette:
      case ShortcutContextRequirement.textFocus:
        return true;
      default:
        return action.id == ShortcutActionIds.addConnection ||
            action.id == ShortcutActionIds.toggleEmbedMoveMode ||
            action.id == ShortcutActionIds.toggleReorderMode;
    }
  }

  /// Hardware intercept and [Shortcuts] both see the same key. Fire once per
  /// press (insert object, ⌘J, …); size up/down may repeat while held.
  void _dispatchOnce(String actionId, {bool allowRepeat = false}) {
    if (!allowRepeat && _pressedActionId == actionId) return;
    if (!_dispatchedThisFrame.add(actionId)) return;
    if (_dispatchedThisFrame.length == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dispatchedThisFrame.clear();
      });
    }
    _pressedActionId = actionId;
    dispatchShortcutAction(context, widget.state, actionId);
  }

  Map<ShortcutActivator, Intent> _shortcutMap() {
    return shortcutActivatorsFor(widget.state.shortcutBindings);
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _shortcutMap(),
      child: Actions(
        actions: {
          AppShortcutIntent: CallbackAction<AppShortcutIntent>(
            onInvoke: (intent) {
              _dispatchOnce(intent.actionId);
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _shellFocusNode,
          autofocus: true,
          skipTraversal: true,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Every Preferences catalog action with a valid binding, including AI slots.
Map<ShortcutActivator, Intent> shortcutActivatorsFor(
  ShortcutBindingsStore store,
) {
  final out = <ShortcutActivator, Intent>{};
  for (final action in kShortcutCatalog) {
    final binding = store.bindingFor(action.id);
    if (!binding.isValid) continue;
    out[binding.toActivator()] = AppShortcutIntent(action.id);
  }
  return out;
}

String? shortcutTooltipSuffix(AppState state, String actionId) {
  final binding = state.shortcutBindings.bindingFor(actionId);
  if (!binding.isValid) return null;
  return binding.displayLabel();
}
