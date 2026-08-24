import 'package:flutter/material.dart';

import '../../../config/api_config.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../model/agent_text_blocks.dart';
import './embeds/table_chart.dart';

/// How one element of the document should be dressed.
///
/// The view itself knows nothing about diffs: a caller hands back a decoration
/// per source-line range, which is how the review dialog paints its changes.
class LineDecoration {
  const LineDecoration({
    this.tint,
    this.barColor,
    this.mark,
    this.markColor,
    this.opacity = 1,
    this.strikethrough = false,
    this.anchorKey,
    this.onTap,
    this.spanFor,
  });

  static const none = LineDecoration();

  final Color? tint;

  /// Left rule, used for the change the reviewer is standing on.
  final Color? barColor;

  /// Small glyph in the leading gutter (a decided change).
  final IconData? mark;
  final Color? markColor;
  final double opacity;
  final bool strikethrough;

  /// Attach to reach this element with `Scrollable.ensureVisible` or measure it.
  final GlobalKey? anchorKey;
  final VoidCallback? onTap;

  /// Word-level marks for one line of text.
  final InlineSpan Function(String text)? spanFor;

  bool get isPlain =>
      tint == null &&
      barColor == null &&
      mark == null &&
      opacity == 1 &&
      !strikethrough &&
      anchorKey == null &&
      onTap == null;
}

typedef LineDecorator = LineDecoration Function(int lineStart, int lineEnd);

LineDecoration _noDecoration(int lineStart, int lineEnd) => LineDecoration.none;

/// Draws agent-text blocks the way the file reads — headings, lists and real
/// embeds — with no editing, no focus nodes and no `AppState`.
class ReadOnlyDocumentView extends StatelessWidget {
  const ReadOnlyDocumentView({
    super.key,
    required this.blocks,
    this.decorate = _noDecoration,
  });

