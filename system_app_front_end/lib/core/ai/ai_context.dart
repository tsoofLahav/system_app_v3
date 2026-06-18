import 'package:flutter/material.dart';

enum AiSourceType { selection, paragraph, task }

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

String? _selectedSubstring(String text, TextSelection? selection) {
  if (selection == null || !selection.isValid || selection.isCollapsed) {
    return null;
  }
  final start = selection.start.clamp(0, text.length);
  final end = selection.end.clamp(0, text.length);
  if (start >= end) return null;
  final slice = text.substring(start, end).trim();
  return slice.isEmpty ? null : slice;
}

String? _lastParagraph(String text) {
  final parts = text.split(RegExp(r'\n\s*\n'));
  for (var i = parts.length - 1; i >= 0; i--) {
    final p = parts[i].trim();
    if (p.isNotEmpty) return p;
  }
  final lines = text.trim();
  return lines.isEmpty ? null : lines;
}

abstract final class AiContextResolver {
  static ResolvedAiContext? resolve({
    required int? topicId,
    required AiFocus? focus,
    required String? lastTaskTitle,
    required int? lastTaskFileId,
  }) {
    if (topicId == null) return null;

    if (focus != null) {
      final selected = _selectedSubstring(focus.fullText, focus.selection);
      if (selected != null) {
        return ResolvedAiContext(
          text: selected,
          sourceType: AiSourceType.selection,
          topicId: topicId,
          fileId: focus.fileId,
          blockId: focus.blockId,
        );
      }

      if (!focus.isTaskInput && focus.fullText.trim().isNotEmpty) {
        final paragraph = _lastParagraph(focus.fullText);
        if (paragraph != null) {
          return ResolvedAiContext(
            text: paragraph,
            sourceType: AiSourceType.paragraph,
            topicId: topicId,
            fileId: focus.fileId,
            blockId: focus.blockId,
          );
        }
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
