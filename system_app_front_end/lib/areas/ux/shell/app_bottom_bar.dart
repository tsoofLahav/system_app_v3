import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/confirm_dialog.dart';
import '../../ui/glass_surface.dart';
import '../arrange/file_arrange_overlay.dart';
import '../layout/file_layout_picker.dart';
import '../shortcuts/app_shortcuts.dart';
import '../shortcuts/shortcut_catalog.dart';
import '../arrange/phone_file_reorder_sheet.dart';
import '../../production_agent/ai_running_status.dart';
import '../../production_agent/ai_tool_bar.dart';
import '../../automations/automation_dialog.dart';
import '../../files/editor/document_editor_controller.dart';
import '../../files/editor/document_insert_bar.dart';
import '../../objects/diagram/diagram_graph_config_dialog.dart';
import '../../objects/diagram/diagram_tag_filter_bar.dart';
import './chrome_anchors.dart';
import './dismiss_focus_on_outside_tap.dart';
import './preferences_dialog.dart';
import '../../objects/views/view_chrome_menu.dart';

abstract final class AppBottomBarMetrics {
  static const barHeight = 44.0;
  static const floatMargin = 12.0;
  static const scrollInset = 72.0;

  static const phoneSegmentHeight = 38.0;
  static const phoneFloatMargin = 5.0;
  static const phoneFooterStripe = 3.0;
  static const phoneSegmentGap = 14.0;

  /// Phone tools row, above the footer stripe — not overlapping it.
  static const phoneBarHeight = phoneFloatMargin * 2 + phoneSegmentHeight;

  static double segmentHeight({required bool phone}) =>
      phone ? phoneSegmentHeight : barHeight;
}

abstract final class AppTopicHeaderMetrics {
  static const headerHeight = 32.0;
  static const addButtonSize = 32.0;
  static const headerGap = 8.0;
  static const horizontalMargin = 16.0;
  static const floatMargin = 6.0;
  static const scrollTopInset = 38.0;
}

const _iconSize = 22.0;
const _iconTapPadding = 4.0;
const _segmentPadding = EdgeInsets.symmetric(horizontal: 4);

