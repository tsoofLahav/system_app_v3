import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Transparent viewport: keep the chrome at the start and center the tools
/// when space permits; scroll the whole row when its natural width is wider.
class ScrollableToolbarRow extends StatelessWidget {
  const ScrollableToolbarRow({
    super.key,
    required this.leading,
    required this.content,
  });

  final Widget leading;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: PointerDeviceKind.values.toSet(),
        ),
        child: SingleChildScrollView(
          primary: false,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: IntrinsicWidth(
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 8),
                  Expanded(child: Center(child: content)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
