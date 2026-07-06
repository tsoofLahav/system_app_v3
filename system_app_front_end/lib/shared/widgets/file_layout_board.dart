import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/brought_file_snapshot.dart';
import '../../core/models/topic.dart';
import '../../design_system/file_layouts.dart';
import '../../features/bring_file/brought_file_slot.dart';
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
    this.slotHeight,
    this.broughtFile,
  });

  final Topic topic;
  final List<AppFile> files;
  final String layoutId;
  final AppState state;
  final Color accent;
  final void Function(AppFile file) onDeleteFile;
  final double? slotHeight;
  final BroughtFileSnapshot? broughtFile;

  @override
  Widget build(BuildContext context) {
    final layout = FileLayouts.byId(layoutId);
    final detail = state.selectedDetail!;

    Widget slotForFile(AppFile file) {
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

    final slots = <Widget>[];
    final guestSlot = broughtFileLayoutSlot(state: state, snapshot: broughtFile);
    if (guestSlot != null) {
      slots.add(SizedBox.expand(child: guestSlot));
    }
    for (final file in files) {
      slots.add(slotForFile(file));
    }

    final fixedCapacity = FileLayouts.fixedCapacityFor(layout.id);
    final primaryCount = fixedCapacity != null
        ? fixedCapacity.clamp(0, slots.length)
        : slots.length;

    final primarySlots = List.generate(primaryCount, (i) => slots[i]);
    final primary = layout.builder(context, primarySlots);
    final sizedPrimary = slotHeight != null
        ? SizedBox(height: slotHeight, child: primary)
        : primary;

    final overflowStart = fixedCapacity ?? slots.length;
    final overflow = slots.length > overflowStart
        ? Padding(
            padding: const EdgeInsets.only(top: AppLayoutSpacing.gap),
            child: Wrap(
              spacing: AppLayoutSpacing.gap,
              runSpacing: AppLayoutSpacing.gap,
              children: [
                for (var i = overflowStart; i < slots.length; i++)
                  SizedBox(width: 280, height: 240, child: slots[i]),
              ],
            ),
          )
        : const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [sizedPrimary, overflow],
    );
  }
}
