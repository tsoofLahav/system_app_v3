import 'package:flutter/material.dart';

import '../../core/models/block.dart';
import '../../design_system/app_typography.dart';

class DetailsHoverBubble extends StatelessWidget {
  const DetailsHoverBubble({
    super.key,
    required this.block,
    this.maxHeight = 240,
    this.maxWidth = 320,
  });

  final Block block;
  final double maxHeight;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final content = block.content;
    final title = content['title']?.toString().trim() ?? '';
    final body = content['text']?.toString().trim() ?? '';
    if (title.isEmpty && body.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    title,
                    style: AppTypography.listItemStyle.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (body.isNotEmpty)
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(body, style: AppTypography.noteBodyStyle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DetailsHoverTarget extends StatefulWidget {
  const DetailsHoverTarget({
    super.key,
    required this.child,
    required this.detailsBlockId,
    required this.loadBlock,
  });

  final Widget child;
  final int? detailsBlockId;
  final Future<Block?> Function(int blockId) loadBlock;

  @override
  State<DetailsHoverTarget> createState() => _DetailsHoverTargetState();
}

class _DetailsHoverTargetState extends State<DetailsHoverTarget> {
  OverlayEntry? _entry;
  Block? _block;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  Future<void> _showOverlay() async {
    final blockId = widget.detailsBlockId;
    if (blockId == null || _entry != null) return;
    _block ??= await widget.loadBlock(blockId);
    if (!mounted || _block == null) return;

    final overlay = Overlay.of(context);
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);

    _entry = OverlayEntry(
      builder: (context) => Positioned(
        left: origin.dx,
        top: origin.dy + box.size.height + 6,
        child: DetailsHoverBubble(block: _block!),
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.detailsBlockId == null) return widget.child;
    return MouseRegion(
      onEnter: (_) => _showOverlay(),
      onExit: (_) => _removeOverlay(),
      child: widget.child,
    );
  }
}
