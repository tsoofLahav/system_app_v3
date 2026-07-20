import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../bring_file/bring_file_picker_dialog.dart';
import '../create_topic/add_file_dialog.dart';
import '../sidebar/app_sidebar.dart';
import '../task_view/task_view_pane.dart';
import '../topic/topic_view.dart';
import '../../shared/widgets/main_pane_loader.dart';
import 'automation_dialog.dart';
import 'ai_tool_bar.dart';
import 'desktop_app_shell.dart';
import 'preferences_dialog.dart';

class PhoneAppShell extends StatefulWidget {
  const PhoneAppShell({super.key, required this.state});

  final AppState state;

  @override
  State<PhoneAppShell> createState() => _PhoneAppShellState();
}

class _PhoneAppShellState extends State<PhoneAppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  AppState get state => widget.state;

  String _title() {
    final s = state.strings;
    if (state.isViewMode && state.selectedViewType != null) {
      return state.viewLabel(state.selectedViewType!);
    }
    final topic = state.selectedTopic ?? state.selectedDetail?.topic;
    if (topic == null) return 'system_app';
    if (topic.isMain) return s['main'];
    return topic.name;
  }

  bool get _showAddFile =>
      !state.isViewMode &&
      state.selectedDetail != null &&
      !state.topicDetailStale;

  bool get _showBringFile =>
      _showAddFile && (state.selectedTopic?.isMain ?? false);

  Future<void> _addFile(BuildContext context) async {
    final topic = state.selectedTopic;
    final detail = state.selectedDetail;
    if (topic == null || detail == null) return;
    final result = await showAddFileDialog(
      context: context,
      state: state,
      topic: topic,
      existingTypes: detail.files.map((f) => f.type).toList(growable: false),
    );
    if (result == null) return;
    await state.addFile(topic: topic, type: result.type, name: result.name);
    if (!context.mounted) return;
    if (state.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.error!)),
      );
    }
  }

  Future<void> _bringFile(BuildContext context) async {
    final entry = await showBringFilePicker(context, state);
    if (entry == null) return;
    await state.bringFileOnPhone(entry.topic, entry.file);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.canvasNeutralBottom,
          drawer: Drawer(
            width: MediaQuery.sizeOf(context).width * 0.86,
            backgroundColor: Colors.transparent,
            child: SafeArea(
              child: AppSidebar(
                state: state,
                isPhone: true,
              ),
            ),
          ),
          appBar: AppBar(
            backgroundColor: AppColors.canvasNeutralBottom.withValues(alpha: 0.92),
            elevation: 0,
            scrolledUnderElevation: 0.5,
            title: Text(
              _title(),
              style: AppTypography.noteTitleStyle.copyWith(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
            leading: IconButton(
              icon: const AppIcon(AppIcons.menu, size: 22),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            actions: [
              if (_showBringFile)
                IconButton(
                  tooltip: state.strings['bringFile'],
                  icon: const AppIcon(AppIcons.bringFile, size: 22),
                  onPressed: () => _bringFile(context),
                ),
              if (_showAddFile)
                IconButton(
                  tooltip: state.strings['addFile'],
                  icon: const AppIcon(AppIcons.add, size: 22),
                  onPressed: () => _addFile(context),
                ),
            ],
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(child: AppShellCanvas()),
              Positioned.fill(
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.sizeOf(context).height * 0.1,
                    ),
                    child: !state.appReady
                        ? const MainPaneLoader()
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: state.isViewMode && state.viewPaneReady
                                ? TaskViewPane(
                                    key: ValueKey(
                                      'view-${state.selectedViewType}',
                                    ),
                                    state: state,
                                  )
                                : TopicView(
                                    key: ValueKey(
                                      'topic-${state.selectedDetail?.topic.id ?? 'none'}',
                                    ),
                                    state: state,
                                  ),
                          ),
                  ),
                ),
              ),
              if (state.isViewMode && state.loading)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: MediaQuery.sizeOf(context).height,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _PhoneBottomToolsSheet(state: state),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PhoneBottomToolsSheet extends StatelessWidget {
  const _PhoneBottomToolsSheet({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    final canAi = state.canUseAiTools;
    final maxSize = canAi ? 0.38 : 0.28;

    return DraggableScrollableSheet(
      initialChildSize: 0.09,
      minChildSize: 0.09,
      maxChildSize: maxSize,
      snap: true,
      snapSizes: [0.09, maxSize],
      builder: (context, scrollController) {
        return SafeArea(
          top: false,
          child: GlassSurface(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            tintOpacity: 0.88,
            elevation: 4,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.text.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                ListTile(
                  leading: const AppIcon(AppIcons.preferences, size: 22),
                  title: Text(s['preferences']),
                  onTap: () =>
                      showPreferencesDialog(context: context, state: state),
                ),
                ListTile(
                  leading: const AppIcon(AppIcons.automations, size: 22),
                  title: Text(s['automations']),
                  onTap: () =>
                      showAutomationDialog(context: context, state: state),
                ),
                if (canAi) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('AI', style: AppTypography.metaStyle),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: AiToolBar(
                      state: state,
                      onTool: (tool) => runAiTool(context, state, tool),
                    ),
                  ),
                  if (state.aiRunning)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.aiCyan.withValues(alpha: 0.85),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(s['aiRunning'], style: AppTypography.metaStyle),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
