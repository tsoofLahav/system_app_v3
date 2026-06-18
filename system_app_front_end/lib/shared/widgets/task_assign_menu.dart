import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/task.dart';
import '../../core/models/task_view_membership.dart';
import '../../core/models/view_section.dart';
import '../../core/registry/view_registry.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';

Future<void> showTaskAssignMenu({
  required BuildContext context,
  required Offset globalPosition,
  required Task task,
  required AppState state,
}) async {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (ctx) => _TaskAssignMenuOverlay(
      position: globalPosition,
      task: task,
      state: state,
      onClose: () => entry.remove(),
    ),
  );

  overlay.insert(entry);
}

class _TaskAssignMenuOverlay extends StatefulWidget {
  const _TaskAssignMenuOverlay({
    required this.position,
    required this.task,
    required this.state,
    required this.onClose,
  });

  final Offset position;
  final Task task;
  final AppState state;
  final VoidCallback onClose;

  @override
  State<_TaskAssignMenuOverlay> createState() => _TaskAssignMenuOverlayState();
}

class _TaskAssignMenuOverlayState extends State<_TaskAssignMenuOverlay> {
  String? _hoveredViewType;
  List<TaskViewMembership> _memberships = [];
  Map<String, List<ViewSection>> _sectionsByView = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final memberships = await widget.state.membershipsForTask(widget.task.id);
    final sectionsByView = <String, List<ViewSection>>{};
    for (final view in ViewRegistry.views) {
      sectionsByView[view.type] = widget.state.sectionsForViewType(view.type);
      if (sectionsByView[view.type]!.isEmpty) {
        try {
          final loaded = await widget.state.loadSectionsForView(view.type);
          sectionsByView[view.type] = loaded;
        } catch (_) {
          sectionsByView[view.type] = [];
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _memberships = memberships;
      _sectionsByView = sectionsByView;
      _loading = false;
    });
  }

  TaskViewMembership? _membershipFor(String viewType) {
    for (final m in _memberships) {
      if (m.viewType == viewType) return m;
    }
    return null;
  }

  Future<void> _toggleView(String viewType) async {
    final existing = _membershipFor(viewType);
    if (existing != null) {
      await widget.state.removeTaskFromView(existing);
    } else {
      await widget.state.addTaskToView(widget.task, viewType);
    }
    await _load();
  }

  Future<void> _assignSection(String viewType, ViewSection? section) async {
    final existing = _membershipFor(viewType);
    if (section == null) {
      if (existing != null) {
        await widget.state.removeTaskFromView(existing);
      }
    } else if (existing != null &&
        existing.sectionName == section.name) {
      await widget.state.removeTaskFromView(existing);
    } else {
      await widget.state.addTaskToView(
        widget.task,
        viewType,
        sectionName: section.name,
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    const menuWidth = 168.0;
    const subWidth = 152.0;
    final left = widget.position.dx.clamp(8.0, screen.width - menuWidth - subWidth - 16);
    final top = widget.position.dy.clamp(8.0, screen.height - 320);

    final hoveredSections = _hoveredViewType != null
        ? (_sectionsByView[_hoveredViewType!] ?? [])
        : <ViewSection>[];

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: AppColors.noteTop,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.noteBorder),
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: menuWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                                child: Text(
                                  widget.state.strings['addTo'],
                                  style: AppTypography.metaStyle.copyWith(
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                              for (final view in ViewRegistry.views)
                                _ViewMenuRow(
                                  label: widget.state.viewLabel(view.type),
                                  isMember: _membershipFor(view.type) != null,
                                  isHovered: _hoveredViewType == view.type,
                                  hasSections:
                                      (_sectionsByView[view.type] ?? []).isNotEmpty,
                                  onHover: () =>
                                      setState(() => _hoveredViewType = view.type),
                                  onTap: () async {
                                    final sections = _sectionsByView[view.type] ?? [];
                                    if (sections.isEmpty) {
                                      await _toggleView(view.type);
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),
                        if (_hoveredViewType != null && hoveredSections.isNotEmpty)
                          Container(
                            width: subWidth,
                            decoration: BoxDecoration(
                              border: BorderDirectional(
                                start: BorderSide(
                                  color: AppColors.noteBorder.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 10, 12, 6),
                                  child: Text(
                                    widget.state.viewLabel(_hoveredViewType!),
                                    style: AppTypography.metaStyle.copyWith(
                                      color: AppColors.text,
                                    ),
                                  ),
                                ),
                                for (final section in hoveredSections)
                                  _SectionMenuRow(
                                    label: section.name,
                                    isSelected: _membershipFor(_hoveredViewType!)
                                            ?.sectionName ==
                                        section.name,
                                    onTap: () =>
                                        _assignSection(_hoveredViewType!, section),
                                  ),
                                _SectionMenuRow(
                                  label: widget.state.strings['removeFromView'],
                                  isDestructive: true,
                                  onTap: () async {
                                    final m = _membershipFor(_hoveredViewType!);
                                    if (m != null) {
                                      await widget.state.removeTaskFromView(m);
                                      await _load();
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewMenuRow extends StatelessWidget {
  const _ViewMenuRow({
    required this.label,
    required this.isMember,
    required this.isHovered,
    required this.hasSections,
    required this.onHover,
    required this.onTap,
  });

  final String label;
  final bool isMember;
  final bool isHovered;
  final bool hasSections;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: isHovered
              ? AppColors.noteBorder.withValues(alpha: 0.35)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              AppIcon(
                isMember ? AppIcons.check : AppIcons.circle,
                size: 14,
                color: isMember ? AppColors.text : AppColors.textHint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: AppTypography.noteBodyStyle),
              ),
              if (hasSections)
                Transform.flip(
                  flipX: Directionality.of(context) == TextDirection.rtl,
                  child: AppIcon(
                    AppIcons.chevronRight,
                    size: 16,
                    color: AppColors.textHint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionMenuRow extends StatelessWidget {
  const _SectionMenuRow({
    required this.label,
    required this.onTap,
    this.isSelected = false,
    this.isDestructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isSelected;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (!isDestructive) ...[
              AppIcon(
                isSelected ? AppIcons.check : AppIcons.circle,
                size: 14,
                color: isSelected ? AppColors.text : AppColors.textHint,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                style: AppTypography.noteBodyStyle.copyWith(
                  color: isDestructive ? Colors.red.shade700 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
