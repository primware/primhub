import 'package:flutter/material.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/ui/pages/Projects/Projects_Widgets/task_item.dart';

import 'package:primhub/ui/pages/Projects/dialogs/item_edit_dialog.dart';
import 'package:primhub/ui/pages/Projects/dialogs/task_create_dialog.dart';
import 'package:flutter_localization/flutter_localization.dart';

class PhaseItem extends StatelessWidget {
  final Map<String, dynamic> phase;
  final bool initiallyExpanded;
  final Map<String, int> statusIdMap;
  final Map<String, String> priorityMap;
  final VoidCallback onRefresh;
  final Function(String type, int id, Map<String, dynamic> data) onEdit;
  final Function(int phaseId, int projectId, Map<String, dynamic> data) onCreateTask;
  final bool isArchived;
  final int projectId;

  const PhaseItem({super.key, required this.phase, required this.initiallyExpanded, required this.statusIdMap, required this.priorityMap, required this.onRefresh, required this.onEdit, required this.onCreateTask, this.isArchived = false, required this.projectId});

  @override
  Widget build(BuildContext context) {
    final tasks = phase['C_ProjectTask'] as List? ?? [];
    final int phaseId = phase['id'] is int ? phase['id'] as int : int.tryParse(phase['id'].toString()) ?? 0;
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ExpansionTile(
        key: Key('phase-$phaseId'),
        initiallyExpanded: initiallyExpanded,
        backgroundColor: Colors.white, // Color cuando se expande
        collapsedBackgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        title: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = MediaQuery.of(context).size.width < 500;
            return Row(
              children: [
                Expanded(
                  child: Text(
                    phase['Name'] ?? 'Fase',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo[900],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tasks.isNotEmpty && !isNarrow) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.task_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('${tasks.length}', style: const TextStyle(color: Colors.grey))
                ],
              ],
            );
          }
        ),
        subtitle: Text(
          phase['Description'] ?? '',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        leading: CircleAvatar(
          backgroundColor: Colors.indigo[50],
          radius: 16,
          child: const Icon(Icons.flag_outlined, size: 18, color: Colors.indigo),
        ),
        trailing: AccessControl.canEditProject && !isArchived
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_task, size: 18, color: Colors.green),
                    tooltip: AppLocale.newTask.getString(context),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => TaskCreateDialog(
                          onSave: (data) => onCreateTask(phaseId, projectId, data),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18, color: Colors.grey),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => ItemEditDialog(
                          type: 'phase',
                          currentName: phase['Name'],
                          currentDesc: phase['Description'] ?? '',
                          currentData: phase,
                          onSave: (data) => onEdit('phase', phaseId, data),
                        ),
                      );
                    },
                  ),
                ],
              )
            : null,
        children: tasks
            .map((task) => TaskItem(
                task: task,
                phase: phase,
                initiallyExpanded: initiallyExpanded,
                statusIdMap: statusIdMap,
                priorityMap: priorityMap,
                onRefresh: onRefresh,
                onEdit: onEdit,
                isArchived: isArchived,
                projectId: projectId))
            .toList(),
      ),
    );
  }
}
