import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_state.dart';
import '../../files/data/topic.dart';
import '../../files/editor/document_editor_controller.dart';
import '../../ui/glass_surface.dart';
import '../arrange/file_arrange_keyboard.dart';
import '../shell/app_bottom_bar.dart';
import '../widgets/layout_picker_tile.dart';
import './file_layouts.dart';
import './topic_file_slots.dart';

Future<void> showFileLayoutPicker(BuildContext context, AppState state) {
  final topic = state.selectedDetail?.topic;
  if (topic == null) return Future.value();

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x00000000),
    pageBuilder: (ctx, _, _) {
      return FileLayoutPicker(state: state, topic: topic);
    },
  ).then((_) {
    DocumentEditorRegistry.restoreActiveWritingFocus();
  });
}

/// Four layout tiles in a glass strip above the bottom bar. No screen scrim.
class FileLayoutPicker extends StatefulWidget {
  const FileLayoutPicker({super.key, required this.state, required this.topic});

  final AppState state;
  final Topic topic;

  @override
  State<FileLayoutPicker> createState() => _FileLayoutPickerState();
}

class _FileLayoutPickerState extends State<FileLayoutPicker> {
  final _focusNode = FocusNode(debugLabel: 'fileLayoutPicker');
  late String _selectedId;
  late List<String> _enabledIds;

  @override
  void initState() {
    super.initState();
    final files = widget.state.selectedDetail?.files ?? const [];
    final ordered = widget.state.orderedFilesFor(widget.topic, files);
    _enabledIds = enabledLayoutIds(ordered.length);
    _selectedId = effectiveLayoutId(
      widget.state.layoutFor(widget.topic),
      ordered.length,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pick(String id) async {
    await widget.state.setLayoutForTopic(widget.topic, id);
    if (mounted) Navigator.of(context).pop();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      if (_enabledIds.contains(_selectedId)) {
        _pick(_selectedId);
      }
      return KeyEventResult.handled;
    }
    final isLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft;
    final isRight = event.logicalKey == LogicalKeyboardKey.arrowRight;
    if (!isLeft && !isRight) return KeyEventResult.ignored;
    if (_enabledIds.isEmpty) return KeyEventResult.handled;
    final delta = spatialHorizontalDelta(
      isRtl: widget.state.isRtl,
      isLeftArrow: isLeft,
    );
    final index = _enabledIds.indexOf(_selectedId);
    final next = stepLayoutFocusIndex(
      currentIndex: index < 0 ? 0 : index,
      layoutCount: _enabledIds.length,
      delta: delta,
    );
    setState(() => _selectedId = _enabledIds[next]);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final bottomInset =
        MediaQuery.paddingOf(context).bottom +
        AppBottomBarMetrics.floatMargin * 2 +
        AppBottomBarMetrics.barHeight +
        8;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset,
              child: Center(
                child: GestureDetector(
                  onTap: () {},
                  child: GlassBarSegment(
                    height: 56,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < FileLayouts.all.length; i++) ...[
                          if (i > 0) const SizedBox(width: 2),
                          Builder(
                            builder: (context) {
                              final layout = FileLayouts.all[i];
                              final enabled = _enabledIds.contains(layout.id);
                              return LayoutPickerTile(
                                layoutId: layout.id,
                                label: s.layoutLabel(layout.id),
                                selected: _selectedId == layout.id,
                                focused: _selectedId == layout.id,
                                enabled: enabled,
                                compact: true,
                                iconWidth: 44,
                                iconHeight: 30,
                                onTap: enabled ? () => _pick(layout.id) : null,
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
