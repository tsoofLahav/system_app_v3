import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/archive_index.dart';
import '../../files/data/topic.dart';
import '../../objects/data/app_view.dart';
import '../../objects/views/create_view_dialog.dart';
import '../shortcuts/app_shortcuts.dart';
import '../shortcuts/shortcut_catalog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/confirm_dialog.dart';
import '../../ui/glass_surface.dart';
import '../widgets/app_context_menu.dart';
import '../widgets/topic_emoji.dart';
import '../widgets/disclosure_icon.dart';
import '../create_topic/create_topic_dialog.dart';
import './sidebar_create_menu.dart';

abstract final class AppSidebarMetrics {
  static const defaultWidth = 200.0;
  static const outerStart = 10.0;
  static const outerEnd = 8.0;
  static const outerVertical = 10.0;
  static const phoneWidthFraction = 0.62;
  static const phoneMaxWidth = 248.0;

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
                  child: Padding(
                    padding: widget.isPhone
                        ? EdgeInsets.only(
                            top: MediaQuery.viewPaddingOf(context).top,
                            bottom: MediaQuery.viewPaddingOf(context).bottom,
                          )
                        : EdgeInsets.zero,
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
                        for (final type in state.topicTypes)
                          _TopicSection(
                            title: state.topicTypeDisplayName(type),
                            topics: state.topicsOfType(type.id),
                            selected: state.selectedTopic,
                            isViewMode: state.isViewMode ||
                                state.isArchiveMode ||
                                state.isDiagramMode,
                            state: state,
                            onSelect: _selectTopic,
                          ),
                        if (state.untypedTopics.isNotEmpty)
                          _TopicSection(
                            title: s['others'],
                            topics: state.untypedTopics,
                            selected: state.selectedTopic,
                            isViewMode: state.isViewMode ||
                                state.isArchiveMode ||
                                state.isDiagramMode,
                            state: state,
                            onSelect: _selectTopic,
                          ),
                        const _SidebarDivider(),
                        _DiagramEntry(state: state, onOpen: _openDiagram),
                        const _SidebarDivider(),
                        _ArchiveSection(
                          state: state,
                          onSelect: (topic) {
                            _closeDrawerIfOpen();
                            state.selectArchiveTopic(topic);
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                    child: Center(
                      child: Builder(
                        builder: (buttonContext) {
                          return Tooltip(
                            message: _shortcutTooltip(
                              s['create'],
                              ShortcutActionIds.addTopic,
                            ),
                            child: IconButton(
                              onPressed: () =>
                                  _openCreateMenu(buttonContext),
                              icon: const AppIcon(AppIcons.add, size: 28),
                              iconSize: 28,
                              color: AppColors.text,
                              padding: const EdgeInsets.all(10),
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  ],
                    ),
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

  Future<void> _openCreateMenu(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    // Tip of the downward caret points at the top center of the +.
    final anchor = box.localToGlobal(Offset(box.size.width / 2, 2));
    // Use the button's context (under the Overlay). Navigator.context sits
    // *above* the Overlay and makes Overlay.of throw.
    await showSidebarCreateMenu(
      context: buttonContext,
      state: widget.state,
      globalPosition: anchor,
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
        child: Text(s['objectsMap'], overflow: TextOverflow.ellipsis),
      ),
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

  Future<void> _deleteView(BuildContext context, AppView view) async {
    final s = state.strings;
    final ok = await showAppConfirmDialog(
      context: context,
      title: s['deleteViewTitle'],
      message: s.deleteViewMessage(view.name),
      confirmLabel: s['delete'],
      cancelLabel: s['cancel'],
      destructive: true,
    );
    if (ok) await state.deleteView(view);
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final next = List<AppView>.from(state.userViews);
    next.insert(newIndex, next.removeAt(oldIndex));
    state.reorderViews(next);
  }

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final views = state.userViews;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 2),
          child: Text(s['views'], style: AppTypography.sidebarSectionStyle),
        ),
        if (views.length < 2 || !state.sidebarReorderMode)
          for (final view in views)
            _ViewTile(
              key: ValueKey(view.id),
              view: view,
              selected: state.selectedViewType == view.type,
              onTap: () => onSelectView(view.type),
              onEdit: () => _renameView(context, view),
              onDelete: () => _deleteView(context, view),
              strings: s,
              attention: state.viewHasAttention(view.id),
            )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: (child, index, animation) {
              return Material(color: Colors.transparent, child: child);
            },
            itemCount: views.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final view = views[index];
              return _ViewTile(
                key: ValueKey(view.id),
                view: view,
                selected: state.selectedViewType == view.type,
                onTap: () => onSelectView(view.type),
                onEdit: () => _renameView(context, view),
                onDelete: () => _deleteView(context, view),
                strings: s,
                dragIndex: index,
                attention: state.viewHasAttention(view.id),
              );
            },
          ),
        const SizedBox(height: 2),
      ],
    );
  }
}

