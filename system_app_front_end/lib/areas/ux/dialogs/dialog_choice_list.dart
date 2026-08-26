import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_metrics.dart';

/// Arrow / Enter / Escape picker in the standard dialog shell.
Future<T?> showAppChoiceDialog<T>({
  required BuildContext context,
  required String title,
  required String cancelLabel,
  required List<T> items,
  required Widget Function(BuildContext context, T item, bool highlighted)
  itemBuilder,
  int initialIndex = 0,
  double maxHeight = 320,
}) {
  return showAppDialog<T>(
    context: context,
    builder: (ctx) => AppAdaptiveDialogShell(
      title: Text(title),
      width: AppDialogMetrics.wideWidth,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(cancelLabel),
        ),
      ],
      child: items.isEmpty
          ? const SizedBox.shrink()
          : DialogChoiceList(
              itemCount: items.length,
              initialIndex: initialIndex,
              maxHeight: maxHeight,
              onActivate: (i) => Navigator.pop(ctx, items[i]),
              itemBuilder: (context, i, highlighted) =>
                  itemBuilder(context, items[i], highlighted),
            ),
    ),
  );
}

/// Label inside a [DialogChoiceList] / [showAppChoiceDialog] row.
class DialogChoiceText extends StatelessWidget {
  const DialogChoiceText(this.text, {super.key, this.leading});

  final String text;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final label = Padding(
      padding: DialogChoiceList.itemPadding,
      child: Text(text, style: AppTypography.noteBodyStyle),
    );
    if (leading == null) return label;
    return Padding(
      padding: DialogChoiceList.itemPadding,
      child: Row(
        children: [
          leading!,
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTypography.noteBodyStyle)),
        ],
      ),
    );
  }
}

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
  static const itemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  const DialogChoiceList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.onActivate,
    this.onTap,
    this.initialIndex = 0,
    this.maxHeight = 360,
    this.autofocus = true,
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
  final bool autofocus;

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
        LogicalKeySet(LogicalKeyboardKey.arrowDown): const _MoveChoiceIntent(1),
        LogicalKeySet(LogicalKeyboardKey.arrowUp): const _MoveChoiceIntent(-1),
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
          autofocus: widget.autofocus,
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
