import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../design_system/app_icons.dart';
import 'block_text_focus.dart';
import 'format_range.dart';
import 'frozen_selection_painter.dart';
import 'span_text_editing_controller.dart';
import 'text_emoji_picker.dart';

/// Text field that registers for block context-menu clipboard/format actions.
class FormattedTextField extends StatefulWidget {
  const FormattedTextField({
    super.key,
    required this.controller,
    required this.style,
    this.blockContent,
    this.hintText,
    this.maxLines,
    this.minLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.onBackspaceAtStart,
    this.onSelectAll,
    this.onPaste,
    this.textInputAction,
    this.focusNode,
    this.onEnter,
    this.stripNewlines = false,
    this.onSecondaryTapDown,
    this.textAlignVertical,
    this.blockId,
    this.emojiSearchHint = 'Search emoji',
    this.emojiPickerTitle = 'Insert emoji…',
    this.aiState,
    this.aiSuggestEmojiLabel = 'Suggest emoji',
  });

  final TextEditingController controller;
  final TextStyle style;
  final Map<String, dynamic>? blockContent;
  final String? hintText;
  final int? maxLines;
  final int minLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onBackspaceAtStart;
  final VoidCallback? onSelectAll;
  final Future<void> Function(String text)? onPaste;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final VoidCallback? onEnter;
  final bool stripNewlines;
  final GestureTapDownCallback? onSecondaryTapDown;
  final TextAlignVertical? textAlignVertical;
  final int? blockId;
  final String emojiSearchHint;
  final String emojiPickerTitle;
  final AppState? aiState;
  final String aiSuggestEmojiLabel;

  @override
  State<FormattedTextField> createState() => _FormattedTextFieldState();
}