class _ViewTile extends StatelessWidget {
  const _ViewTile({
    super.key,
    required this.view,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.strings,
    this.dragIndex,
    this.attention = false,
  });

  final AppView view;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final AppStrings strings;
  final int? dragIndex;
  final bool attention;

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final action = await AppContextMenu.show(
      context: context,
      globalPosition: globalPosition,
      isRtl: strings.isRtl,
      entries: [
        AppContextMenuItem(value: 'edit', label: strings['edit']),
        AppContextMenuItem(
          value: 'delete',
          label: strings['delete'],
          destructive: true,
        ),
      ],
    );

    if (action == 'edit') onEdit();
    if (action == 'delete') onDelete();
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
          padding: const EdgeInsetsDirectional.fromSTEB(20, 3, 4, 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  view.name,
                  style: AppTypography.sidebarItemStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (attention)
                Tooltip(
                  message: strings['viewAttention'],
                  child: Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsetsDirectional.only(end: 6),
                    decoration: const BoxDecoration(
                      color: AppColors.destructive,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              if (dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex!,
                  child: const _SidebarDragHandle(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArchiveSection extends StatefulWidget {
  const _ArchiveSection({
    required this.state,
    required this.onSelect,
  });

  final AppState state;
  final ValueChanged<Topic> onSelect;

  @override
  State<_ArchiveSection> createState() => _ArchiveSectionState();
}

class _ArchiveSectionState extends State<_ArchiveSection> {
  bool expanded = false;
  final Set<int> _expandedTypeIds = {};
  var _othersExpanded = false;

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
              onTap: () => widget.onSelect(index.daily!.topic),
              onEdit: () {},
            ),
          for (final type in widget.state.topicTypes)
            if (index.topicsOfType(type.id).isNotEmpty)
              _ArchiveTopicGroup(
                title: widget.state.topicTypeDisplayName(type),
                expanded: _expandedTypeIds.contains(type.id),
                onToggle: () => setState(() {
                  if (!_expandedTypeIds.add(type.id)) {
                    _expandedTypeIds.remove(type.id);
                  }
                }),
                entries: index.topicsOfType(type.id),
                state: widget.state,
                onSelect: widget.onSelect,
              ),
          if (index.untypedTopics.isNotEmpty)
            _ArchiveTopicGroup(
              title: s['others'],
              expanded: _othersExpanded,
              onToggle: () =>
                  setState(() => _othersExpanded = !_othersExpanded),
              entries: index.untypedTopics,
              state: widget.state,
              onSelect: widget.onSelect,
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
    required this.onSelect,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final List<ArchiveTopicEntry> entries;
  final AppState state;
  final ValueChanged<Topic> onSelect;

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
              onTap: () => onSelect(entry.topic),
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
          widget.topics.length < 2 || !widget.state.sidebarReorderMode
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final topic in widget.topics) _topicTile(context, topic),
                  ],
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, index, animation) {
              return Material(color: Colors.transparent, child: child);
            },
                  itemCount: widget.topics.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final next = List<Topic>.from(widget.topics);
                    next.insert(newIndex, next.removeAt(oldIndex));
                    widget.state.reorderTopics(next);
                  },
                  itemBuilder: (context, index) {
                    final topic = widget.topics[index];
                    return KeyedSubtree(
                      key: ValueKey(topic.id),
                      child: _topicTile(context, topic, dragIndex: index),
                    );
                  },
                ),
        const SizedBox(height: 2),
      ],
    );
  }

  Widget _topicTile(BuildContext context, Topic topic, {int? dragIndex}) {
    return _TopicTile(
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
      dragIndex: dragIndex,
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
      topicTypeId: result.topicTypeId,
      clearTopicType: result.topicTypeId == null,
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
    this.dragIndex,
  });

  final Topic topic;
  final String displayName;
  final bool selected;
  final AppState state;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final Future<void> Function()? onDuplicate;
  final VoidCallback? onDelete;
  final int? dragIndex;

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final s = state.strings;
    final action = await AppContextMenu.show(
      context: context,
      globalPosition: globalPosition,
      isRtl: s.isRtl,
      entries: [
        AppContextMenuItem(value: 'edit', label: s['edit']),
        if (onDuplicate != null)
          AppContextMenuItem(value: 'duplicate', label: s['duplicateTopic']),
        if (onDelete != null)
          AppContextMenuItem(
            value: 'delete',
            label: s['delete'],
            destructive: true,
          ),
      ],
    );

    if (!context.mounted) return;
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
          padding: const EdgeInsetsDirectional.fromSTEB(20, 3, 4, 3),
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
              if (dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex!,
                  child: const _SidebarDragHandle(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarDragHandle extends StatelessWidget {
  const _SidebarDragHandle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsetsDirectional.only(start: 4),
      child: AppIcon(AppIcons.menu, size: 14),
    );
  }
}
