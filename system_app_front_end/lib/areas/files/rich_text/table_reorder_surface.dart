import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../editor/drag_mode_frame.dart';

/// Which axis [TableReorderSurface] is permuting.
enum TableReorderKind {
  rows,
  columns,
}

class _RowDrag {
  const _RowDrag(this.index);
  final int index;
}

class _ColDrag {
  const _ColDrag(this.index);
  final int index;
}

/// Glass grab surface for table row/column reorder (no drag handles).
///
/// Exit: tap outside, Escape, or Done — same language as task Reorder Mode.
class TableReorderSurface extends StatelessWidget {
  const TableReorderSurface({
    super.key,
    required this.kind,
    required this.cells,
    required this.strings,
    required this.onMoveRow,
    required this.onMoveColumn,
    required this.onDone,
  });

  final TableReorderKind kind;
  final List<List<String>> cells;
  final AppStrings strings;
  final void Function(int from, int to) onMoveRow;
  final void Function(int from, int to) onMoveColumn;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final title = kind == TableReorderKind.rows
        ? strings['reorderRows']
        : strings['reorderColumns'];

    return TapRegion(
      onTapOutside: (_) => onDone(),
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            onDone();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DragModeFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppTypography.metaStyle.copyWith(
                        color: AppColors.textHint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onDone,
                    child: Text(
                      strings['doneReorder'],
                      style: AppTypography.metaStyle.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Local overlay + clip so the drag ghost stays inside the
              // table (Draggable otherwise paints in the app overlay).
              _ClippedTableDragOverlay(
                child: kind == TableReorderKind.rows
                    ? _ReorderRows(
                        cells: cells,
                        onMove: onMoveRow,
                      )
                    : _ReorderColumns(
                        cells: cells,
                        onMove: onMoveColumn,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hosts drag feedback in a clipped overlay sized to the table, not the pane.
class _ClippedTableDragOverlay extends StatefulWidget {
  const _ClippedTableDragOverlay({required this.child});

  final Widget child;

  @override
  State<_ClippedTableDragOverlay> createState() =>
      _ClippedTableDragOverlayState();
}

class _ClippedTableDragOverlayState extends State<_ClippedTableDragOverlay> {
  late final OverlayEntry _entry = OverlayEntry(
    canSizeOverlay: true,
    builder: (context) => widget.child,
  );

  @override
  void didUpdateWidget(_ClippedTableDragOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Overlay(
        clipBehavior: Clip.hardEdge,
        initialEntries: [_entry],
      ),
    );
  }
}

class _ReorderRows extends StatelessWidget {
  const _ReorderRows({required this.cells, required this.onMove});

  final List<List<String>> cells;
  final void Function(int from, int to) onMove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 280.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < cells.length; r++) ...[
              if (r > 0) const SizedBox(height: 6),
              DragTarget<_RowDrag>(
                onWillAcceptWithDetails: (d) => d.data.index != r,
                onAcceptWithDetails: (d) => onMove(d.data.index, r),
                builder: (context, candidate, _) {
                  Widget row() => _glassGrab(
                    highlight: candidate.isNotEmpty,
                    child: Row(
                      children: [
                        for (var c = 0; c < cells[r].length; c++) ...[
                          if (c > 0) const SizedBox(width: 4),
                          Expanded(child: _cellLabel(cells[r][c])),
                        ],
                      ],
                    ),
                  );
                  return Draggable<_RowDrag>(
                    data: _RowDrag(r),
                    rootOverlay: false,
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(width: width, child: row()),
                    ),
                    childWhenDragging: Opacity(opacity: 0.28, child: row()),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: row(),
                    ),
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ReorderColumns extends StatelessWidget {
  const _ReorderColumns({required this.cells, required this.onMove});

  final List<List<String>> cells;
  final void Function(int from, int to) onMove;

  @override
  Widget build(BuildContext context) {
    final cols = cells.isEmpty ? 0 : cells.first.length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < cols; c++) ...[
          if (c > 0) const SizedBox(width: 6),
          Expanded(
            child: DragTarget<_ColDrag>(
              onWillAcceptWithDetails: (d) => d.data.index != c,
              onAcceptWithDetails: (d) => onMove(d.data.index, c),
              builder: (context, candidate, _) {
                Widget column() => _glassGrab(
                  highlight: candidate.isNotEmpty,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var r = 0; r < cells.length; r++) ...[
                        if (r > 0) const SizedBox(height: 4),
                        _cellLabel(cells[r][c]),
                      ],
                    ],
                  ),
                );
                return Draggable<_ColDrag>(
                  data: _ColDrag(c),
                  rootOverlay: false,
                  feedback: Material(
                    color: Colors.transparent,
                    child: column(),
                  ),
                  childWhenDragging: Opacity(opacity: 0.28, child: column()),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: column(),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

Widget _glassGrab({required Widget child, bool highlight = false}) {
  final body = DragModeFrame.chip(child: child);
  if (!highlight) return body;
  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: AppColors.primary.withValues(alpha: 0.55),
        width: 1.5,
      ),
    ),
    child: body,
  );
}

Widget _cellLabel(String text) {
  return Container(
    constraints: const BoxConstraints(minHeight: 28),
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Text(
      text.isEmpty ? ' ' : text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.documentParagraphStyle.copyWith(fontSize: 13),
    ),
  );
}
