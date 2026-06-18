import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/topic.dart';
import '../../design_system/file_layouts.dart';
import 'file_section.dart';

class FileLayoutBoard extends StatelessWidget {
  const FileLayoutBoard({
    super.key,
    required this.topic,
    required this.files,
    required this.layoutId,
    required this.state,
    required this.accent,
    required this.onDeleteFile,
  });

  final Topic topic;
  final List<AppFile> files;
  final String layoutId;
  final AppState state;
  final Color accent;
  final void Function(AppFile file) onDeleteFile;

  @override
  Widget build(BuildContext context) {
    final layout = FileLayouts.byId(layoutId);
    final detail = state.selectedDetail!;

    Widget slotAt(int fileIndex) {
      final file = files[fileIndex];
      return SizedBox.expand(
        child: FileSection(
          topic: topic,
          file: file,
          blocks: detail.blocksByFileId[file.id] ?? [],
          state: state,
          accent: accent,
          onDelete: () => onDeleteFile(file),
        ),
      );
    }

    final fixedCapacity = FileLayouts.fixedCapacityFor(layout.id);
    final primaryCount = fixedCapacity != null
        ? fixedCapacity.clamp(0, files.length)
        : files.length;

    final slots = List.generate(primaryCount, slotAt);
    final primary = layout.builder(context, slots);

    final overflowStart = fixedCapacity ?? files.length;
    final overflow = files.length > overflowStart
        ? Padding(
            padding: const EdgeInsets.only(top: AppLayoutSpacing.gap),
            child: Wrap(
              spacing: AppLayoutSpacing.gap,
              runSpacing: AppLayoutSpacing.gap,
              children: [
                for (var i = overflowStart; i < files.length; i++)
                  SizedBox(width: 280, height: 240, child: slotAt(i)),
              ],
            ),
          )
        : const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [primary, overflow],
    );
  }
}
