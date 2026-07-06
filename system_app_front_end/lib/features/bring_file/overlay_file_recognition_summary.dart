import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../config/api_config.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../blocks/graph_content.dart';
import 'bring_file_preview.dart';

/// Compact, card-native summary for quick file recognition in overlay pickers.
class OverlayFileRecognitionSummary extends StatelessWidget {
  const OverlayFileRecognitionSummary({
    super.key,
    required this.preview,
    required this.loaded,
    required this.strings,
  });

  final OverlayFilePreviewData? preview;
  final bool loaded;
  final AppStrings strings;

  static const _maxLines = 4;

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return _message(strings['bringFilePreviewLoading']);
    }

    final data = preview;
    if (data == null || data.isEmpty) {
      return _message(strings['bringFilePreviewEmpty']);
    }

    final content = _extractRecognitionContent(
      blocks: data.blocks,
      tasksByBlockId: data.tasksByBlockId,
    );
    if (!content.hasContent) {
      return _message(strings['bringFilePreviewEmpty']);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (content.hero != null) ...[
              _RecognitionHero(hero: content.hero!),
              if (content.lines.isNotEmpty) const SizedBox(height: 6),
            ],
            if (content.lines.isNotEmpty)
              Expanded(
                child: ClipRect(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: content.lines.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      return _RecognitionLineText(line: content.lines[index]);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _message(String text) {
    return Align(
      alignment: Alignment.topLeft,
      child: Text(
        text,
        style: AppTypography.metaStyle.copyWith(
          color: AppColors.noteHint.withValues(alpha: 0.78),
          fontSize: 11,
        ),
      ),
    );
  }
}

class _RecognitionContent {
  const _RecognitionContent({this.hero, this.lines = const []});

  final _RecognitionHeroData? hero;
  final List<_RecognitionLine> lines;

  bool get hasContent => hero != null || lines.isNotEmpty;
}

class _RecognitionHeroData {
  const _RecognitionHeroData.image(this.imageUrl)
      : kind = _RecognitionHeroKind.image,
        boardColor = null,
        graphLabels = null,
        graphValues = null,
        graphColors = null,
        tableRows = null;

  const _RecognitionHeroData.board(this.boardColor)
      : kind = _RecognitionHeroKind.board,
        imageUrl = null,
        graphLabels = null,
        graphValues = null,
        graphColors = null,
        tableRows = null;

  const _RecognitionHeroData.graph({
    required this.graphLabels,
    required this.graphValues,
    required this.graphColors,
  })  : kind = _RecognitionHeroKind.graph,
        imageUrl = null,
        boardColor = null,
        tableRows = null;

  const _RecognitionHeroData.table(this.tableRows)
      : kind = _RecognitionHeroKind.table,
        imageUrl = null,
        boardColor = null,
        graphLabels = null,
        graphValues = null,
        graphColors = null;

  final _RecognitionHeroKind kind;
  final String? imageUrl;
  final Color? boardColor;
  final List<String>? graphLabels;
  final List<double>? graphValues;
  final List<Color>? graphColors;
  final List<List<String>>? tableRows;
}

enum _RecognitionHeroKind { image, board, graph, table }

enum _RecognitionLineKind { lead, body, bullet }

class _RecognitionLine {
  const _RecognitionLine({required this.kind, required this.text});

  final _RecognitionLineKind kind;
  final String text;
}

_RecognitionContent _extractRecognitionContent({
  required List<Block> blocks,
  required Map<int, List<Task>> tasksByBlockId,
}) {
  _RecognitionHeroData? hero;
  final lines = <_RecognitionLine>[];
  var leadUsed = false;

  void addLine(_RecognitionLineKind kind, String raw) {
    if (lines.length >= OverlayFileRecognitionSummary._maxLines) return;
    final text = raw.trim();
    if (text.isEmpty) return;
    lines.add(_RecognitionLine(kind: kind, text: text));
  }

  for (final block in blocks.take(overlayFilePreviewMaxBlocks)) {
    if (hero == null) {
      hero = _heroFromBlock(block);
    }

    switch (block.type) {
      case 'header':
        if (!leadUsed) {
          addLine(_RecognitionLineKind.lead, block.text);
          leadUsed = true;
        }
      case 'text':
      case 'summary':
        for (final part in block.text.split('\n')) {
          addLine(_RecognitionLineKind.body, part);
          if (lines.length >= OverlayFileRecognitionSummary._maxLines) break;
        }
      case 'task_list':
        for (final task in tasksByBlockId[block.id] ?? const <Task>[]) {
          addLine(_RecognitionLineKind.bullet, task.title);
          if (lines.length >= OverlayFileRecognitionSummary._maxLines) break;
        }
      case 'list':
        for (final item in _listItems(block.content['items'])) {
          addLine(_RecognitionLineKind.bullet, item);
          if (lines.length >= OverlayFileRecognitionSummary._maxLines) break;
        }
      case 'checklist':
        for (final item in _checklistItems(block.content['items'])) {
          final prefix = item.done ? '☑ ' : '☐ ';
          addLine(_RecognitionLineKind.bullet, '$prefix${item.text}');
          if (lines.length >= OverlayFileRecognitionSummary._maxLines) break;
        }
      case 'measurement':
        addLine(
          _RecognitionLineKind.body,
          '${block.content['label'] ?? ''}: ${block.content['value'] ?? ''} ${block.content['unit'] ?? ''}',
        );
      default:
        break;
    }

    if (lines.length >= OverlayFileRecognitionSummary._maxLines &&
        hero != null) {
      break;
    }
  }

  return _RecognitionContent(hero: hero, lines: lines);
}

_RecognitionHeroData? _heroFromBlock(Block block) {
  switch (block.type) {
    case 'image':
      final path = block.content['image_path'] as String? ?? '';
      if (path.isEmpty) return null;
      final url = path.startsWith('http') ? path : '${ApiConfig.baseUrl}$path';
      return _RecognitionHeroData.image(url);
    case 'board':
      return _RecognitionHeroData.board(_boardColor(block.content['background_color']));
    case 'graph':
      final labels = graphLabels(block.content);
      final values = graphValues(block.content, labels.length);
      if (values.every((v) => v <= 0)) return null;
      return _RecognitionHeroData.graph(
        graphLabels: labels.take(4).toList(),
        graphValues: values.take(4).toList(),
        graphColors: graphColumnColors(block.content, labels.length).take(4).toList(),
      );
    case 'table':
      final rows = _tableRows(block.content['rows']);
      if (rows.isEmpty) return null;
      return _RecognitionHeroData.table(rows.take(2).toList());
    default:
      return null;
  }
}

List<String> _listItems(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map)
        item['text']?.toString() ?? ''
      else
        item?.toString() ?? '',
  ].where((line) => line.trim().isNotEmpty).toList();
}

