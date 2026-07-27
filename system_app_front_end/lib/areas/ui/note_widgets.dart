import 'package:flutter/material.dart';

import './app_colors.dart';

/// Main-pane wrapper. Canvas gradient is painted once by [AppShell] so sidebar
/// and content share a single continuous background.
class TopicCanvasBackground extends StatelessWidget {
  const TopicCanvasBackground({
    super.key,
    required this.child,
    this.accent,
    this.isMain,
  });

  final Widget child;

  /// Kept for call-site stability; canvas is always neutral.
  final Color? accent;
  final bool? isMain;

  @override
  Widget build(BuildContext context) => child;
}

/// A file's surface. Given a topic accent it wears that topic's color, at a
/// strength fixed per file — see [AppColors.fileTintStrength].
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.child,
    this.topicAccent,
    this.fileId,
    this.isMainTopic = false,
  });

  final Widget child;
  final Color? topicAccent;
  final int? fileId;
  final bool isMainTopic;

  @override
  Widget build(BuildContext context) {
    final decoration = topicAccent != null && fileId != null
        ? AppColors.filePaneDecoration(
            topicAccent!,
            fileId!,
            isMainTopic: isMainTopic,
          )
        : AppColors.noteDecoration();

    return DecoratedBox(
      decoration: decoration,
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
    );
  }
}
