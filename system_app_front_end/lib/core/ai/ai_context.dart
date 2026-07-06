import 'package:flutter/material.dart';

import '../text/line_range.dart';

enum AiSourceType { selection, line, task }

class AiFocus {
  const AiFocus({
    required this.fileId,
    this.blockId,
    required this.fullText,
    this.selection,
    this.isTaskInput = false,
  });

  final int fileId;
  final int? blockId;
  final String fullText;
  final TextSelection? selection;
  final bool isTaskInput;
}

class ResolvedAiContext {
  const ResolvedAiContext({
    required this.text,
    required this.sourceType,
    required this.topicId,
    this.fileId,
    this.blockId,
  });

  final String text;
  final AiSourceType sourceType;
  final int topicId;
  final int? fileId;
  final int? blockId;

  Map<String, dynamic> toJson() => {
        'text': text,
        'source_type': sourceType.name,
        if (fileId != null) 'file_id': fileId,
        if (blockId != null) 'block_id': blockId,
      };
}

String? _textFromSelection(String text, TextSelection? selection) {
  if (selection == null || !selection.isValid) return null;
  final range = LineRange.resolve(text, selection);
  if (!range.isValid) return null;
  final slice = text.substring(range.start, range.end).trim();
  return slice.isEmpty ? null : slice;
}

abstract final class AiContextResolver {
  static ResolvedAiContext? resolve({
    required int? topicId,
    required AiFocus? focus,
    required String? lastTaskTitle,
    required int? lastTaskFileId,
  }) {
    if (topicId == null) return null;

    if (focus != null && focus.selection != null) {
      final selected = _textFromSelection(focus.fullText, focus.selection);
      if (selected != null) {
        final sourceType = focus.selection!.isCollapsed
            ? AiSourceType.line
            : AiSourceType.selection;
        return ResolvedAiContext(
          text: selected,
          sourceType: sourceType,
          topicId: topicId,
          fileId: focus.fileId,
          blockId: focus.blockId,
        );
      }
    }

    if (lastTaskTitle != null && lastTaskTitle.trim().isNotEmpty) {
      return ResolvedAiContext(
        text: lastTaskTitle.trim(),
        sourceType: AiSourceType.task,
        topicId: topicId,
        fileId: lastTaskFileId,
      );
    }

    return null;
  }
}
