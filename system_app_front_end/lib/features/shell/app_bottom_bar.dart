import 'package:flutter/material.dart';

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
  static const barHeight = 54.0;
  static const floatMargin = 12.0;
  static const scrollInset = 82.0;
}

abstract final class AppTopicHeaderMetrics {
  static const headerHeight = 32.0;
  static const addButtonSize = 32.0;
  static const headerGap = 8.0;
  static const horizontalMargin = 16.0;
  static const floatMargin = 10.0;
  static const scrollTopInset = 52.0;
}

const _iconSize = 22.0;

class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key, required this.state});

  final AppState state;

  bool get _showLayout => !state.isViewMode && state.selectedDetail != null;

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
    final hasGraphData = state.hasDataForGraph;

    return SafeArea(
      top: false,
      child: FloatingGlassPill(
        verticalMargin: AppBottomBarMetrics.floatMargin,
        height: AppBottomBarMetrics.barHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BarIconButton(
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
            if (_showLayout) ...[
              _BarIconButton(
                tooltip: s['layout'],
                icon: AppIcons.layout,
                onPressed: () => _showLayoutPicker(context),
              ),
              _PaneDragToggle(state: state),
            ],
            if (canAi) ...[
              const SizedBox(width: 4),
              Container(
                width: 1,
                height: 26,
                color: AppColors.textHint.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 4),
              _AiToolGroup(
                state: state,
                enabled: hasContext && !state.aiRunning,
                graphEnabled: (hasContext || hasGraphData) && !state.aiRunning,
                running: state.aiRunning,
                onTool: (tool) => _runTool(context, tool),
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
            const SizedBox(width: 4),
          ],
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

    showDialog<void>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        title: Text(s['aiDone']),
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
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      onPressed: onPressed,
      icon: AppIcon(
        icon,
        size: _iconSize,
        color: AppColors.text.withValues(alpha: 0.72),
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
          child: Container(
            width: 78,
            height: 34,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: AppColors.noteTop.withValues(alpha: 0.52),
              border: Border.all(
                color: AppColors.noteBorder.withValues(alpha: 0.85),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: on
                      ? AlignmentDirectional.centerStart
                      : AlignmentDirectional.centerEnd,
                  child: Container(
                    width: 34,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: AppColors.noteTop.withValues(alpha: 0.95),
                      border: Border.all(
                        color: AppColors.noteBorder.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      width: 34,
                      child: Center(
                        child: AppIcon(
                          AppIcons.paneDrag,
                          size: 16,
                          color: on
                              ? AppColors.text.withValues(alpha: 0.9)
                              : AppColors.textHint.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      child: Center(
                        child: AppIcon(
                          AppIcons.summarize,
                          size: 16,
                          color: on
                              ? AppColors.textHint.withValues(alpha: 0.7)
                              : AppColors.text.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiToolGroup extends StatefulWidget {
  const _AiToolGroup({
    required this.state,
    required this.enabled,
    required this.graphEnabled,
    required this.running,
    required this.onTool,
  });

  final AppState state;
  final bool enabled;
  final bool graphEnabled;
  final bool running;
  final ValueChanged<String> onTool;

  @override
  State<_AiToolGroup> createState() => _AiToolGroupState();
}

class _AiToolGroupState extends State<_AiToolGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final cyan = AppColors.aiCyan;

    return GlassSurface(
      borderRadius: BorderRadius.circular(999),
      blurSigma: 10,
      tintOpacity: 0.12,
      showTopHighlight: true,
      elevation: 1,
      border: Border.all(color: cyan.withValues(alpha: 0.35), width: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AiToggleButton(
            tooltip: s['ai'],
            expanded: _expanded,
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...[
            _AiToolButton(
              tooltip: s['aiConsult'],
              icon: AppIcons.consult,
              enabled: widget.enabled && !widget.running,
              onPressed: () => widget.onTool('consult'),
            ),
            _AiToolButton(
              tooltip: s['aiSummarize'],
              icon: AppIcons.summarize,
              enabled: widget.enabled && !widget.running,
              onPressed: () => widget.onTool('summarize_to_doc'),
            ),
            _AiToolButton(
              tooltip: s['aiSmartList'],
              icon: AppIcons.smartList,
              enabled: widget.enabled && !widget.running,
              onPressed: () => widget.onTool('smart_list'),
            ),
            _AiToolButton(
              tooltip: s['aiImage'],
              icon: AppIcons.image,
              enabled: widget.enabled && !widget.running,
              onPressed: () => widget.onTool('create_image'),
            ),
            _AiToolButton(
              tooltip: s['aiGraph'],
              icon: AppIcons.graph,
              enabled: widget.graphEnabled,
              onPressed: () => widget.onTool('create_graph'),
            ),
            _AiToolButton(
              tooltip: s['aiReview'],
              icon: AppIcons.review,
              enabled: !widget.running,
              onPressed: () => widget.onTool('review'),
            ),
          ],
        ],
      ),
    );
  }
}

class _AiToggleButton extends StatelessWidget {
  const _AiToggleButton({
    required this.tooltip,
    required this.expanded,
    required this.onPressed,
  });

  final String tooltip;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cyan = AppColors.aiCyan;

    return IconButton(
      tooltip: tooltip,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      onPressed: onPressed,
      icon: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: cyan.withValues(alpha: expanded ? 0.7 : 0.35),
            width: 1,
          ),
          color: cyan.withValues(alpha: expanded ? 0.1 : 0.05),
        ),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: AppIcon(
            AppIcons.ai,
            size: _iconSize,
            color: cyan.withValues(alpha: expanded ? 0.95 : 0.65),
          ),
        ),
      ),
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
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
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
