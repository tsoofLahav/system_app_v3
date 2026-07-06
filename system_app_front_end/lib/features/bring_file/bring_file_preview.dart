import '../../core/models/block.dart';
import '../../core/models/task.dart';

/// Blocks + task data used to render a read-only mini snapshot in overlay cards.
class OverlayFilePreviewData {
  const OverlayFilePreviewData({
    required this.blocks,
    required this.tasksByBlockId,
  });

  final List<Block> blocks;
  final Map<int, List<Task>> tasksByBlockId;

  bool get isEmpty => blocks.isEmpty;

  static const empty = OverlayFilePreviewData(
    blocks: [],
    tasksByBlockId: {},
  );
}

/// How many top blocks to load tasks for and render in overlay snapshots.
const overlayFilePreviewMaxBlocks = 8;

Future<OverlayFilePreviewData> previewDataForFile(
  List<Block> blocks,
  Future<List<Task>> Function(int blockId) tasksForBlock,
) async {
  final previewBlocks = blocks.take(overlayFilePreviewMaxBlocks).toList();
  final tasksByBlockId = <int, List<Task>>{};

  for (final block in previewBlocks) {
    if (block.type != 'task' && block.type != 'task_list') continue;
    tasksByBlockId[block.id] = await tasksForBlock(block.id);
  }

  return OverlayFilePreviewData(
    blocks: blocks,
    tasksByBlockId: tasksByBlockId,
  );
}