class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key, required this.state});

  final AppState state;

  bool get _showArrange =>
      !isPhoneLayout &&
      !state.isArchiveMode &&
      !state.isViewMode &&
      !state.isDiagramMode &&
      state.selectedDetail != null;

  bool get _showArchiveDelete =>
      state.isArchiveMode && state.archiveTotalCount > 0;

  @override
  Widget build(BuildContext context) {
    // Rebuild for both app state and editor focus, so the insert segment
    // appears in the centered group when a document is active.
    return KeepEditorFocus(
      child: ListenableBuilder(
        listenable: Listenable.merge([state, DocumentEditorRegistry.notifier]),
        builder: (context, _) => _buildBar(context),
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    final s = state.strings;
    final canAi = state.canUseAiTools;
    final hasEditor = DocumentEditorRegistry.active != null;
    final diagramMode = state.isDiagramMode;

    final chrome = _chromeSegment(context, s);
    final center = _centerSegments(context, s, canAi);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: AppBottomBarMetrics.floatMargin,
        ),
        child: Row(
          // Preferences / automations at the start edge (left in English,
          // right in Hebrew). Insert tools and AI stay in the remaining middle.
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            chrome,
            const SizedBox(width: 8),
            Expanded(
              child: diagramMode
                  ? DiagramTagFilterBar(state: state)
                  : Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasEditor) ...[
                            DocumentInsertBar(state: state, embedded: true),
                            if (center.isNotEmpty) const SizedBox(width: 8),
                          ],
                          ...center,
                        ],
                      ),
                    ),
            ),
            if (diagramMode && center.isNotEmpty) ...[
              const SizedBox(width: 8),
              ...center,
            ],
          ],
        ),
      ),
    );
  }

  Widget _chromeSegment(BuildContext context, AppStrings s) {
    return GlassBarSegment(
      height: AppBottomBarMetrics.barHeight,
      padding: _segmentPadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BarIconButton(
            buttonKey: ChromeAnchors.preferencesButton,
            tooltip: s['preferences'],
            icon: AppIcons.preferences,
            onPressed: () =>
                showPreferencesDialog(context: context, state: state),
          ),
          _BarIconButton(
            tooltip: s['automations'],
            icon: AppIcons.automations,
            onPressed: () =>
                showAutomationDialog(context: context, state: state),
          ),
          if (state.isDiagramMode)
            _BarIconButton(
              tooltip: s['diagramGraphConfig'],
              icon: AppIcons.diagramGraphConfig,
              onPressed: () =>
                  showDiagramGraphConfigDialog(context: context, state: state),
            ),
          if (_showArrange) ...[
            _BarIconButton(
              tooltip: _shortcutTooltip(
                state,
                s['layout'],
                ShortcutActionIds.openFileLayout,
              ),
              icon: AppIcons.layout,
              onPressed: () => showFileLayoutPicker(context, state),
            ),
            _BarIconButton(
              tooltip: _shortcutTooltip(
                state,
                s['arrangeFiles'],
                ShortcutActionIds.openArrange,
              ),
              icon: AppIcons.arrange,
              onPressed: () => showFileArrangeOverlay(context, state),
            ),
          ],
          if (_showArchiveDelete)
            _BarIconButton(
              tooltip: state.archiveDeleteMode
                  ? (state.archiveDeleteSelection.isEmpty
                        ? s['archiveDeleteDone']
                        : s['archiveDeleteConfirm'])
                  : s['archiveDeleteSelect'],
              icon: AppIcons.trash,
              active: state.archiveDeleteMode,
              onPressed: () => _handleArchiveDelete(context),
            ),
        ],
      ),
    );
  }

  List<Widget> _centerSegments(BuildContext context, AppStrings s, bool canAi) {
    return [
      if (_showArchiveDelete && state.archiveDeleteMode) ...[
        GlassBarSegment(
          height: AppBottomBarMetrics.barHeight,
          padding: _segmentPadding,
          child: TextButton(
            onPressed: state.archiveDeleteSelection.isEmpty
                ? null
                : () => _confirmArchiveDelete(context),
            child: Text(
              s['archiveDeleteConfirm'],
              style: AppTypography.metaStyle.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (canAi || state.aiRunning) const SizedBox(width: 8),
      ],
      if (canAi)
        GlassBarSegment(
          style: AppGlassStyle.aiAccent,
          height: AppBottomBarMetrics.barHeight,
          padding: _segmentPadding,
          label: 'AI',
          labelOnBorder: true,
          child: AiToolBar(state: state, compact: true),
        ),
        if (state.aiRunning) ...[
          if (canAi) const SizedBox(width: 8),
          AiRunningStatus(state: state),
        ],
    ];
  }

  Future<void> _handleArchiveDelete(BuildContext context) async {
    if (!state.archiveDeleteMode) {
      state.toggleArchiveDeleteMode();
      return;
    }
    if (state.archiveDeleteSelection.isEmpty) {
      state.toggleArchiveDeleteMode();
      return;
    }
    await _confirmArchiveDelete(context);
  }

  Future<void> _confirmArchiveDelete(BuildContext context) async {
    final s = state.strings;
    final count = state.archiveDeleteSelection.length;
    final ok = await showAppConfirmDialog(
      context: context,
      title: s['archiveDeleteTitle'],
      message: s.archiveDeleteBody(count),
      confirmLabel: s['delete'],
      cancelLabel: s['cancel'],
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await state.deleteSelectedArchiveFiles();
  }
}

/// Phone topic tools: the same parts as the desktop bar, in one horizontally
/// scrolling row. File-carousel swipes and this strip are separate hit targets.
class PhoneBottomBar extends StatelessWidget {
  const PhoneBottomBar({super.key, required this.state});

  final AppState state;

  static bool showInsert(AppState state) =>
      !state.isArchiveMode &&
      !state.isViewMode &&
      !state.isDiagramMode &&
      DocumentEditorRegistry.active != null;

  static bool showAi(AppState state) => state.canUseAiTools || state.aiRunning;

  static bool showArrange(AppState state) =>
      !state.isArchiveMode &&
      !state.isViewMode &&
      !state.isDiagramMode &&
      state.selectedDetail != null;

  static bool showArchiveDeleteConfirm(AppState state) =>
      state.isArchiveMode &&
      state.archiveDeleteMode &&
      state.archiveDeleteSelection.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return KeepEditorFocus(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          state,
          DocumentEditorRegistry.notifier,
          DocumentEditorRegistry.objectGateNotifier,
          ViewChromeRegistry.notifier,
        ]),
        builder: (context, _) => _buildBar(context),
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    final s = state.strings;
    final viewChrome = ViewChromeRegistry.active;
    final objectPad = _objectPad(s);
    final parts = <Widget>[
      ?objectPad,
      _chromeSegment(context, s),
      if (state.isDiagramMode)
        DiagramTagFilterBar(state: state, tightShadow: true),
      if (state.isViewMode && viewChrome != null)
        ViewChromeMenu(
          state: state,
          displayMode: state.viewDisplayMode,
          frameReorderMode: viewChrome.frameReorderMode,
          onToggleDisplayMode: viewChrome.onToggleDisplayMode,
          onAddSection: viewChrome.onAddSection,
          onStartFrameReorder: viewChrome.onStartFrameReorder,
        ),
      if (showInsert(state)) DocumentInsertBar(state: state, embedded: true),
      if (showArchiveDeleteConfirm(state)) _archiveConfirmSegment(context, s),
      if (showAi(state)) _aiSegment(),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        12,
        AppBottomBarMetrics.phoneFloatMargin,
        12,
        AppBottomBarMetrics.phoneFloatMargin,
      ),
      child: SingleChildScrollView(
        primary: false,
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0)
                const SizedBox(width: AppBottomBarMetrics.phoneSegmentGap),
              parts[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _chromeSegment(BuildContext context, AppStrings s) {
    return GlassBarSegment(
      height: AppBottomBarMetrics.phoneSegmentHeight,
      padding: _segmentPadding,
      tightShadow: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BarIconButton(
            buttonKey: ChromeAnchors.preferencesButton,
            tooltip: s['preferences'],
            icon: AppIcons.preferences,
            onPressed: () =>
                showPreferencesDialog(context: context, state: state),
          ),
          _BarIconButton(
            tooltip: s['automations'],
            icon: AppIcons.automations,
            onPressed: () =>
                showAutomationDialog(context: context, state: state),
          ),
          if (state.isDiagramMode)
            _BarIconButton(
              tooltip: s['diagramGraphConfig'],
              icon: AppIcons.diagramGraphConfig,
              onPressed: () =>
                  showDiagramGraphConfigDialog(context: context, state: state),
            ),
          if (showArrange(state))
            _BarIconButton(
              tooltip: s['arrangeFiles'],
              icon: AppIcons.arrange,
              onPressed: () =>
                  showPhoneFileReorderSheet(context: context, state: state),
            ),
          if (state.isArchiveMode && state.archiveTotalCount > 0)
            _BarIconButton(
              tooltip: state.archiveDeleteMode
                  ? (state.archiveDeleteSelection.isEmpty
                        ? s['archiveDeleteDone']
                        : s['archiveDeleteConfirm'])
                  : s['archiveDeleteSelect'],
              icon: AppIcons.trash,
              active: state.archiveDeleteMode,
              onPressed: () => _handleArchiveDelete(context),
            ),
        ],
      ),
    );
  }

  Widget _archiveConfirmSegment(BuildContext context, AppStrings s) {
    return GlassBarSegment(
      height: AppBottomBarMetrics.phoneSegmentHeight,
      padding: _segmentPadding,
      tightShadow: true,
      child: TextButton(
        onPressed: () => _confirmArchiveDelete(context),
        child: Text(
          s['archiveDeleteConfirm'],
          style: AppTypography.metaStyle.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _aiSegment() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.canUseAiTools)
          GlassBarSegment(
            style: AppGlassStyle.aiAccent,
            height: AppBottomBarMetrics.phoneSegmentHeight,
            padding: _segmentPadding,
            label: 'AI',
            labelOnBorder: true,
            tightShadow: true,
            child: AiToolBar(state: state, compact: true),
          ),
        if (state.aiRunning) ...[
          if (state.canUseAiTools)
            const SizedBox(width: AppBottomBarMetrics.phoneSegmentGap),
          AiRunningStatus(state: state),
        ],
      ],
    );
  }

  Widget? _objectPad(AppStrings s) {
    final editor = DocumentEditorRegistry.active;
    if (editor == null) return null;
    final leave = editor.canLeaveObject?.call() ?? false;
    final enter = editor.canEnterObject?.call() ?? false;
    if (!leave && !enter) return null;
    return GlassBarSegment(
      height: AppBottomBarMetrics.phoneSegmentHeight,
      padding: _segmentPadding,
      tightShadow: true,
      child: ObjectArrowPad(
        leftTooltip: s['objectArrowLeft'],
        downTooltip: s['objectArrowDown'],
        upTooltip: s['objectArrowUp'],
        rightTooltip: s['objectArrowRight'],
        enterLeaveTooltip: leave ? s['objectLeave'] : s['objectEnter'],
        leave: leave,
        onNudge: (direction) => editor.nudgeObjectCaret?.call(direction),
        onEnterOrLeave: () {
          if (leave) {
            editor.leaveObject?.call();
          } else {
            editor.enterObject?.call();
          }
        },
      ),
    );
  }

  Future<void> _handleArchiveDelete(BuildContext context) async {
    if (!state.archiveDeleteMode) {
      state.toggleArchiveDeleteMode();
      return;
    }
    if (state.archiveDeleteSelection.isEmpty) {
      state.toggleArchiveDeleteMode();
      return;
    }
    await _confirmArchiveDelete(context);
  }

  Future<void> _confirmArchiveDelete(BuildContext context) async {
    final s = state.strings;
    final count = state.archiveDeleteSelection.length;
    final ok = await showAppConfirmDialog(
      context: context,
      title: s['archiveDeleteTitle'],
      message: s.archiveDeleteBody(count),
      confirmLabel: s['delete'],
      cancelLabel: s['cancel'],
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await state.deleteSelectedArchiveFiles();
  }
}

/// Phone object-pad arrows. Physical left/right — never mirrors with the app UI.
///
/// The icons only *draw* a direction. Hebrew still means left is left.
class ObjectArrowPad extends StatelessWidget {
  const ObjectArrowPad({
    super.key,
    required this.leftTooltip,
    required this.downTooltip,
    required this.upTooltip,
    required this.rightTooltip,
    required this.enterLeaveTooltip,
    required this.leave,
    required this.onNudge,
    required this.onEnterOrLeave,
  });

  static const padKey = Key('object-arrow-pad');

  final String leftTooltip;
  final String downTooltip;
  final String upTooltip;
  final String rightTooltip;
  final String enterLeaveTooltip;
  final bool leave;
  final ValueChanged<AxisDirection> onNudge;
  final VoidCallback onEnterOrLeave;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        key: padKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          _BarIconButton(
            tooltip: leftTooltip,
            icon: AppIcons.arrowLeft,
            textDirection: TextDirection.ltr,
            onPressed: () => onNudge(AxisDirection.left),
          ),
          _BarIconButton(
            tooltip: downTooltip,
            icon: AppIcons.arrowDown,
            textDirection: TextDirection.ltr,
            onPressed: () => onNudge(AxisDirection.down),
          ),
          _BarIconButton(
            tooltip: upTooltip,
            icon: AppIcons.arrowUp,
            textDirection: TextDirection.ltr,
            onPressed: () => onNudge(AxisDirection.up),
          ),
          _BarIconButton(
            tooltip: rightTooltip,
            icon: AppIcons.arrowRight,
            textDirection: TextDirection.ltr,
            onPressed: () => onNudge(AxisDirection.right),
          ),
          _BarIconButton(
            tooltip: enterLeaveTooltip,
            icon: leave ? AppIcons.leaveObject : AppIcons.enterObject,
            textDirection: TextDirection.ltr,
            active: leave,
            onPressed: onEnterOrLeave,
          ),
        ],
      ),
    );
  }
}

String _shortcutTooltip(AppState state, String label, String actionId) {
  final suffix = shortcutTooltipSuffix(state, actionId);
  return suffix == null ? label : '$label ($suffix)';
}

class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.buttonKey,
    this.textDirection,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;
  final Key? buttonKey;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      tooltip: tooltip,
      padding: const EdgeInsets.all(_iconTapPadding),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      onPressed: onPressed,
      icon: AppIcon(
        icon,
        size: _iconSize,
        textDirection: textDirection,
        color: active
            ? AppColors.primary.withValues(alpha: 0.88)
            : AppColors.text.withValues(alpha: 0.72),
      ),
    );
  }
}
