import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/app_colors.dart';

class _MoveChoiceIntent extends Intent {
  const _MoveChoiceIntent(this.delta);
  final int delta;
}

class _ActivateChoiceIntent extends Intent {
  const _ActivateChoiceIntent();
}

class _DismissChoiceIntent extends Intent {
  const _DismissChoiceIntent();
}

/// Arrow / Enter / Escape list for dialogs that currently only respond to taps.
class DialogChoiceList extends StatefulWidget {
  const DialogChoiceList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.onActivate,
    this.onTap,
    this.initialIndex = 0,
    this.maxHeight = 360,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index, bool highlighted)
      itemBuilder;
  final ValueChanged<int> onActivate;
  /// Defaults to [onActivate]. Use a different callback when tap should not
  /// also close the dialog.
  final ValueChanged<int>? onTap;
  final int initialIndex;
  final double maxHeight;

  @override
  State<DialogChoiceList> createState() => _DialogChoiceListState();
}

class _DialogChoiceListState extends State<DialogChoiceList> {
  late int _index;
  late final ScrollController _scroll;
  final _keys = <GlobalKey>[];

  @override
  void initState() {
    super.initState();
    _index = widget.itemCount == 0
        ? 0
        : widget.initialIndex.clamp(0, widget.itemCount - 1);
    _scroll = ScrollController();
  }

  @override
  void didUpdateWidget(DialogChoiceList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount == 0) {
      _index = 0;
      return;
    }
    if (_index >= widget.itemCount) {
      _index = widget.itemCount - 1;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _move(int delta) {
    if (widget.itemCount <= 0) return;
    final next = (_index + delta).clamp(0, widget.itemCount - 1);
    if (next == _index) return;
    setState(() => _index = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _keyAt(_index).currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 80),
        );
      }
    });
  }

  void _activate() {
    if (widget.itemCount <= 0) return;
    widget.onActivate(_index);
  }

  GlobalKey _keyAt(int index) {
    while (_keys.length <= index) {
      _keys.add(GlobalKey());
    }
    return _keys[index];
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): const _DismissChoiceIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown):
            const _MoveChoiceIntent(1),
        LogicalKeySet(LogicalKeyboardKey.arrowUp):
            const _MoveChoiceIntent(-1),
        LogicalKeySet(LogicalKeyboardKey.enter): const _ActivateChoiceIntent(),
        LogicalKeySet(LogicalKeyboardKey.numpadEnter):
            const _ActivateChoiceIntent(),
      },
      child: Actions(
        actions: {
          _DismissChoiceIntent: CallbackAction<_DismissChoiceIntent>(
            onInvoke: (_) {
              Navigator.maybePop(context);
              return null;
            },
          ),
          _MoveChoiceIntent: CallbackAction<_MoveChoiceIntent>(
            onInvoke: (intent) {
              _move(intent.delta);
              return null;
            },
          ),
          _ActivateChoiceIntent: CallbackAction<_ActivateChoiceIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: ListView.builder(
              controller: _scroll,
              shrinkWrap: true,
              itemCount: widget.itemCount,
              itemBuilder: (context, index) {
                final highlighted = index == _index;
                return KeyedSubtree(
                  key: _keyAt(index),
                  child: Material(
                    color: highlighted
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() => _index = index);
                        (widget.onTap ?? widget.onActivate)(index);
                      },
                      onHover: (hover) {
                        if (hover && _index != index) {
                          setState(() => _index = index);
                        }
                      },
                      child: widget.itemBuilder(context, index, highlighted),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