class _FormattedTextFieldState extends State<FormattedTextField> {
  late FocusNode _focusNode;
  bool _ownsFocus = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocus = true;
    }
    _focusNode.addListener(_onFocusChanged);
    _focusNode.onKeyEvent = _onFocusKeyEvent;
  }

  @override
  void dispose() {
    _focusNode.onKeyEvent = null;
    _focusNode.removeListener(_onFocusChanged);
    BlockTextFocusRegistry.unregister(widget.controller);
    if (_ownsFocus) _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      BlockTextFocusRegistry.register(
        controller: widget.controller,
        changed: _notifyChanged,
        blockContent: widget.blockContent,
        fontSize: widget.style.fontSize ?? 12.5,
        focusNode: _focusNode,
        blockId: widget.blockId,
      );
    } else {
      if ((BlockTextFocusRegistry.isInMenuSession ||
              BlockTextFocusRegistry.isInEmojiPickerSession) &&
          BlockTextFocusRegistry.activeController == widget.controller) {
        return;
      }
      BlockTextFocusRegistry.unregister(widget.controller);
    }
  }

  void _notifyChanged() {
    final controller = widget.controller;
    if (controller is SpanTextEditingController) {
      controller.ensureSpansMatchText();
    }
    widget.onChanged?.call(controller.text);
  }

  KeyEventResult _onFocusKeyEvent(FocusNode node, KeyEvent event) {
    if (!_focusNode.hasFocus) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    if (isMeta && event.logicalKey == LogicalKeyboardKey.keyE &&
        HardwareKeyboard.instance.isShiftPressed) {
      _openEmojiPicker();
      return KeyEventResult.handled;
    }

    if (isMeta && event.logicalKey == LogicalKeyboardKey.keyM &&
        HardwareKeyboard.instance.isShiftPressed &&
        widget.aiState != null) {
      final state = widget.aiState!;
      if (state.canRunAiTool('suggest_emoji') && !state.aiRunning) {
        runSuggestEmoji(context, state);
        return KeyEventResult.handled;
      }
    }

    if (isMeta && event.logicalKey == LogicalKeyboardKey.keyA) {
      widget.onSelectAll?.call();
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed &&
        widget.onEnter != null) {
      widget.onEnter!();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        widget.controller.text.isEmpty &&
        widget.controller.selection.baseOffset == 0 &&
        widget.onBackspaceAtStart != null) {
      widget.onBackspaceAtStart!();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _openEmojiPicker() {
    if (!mounted) return;
    showTextEmojiPicker(
      context: context,
      searchHint: widget.emojiSearchHint,
      title: widget.emojiPickerTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final formatters = <TextInputFormatter>[
      if (widget.onEnter != null) _SubmitOnEnterFormatter(widget.onEnter!),
      if (widget.stripNewlines) _StripNewlinesFormatter(),
    ];

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton) {
          if (widget.onSecondaryTapDown != null) {
            widget.onSecondaryTapDown!(
              TapDownDetails(globalPosition: event.position),
            );
            return;
          }
          if (_focusNode.hasFocus ||
              BlockTextFocusRegistry.activeController == widget.controller) {
            FormatRange.capturePending(
              widget.controller.text,
              widget.controller.selection,
            );
          }
        }
      },
      child: ValueListenableBuilder<int>(
        valueListenable: BlockTextFocusRegistry.menuSessionListenable,
        builder: (context, _, child) {
          final frozenRange = BlockTextFocusRegistry.frozenFormatRange;
          final showOverlay = BlockTextFocusRegistry.isInMenuSession &&
              BlockTextFocusRegistry.activeController == widget.controller &&
              frozenRange != null &&
              frozenRange.isValid;

          if (!showOverlay) return child!;

          final theme = Theme.of(context);
          final selectionColor = theme.textSelectionTheme.selectionColor ??
              theme.colorScheme.primary.withValues(alpha: 0.3);

          return _FrozenSelectionOverlay(
            selection: frozenRange.selection,
            selectionColor: selectionColor,
            child: child!,
          );
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                style: style,
                textAlignVertical: widget.textAlignVertical,
                maxLines: widget.maxLines,
                minLines: widget.minLines,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.hintText,
                  hintStyle: style.copyWith(
                    color: style.color?.withValues(alpha: 0.35),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                textInputAction: widget.onEnter != null
                    ? TextInputAction.none
                    : widget.textInputAction,
                onChanged: (_) => _notifyChanged(),
                onSubmitted: widget.onSubmitted,
                onTap: () => _onFocusChanged(),
                inputFormatters: formatters.isEmpty ? null : formatters,
                contextMenuBuilder: (context, editableTextState) {
                  return const SizedBox.shrink();
                },
              ),
            ),
            ListenableBuilder(
              listenable: _focusNode,
              builder: (context, _) {
                if (!_focusNode.hasFocus) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4, top: 1),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.aiState != null)
                        ListenableBuilder(
                          listenable: widget.controller,
                          builder: (context, _) {
                            final state = widget.aiState!;
                            if (!BlockTextFocusRegistry.hasMarkedText ||
                                !state.canRunAiTool('suggest_emoji')) {
                              return const SizedBox.shrink();
                            }
                            return IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              tooltip: widget.aiSuggestEmojiLabel,
                              onPressed: state.aiRunning
                                  ? null
                                  : () => runSuggestEmoji(context, state),
                              icon: AppIcon(
                                AppIcons.ai,
                                size: 14,
                                color: style.color?.withValues(alpha: 0.62),
                              ),
                            );
                          },
                        ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        tooltip: widget.emojiPickerTitle,
                        onPressed: () {
                          _focusNode.requestFocus();
                          _openEmojiPicker();
                        },
                        icon: AppIcon(
                          AppIcons.smiley,
                          size: 15,
                          color: style.color?.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Highlights the frozen range using [RenderEditable] selection boxes.
class _FrozenSelectionOverlay extends StatefulWidget {
  const _FrozenSelectionOverlay({
    required this.selection,
    required this.selectionColor,
    required this.child,
  });

  final TextSelection selection;
  final Color selectionColor;
  final Widget child;

  @override
  State<_FrozenSelectionOverlay> createState() => _FrozenSelectionOverlayState();
}

class _FrozenSelectionOverlayState extends State<_FrozenSelectionOverlay> {
  List<Rect> _rects = const [];

  @override
  void initState() {
    super.initState();
    BlockTextFocusRegistry.menuSessionListenable.addListener(_scheduleMeasure);
  }

  @override
  void dispose() {
    BlockTextFocusRegistry.menuSessionListenable.removeListener(_scheduleMeasure);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _FrozenSelectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      _scheduleMeasure();
    }
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measure();
    });
  }

  void _measure() {
    final host = context.findRenderObject() as RenderBox?;
    final editable = host == null ? null : _findRenderEditable(host);
    if (editable == null || host == null || !host.hasSize) {
      if (_rects.isNotEmpty) setState(() => _rects = const []);
      return;
    }

    if (!widget.selection.isValid || widget.selection.isCollapsed) {
      if (_rects.isNotEmpty) setState(() => _rects = const []);
      return;
    }

    final transform = editable.getTransformTo(host);
    final boxes = editable.getBoxesForSelection(widget.selection);
    final next = <Rect>[
      for (final box in boxes)
        MatrixUtils.transformRect(transform, box.toRect()),
    ];

    if (!FrozenSelectionPainter.rectsEqual(_rects, next)) {
      setState(() => _rects = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    return CustomPaint(
      foregroundPainter: FrozenSelectionPainter(
        rects: _rects,
        selectionColor: widget.selectionColor,
      ),
      child: widget.child,
    );
  }
}

RenderEditable? _findRenderEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? found;
  root.visitChildren((child) {
    found ??= _findRenderEditable(child);
  });
  return found;
}

/// Enter creates a new list/task row instead of a soft line break.
class _SubmitOnEnterFormatter extends TextInputFormatter {
  _SubmitOnEnterFormatter(this.onSubmit);

  final VoidCallback onSubmit;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.contains('\n')) return newValue;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSubmit());
    return oldValue;
  }
}

class _StripNewlinesFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.contains('\n')) return newValue;
    final cleaned = newValue.text.replaceAll('\n', ' ');
    return newValue.copyWith(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
      composing: TextRange.empty,
    );
  }
}
