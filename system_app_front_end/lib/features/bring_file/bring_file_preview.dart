import '../../core/models/app_file.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';

const bringFilePreviewMaxLines = 4;

List<String> previewLinesFromBlocks(
  List<Block> blocks, {
  int maxLines = bringFilePreviewMaxLines,
}) {
  final lines = <String>[];

  void addLine(String line) {
    if (line.isEmpty || lines.length >= maxLines) return;
    lines.add(line);
  }

  for (final block in blocks) {
    if (lines.length >= maxLines) break;
    switch (block.type) {
      case 'header':
        addLine(block.text.trim());
      case 'text':
      case 'summary':
        for (final part in block.text.split('\n')) {
          addLine(part.trim());
          if (lines.length >= maxLines) break;
        }
      default:
        continue;
    }
  }

  return lines;
}

Future<List<String>> previewLinesForFile(
  AppFile file,
  List<Block> blocks,
  Future<List<Task>> Function(int blockId) tasksForBlock,
) async {
  final lines = previewLinesFromBlocks(blocks);
  if (lines.isNotEmpty) return lines;

  for (final block in blocks) {
    if (block.type != 'task_list') continue;
    final tasks = await tasksForBlock(block.id);
    for (final task in tasks) {
      if (lines.length >= bringFilePreviewMaxLines) break;
      final title = task.title.trim();
      if (title.isNotEmpty) lines.add('• $title');
    }
    if (lines.isNotEmpty) break;
  }

  return lines;
}
