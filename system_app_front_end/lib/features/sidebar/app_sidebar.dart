import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/archive_index.dart';
import '../../core/models/topic.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import '../../core/shortcuts/shortcut_catalog.dart';
import '../../core/registry/view_registry.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../../shared/widgets/topic_emoji.dart';
import '../../shared/widgets/disclosure_icon.dart';
import '../create_topic/create_topic_dialog.dart';

abstract final class AppSidebarMetrics {
  static const defaultWidth = 200.0;
  static const outerStart = 10.0;
  static const outerEnd = 8.0;
  static const outerVertical = 10.0;

  static double contentInset(double panelWidth) =>
      outerStart + panelWidth + outerEnd;
}

class AppSidebar extends StatefulWidget {
  const AppSidebar({
    super.key,
    required this.state,
    required this.width,
    required this.onWidthChanged,
  });

  final AppState state;
  final double width;
  final ValueChanged<double> onWidthChanged;

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  static const double _minWidth = 150;
  static const double _maxWidth = 340;
  static const double _resizeHandleWidth = 10;
  static const _sidebarRadius = 14.0;
  static const _panelTint = Color(0xFFDDF6F2);

  void _resize(DragUpdateDetails details) {
    final direction = Directionality.of(context);
    final delta = direction == TextDirection.rtl
        ? -details.delta.dx
        : details.delta.dx;
    final next = (widget.width + delta).clamp(_minWidth, _maxWidth).toDouble();
    widget.onWidthChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final s = state.strings;

    return SizedBox(
      width: widget.width,
      child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_sidebarRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: GlassSurface(
                  borderRadius: BorderRadius.circular(_sidebarRadius),
                  blurSigma: 22,
                  tintOpacity: 0.76,
                  tintColor: _panelTint,
                  elevation: 0,
                  border: Border.all(
                    color: AppColors.noteBorder.withValues(alpha: 0.5),
                    width: AppColors.filePaneBorderWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextButton(
                      onPressed: () => state.goHome(),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.text,
                        backgroundColor:
                            !state.isViewMode &&
                                !state.isArchiveMode &&
                                state.selectedTopic?.isMain == true
                            ? AppColors.noteBorder.withValues(alpha: 0.35)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(s['main'], overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                  const _SidebarDivider(),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        _ViewSection(state: state),
                        const _SidebarDivider(),
                        _TopicSection(
                          title: s['projects'],
                          topics: state.projects,
                          selected: state.selectedTopic,
                          isViewMode: state.isViewMode || state.isArchiveMode,
                          state: state,
                          onSelect: state.selectTopic,
                        ),
                        _TopicSection(
                          title: s['processes'],
                          topics: state.processes,
                          selected: state.selectedTopic,
                          isViewMode: state.isViewMode,
                          state: state,
                          onSelect: state.selectTopic,
                        ),
                        _TopicSection(
                          title: s['areas'],
                          topics: state.areas,
                          selected: state.selectedTopic,
                          isViewMode: state.isViewMode,
                          state: state,
                          onSelect: state.selectTopic,
                        ),
                        _TopicSection(
                          title: s['others'],
                          topics: state.others,
                          selected: state.selectedTopic,
                          isViewMode: state.isViewMode,
                          state: state,
                          onSelect: state.selectTopic,
                        ),
                        const _SidebarDivider(),
                        _ArchiveSection(state: state),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Tooltip(
                      message: _shortcutTooltip(
                        s['newTopic'],
                        ShortcutActionIds.addTopic,
                      ),
                      child: TextButton.icon(
                        onPressed: () => _createTopic(context),
                        icon: const AppIcon(AppIcons.add, size: 18),
                        label: Text(
                          s['newTopic'],
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.text,
                          alignment: AlignmentDirectional.centerStart,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            bottom: 0,
            end: 0,
            width: _resizeHandleWidth,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: _resize,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createTopic(BuildContext context) async {
    final state = widget.state;
    final result = await showDialog<CreateTopicResult>(
      context: context,
      builder: (_) => CreateTopicDialog(state: state),
    );
    if (result == null) return;
    await state.createTopic(
      name: result.name,
      type: result.type,
      icon: result.icon,
      color: result.color,
      selectedFileTypes: result.selectedFileTypes,
    );
  }

  String _shortcutTooltip(String label, String actionId) {
    final suffix = shortcutTooltipSuffix(widget.state, actionId);
    if (suffix == null) return label;
    return '$label ($suffix)';
  }
}

class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppColors.noteBorder.withValues(alpha: 0.45),
      ),
    );
  }
}

class _ViewSection extends StatelessWidget {
  const _ViewSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 2),
          child: Text(s['views'], style: AppTypography.sidebarSectionStyle),
        ),
        for (final view in ViewRegistry.views)
          _ViewTile(
            label: state.viewLabel(view.type),
            selected: state.selectedViewType == view.type,
            onTap: () => state.selectView(view.type),
          ),
        const SizedBox(height: 2),
      ],
    );
  }
}

