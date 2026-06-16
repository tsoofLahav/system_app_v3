import 'package:flutter/material.dart';

import 'app_colors.dart';

class TopicCanvasBackground extends StatelessWidget {
  const TopicCanvasBackground({
    super.key,
    required this.accent,
    required this.isMain,
    required this.child,
  });

  final Color accent;
  final bool isMain;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.topicCanvasGradient(accent, isMain: isMain),
      ),
      child: child,
    );
  }
}

class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: AppColors.noteDecoration(accent: accent),
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
    );
  }
}
