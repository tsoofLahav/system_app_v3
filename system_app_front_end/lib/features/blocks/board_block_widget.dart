import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/api_config.dart';
import '../../core/models/block.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../../shared/utils/local_image_picker.dart';
import 'board_content.dart';
import 'board_crop_overlay.dart';
import 'board_item_image.dart';

enum _BoardHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

class BoardBlockWidget extends StatefulWidget {
  const BoardBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
    required this.onCommit,
    required this.uploadImage,
    required this.onRunAiImage,
    required this.addImageTooltip,
    required this.aiImageTooltip,
    required this.cropTooltip,
    required this.aiPromptTitle,
    required this.aiPromptHint,
    required this.emptyHint,
    required this.deleteImageLabel,
    required this.cancelLabel,
    required this.submitLabel,
    this.aiRunning = false,
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final ValueChanged<Map<String, dynamic>> onCommit;
  final Future<Map<String, dynamic>> Function(String filename, List<int> bytes)
      uploadImage;
  final Future<void> Function(String prompt) onRunAiImage;
  final String addImageTooltip;
  final String aiImageTooltip;
  final String cropTooltip;
  final String aiPromptTitle;
  final String aiPromptHint;
  final String emptyHint;
  final String deleteImageLabel;
  final String cancelLabel;
  final String submitLabel;
  final bool aiRunning;

  @override
  State<BoardBlockWidget> createState() => _BoardBlockWidgetState();
}

class _BoardBlockWidgetState extends State<BoardBlockWidget> {
  String? _selectedId;
  bool _cropMode = false;
  Rect? _cropSelectionLocal;
  List<BoardItem>? _localItems;
  final _focusNode = FocusNode();

  static const _minSize = 48.0;
  static const _handleSize = 10.0;
  static const _handleHit = 18.0;
  static const _canvasMinHeight = 320.0;
  static const _canvasPadding = 16.0;

  List<BoardItem> get _items =>
      _localItems ?? boardItemsFromContent(widget.block.content);