List<({String text, bool done})> _checklistItems(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map)
        (
          text: item['text']?.toString() ?? '',
          done: item['done'] == true,
        ),
  ].where((item) => item.text.trim().isNotEmpty).toList();
}

List<List<String>> _tableRows(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final row in raw)
      if (row is List)
        [
          for (final cell in row.take(3))
            cell?.toString().trim() ?? '',
        ].where((cell) => cell.isNotEmpty).toList()
      else
        [row.toString().trim()],
  ].where((row) => row.isNotEmpty).toList();
}

Color _boardColor(Object? value) {
  if (value is int) return Color(value);
  return AppColors.noteTop;
}

class _RecognitionHero extends StatelessWidget {
  const _RecognitionHero({required this.hero});

  final _RecognitionHeroData hero;

  @override
  Widget build(BuildContext context) {
    return switch (hero.kind) {
      _RecognitionHeroKind.image => ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: Image.network(
              hero.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stackTrace) => _heroFallback(
                Icons.image_outlined,
              ),
            ),
          ),
        ),
      _RecognitionHeroKind.board => ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 40,
            width: double.infinity,
            color: hero.boardColor,
            alignment: Alignment.center,
            child: Icon(
              Icons.dashboard_outlined,
              size: 18,
              color: AppColors.text.withValues(alpha: 0.3),
            ),
          ),
        ),
      _RecognitionHeroKind.graph => _GraphHero(
          labels: hero.graphLabels!,
          values: hero.graphValues!,
          colors: hero.graphColors!,
        ),
      _RecognitionHeroKind.table => _TableHero(rows: hero.tableRows!),
    };
  }

  Widget _heroFallback(IconData icon) {
    return ColoredBox(
      color: AppColors.noteBorder.withValues(alpha: 0.2),
      child: Center(
        child: Icon(
          icon,
          size: 18,
          color: AppColors.noteHint.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}

class _GraphHero extends StatelessWidget {
  const _GraphHero({
    required this.labels,
    required this.values,
    required this.colors,
  });

  final List<String> labels;
  final List<double> values;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<double>(0, (a, b) => a > b ? a : b);
    if (maxValue <= 0) return const SizedBox.shrink();

    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
                child: Container(
                  height: (values[i] / maxValue) * 28,
                  decoration: BoxDecoration(
                    color: colors[i % colors.length].withValues(alpha: 0.88),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TableHero extends StatelessWidget {
  const _TableHero({required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final columnCount = rows
        .map((row) => row.length)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: {
          for (var i = 0; i < columnCount; i++) i: const FlexColumnWidth(),
        },
        children: [
          for (final row in rows)
            TableRow(
              children: [
                for (var i = 0; i < columnCount; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Text(
                      i < row.length ? row[i] : '',
                      style: AppTypography.metaStyle.copyWith(
                        fontSize: 10,
                        color: AppColors.text.withValues(alpha: 0.82),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RecognitionLineText extends StatelessWidget {
  const _RecognitionLineText({required this.line});

  final _RecognitionLine line;

  @override
  Widget build(BuildContext context) {
    final style = switch (line.kind) {
      _RecognitionLineKind.lead => AppTypography.metaStyle.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.text.withValues(alpha: 0.9),
          height: 1.3,
        ),
      _RecognitionLineKind.bullet => AppTypography.metaStyle.copyWith(
          fontSize: 11,
          color: AppColors.text.withValues(alpha: 0.78),
          height: 1.35,
        ),
      _RecognitionLineKind.body => AppTypography.metaStyle.copyWith(
          fontSize: 11,
          color: AppColors.text.withValues(alpha: 0.74),
          height: 1.35,
        ),
    };

    return Text(
      line.kind == _RecognitionLineKind.bullet ? '• ${line.text}' : line.text,
      style: style,
      maxLines: line.kind == _RecognitionLineKind.lead ? 1 : 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
