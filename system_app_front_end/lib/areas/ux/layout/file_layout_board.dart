import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../files/data/app_file.dart';
import '../../files/data/topic.dart';
import '../../files/editor/document_pane.dart';
import '../topic/topic_appearance.dart';
import './file_layouts.dart';
import './topic_file_slots.dart';

/// Draws a topic's files in the shape the user chose.
///
/// It is handed the files that fit — deciding which those are belongs to
/// [shownFiles]. Every slot is a fixed rectangle, so each pane scrolls its own
/// document instead of stretching the canvas.
class FileLayoutBoard extends StatelessWidget {
  const FileLayoutBoard({
    super.key,
    required this.topic,
    required this.files,
    required this.layoutId,
    required this.state,
    required this.onDeleteFile,
    this.slotHeight,
  });

  final Topic topic;
  final List<AppFile> files;
  final String layoutId;
  final AppState state;
  final void Function(AppFile file) onDeleteFile;

  /// Height for the layouts that fill the viewport. `row` and `grid` size
  /// their own rectangles and ignore it.
  final double? slotHeight;

  @override
  Widget build(BuildContext context) {
    final layout = FileLayouts.byId(effectiveLayoutId(layoutId, files.length));

    final slots = [
      for (final file in files)
        SizedBox.expand(
          child: DocumentPane(
            key: ValueKey(
              state.isBroughtFileOnCanvas(topic, file.id)
                  ? 'brought-${file.id}'
                  : file.id,
            ),
            topic: state.canvasTopicFor(topic, file),
            file: file,
            state: state,
            accent: TopicAppearance.accentFor(state.canvasTopicFor(topic, file)),
            isBrought: state.isBroughtFileOnCanvas(topic, file.id),
            onDelete: () => onDeleteFile(file),
          ),
        ),
    ];

    final board = layout.builder(context, slots);
    if (slotHeight == null || layout.fixedCapacity == null) return board;
    return SizedBox(height: slotHeight, child: board);
  }
}
