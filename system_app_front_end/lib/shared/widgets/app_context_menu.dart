import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import 'disclosure_icon.dart';

/// One row, divider, or hover submenu in a compact context menu.
sealed class AppContextMenuEntry {
  const AppContextMenuEntry();
}

class AppContextMenuItem extends AppContextMenuEntry {
  const AppContextMenuItem({
    required this.value,
    required this.label,
    this.enabled = true,
    this.destructive = false,
  });

  final String value;
  final String label;
  final bool enabled;
  final bool destructive;
}

class AppContextMenuSubmenu extends AppContextMenuEntry {
  const AppContextMenuSubmenu({
    required this.label,
    required this.children,
  });

  final String label;
  final List<AppContextMenuItem> children;
}

class AppContextMenuDivider extends AppContextMenuEntry {
  const AppContextMenuDivider();
}

abstract final class AppContextMenu {
  static const _itemHeight = 28.0;
  static const _menuWidth = 196.0;
  static const _submenuWidth = 188.0;
  static const _horizontalPadding = 10.0;
  static const _bubbleRadius = 12.0;
  static const _submenuGap = 4.0;

  static VoidCallback? _dismissActive;
  static Object? _dismissActiveSession;

  /// Closes the currently open context menu, if any.
  static void dismissActive() {
    final dismiss = _dismissActive;
    _dismissActive = null;
    _dismissActiveSession = null;
    dismiss?.call();
  }

  static TextStyle _labelStyle({
    bool destructive = false,
    bool highlighted = false,
  }) {
    final base = AppTypography.sidebarItemStyle;
    return base.copyWith(
      fontSize: 11.5,
      height: 1.0,
      decoration: TextDecoration.none,
      decorationColor: Colors.transparent,
      color: highlighted
          ? Colors.white
          : destructive
              ? const Color(0xFFB45309)
              : AppColors.text.withValues(alpha: 0.92),
    );
  }

  static Widget _menuLabel(String text, TextStyle style) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      style: style,
    );
  }

  static Future<String?> show({
    required BuildContext context,
    required Offset globalPosition,
    required List<AppContextMenuEntry> entries,
    required bool isRtl,
  }) {
    dismissActive();

    final overlay = Overlay.of(context, rootOverlay: true);
    final textDirection = isRtl ? TextDirection.rtl : TextDirection.ltr;
    final completer = Completer<String?>();
    late OverlayEntry entry;
    var removed = false;
    final session = Object();

    void close([String? value]) {
      if (!completer.isCompleted) completer.complete(value);
      if (identical(_dismissActiveSession, session)) {
        _dismissActiveSession = null;
        _dismissActive = null;
      }
      if (!removed) {
        removed = true;
        entry.remove();
      }
    }

    _dismissActiveSession = session;
    _dismissActive = () => close(null);

    entry = OverlayEntry(
      builder: (overlayContext) => Directionality(
        textDirection: textDirection,
        child: _BubbleContextMenuHost(
          globalPosition: globalPosition,
          entries: entries,
          isRtl: isRtl,
          onSelect: close,
          onDismiss: () => close(null),
        ),
      ),
    );

    overlay.insert(entry);
    return completer.future;
  }
}

class _BubbleContextMenuHost extends StatefulWidget {
  const _BubbleContextMenuHost({
    required this.globalPosition,
    required this.entries,
    required this.isRtl,
    required this.onSelect,
    required this.onDismiss,
  });

  final Offset globalPosition;
  final List<AppContextMenuEntry> entries;
  final bool isRtl;
  final ValueChanged<String> onSelect;
  final VoidCallback onDismiss;

  @override
  State<_BubbleContextMenuHost> createState() => _BubbleContextMenuHostState();
}