  @override
  void didUpdateWidget(BoardBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.block.content != oldWidget.block.content) {
      _localItems = null;
    }
  }

  void _applyItems(List<BoardItem> items, {bool commit = false}) {
    setState(() => _localItems = items);
    final content = boardContentFromItems(items);
    widget.onChanged(content);
    if (commit) widget.onCommit(content);
  }

  BoardItem? _itemById(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<BoardItem> _replaceItem(BoardItem next) {
    return _items.map((item) => item.id == next.id ? next : item).toList();
  }

  void _selectItem(String id) {
    if (_cropMode && _selectedId != null && _selectedId != id) {
      _bakeCrop(_selectedId!);
    }
    final items = _items;
    final item = _itemById(id);
    if (item == null) return;
    final nextZ = nextBoardZIndex(items);
    final updated = item.copyWith(zIndex: nextZ);
    _applyItems(_replaceItem(updated));
    setState(() {
      _selectedId = id;
      if (_cropMode) {
        _cropSelectionLocal = boardItemInitialCropSelection(item);
      }
    });
    _focusNode.requestFocus();
  }

  Future<void> _addImage() async {
    final picked = await pickLocalImageFile();
    if (picked == null || !mounted) return;
    try {
      final uploaded = await widget.uploadImage(picked.$1, picked.$2);
      final items = _items;
      final (x, y) = staggerBoardPlacement(items);
      final next = BoardItem(
        id: nextBoardItemId(items),
        imagePath: uploaded['image_path'] as String? ?? '',
        filename: uploaded['filename'] as String? ?? picked.$1,
        x: x,
        y: y,
        width: 220,
        height: 165,
        zIndex: nextBoardZIndex(items),
      );
      if (next.imagePath.isEmpty) return;
      _applyItems([...items, next], commit: true);
      setState(() => _selectedId = next.id);
    } catch (_) {
      // Upload errors surface via AppState elsewhere when wired from FileSection.
    }
  }

  void _deleteSelected() {
    final id = _selectedId;
    if (id == null) return;
    _applyItems(_items.where((item) => item.id != id).toList(), commit: true);
    setState(() => _selectedId = null);
  }

  double _contentHeight(List<BoardItem> items) {
    var needed = _canvasMinHeight;
    for (final item in items) {
      needed = math.max(needed, item.y + item.height + _canvasPadding);
    }
    return needed;
  }

  double _viewportHeight(double maxHeight, List<BoardItem> items) {
    if (!maxHeight.isFinite || maxHeight <= 0) {
      return _contentHeight(items);
    }
    return math.max(maxHeight, _contentHeight(items));
  }

  String _imageUrl(String path) =>
      path.startsWith('http') ? path : '${ApiConfig.baseUrl}$path';

  void _onItemDragUpdate(String id, Offset delta) {
    final item = _itemById(id);
    if (item == null) return;
    final next = item.copyWith(
      x: (item.x + delta.dx).clamp(0, 10000),
      y: (item.y + delta.dy).clamp(0, 10000),
    );
    _applyItems(_replaceItem(next));
  }

  void _onResizeUpdate(String id, _BoardHandle handle, Offset delta) {
    final base = _itemById(id);
    if (base == null) return;

    var left = base.x;
    var top = base.y;
    var width = base.width;
    var height = base.height;

    switch (handle) {
      case _BoardHandle.right:
        width = base.width + delta.dx;
      case _BoardHandle.left:
        left = base.x + delta.dx;
        width = base.width - delta.dx;
      case _BoardHandle.bottom:
        height = base.height + delta.dy;
      case _BoardHandle.top:
        top = base.y + delta.dy;
        height = base.height - delta.dy;
      case _BoardHandle.bottomRight:
        width = base.width + delta.dx;
        height = base.height + delta.dy;
      case _BoardHandle.bottomLeft:
        left = base.x + delta.dx;
        width = base.width - delta.dx;
        height = base.height + delta.dy;
      case _BoardHandle.topRight:
        width = base.width + delta.dx;
        top = base.y + delta.dy;
        height = base.height - delta.dy;
      case _BoardHandle.topLeft:
        left = base.x + delta.dx;
        top = base.y + delta.dy;
        width = base.width - delta.dx;
        height = base.height - delta.dy;
    }

    if (width < _minSize) {
      if (handle == _BoardHandle.left ||
          handle == _BoardHandle.topLeft ||
          handle == _BoardHandle.bottomLeft) {
        left -= _minSize - width;
      }
      width = _minSize;
    }
    if (height < _minSize) {
      if (handle == _BoardHandle.top ||
          handle == _BoardHandle.topLeft ||
          handle == _BoardHandle.topRight) {
        top -= _minSize - height;
      }
      height = _minSize;
    }

    final next = base.copyWith(
      x: left.clamp(0, 10000),
      y: top.clamp(0, 10000),
      width: width,
      height: height,
    );
    _applyItems(_replaceItem(next));
  }

  void _bakeCrop(String id) {
    final item = _itemById(id);
    final sel = _cropSelectionLocal;
    if (item == null || sel == null) return;
    final baked = bakeBoardItemVirtualSelection(item, sel);
    _applyItems(_replaceItem(baked), commit: true);
    setState(() => _cropSelectionLocal = null);
  }

  void _onCropSelectionMove(Offset delta) {
    final item = _itemById(_selectedId ?? '');
    final sel = _cropSelectionLocal;
    if (item == null || sel == null) return;
    final canvas = boardItemCropVirtualCanvas(item);
    setState(() {
      _cropSelectionLocal = clampCropSelection(
        sel.shift(delta),
        canvas.fullW,
        canvas.fullH,
        _minSize,
      );
    });
  }

  void _onCropSelectionResize(BoardCropHandle handle, Offset delta) {
    final item = _itemById(_selectedId ?? '');
    final sel = _cropSelectionLocal;
    if (item == null || sel == null) return;
    final canvas = boardItemCropVirtualCanvas(item);
    setState(() {
      _cropSelectionLocal = resizeCropSelection(
        sel,
        handle,
        delta,
        canvas.fullW,
        canvas.fullH,
        _minSize,
      );
    });
  }

  Future<void> _promptAiImage() async {
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) => _BoardAiImagePromptDialog(
        title: widget.aiPromptTitle,
        hint: widget.aiPromptHint,
        cancelLabel: widget.cancelLabel,
        submitLabel: widget.submitLabel,
      ),
    );
    if (prompt == null || prompt.isEmpty || !mounted) return;
    try {
      await widget.onRunAiImage(prompt);
    } catch (_) {
      // AppState sets error; parent may show snackbar.
    }
  }

  void _toggleCropMode() {
    if (_selectedId == null) return;
    if (_cropMode) {
      _bakeCrop(_selectedId!);
      setState(() => _cropMode = false);
    } else {
      final item = _itemById(_selectedId!);
      if (item == null) return;
      setState(() {
        _cropMode = true;
        _cropSelectionLocal = boardItemInitialCropSelection(item);
      });
    }
  }

  Widget _buildToolbar() {
    final hasSelection = _selectedId != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.noteBorder.withValues(alpha: 0.4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BoardToolButton(
                  tooltip: widget.addImageTooltip,
                  icon: AppIcons.add,
                  onPressed: _addImage,
                ),
                _BoardToolButton(
                  tooltip: widget.aiImageTooltip,
                  icon: AppIcons.image,
                  enabled: !widget.aiRunning,
                  onPressed: widget.aiRunning ? null : _promptAiImage,
                ),
                _BoardToolButton(
                  tooltip: widget.cropTooltip,
                  icon: AppIcons.crop,
                  enabled: hasSelection && !widget.aiRunning,
                  selected: _cropMode && hasSelection,
                  onPressed: hasSelection ? _toggleCropMode : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_selectedId != null) {
        _deleteSelected();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final canvasHeight = _viewportHeight(
                  constraints.maxHeight,
                  items,
                );

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_cropMode && _selectedId != null) {
                      _bakeCrop(_selectedId!);
                    }
                    setState(() {
                      _selectedId = null;
                      _cropMode = false;
                      _cropSelectionLocal = null;
                    });
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.noteBorder.withValues(alpha: 0.45),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SingleChildScrollView(
                        child: SizedBox(
                          height: canvasHeight,
                          width: constraints.maxWidth,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              if (items.isEmpty)
                                SizedBox(
                                  height: math.max(
                                    canvasHeight,
                                    _canvasMinHeight,
                                  ),
                                  width: constraints.maxWidth,
                                  child: Center(
                                    child: Text(
                                      widget.emptyHint,
                                      style: AppTypography.noteBodyStyle
                                          .copyWith(
                                        color: AppColors.noteHint,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              for (final item in items)
                                _BoardItemLayer(
                                  item: item,
                                  url: _imageUrl(item.imagePath),
                                  selected: _selectedId == item.id,
                                  cropMode:
                                      _cropMode && _selectedId == item.id,
                                  cropSelection: _cropMode &&
                                          _selectedId == item.id
                                      ? _cropSelectionLocal
                                      : null,
                                  onSelect: () => _selectItem(item.id),
                                  onDragUpdate: (delta) {
                                    _onItemDragUpdate(item.id, delta);
                                  },
                                  onDragEnd: () {
                                    _applyItems(_items, commit: true);
                                  },
                                  onResizeUpdate: (handle, delta) {
                                    _onResizeUpdate(item.id, handle, delta);
                                  },
                                  onResizeEnd: () {
                                    _applyItems(_items, commit: true);
                                  },
                                  onCropMove: _onCropSelectionMove,
                                  onCropResize: _onCropSelectionResize,
                                  onDelete: () {
                                    setState(() => _selectedId = item.id);
                                    _deleteSelected();
                                  },
                                  deleteLabel: widget.deleteImageLabel,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardItemLayer extends StatelessWidget {
  const _BoardItemLayer({
    required this.item,
    required this.url,
    required this.selected,
    required this.cropMode,
    required this.cropSelection,
    required this.onSelect,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeUpdate,
    required this.onResizeEnd,
    required this.onCropMove,
    required this.onCropResize,
    required this.onDelete,
    required this.deleteLabel,
  });

  final BoardItem item;
  final String url;
  final bool selected;
  final bool cropMode;
  final Rect? cropSelection;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final void Function(_BoardHandle handle, Offset delta) onResizeUpdate;
  final VoidCallback onResizeEnd;
  final ValueChanged<Offset> onCropMove;
  final void Function(BoardCropHandle handle, Offset delta) onCropResize;
  final VoidCallback onDelete;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    if (cropMode && cropSelection != null) {
      return _buildCropCanvas(context);
    }
    return _buildNormalLayer(context);
  }

  Widget _buildCropCanvas(BuildContext context) {
    final canvas = boardItemCropVirtualCanvas(item);
    final selection = cropSelection!;

    return Positioned(
      left: canvas.canvasX,
      top: canvas.canvasY,
      width: canvas.fullW,
      height: canvas.fullH,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSelect,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: canvas.fullW,
              height: canvas.fullH,
              child: BoardCropSourceImage(
                url: url,
                width: canvas.fullW,
                height: canvas.fullH,
              ),
            ),
            BoardCropShade(
              itemWidth: canvas.fullW,
              itemHeight: canvas.fullH,
              selection: selection,
            ),
            BoardCropSelectionFrame(
              selection: selection,
              onMove: onCropMove,
              onMoveEnd: () {},
              onResize: onCropResize,
              onResizeEnd: () {},
            ),
            Positioned(
              left: math.max(4, selection.right - 56),
              top: selection.top + 4,
              child: Material(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      deleteLabel,
                      style: AppTypography.metaStyle.copyWith(fontSize: 11),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalLayer(BuildContext context) {
    return Positioned(
      left: item.x,
      top: item.y,
      width: item.width,
      height: item.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSelect,
        onPanUpdate: (d) => onDragUpdate(d.delta),
        onPanEnd: (_) => onDragEnd(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: item.width,
              height: item.height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected
                        ? AppColors.text.withValues(alpha: 0.4)
                        : Colors.transparent,
                    width: selected ? 1.5 : 0,
                  ),
                ),
                child: BoardItemImage(
                  item: item,
                  url: url,
                ),
              ),
            ),
            if (selected) ...[
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(4),
                  child: InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        deleteLabel,
                        style: AppTypography.metaStyle.copyWith(fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ),
              for (final handle in _BoardHandle.values)
                _BoardResizeHandle(
                  handle: handle,
                  width: item.width,
                  height: item.height,
                  onDragUpdate: (delta) => onResizeUpdate(handle, delta),
                  onDragEnd: onResizeEnd,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BoardResizeHandle extends StatefulWidget {
  const _BoardResizeHandle({
    required this.handle,
    required this.width,
    required this.height,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final _BoardHandle handle;
  final double width;
  final double height;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  State<_BoardResizeHandle> createState() => _BoardResizeHandleState();
}

class _BoardResizeHandleState extends State<_BoardResizeHandle> {
  Offset? _lastGlobal;

  MouseCursor get _cursor => switch (widget.handle) {
        _BoardHandle.topLeft || _BoardHandle.bottomRight =>
          SystemMouseCursors.resizeUpLeftDownRight,
        _BoardHandle.topRight || _BoardHandle.bottomLeft =>
          SystemMouseCursors.resizeUpRightDownLeft,
        _BoardHandle.top || _BoardHandle.bottom =>
          SystemMouseCursors.resizeUpDown,
        _BoardHandle.left || _BoardHandle.right =>
          SystemMouseCursors.resizeLeftRight,
      };

  (double? left, double? top, double? right, double? bottom) _insets() {
    const inset = _BoardBlockWidgetState._handleHit / 2;
    switch (widget.handle) {
      case _BoardHandle.topLeft:
        return (-inset, -inset, null, null);
      case _BoardHandle.top:
        return (widget.width / 2 - inset, -inset, null, null);
      case _BoardHandle.topRight:
        return (null, -inset, -inset, null);
      case _BoardHandle.right:
        return (null, widget.height / 2 - inset, -inset, null);
      case _BoardHandle.bottomRight:
        return (null, null, -inset, -inset);
      case _BoardHandle.bottom:
        return (widget.width / 2 - inset, null, null, -inset);
      case _BoardHandle.bottomLeft:
        return (-inset, null, null, -inset);
      case _BoardHandle.left:
        return (-inset, widget.height / 2 - inset, null, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = _insets();
    return Positioned(
      left: insets.$1,
      top: insets.$2,
      right: insets.$3,
      bottom: insets.$4,
      child: MouseRegion(
        cursor: _cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _lastGlobal = d.globalPosition,
          onPanUpdate: (d) {
            if (_lastGlobal == null) return;
            final delta = d.globalPosition - _lastGlobal!;
            _lastGlobal = d.globalPosition;
            widget.onDragUpdate(delta);
          },
          onPanEnd: (_) {
            _lastGlobal = null;
            widget.onDragEnd();
          },
          onPanCancel: () {
            _lastGlobal = null;
            widget.onDragEnd();
          },
          child: SizedBox(
            width: _BoardBlockWidgetState._handleHit,
            height: _BoardBlockWidgetState._handleHit,
            child: Center(
              child: Container(
                width: _BoardBlockWidgetState._handleSize,
                height: _BoardBlockWidgetState._handleSize,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: AppColors.text.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardAiImagePromptDialog extends StatefulWidget {
  const _BoardAiImagePromptDialog({
    required this.title,
    required this.hint,
    required this.cancelLabel,
    required this.submitLabel,
  });

  final String title;
  final String hint;
  final String cancelLabel;
  final String submitLabel;

  @override
  State<_BoardAiImagePromptDialog> createState() =>
      _BoardAiImagePromptDialogState();
}

class _BoardAiImagePromptDialogState extends State<_BoardAiImagePromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppGlassDialog(
      title: Text(widget.title),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.submitLabel),
        ),
      ],
      child: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 4,
        decoration: AppTypography.noteInputDecoration(
          hint: widget.hint,
        ),
        style: AppTypography.noteBodyStyle,
      ),
    );
  }
}

class _BoardToolButton extends StatelessWidget {
  const _BoardToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? AppColors.aiCyan.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: active ? onPressed : null,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 26,
            height: 22,
            child: Center(
              child: AppIcon(
                icon,
                size: 14,
                enabled: active,
                color: selected
                    ? AppColors.aiCyan.withValues(alpha: 0.9)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