  final List<AgentBlock> blocks;
  final LineDecorator decorate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in blocks) _buildBlock(context, block),
      ],
    );
  }

  Widget _buildBlock(BuildContext context, AgentBlock block) {
    return switch (block) {
      AgentHeadingBlock() => _line(
          block.lineStart,
          block.lineEnd,
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 2),
            child: _text(
              block.text,
              AppTypography.documentHeadingStyle(block.level),
              block.lineStart,
              block.lineEnd,
            ),
          ),
        ),
      AgentParagraphBlock() => _line(
          block.lineStart,
          block.lineEnd,
          _text(
            block.text,
            AppTypography.documentParagraphStyle,
            block.lineStart,
            block.lineEnd,
          ),
        ),
      AgentSpacerBlock() => SizedBox(height: 6.0 * block.count.clamp(1, 6)),
      AgentListBlock() => _list(block),
      AgentTaskListBlock() => _embedCard(block.lineStart, block.lineEnd, _tasks(block)),
      AgentInfoBlock() => _embedCard(block.lineStart, block.lineEnd, _info(block)),
      AgentTableBlock() => _embedCard(block.lineStart, block.lineEnd, _table(block)),
      AgentGraphBlock() =>
        _embedCard(block.lineStart, block.lineEnd, _graph(context, block)),
      AgentImageBlock() => _embedCard(block.lineStart, block.lineEnd, _image(block)),
      AgentUnknownBlock() => _line(
          block.lineStart,
          block.lineEnd,
          block.isMarker
              ? _structureRule()
              : _text(
                  block.text,
                  AppTypography.documentParagraphStyle
                      .copyWith(color: AppColors.textHint),
                  block.lineStart,
                  block.lineEnd,
                ),
        ),
    };
  }

  Widget _text(String text, TextStyle style, int lineStart, int lineEnd) {
    final d = decorate(lineStart, lineEnd);
    final resolved = d.strikethrough
        ? style.copyWith(decoration: TextDecoration.lineThrough)
        : style;
    final span = d.spanFor;
    if (span == null) {
      return Text(text.isEmpty ? ' ' : text, style: resolved);
    }
    return Text.rich(span(text), style: resolved);
  }

  /// Wrap one element in its decoration: tint, active rule, decided glyph.
  Widget _line(int lineStart, int lineEnd, Widget child) {
    final d = decorate(lineStart, lineEnd);
    Widget body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: child,
    );
    if (d.opacity != 1) {
      body = Opacity(opacity: d.opacity, child: body);
    }

    Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 14,
          child: d.mark == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(d.mark, size: 11, color: d.markColor),
                ),
        ),
        Expanded(child: body),
      ],
    );

    row = DecoratedBox(
      decoration: BoxDecoration(
        color: d.tint,
        borderRadius: BorderRadius.circular(4),
        border: d.barColor == null
            ? null
            : Border(left: BorderSide(color: d.barColor!, width: 2)),
      ),
      child: row,
    );

    if (d.onTap != null) {
      row = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: d.onTap,
        child: row,
      );
    }
    return KeyedSubtree(key: d.anchorKey, child: row);
  }

  /// Embed chrome: the quiet card an object sits in inside a file.
  Widget _embedCard(int lineStart, int lineEnd, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: _line(
        lineStart,
        lineEnd,
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.noteTop.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.noteBorder.withValues(alpha: 0.7)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _list(AgentListBlock block) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in block.items)
          _line(
            item.line,
            item.line,
            Padding(
              padding: EdgeInsets.only(left: 8 + item.indent * 14.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: block.ordered ? 20 : 12,
                    child: Text(item.marker, style: AppTypography.listItemStyle),
                  ),
                  Expanded(
                    child: _text(
                      item.text,
                      AppTypography.listItemStyle,
                      item.line,
                      item.line,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _tasks(AgentTaskListBlock block) {
    if (block.tasks.isEmpty) {
      return Text('No tasks', style: AppTypography.metaStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final task in block.tasks)
          _line(
            task.line,
            task.line,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6),
                  child: _taskBox(task.done),
                ),
                Expanded(
                  child: _text(
                    task.title,
                    task.done
                        ? AppTypography.taskRowStyle.copyWith(
                            color: AppColors.textHint,
                            decoration: TextDecoration.lineThrough,
                          )
                        : AppTypography.taskRowStyle,
                    task.line,
                    task.line,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _info(AgentInfoBlock block) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (block.titleLine >= 0)
          _line(
            block.titleLine,
            block.titleLine,
            _text(
              block.title,
              AppTypography.blockHeaderStyle,
              block.titleLine,
              block.titleLine,
            ),
          ),
        for (final body in block.bodyLines)
          _line(
            body.line,
            body.line,
            _text(
              body.text,
              AppTypography.noteBodyStyle,
              body.line,
              body.line,
            ),
          ),
      ],
    );
  }

  Widget _table(AgentTableBlock block) {
    if (block.rows.isEmpty) {
      return Text('Empty table', style: AppTypography.metaStyle);
    }
    final columns = block.columnCount;
    final border = BorderSide(
      color: AppColors.noteBorder.withValues(alpha: 0.8),
      width: 0.5,
    );
    return Table(
      border: TableBorder(
        horizontalInside: border,
        verticalInside: border,
      ),
      defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
      children: [
        for (final row in block.rows) _tableRow(row, columns),
      ],
    );
  }

  TableRow _tableRow(AgentTableRow row, int columns) {
    final d = decorate(row.line, row.line);
    final cells = <Widget>[];
    for (var c = 0; c < columns; c++) {
      final text = c < row.cells.length ? row.cells[c] : '';
      Widget cell = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: _text(
          text,
          AppTypography.noteBodyStyle,
          row.line,
          row.line,
        ),
      );
      if (d.opacity != 1) cell = Opacity(opacity: d.opacity, child: cell);
      if (c == 0) {
        cell = KeyedSubtree(key: d.anchorKey, child: cell);
        if (d.mark != null) {
          cell = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 4),
                child: Icon(d.mark, size: 11, color: d.markColor),
              ),
              Expanded(child: cell),
            ],
          );
        }
      }
      cells.add(cell);
    }
    Widget wrap(Widget child) => d.onTap == null
        ? child
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: d.onTap,
            child: child,
          );
    return TableRow(
      decoration: BoxDecoration(
        color: d.tint,
        border: d.barColor == null
            ? null
            : Border(left: BorderSide(color: d.barColor!, width: 2)),
      ),
      children: [for (final cell in cells) wrap(cell)],
    );
  }

  Widget _graph(BuildContext context, AgentGraphBlock block) {
    final values = <double>[];
    for (final raw in block.values) {
      values.add(double.tryParse(raw.trim()) ?? 0);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TableChartView(
          type: block.chartType.isEmpty ? 'bar' : block.chartType,
          values: values,
          labels: block.labels,
          colors: [for (final raw in block.colors) _parseHex(raw)],
          textDirection: Directionality.of(context),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 10,
          runSpacing: 2,
          children: [
            for (var i = 0; i < block.labels.length; i++)
              Text(
                '${block.labels[i]}'
                '${i < block.values.length ? ' · ${block.values[i]}' : ''}',
                style: AppTypography.metaStyle,
              ),
          ],
        ),
      ],
    );
  }

  Widget _image(AgentImageBlock block) {
    final url = block.url.isEmpty
        ? null
        : (block.url.startsWith('http')
            ? block.url
            : '${ApiConfig.baseUrl}${block.url}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              url,
              height: 96,
              fit: BoxFit.contain,
              errorBuilder: (_, error, stack) =>
                  Icon(AppIcons.image, size: 18, color: AppColors.textHint),
            ),
          )
        else
          Icon(AppIcons.image, size: 18, color: AppColors.textHint),
        if (block.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(block.caption, style: AppTypography.metaStyle),
          ),
      ],
    );
  }
}

/// Stands in for a structure marker: the line is there and can be reviewed,
/// but the reader sees a boundary rather than `[BULLET_LIST]`.
Widget _structureRule() {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Container(
      height: 2,
      width: 28,
      decoration: BoxDecoration(
        color: AppColors.textHint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// The task mark as [TaskMark] draws it, minus the tap target.
Widget _taskBox(bool done) {
  const size = 13.0;
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * 0.15),
      color: done
          ? AppColors.aiCyan.withValues(alpha: 0.14)
          : Colors.transparent,
      border: Border.all(
        color: done
            ? AppColors.aiCyan.withValues(alpha: 0.65)
            : AppColors.noteBorder.withValues(alpha: 0.85),
      ),
    ),
    child: done
        ? Icon(
            AppIcons.check,
            size: size - 4,
            color: AppColors.aiCyan.withValues(alpha: 0.92),
          )
        : null,
  );
}

Color _parseHex(String raw) {
  final hex = raw.trim().replaceFirst('#', '');
  if (hex.length != 6) return AppColors.primary;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? AppColors.primary : Color(0xFF000000 | value);
}
