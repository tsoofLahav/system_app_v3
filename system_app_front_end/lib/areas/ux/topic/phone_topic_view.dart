import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../create_topic/add_file_dialog.dart';
import '../../files/editor/document_pane.dart';

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
          OutlinedButton(
            onPressed: () async {
              final result = await showAddFileDialog(
                context: context,
                state: state,
                topic: topic,
              );
              if (result == null) return;
              await state.addFile(
                topic: topic,
                name: result.name,
                isEssence: result.isEssence,
              );
            },
            child: Text(state.strings['addFile']),
          ),
      ],
    );
  }
}
