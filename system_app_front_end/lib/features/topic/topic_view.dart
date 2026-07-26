import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/topic.dart';
import '../../core/registry/topic_appearance.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/glass_surface.dart';
import '../../shared/widgets/files_section_divider.dart';
import '../../shared/widgets/main_pane_loader.dart';
import '../document/document_pane.dart';
import 'phone_topic_view.dart';

class TopicView extends StatelessWidget {
  const TopicView({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.loading &&
        state.selectedDetail == null &&
        state.selectedTopic == null) {
      return const MainPaneLoader();
    }

    if (state.error != null &&
        state.selectedDetail == null &&
        state.selectedTopic == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => state.initialize(),
              child: Text(state.strings['retry']),
            ),
          ],
        ),
      );
    }

    final detail = state.selectedDetail;
    if (detail == null && !state.topicDetailStale) {
      return Center(child: Text(state.strings['selectTopic']));
    }

    final topic = detail?.topic ?? state.selectedTopic;
    if (topic == null) {
      return Center(child: Text(state.strings['selectTopic']));
    }

    if (state.topicDetailStale) {
      return const MainPaneLoader();
    }

    final files = detail!.files;
    final essence = state.mainFilesFor(topic, files);
    final additionals = state.secondaryFilesFor(topic, files);
    final accent = TopicAppearance.colorFromHex(topic.color);

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final file in essence)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: DocumentPane(
                    topic: topic,
                    file: file,
                    state: state,
                    accent: accent,
                    onDelete: () => state.deleteFile(file),
                  ),
                ),
              if (essence.isNotEmpty && additionals.isNotEmpty)
                const FilesSectionDivider(),
              for (final file in additionals)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: DocumentPane(
                    topic: topic,
                    file: file,
                    state: state,
                    onDelete: () => state.deleteFile(file),
                  ),
                ),
              if (essence.isEmpty && additionals.isEmpty)
                Center(
                  child: TextButton.icon(
                    onPressed: () => _addFile(context, topic, isEssence: true),
                    icon: const Icon(Icons.note_add_outlined),
                    label: Text(state.strings['addFile'] ?? 'Add file'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addFile(
    BuildContext context,
    Topic topic, {
    required bool isEssence,
  }) async {
    await state.addFile(
      topic: topic,
      name: isEssence ? 'Essence' : 'Document',
      isEssence: isEssence,
    );
  }
}
