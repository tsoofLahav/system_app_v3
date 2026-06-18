import 'package:flutter/material.dart';

import '../../core/registry/topic_appearance.dart';

class TopicEmoji extends StatelessWidget {
  const TopicEmoji({
    super.key,
    required this.value,
    this.size = 18,
  });

  final String? value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      TopicAppearance.emojiFromId(value),
      style: TextStyle(fontSize: size, height: 1.1),
    );
  }
}
