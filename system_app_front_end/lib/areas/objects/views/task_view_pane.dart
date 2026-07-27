import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../ui/app_typography.dart';
import '../tasks/task_row.dart';

class TaskViewPane extends StatelessWidget {
  const TaskViewPane({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final viewType = state.selectedViewType;
    if (viewType == null) {
      return Center(child: Text(state.strings['selectView']));
    }

    final label = state.viewLabel(viewType);
    final tasks = state.viewTasks;
    final sections = state.sectionsForViewType(viewType);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
      children: [
        Text(label, style: AppTypography.pageTitleStyle),
        const SizedBox(height: 12),
        if (sections.isEmpty && tasks.isEmpty)
          Text(state.strings['emptyView'] ?? 'No tasks in this view yet.')
        else ...[
          for (final section in sections) ...[
            Text(section, style: AppTypography.noteTitleStyle),
            const SizedBox(height: 8),
          ],
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TaskRow(
                task: task,
                state: state,
                onToggle: () => state.toggleTaskStatus(task),
                onTitleChanged: (title) => state.updateTaskTitle(task, title),
              ),
            ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            final controller = TextEditingController();
            final name = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(state.strings.newSectionTitle(label)),
                content: TextField(
                  controller: controller,
                  decoration: InputDecoration(labelText: state.strings['sectionName']),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(state.strings['cancel'])),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    child: Text(state.strings['add']),
                  ),
                ],
              ),
            );
            if (name != null && name.isNotEmpty) {
              await state.createViewSection(viewType, name);
            }
          },
          icon: const Icon(Icons.add),
          label: Text(state.strings['addSection'] ?? 'Add section'),
        ),
      ],
    );
  }
}
