import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/app_state.dart';
import '../../core/services/ai_service.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/file_layouts.dart';
import '../../design_system/glass_surface.dart';
import '../../design_system/layout_preview_icon.dart';
import 'automation_dialog.dart';
import 'preferences_dialog.dart';

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

  bool get _showLayout =>
      !state.isArchiveMode && !state.isViewMode && state.selectedDetail != null;

  bool get _showArchiveDelete =>
      state.isArchiveMode && state.archiveTotalCount > 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => _buildBar(context),
    );
  }

  Widget _buildBar(BuildContext context) {
    final s = state.strings;
    final canAi = state.canUseAiTools;
    final hasContext = state.hasAiContext;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: AppBottomBarMetrics.floatMargin,
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassBarSegment(
                height: AppBottomBarMetrics.barHeight,
                padding: _segmentPadding,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BarIconButton(
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
                    if (_showLayout)
                      _BarIconButton(
                        tooltip: s['layout'],
                        icon: AppIcons.layout,
                        onPressed: () => _showLayoutPicker(context),
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
              ),
              if (_showArchiveDelete && state.archiveDeleteMode) ...[
                const SizedBox(width: 8),
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
              ],
              if (_showLayout) ...[
                const SizedBox(width: 8),
                GlassBarSegment(
                  height: AppBottomBarMetrics.barHeight,
                  padding: _segmentPadding,
                  child: _PaneDragToggle(state: state),
                ),
              ],
              if (canAi) ...[
                const SizedBox(width: 8),
                GlassBarSegment(
                  style: AppGlassStyle.aiAccent,
                  height: AppBottomBarMetrics.barHeight,
                  padding: _segmentPadding,
                  label: 'AI',
                  labelOnBorder: true,
                  child: _AiToolGroup(
                    enabled: hasContext && !state.aiRunning,
                    graphEnabled: hasContext && !state.aiRunning,
                    running: state.aiRunning,
                    strings: s,
                    onTool: (tool) => _runTool(context, tool),
                  ),
                ),
              ],
              if (state.aiRunning) ...[
                const SizedBox(width: 8),
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runTool(BuildContext context, String tool) async {
    final s = state.strings;
    if (!state.canRunAiTool(tool)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s['aiNoContext'])));
      return;
    }

    if (tool == 'review') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s['aiReviewSoon'])));
      return;
    }

    try {
      final result = await state.runAiTool(tool);
      if (!context.mounted || result == null) return;
      _showResult(context, result);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _showResult(BuildContext context, AiRunResult result) {
    final s = state.strings;
    final message = result.result ?? s['aiDone'];
    final topic = result.targetTopicName;
    final file = result.targetFileName;
    final target = topic != null && file != null
        ? '$topic → $file'
        : (file ?? topic);
    final title = result.status == 'not_graphable' ? s['aiGraph'] : s['aiDone'];

    showDialog<void>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        title: Text(title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s['ok'])),
        ],
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (target != null) ...[
                Text(target, style: AppTypography.metaStyle),
                const SizedBox(height: 8),
              ],
              Text(message, style: AppTypography.noteBodyStyle),
            ],
          ),
        ),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        title: Text(s['archiveDeleteTitle']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s['cancel']),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s['delete']),
          ),
        ],
        child: Text(s.archiveDeleteBody(count)),
      ),
    );
    if (ok != true || !context.mounted) return;
    await state.deleteSelectedArchiveFiles();
  }

  void _showLayoutPicker(BuildContext context) {
    final topic = state.selectedDetail?.topic;
    if (topic == null) return;

    final s = state.strings;
    final layoutId = state.layoutFor(topic);
    final fileCount = state
        .mainFilesFor(topic, state.selectedDetail!.files)
        .length;

    showDialog<void>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        title: Text(s['layout']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s['cancel']),
          ),
        ],
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (final layout in FileLayouts.all)
              _LayoutPickerTile(
                layoutId: layout.id,
                label: s.layoutLabel(layout.id),
                selected: layoutId == layout.id,
                enabled: FileLayouts.isAvailable(layout.id, fileCount),
                onTap: FileLayouts.isAvailable(layout.id, fileCount)
                    ? () {
                        state.setLayoutForTopic(topic, layout.id);
                        Navigator.pop(ctx);
                      }
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
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

class _PaneDragToggle extends StatelessWidget {
  const _PaneDragToggle({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final on = state.paneDragMode;

    return Tooltip(
      message: on ? s['paneDragOn'] : s['paneDrag'],
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: state.togglePaneDragMode,
          borderRadius: BorderRadius.circular(999),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PaneModeIcon(
                icon: AppIcons.paneDrag,
                active: on,
              ),
              _PaneModeIcon(
                icon: AppIcons.summarize,
                active: !on,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaneModeIcon extends StatelessWidget {
  const _PaneModeIcon({required this.icon, required this.active});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(_iconTapPadding),
      child: AppIcon(
        icon,
        size: _iconSize,
        color: active
            ? AppColors.text.withValues(alpha: 0.78)
            : AppColors.textHint.withValues(alpha: 0.38),
      ),
    );
  }
}

class _AiToolGroup extends StatelessWidget {
  const _AiToolGroup({
    required this.strings,
    required this.enabled,
    required this.graphEnabled,
    required this.running,
    required this.onTool,
  });

  final AppStrings strings;
  final bool enabled;
  final bool graphEnabled;
  final bool running;
  final ValueChanged<String> onTool;

  @override
  Widget build(BuildContext context) {
    final s = strings;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AiToolButton(
          tooltip: s['aiConsult'],
          icon: AppIcons.consult,
          enabled: enabled && !running,
          onPressed: () => onTool('consult'),
        ),
        _AiToolButton(
          tooltip: s['aiSummarize'],
          icon: AppIcons.summarize,
          enabled: enabled && !running,
          onPressed: () => onTool('summarize_to_doc'),
        ),
        _AiToolButton(
          tooltip: s['aiSmartList'],
          icon: AppIcons.smartList,
          enabled: enabled && !running,
          onPressed: () => onTool('smart_list'),
        ),
        _AiToolButton(
          tooltip: s['aiImage'],
          icon: AppIcons.image,
          enabled: enabled && !running,
          onPressed: () => onTool('create_image'),
        ),
        _AiToolButton(
          tooltip: s['aiGraph'],
          icon: AppIcons.graph,
          enabled: graphEnabled,
          onPressed: () => onTool('create_graph'),
        ),
        _AiToolButton(
          tooltip: s['aiReview'],
          icon: AppIcons.review,
          enabled: !running,
          onPressed: () => onTool('review'),
        ),
      ],
    );
  }
}

class _AiToolButton extends StatelessWidget {
  const _AiToolButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      padding: const EdgeInsets.all(_iconTapPadding),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      onPressed: enabled ? onPressed : null,
      icon: AppIcon(
        icon,
        size: _iconSize,
        enabled: enabled,
        color: enabled
            ? AppColors.text.withValues(alpha: 0.78)
            : AppColors.textHint.withValues(alpha: 0.32),
      ),
    );
  }
}

class _LayoutPickerTile extends StatelessWidget {
  const _LayoutPickerTile({
    required this.layoutId,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String layoutId;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutPreviewIcon(
                  layoutId: layoutId,
                  selected: selected,
                  enabled: enabled,
                  width: 56,
                  height: 40,
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 72,
                  child: Text(
                    label,
                    style: AppTypography.metaStyle.copyWith(
                      fontSize: 10,
                      color: enabled
                          ? (selected
                                ? Theme.of(context).colorScheme.primary
                                : AppColors.text)
                          : AppColors.textHint,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
