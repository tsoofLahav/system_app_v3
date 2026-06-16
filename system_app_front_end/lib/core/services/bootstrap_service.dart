import '../models/topic.dart';
import '../registry/file_behavior_registry.dart';
import '../registry/file_registry.dart';
import '../registry/topic_appearance.dart';
import 'block_service.dart';
import 'file_service.dart';
import 'topic_service.dart';

class BootstrapService {
  BootstrapService({
    required TopicService topicService,
    required FileService fileService,
    required BlockService blockService,
  }) : _topics = topicService,
       _files = fileService,
       _blocks = blockService;

  final TopicService _topics;
  final FileService _files;
  final BlockService _blocks;

  Future<Topic> ensureMainTopic() async {
    final all = await _topics.listTopics();
    final existing = all.where((t) => t.isMain).toList();
    if (existing.isNotEmpty) {
      await _ensureDailyFile(existing.first);
      return existing.first;
    }

    final topic = await _topics.createTopic(
      name: FileRegistry.mainTopicName,
      type: 'area',
      icon: 'home',
      color: TopicAppearance.defaultColor,
    );
    await _ensureDailyFile(topic);
    return topic;
  }

  Future<void> _ensureDailyFile(Topic topic) async {
    final files = await _files.listForTopic(topic.id);
    final daily = files.where((f) => f.type == 'main').toList();
    if (daily.isEmpty) {
      final file = await _files.createFile(
        topicId: topic.id,
        name: 'Daily',
        type: 'main',
        orderIndex: 0,
        isMain: true,
      );
      final defaults = FileBehaviorRegistry.defaultBlocksForFileType(file.type);
      for (var i = 0; i < defaults.length; i++) {
        final spec = defaults[i];
        await _blocks.createBlock(
          fileId: file.id,
          type: spec.type,
          content: spec.content,
          orderIndex: i,
        );
      }
    }
  }
}