class _BubbleContextMenuHostState extends State<_BubbleContextMenuHost> {
  int? _openSubmenuIndex;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): _DismissIntent(),
      },
      child: Actions(
        actions: {
          _DismissIntent: CallbackAction<_DismissIntent>(
            onInvoke: (_) {
              widget.onDismiss();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: widget.onDismiss,
                  onSecondaryTapDown: (_) => widget.onDismiss(),
                ),
              ),
              _positionedMenu(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _positionedMenu(BuildContext context) {
    final overlayBox =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox;
    final local = overlayBox.globalToLocal(widget.globalPosition);
    final isRtl = widget.isRtl;

    final mainHeight = _menuHeight(widget.entries);
    final hostHeight = _hostHeight(_openSubmenuIndex);

    final totalWidth = AppContextMenu._menuWidth +
        (_openSubmenuIndex == null
            ? 0
            : AppContextMenu._submenuWidth + AppContextMenu._submenuGap);
    final totalHeight = hostHeight;

    var left = local.dx;
    var top = local.dy;

    if (isRtl) {
      left -= totalWidth;
    }
    if (left + totalWidth > overlayBox.size.width - 8) {
      left = overlayBox.size.width - totalWidth - 8;
    }
    if (left < 8) left = 8;
    if (top + totalHeight > overlayBox.size.height - 8) {
      top = overlayBox.size.height - totalHeight - 8;
    }
    if (top < 8) top = 8;

    return Positioned(
      left: left,
      top: top,
      child: SizedBox(
        width: totalWidth,
        height: totalHeight,
        child: MouseRegion(
          onExit: (_) => _scheduleCloseSubmenu(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (_openSubmenuIndex != null && isRtl)
                _positionedSubmenu(isRtl: true, mainHeight: mainHeight),
              Positioned(
                left: _openSubmenuIndex != null && isRtl
                    ? AppContextMenu._submenuWidth + AppContextMenu._submenuGap
                    : 0,
                top: 0,
                child: _BubbleMenuPanel(
                  width: AppContextMenu._menuWidth,
                  children: _buildMainEntries(context),
                ),
              ),
              if (_openSubmenuIndex != null && !isRtl) ...[
                _submenuBridge(isRtl: false),
                _positionedSubmenu(isRtl: false, mainHeight: mainHeight),
              ],
              if (_openSubmenuIndex != null && isRtl) _submenuBridge(isRtl: true),
            ],
          ),
        ),
      ),
    );
  }

  double _hostHeight(int? submenuIndex) {
    final mainHeight = _menuHeight(widget.entries);
    if (submenuIndex == null) return mainHeight;
    final submenu = _submenuAt(submenuIndex);
    if (submenu == null) return mainHeight;
    final submenuBottom =
        _submenuTop(submenuIndex, mainHeight) + _submenuPanelHeight(submenu);
    return submenuBottom > mainHeight ? submenuBottom : mainHeight;
  }

  double _submenuTop(int index, double mainHeight) {
    final submenu = _submenuAt(index);
    if (submenu == null) return _rowTop(index);
    final alignedTop = _rowTop(index);
    final submenuHeight = _submenuPanelHeight(submenu);
    final overflow = alignedTop + submenuHeight - mainHeight;
    if (overflow <= 0) return alignedTop;
    return (alignedTop - overflow).clamp(0.0, alignedTop);
  }

  Widget _submenuBridge({required bool isRtl}) {
    final index = _openSubmenuIndex;
    final submenu = index == null ? null : _submenuAt(index);
    if (index == null || submenu == null) return const SizedBox.shrink();

    final mainHeight = _menuHeight(widget.entries);
    final top = _submenuTop(index, mainHeight);
    final height = _submenuPanelHeight(submenu);

    return Positioned(
      top: top,
      left: isRtl ? AppContextMenu._submenuWidth : AppContextMenu._menuWidth,
      width: AppContextMenu._submenuGap,
      height: height,
      child: MouseRegion(
        onEnter: (_) => _submenuCloseTimer?.cancel(),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _positionedSubmenu({
    required bool isRtl,
    required double mainHeight,
  }) {
    final submenu = _submenuAt(_openSubmenuIndex!);
    if (submenu == null) return const SizedBox.shrink();

    return Positioned(
      top: _submenuTop(_openSubmenuIndex!, mainHeight),
      left: isRtl ? 0 : AppContextMenu._menuWidth + AppContextMenu._submenuGap,
      child: MouseRegion(
        onEnter: (_) => _submenuCloseTimer?.cancel(),
        child: _BubbleMenuPanel(
          width: AppContextMenu._submenuWidth,
          children: _buildSubmenuEntries(submenu),
        ),
      ),
    );
  }

  double _rowTop(int index) {
    var top = 5.0;
    for (var i = 0; i < index; i++) {
      top += widget.entries[i] is AppContextMenuDivider ? 9 : AppContextMenu._itemHeight;
    }
    return top;
  }

  Timer? _submenuCloseTimer;

  void _scheduleCloseSubmenu() {
    _submenuCloseTimer?.cancel();
    _submenuCloseTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _openSubmenuIndex = null);
    });
  }

  void _openSubmenu(int index) {
    _submenuCloseTimer?.cancel();
    if (_openSubmenuIndex != index) {
      setState(() => _openSubmenuIndex = index);
    }
  }

  AppContextMenuSubmenu? _submenuAt(int index) {
    final entry = widget.entries[index];
    return entry is AppContextMenuSubmenu ? entry : null;
  }

  List<Widget> _buildMainEntries(BuildContext context) {
    final widgets = <Widget>[];
    for (var i = 0; i < widget.entries.length; i++) {
      final entry = widget.entries[i];
      if (entry is AppContextMenuDivider) {
        widgets.add(const _MenuDivider());
        continue;
      }
      if (entry is AppContextMenuSubmenu) {
        widgets.add(
          _SubmenuTriggerRow(
            label: entry.label,
            isOpen: _openSubmenuIndex == i,
            onHover: () => _openSubmenu(i),
          ),
        );
        continue;
      }
      final item = entry as AppContextMenuItem;
      widgets.add(
        _MenuActionRow(
          label: item.label,
          enabled: item.enabled,
          destructive: item.destructive,
          onTap: item.enabled ? () => widget.onSelect(item.value) : null,
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildSubmenuEntries(AppContextMenuSubmenu? submenu) {
    if (submenu == null) return const [];
    return [
      for (final item in submenu.children)
        _MenuActionRow(
          label: item.label,
          enabled: item.enabled,
          destructive: item.destructive,
          onTap: item.enabled ? () => widget.onSelect(item.value) : null,
        ),
    ];
  }

  @override
  void dispose() {
    _submenuCloseTimer?.cancel();
    super.dispose();
  }
}

class _BubbleMenuPanel extends StatelessWidget {
  const _BubbleMenuPanel({
    required this.width,
    required this.children,
  });

  final double width;
  final List<Widget> children;

  static final _menuStyle = GlassStyleSpec(
    blurSigma: 28,
    tintOpacity: 0.88,
    tintColor: const Color(0xFFF4F4F5),
    showTopHighlight: false,
    elevation: 0,
    border: Border.all(
      color: Colors.black.withValues(alpha: 0.1),
      width: 0.65,
    ),
  );

  static List<BoxShadow> get _shadows => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.16),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppContextMenu._bubbleRadius),
        boxShadow: _shadows,
      ),
      child: GlassSurface.styled(
        style: _menuStyle,
        borderRadius: BorderRadius.circular(AppContextMenu._bubbleRadius),
        border: _menuStyle.border,
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _SubmenuTriggerRow extends StatefulWidget {
  const _SubmenuTriggerRow({
    required this.label,
    required this.isOpen,
    required this.onHover,
  });

  final String label;
  final bool isOpen;
  final VoidCallback onHover;

  @override
  State<_SubmenuTriggerRow> createState() => _SubmenuTriggerRowState();
}

class _SubmenuTriggerRowState extends State<_SubmenuTriggerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.isOpen || _hovered;
    final chevronColor = highlighted
        ? Colors.white
        : AppColors.text.withValues(alpha: 0.45);
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: _MenuRowChrome(
        highlighted: highlighted,
        child: Row(
          children: [
            Expanded(
              child: AppContextMenu._menuLabel(
                widget.label,
                AppContextMenu._labelStyle(highlighted: highlighted),
              ),
            ),
            const SizedBox(width: 4),
            DisclosureIcon(
              expanded: false,
              size: 16,
              color: chevronColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuActionRow extends StatefulWidget {
  const _MenuActionRow({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;

  @override
  State<_MenuActionRow> createState() => _MenuActionRowState();
}

class _MenuActionRowState extends State<_MenuActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _hovered && widget.enabled;
    return MouseRegion(
      onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: _MenuRowChrome(
          highlighted: highlighted,
          child: AppContextMenu._menuLabel(
            widget.label,
            AppContextMenu._labelStyle(
              destructive: widget.destructive && !highlighted,
              highlighted: highlighted,
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRowChrome extends StatelessWidget {
  const _MenuRowChrome({
    required this.child,
    required this.highlighted,
  });

  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppContextMenu._itemHeight,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.symmetric(
        horizontal: AppContextMenu._horizontalPadding,
      ),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFF007AFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: AppColors.text.withValues(alpha: 0.12),
      ),
    );
  }
}

class _DismissIntent extends Intent {
  const _DismissIntent();
}

double _menuHeight(List<AppContextMenuEntry> entries) {
  var height = 10.0; // vertical panel padding
  for (final entry in entries) {
    if (entry is AppContextMenuDivider) {
      height += 9;
    } else {
      height += AppContextMenu._itemHeight;
    }
  }
  return height;
}

double _submenuPanelHeight(AppContextMenuSubmenu? submenu) {
  if (submenu == null) return 0;
  return 10 + submenu.children.length * AppContextMenu._itemHeight;
}
