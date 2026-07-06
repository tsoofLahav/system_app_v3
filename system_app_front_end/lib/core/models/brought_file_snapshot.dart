import 'app_file.dart';
import 'block.dart';
import 'task.dart';
import 'topic.dart';

class BroughtFileSnapshot {
  const BroughtFileSnapshot({
    required this.sourceTopic,
    required this.file,
    required this.blocks,
    required this.tasksByBlockId,
  });

  final Topic sourceTopic;
  final AppFile file;
  final List<Block> blocks;
  final Map<int, List<Task>> tasksByBlockId;

  BroughtFileSnapshot copyWith({
    Topic? sourceTopic,
    AppFile? file,
    List<Block>? blocks,
    Map<int, List<Task>>? tasksByBlockId,
  }) {
    return BroughtFileSnapshot(
      sourceTopic: sourceTopic ?? this.sourceTopic,
      file: file ?? this.file,
      blocks: blocks ?? this.blocks,
      tasksByBlockId: tasksByBlockId ?? this.tasksByBlockId,
    );
  }
}
