import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/topic.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_typography.dart';
import 'archive_file_preview.dart';

class ArchiveTopicView extends StatelessWidget {
  const ArchiveTopicView({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final topic = state.selectedArchiveTopic;
    if (topic == null) {
      return Center(child: Text(state.strings['selectTopic']));
    }

    final entry = state.archiveIndex.daily?.topic.id == topic.id
        ? state.archiveIndex.daily
        : state.archiveIndex.topics
            .where((e) => e.topic.id == topic.id)
            .firstOrNull;

    final files = entry?.files ?? const <AppFile>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
      children: [
        Text(
          state.topicDisplayName(topic),
          style: AppTypography.pageTitleStyle,
        ),
        const SizedBox(height: 16),
        if (files.isEmpty)
          Text(state.strings['archiveEmpty'] ?? 'No archived files.')
        else
          for (final file in files)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ArchiveFilePreview(state: state, file: file),
            ),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
