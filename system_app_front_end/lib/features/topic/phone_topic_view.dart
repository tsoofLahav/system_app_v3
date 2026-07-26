import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/topic.dart';
import '../../design_system/app_typography.dart';
import '../document/document_pane.dart';

class PhoneTopicView extends StatelessWidget {
  const PhoneTopicView({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final detail = state.selectedDetail;
    final topic = detail?.topic ?? state.selectedTopic;
    if (topic == null || detail == null) {
      return Center(child: Text(state.strings['selectTopic']));
    }

    final files = [...detail.files]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        for (final file in files)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DocumentPane(
              topic: topic,
              file: file,
              state: state,
              onDelete: () => state.deleteFile(file),
            ),
          ),
        if (files.isEmpty)
          TextButton(
            onPressed: () => state.addFile(topic: topic, name: 'Document', isEssence: true),
            child: Text(state.strings['addFile'] ?? 'Add file'),
          ),
      ],
    );
  }
}
