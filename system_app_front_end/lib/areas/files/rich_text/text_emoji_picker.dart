import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/dialog_metrics.dart';
import '../../ui/glass_surface.dart';
import '../../ux/create_topic/icon_category_picker.dart';
import '../../ux/shell/app_bottom_bar.dart';
import '../../ux/shell/dismiss_focus_on_outside_tap.dart';
import '../editor/document_editor_controller.dart';
import './block_text_focus.dart';
import './text_emoji_insert.dart';

/// Insert-bar emoji palette — desktop is a movable overlay so typing can
/// continue; phone is a keyboard-height panel above the tool pills.
abstract final class TextEmojiPalette {
  static final ValueNotifier<bool> open = ValueNotifier(false);

  static OverlayEntry? _entry;

  static bool get isOpen => _entry != null;

  static void toggle(BuildContext context, AppStrings strings) {
    if (_entry != null) {
      close();
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    BlockTextFocusRegistry.beginEmojiPickerSession(
      allowUnfocusedRecent:
          DocumentEditorRegistry.active?.canLeaveObject?.call() == true,
    );
    if (isPhoneLayout) {
      FocusManager.instance.primaryFocus?.unfocus();
    }

    _entry = OverlayEntry(
      builder: (ctx) => isPhoneLayout
          ? _PhoneEmojiKeyboard(strings: strings, onClose: close)
          : _DesktopEmojiPalette(strings: strings, onClose: close),
    );
    overlay.insert(_entry!);
    open.value = true;
    HardwareKeyboard.instance.addHandler(_onKey);
    DocumentEditorRegistry.notifier.addListener(_closeIfNoEditor);
  }

  static void close() {
    if (_entry == null) return;
    DocumentEditorRegistry.notifier.removeListener(_closeIfNoEditor);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _entry?.remove();
    _entry = null;
    open.value = false;
    BlockTextFocusRegistry.endEmojiPickerSession(restoreFocus: isPhoneLayout);
    if (isPhoneLayout) {
      DocumentEditorRegistry.restoreActiveWritingFocus();
    }
  }

  static void _closeIfNoEditor() {
    if (DocumentEditorRegistry.active == null) close();
  }

  static bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (event is KeyDownEvent) close();
    return true;
  }
}

class _DesktopEmojiPalette extends StatefulWidget {
  const _DesktopEmojiPalette({required this.strings, required this.onClose});

  final AppStrings strings;
  final VoidCallback onClose;

  @override
  State<_DesktopEmojiPalette> createState() => _DesktopEmojiPaletteState();
}

class _DesktopEmojiPaletteState extends State<_DesktopEmojiPalette> {
  static const _width = AppDialogMetrics.wideWidth;
  static const _pickerHeight = 280.0;
  static const _approxHeight = 392.0;

  Offset? _offset;

  Offset _initial(Size screen, bool rtl) {
    final bar = AppBottomBarMetrics.barHeight +
        AppBottomBarMetrics.floatMargin +
        16;
    final dx = rtl
        ? 16.0
        : (screen.width - _width - 16).clamp(8.0, screen.width);
    final dy = (screen.height - bar - _approxHeight).clamp(8.0, screen.height);
    return Offset(dx, dy);
  }

  Offset _clamp(Offset raw, Size screen) {
    return Offset(
      raw.dx.clamp(8.0, (screen.width - _width).clamp(8.0, screen.width)),
      raw.dy.clamp(
        8.0,
        (screen.height - _approxHeight).clamp(8.0, screen.height),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _offset ??= _initial(screen, rtl);
    final pos = _clamp(_offset!, screen);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: KeepEditorFocus(
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          child: GlassSurface.styled(
            style: AppGlassStyle.floating,
            borderRadius: BorderRadius.circular(AppGlassStyle.dialogRadius),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: SizedBox(
              width: _width - 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) {
                      setState(
                        () => _offset = _clamp((_offset ?? pos) + d.delta, screen),
                      );
                    },
                    child: Row(
                      children: [
                        AppIcon(
                          AppIcons.drag,
                          size: 16,
                          color: AppColors.text.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.strings['emoji'],
                            style: AppTypography.metaStyle.copyWith(
                              color: AppColors.text.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: widget.onClose,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            widget.strings['done'],
                            style: AppTypography.metaStyle.copyWith(
                              color: AppColors.primary.withValues(alpha: 0.92),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  IconCategoryPicker(
                    selectedId: '',
                    searchHint: widget.strings['searchEmoji'],
                    keyboardHint: widget.strings['emojiPickerKeyboardHint'],
                    height: _pickerHeight,
                    autofocusGrid: false,
                    onSelected: insertEmojiIntoActiveText,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneEmojiKeyboard extends StatelessWidget {
  const _PhoneEmojiKeyboard({required this.strings, required this.onClose});

  final AppStrings strings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    final barReserve = viewPadding.bottom +
        AppBottomBarMetrics.phoneFooterStripe +
        AppBottomBarMetrics.phoneBarHeight;
    final bottom = insets.bottom > barReserve ? insets.bottom : barReserve;

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: KeepEditorFocus(
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          child: GlassSurface.styled(
            style: AppGlassStyle.floating,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppGlassStyle.floatingRadius),
            ),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings['emoji'],
                        style: AppTypography.metaStyle.copyWith(
                          color: AppColors.text.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onClose,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        strings['done'],
                        style: AppTypography.metaStyle.copyWith(
                          color: AppColors.primary.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                IconCategoryPicker(
                  selectedId: '',
                  searchHint: strings['searchEmoji'],
                  height: 300,
                  columns: 8,
                  autofocusGrid: false,
                  onSelected: insertEmojiIntoActiveText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