class _ViewTile extends StatelessWidget {
  const _ViewTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.5)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 3, 8, 3),
          child: Text(
            label,
            style: AppTypography.sidebarItemStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _ArchiveSection extends StatefulWidget {
  const _ArchiveSection({required this.state});

  final AppState state;

  @override
  State<_ArchiveSection> createState() => _ArchiveSectionState();
}

class _ArchiveSectionState extends State<_ArchiveSection> {
  bool expanded = false;
  var _projectsExpanded = true;
  var _processesExpanded = true;
  var _areasExpanded = true;
  var _othersExpanded = true;

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final index = widget.state.archiveIndex;
    if (index.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => expanded = !expanded),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 2),
            child: Row(
              children: [
                DisclosureIcon(expanded: expanded, color: AppColors.text),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    s['archive'],
                    style: AppTypography.sidebarSectionStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          if (index.daily != null)
            _TopicTile(
              topic: index.daily!.topic,
              displayName: widget.state.topicDisplayName(index.daily!.topic),
              selected: widget.state.isArchiveMode &&
                  widget.state.selectedArchiveTopic?.id == index.daily!.topic.id,
              state: widget.state,
              onTap: () => widget.state.selectArchiveTopic(index.daily!.topic),
              onEdit: () {},
            ),
          if (index.projects.isNotEmpty)
            _ArchiveTopicGroup(
              title: s['projects'],
              expanded: _projectsExpanded,
              onToggle: () =>
                  setState(() => _projectsExpanded = !_projectsExpanded),
              entries: index.projects,
              state: widget.state,
            ),
          if (index.processes.isNotEmpty)
            _ArchiveTopicGroup(
              title: s['processes'],
              expanded: _processesExpanded,
              onToggle: () =>
                  setState(() => _processesExpanded = !_processesExpanded),
              entries: index.processes,
              state: widget.state,
            ),
          if (index.areas.isNotEmpty)
            _ArchiveTopicGroup(
              title: s['areas'],
              expanded: _areasExpanded,
              onToggle: () => setState(() => _areasExpanded = !_areasExpanded),
              entries: index.areas,
              state: widget.state,
            ),
          if (index.others.isNotEmpty)
            _ArchiveTopicGroup(
              title: s['others'],
              expanded: _othersExpanded,
              onToggle: () =>
                  setState(() => _othersExpanded = !_othersExpanded),
              entries: index.others,
              state: widget.state,
            ),
        ],
        const SizedBox(height: 2),
      ],
    );
  }
}

class _ArchiveTopicGroup extends StatelessWidget {
  const _ArchiveTopicGroup({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.entries,
    required this.state,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final List<ArchiveTopicEntry> entries;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 3, 8, 2),
            child: Row(
              children: [
                DisclosureIcon(
                  expanded: expanded,
                  color: AppColors.text.withValues(alpha: 0.72),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.metaStyle.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final entry in entries)
            _TopicTile(
              topic: entry.topic,
              displayName: state.topicDisplayName(entry.topic),
              selected: state.isArchiveMode &&
                  state.selectedArchiveTopic?.id == entry.topic.id,
              state: state,
              onTap: () => state.selectArchiveTopic(entry.topic),
              onEdit: () {},
            ),
      ],
    );
  }
}

class _TopicSection extends StatefulWidget {
  const _TopicSection({
    required this.title,
    required this.topics,
    required this.selected,
    required this.isViewMode,
    required this.state,
    required this.onSelect,
  });

  final String title;
  final List<Topic> topics;
  final Topic? selected;
  final bool isViewMode;
  final AppState state;
  final Future<void> Function(Topic) onSelect;

  @override
  State<_TopicSection> createState() => _TopicSectionState();
}

class _TopicSectionState extends State<_TopicSection> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => expanded = !expanded),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 2),
            child: Row(
              children: [
                DisclosureIcon(expanded: expanded, color: AppColors.text),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.title,
                    style: AppTypography.sidebarSectionStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          ...widget.topics.map(
            (topic) => _TopicTile(
              topic: topic,
              displayName: widget.state.topicDisplayName(topic),
              selected: !widget.isViewMode && widget.selected?.id == topic.id,
              state: widget.state,
              onTap: () => widget.onSelect(topic),
              onEdit: () => _editTopic(context, topic),
              onDuplicate: topic.isMain
                  ? null
                  : () => widget.state.duplicateTopic(topic),
              onDelete: topic.isMain
                  ? null
                  : () => _confirmDelete(context, topic),
            ),
          ),
        const SizedBox(height: 2),
      ],
    );
  }

  Future<void> _editTopic(BuildContext context, Topic topic) async {
    final result = await showDialog<EditTopicResult>(
      context: context,
      builder: (_) => CreateTopicDialog(state: widget.state, topic: topic),
    );
    if (result == null) return;
    await widget.state.updateTopic(
      topic: topic,
      name: result.name,
      icon: result.icon,
      color: result.color,
    );
  }

  Future<void> _confirmDelete(BuildContext context, Topic topic) async {
    final s = widget.state.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        title: Text(s['deleteTopicTitle']),
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
        child: Text(s.deleteTopicMessage(topic.name)),
      ),
    );
    if (ok == true) {
      await widget.state.deleteTopic(topic);
    }
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.topic,
    required this.displayName,
    required this.selected,
    required this.state,
    required this.onTap,
    required this.onEdit,
    this.onDuplicate,
    this.onDelete,
  });

  final Topic topic;
  final String displayName;
  final bool selected;
  final AppState state;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final Future<void> Function()? onDuplicate;
  final VoidCallback? onDelete;

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final s = state.strings;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(value: 'edit', child: Text(s['edit'])),
        if (onDuplicate != null)
          PopupMenuItem(value: 'duplicate', child: Text(s['duplicateTopic'])),
        if (onDelete != null)
          PopupMenuItem(value: 'delete', child: Text(s['delete'])),
      ],
    );

    if (action == 'edit') onEdit();
    if (action == 'duplicate') await onDuplicate?.call();
    if (action == 'delete') onDelete?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.5)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 3, 8, 3),
          child: Row(
            children: [
              TopicEmoji(value: topic.icon, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  displayName,
                  style: AppTypography.sidebarItemStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
