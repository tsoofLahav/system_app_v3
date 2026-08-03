import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/archive_index.dart';
import '../../files/data/topic.dart';
import '../../objects/data/app_view.dart';
import '../../objects/tags/create_tag_dialog.dart';
import '../../objects/views/create_view_dialog.dart';
import '../shortcuts/app_shortcuts.dart';
import '../shortcuts/shortcut_catalog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/confirm_dialog.dart';
import '../../ui/glass_surface.dart';
import '../widgets/topic_emoji.dart';
import '../widgets/disclosure_icon.dart';
import '../create_topic/create_topic_dialog.dart';
import '../topic/topic_appearance.dart';

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
    this.isPhone = false,
    this.width = AppSidebarMetrics.defaultWidth,
    this.onWidthChanged,
  });

  final AppState state;
  final bool isPhone;
  final double width;
  final ValueChanged<double>? onWidthChanged;

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  static const double _minWidth = 150;
  static const double _maxWidth = 340;
  static const double _resizeHandleWidth = 10;
  static const _sidebarRadius = 14.0;
  static const _panelTint = AppColors.glassTint;

  void _resize(DragUpdateDetails details) {
    final onWidthChanged = widget.onWidthChanged;
    if (onWidthChanged == null) return;
    final direction = Directionality.of(context);
    final delta = direction == TextDirection.rtl
        ? -details.delta.dx
        : details.delta.dx;
    final next = (widget.width + delta).clamp(_minWidth, _maxWidth).toDouble();
    onWidthChanged(next);
  }

  void _closeDrawerIfOpen() {
    if (!widget.isPhone || !mounted) return;
    Navigator.of(context).pop();
  }

  void _goHome() {
    _closeDrawerIfOpen();
    widget.state.goHome();
  }

  Future<void> _selectTopic(Topic topic) async {
    _closeDrawerIfOpen();
    await widget.state.selectTopic(topic);
  }

  Future<void> _selectView(String viewType) async {
    _closeDrawerIfOpen();
    await widget.state.selectView(viewType);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final s = state.strings;
    final panelWidth = widget.isPhone ? double.infinity : widget.width;
    final borderRadius = widget.isPhone
        ? BorderRadius.zero
        : BorderRadius.circular(_sidebarRadius);

    return SizedBox(
      width: panelWidth,
      child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  boxShadow: widget.isPhone
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: GlassSurface(
                  borderRadius: borderRadius,
                  blurSigma: widget.isPhone ? 0 : 22,
                  tintOpacity: widget.isPhone ? 1 : 0.76,
                  tintColor: _panelTint,
                  elevation: 0,
                  border: widget.isPhone
                      ? null
                      : Border.all(
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
                      onPressed: _goHome,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.text,
                        backgroundColor:
                            !state.isViewMode &&
                                !state.isArchiveMode &&
                                !state.isDiagramMode &&
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
                        _ViewSection(state: state, onSelectView: _selectView),
                        const _SidebarDivider(),
                        _DiagramEntry(state: state, onOpen: _openDiagram),
                        const _SidebarDivider(),
                        _TopicSection(
                          title: s['projects'],
                          topics: state.projects,
                          selected: state.selectedTopic,
                          isViewMode: state.isViewMode ||
                              state.isArchiveMode ||
                              state.isDiagramMode,
                          state: state,
                          onSelect: _selectTopic,
                        ),
                        _TopicSection(
                          title: s['processes'],
                          topics: state.processes,
                          selected: state.selectedTopic,
                          isViewMode:
                              state.isViewMode || state.isDiagramMode,
                          state: state,
                          onSelect: _selectTopic,
                        ),
                        _TopicSection(
                          title: s['areas'],
                          topics: state.areas,
                          selected: state.selectedTopic,
                          isViewMode:
                              state.isViewMode || state.isDiagramMode,
                          state: state,
                          onSelect: _selectTopic,
                        ),
                        _TopicSection(
                          title: s['others'],
                          topics: state.others,
                          selected: state.selectedTopic,
                          isViewMode:
                              state.isViewMode || state.isDiagramMode,
                          state: state,
                          onSelect: _selectTopic,
                        ),
                        const _SidebarDivider(),
                        _TagsSection(state: state),
                        if (!widget.isPhone) ...[
                          const _SidebarDivider(),
                          _ArchiveSection(state: state),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Tooltip(
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
                        Tooltip(
                          message: _shortcutTooltip(
                            s['newView'],
                            ShortcutActionIds.addView,
                          ),
                          child: TextButton.icon(
                            onPressed: () => _createView(context),
                            icon: const AppIcon(AppIcons.add, size: 18),
                            label: Text(
                              s['newView'],
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
                        TextButton.icon(
                          onPressed: () => _createTag(context),
                          icon: const AppIcon(AppIcons.add, size: 18),
                          label: Text(
                            s['newTag'],
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
                      ],
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ),
          if (!widget.isPhone)
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
    _closeDrawerIfOpen();
    final result = await showAppDialog<CreateTopicResult>(
      context: context,
      builder: (_) => CreateTopicDialog(state: state),
    );
    if (result == null) return;
    await state.createTopic(
      name: result.name,
      type: result.type,
      icon: result.icon,
      color: result.color,
    );
  }

  Future<void> _createView(BuildContext context) async {
    final state = widget.state;
    _closeDrawerIfOpen();
    final name = await showCreateViewDialog(context: context, state: state);
    if (name == null) return;
    await state.createView(name: name);
  }

  Future<void> _createTag(BuildContext context) async {
    final state = widget.state;
    _closeDrawerIfOpen();
    final result = await showCreateTagDialog(context: context, state: state);
    if (result == null) return;
    await state.createWorkspaceTag(
      name: result.name,
      icon: result.icon,
      color: result.color,
    );
  }

  Future<void> _openDiagram() async {
    _closeDrawerIfOpen();
    await widget.state.openDiagram();
  }

  String _shortcutTooltip(String label, String actionId) {
    final suffix = shortcutTooltipSuffix(widget.state, actionId);
    if (suffix == null) return label;
    return '$label ($suffix)';
  }
}

class _DiagramEntry extends StatelessWidget {
  const _DiagramEntry({required this.state, required this.onOpen});

  final AppState state;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton(
        onPressed: onOpen,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.text,
          backgroundColor: state.isDiagramMode
              ? AppColors.noteBorder.withValues(alpha: 0.35)
              : Colors.transparent,
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        child: Text(s['diagram'], overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _TagsSection extends StatefulWidget {
  const _TagsSection({required this.state});

  final AppState state;

  @override
  State<_TagsSection> createState() => _TagsSectionState();
}

class _TagsSectionState extends State<_TagsSection> {
  var expanded = true;

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final tags = widget.state.objectTags;
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
                    s['tags'],
                    style: AppTypography.sidebarSectionStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final tag in tags)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(28, 2, 8, 2),
              child: Row(
                children: [
                  Text(
                    tag.icon?.isNotEmpty == true
                        ? tag.icon!
                        : TopicAppearance.defaultEmoji,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tag.name,
                      style: AppTypography.metaStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        if (expanded && tags.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(28, 4, 8, 4),
            child: Text(
              s['noTagsYet'],
              style: AppTypography.metaStyle.copyWith(
                color: AppColors.textHint,
              ),
            ),
          ),
      ],
    );
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
  const _ViewSection({required this.state, required this.onSelectView});

  final AppState state;
  final Future<void> Function(String viewType) onSelectView;

  Future<void> _renameView(BuildContext context, AppView view) async {
    final name = await showCreateViewDialog(
      context: context,
      state: state,
      view: view,
    );
    if (name == null) return;
    await state.renameView(view, name: name);
  }

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
        for (final view in state.userViews)
          _ViewTile(
            label: view.name,
            selected: state.selectedViewType == view.type,
            onTap: () => onSelectView(view.type),
            onEdit: () => _renameView(context, view),
            strings: s,
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
    required this.onEdit,
    required this.strings,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final AppStrings strings;

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(value: 'edit', child: Text(strings['edit'])),
      ],
    );

    if (action == 'edit') onEdit();
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
    final result = await showAppDialog<EditTopicResult>(
      context: context,
      builder: (_) => CreateTopicDialog(state: widget.state, topic: topic),
    );
    if (result == null) return;
    await widget.state.updateTopic(
      topic,
      name: result.name,
      icon: result.icon,
      color: result.color,
    );
  }

  Future<void> _confirmDelete(BuildContext context, Topic topic) async {
    final s = widget.state.strings;
    final ok = await showAppConfirmDialog(
      context: context,
      title: s['deleteTopicTitle'],
      message: s.deleteTopicMessage(topic.name),
      confirmLabel: s['delete'],
      cancelLabel: s['cancel'],
      destructive: true,
    );
    if (ok) {
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
