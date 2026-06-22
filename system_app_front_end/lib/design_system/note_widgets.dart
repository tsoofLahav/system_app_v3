import 'package:flutter/material.dart';

import 'app_colors.dart';

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
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: AppColors.neutralCanvasGradient,
      ),
      child: child,
    );
  }
}

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.child,
    this.topicAccent,
    this.fileType,
    this.isMainTopic = false,
  });

  final Widget child;
  final Color? topicAccent;
  final String? fileType;
  final bool isMainTopic;

  @override
  Widget build(BuildContext context) {
    final decoration = topicAccent != null && fileType != null
        ? AppColors.filePaneDecoration(
            topicAccent!,
            fileType!,
            isMainTopic: isMainTopic,
          )
        : AppColors.noteDecoration();

    return DecoratedBox(
      decoration: decoration,
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
    );
  }
}
