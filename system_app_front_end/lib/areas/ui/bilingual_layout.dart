import 'package:flutter/material.dart';

/// Primary content at layout [start], trailing control at layout [end].
///
/// In LTR: content on the left, trailing on the right.
/// In RTL: content on the right, trailing on the left.
///
/// Inherit [Directionality] from the app — do not wrap this in a forced
/// [TextDirection.ltr] unless you intentionally want English physical layout.
class StartTrailingRow extends StatelessWidget {
  const StartTrailingRow({
    super.key,
    required this.content,
    required this.trailing,
    this.gap = 8,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final Widget content;
  final Widget trailing;
  final double gap;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Expanded(child: content),
        SizedBox(width: gap),
        trailing,
      ],
    );
  }
}

/// Dialog footer actions aligned to the reading-direction trailing edge.
///
/// LTR: buttons on the right. RTL: buttons on the left.
class DialogActionsRow extends StatelessWidget {
  const DialogActionsRow({
    super.key,
    required this.children,
    this.gap = 8,
  });

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          children[i],
        ],
      ],
    );
  }
}
