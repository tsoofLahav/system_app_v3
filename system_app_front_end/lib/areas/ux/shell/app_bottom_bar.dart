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
import '../../production_agent/ai_tool_bar.dart';
import '../../automations/automation_dialog.dart';
import '../../files/editor/document_editor_controller.dart';
import '../../files/editor/document_insert_bar.dart';
import '../../objects/diagram/diagram_graph_config_dialog.dart';
import '../../objects/diagram/diagram_tag_filter_bar.dart';
import './chrome_anchors.dart';
import './preferences_dialog.dart';

abstract final class AppBottomBarMetrics {
  static const barHeight = 44.0;
  static const floatMargin = 12.0;
  static const scrollInset = 72.0;
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
    return ListenableBuilder(
      listenable: Listenable.merge([
        state,
        DocumentEditorRegistry.notifier,
      ]),
      builder: (context, _) => _buildBar(context),
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
            onPressed: () => showPreferencesDialog(
              context: context,
              state: state,
            ),
          ),
          _BarIconButton(
            tooltip: s['automations'],
            icon: AppIcons.automations,
            onPressed: () => showAutomationDialog(
              context: context,
              state: state,
            ),
          ),
          if (state.isDiagramMode)
            _BarIconButton(
              tooltip: s['diagramGraphConfig'],
              icon: AppIcons.diagramGraphConfig,
              onPressed: () => showDiagramGraphConfigDialog(
                context: context,
                state: state,
              ),
            ),
          if (_showArrange)
            _BarIconButton(
              tooltip: s['arrangeFiles'],
              icon: AppIcons.arrange,
              onPressed: () => showFileArrangeOverlay(context, state),
            ),
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

  List<Widget> _centerSegments(
    BuildContext context,
    AppStrings s,
    bool canAi,
  ) {
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
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.aiCyan.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(width: 6),
            Text(s['aiRunning'], style: AppTypography.metaStyle),
          ],
        ),
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

class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.buttonKey,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;
  final Key? buttonKey;

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
        color: active
            ? AppColors.primary.withValues(alpha: 0.88)
            : AppColors.text.withValues(alpha: 0.72),
      ),
    );
  }
}
