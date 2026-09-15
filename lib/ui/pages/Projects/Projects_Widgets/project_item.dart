import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/api/access_control.dart';

import 'package:primhub/ui/pages/Projects/dialogs/phase_create_dialog.dart';
import 'package:primhub/ui/pages/Projects/dialogs/project_calendar_dialog.dart';
import 'package:primhub/ui/pages/Projects/dialogs/project_info_dialog.dart';
import 'package:primhub/ui/pages/Projects/Projects_Widgets/phase_item.dart';
import 'package:primhub/ui/pages/Projects/Projects_Widgets/task_item.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:flutter_localization/flutter_localization.dart';

class ProjectItem extends StatelessWidget {
  final Map<String, dynamic> project;
  final bool isExpanded;
  final Map<String, int> statusIdMap;
  final Map<String, String> priorityMap;
  final VoidCallback onRefresh;
  final Function(String type, int id, Map<String, dynamic> data) onEdit;
  final Function(int projectId, Map<String, dynamic> data) onCreatePhase;
  final Function(int phaseId, int projectId, Map<String, dynamic> data) onCreateTask;
  final Function(Map<String, dynamic> project, String viewType) onShowFiles;
  final VoidCallback? onToggleExpansion;
  final bool isArchived;
  final Map<String, dynamic>? stats;

  const ProjectItem({
    super.key,
    required this.project,
    required this.isExpanded,
    required this.statusIdMap,
    required this.priorityMap,
    required this.onRefresh,
    required this.onEdit,
    required this.onCreatePhase,
    required this.onCreateTask,
    required this.onShowFiles,
    this.onToggleExpansion,
    this.isArchived = false,
    this.stats,
  });

  @override
  Widget build(BuildContext context) {
    // ... (sorting logic stays same)
    final phases = (project['C_ProjectPhase'] as List? ?? []).map((e) {
      if (e is Map) return Map<String, dynamic>.from(e);
      return <String, dynamic>{};
    }).toList();
    phases.sort((a, b) {
      final idA = a['id'] is int ? a['id'] : int.tryParse(a['id']?.toString() ?? '0') ?? 0;
      final idB = b['id'] is int ? b['id'] : int.tryParse(b['id']?.toString() ?? '0') ?? 0;
      return idA.compareTo(idB);
    });

    final directTasks = (project['C_ProjectTask'] as List? ?? []).map((e) {
      if (e is Map) return Map<String, dynamic>.from(e);
      return <String, dynamic>{};
    }).toList();
    directTasks.sort((a, b) {
      final idA = a['id'] is int ? a['id'] : int.tryParse(a['id']?.toString() ?? '0') ?? 0;
      final idB = b['id'] is int ? b['id'] : int.tryParse(b['id']?.toString() ?? '0') ?? 0;
      return idA.compareTo(idB);
    });

    final int projId = project['id'] is int ? project['id'] as int : int.tryParse(project['id'].toString()) ?? 0;

    int totalPhases = phases.length;
    int totalTasks = directTasks.length;
    for (var phase in phases) {
      if (phase['C_ProjectTask'] is List) {
        totalTasks += (phase['C_ProjectTask'] as List).length;
      }
    }
    
    int totalRequests = 0;
    try {
      final projIdStr = projId.toString();
      totalRequests = GlobalCache.requests.where((r) {
        final rProjId = r['C_Project_ID'];
        if (rProjId is Map) {
          return rProjId['id']?.toString() == projIdStr;
        }
        return rProjId?.toString() == projIdStr;
      }).length;
    } catch (_) {
      // Ignored: Fail silently
    }

    final colorScheme = Theme.of(context).colorScheme;
    final uniformColor = colorScheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      child: ExpansionTile(
          key: Key('project-$projId-$isExpanded'),
          initiallyExpanded: isExpanded,
          backgroundColor: Colors.white,
          collapsedBackgroundColor: Colors.white,
          iconColor: uniformColor,
          trailing: const SizedBox.shrink(),
          onExpansionChanged: (expanded) {
            if (onToggleExpansion != null) {
              onToggleExpansion!();
            }
          },
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: uniformColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.folder, color: uniformColor, size: 24),
          ),
          title: LayoutBuilder(
            builder: (context, constraints) {

              return Row(
                children: [
                  Expanded(
                    child: Text(
                      project['Name'] ?? 'Sin Nombre',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (AccessControl.canEditProject)
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20, color: Colors.blueGrey),
                      tooltip: isArchived ? AppLocale.reactivateProject.getString(context) : AppLocale.editProject.getString(context),
                      onPressed: () {
                        onEdit('project', projId, {
                          'Name': project['Name'] ?? '',
                          'Description': project['Description'] ?? '',
                        });
                      },
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                ],
              );
            },
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (project['Description'] != null)
                Text(
                  project['Description'],
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _buildCounterBadge(
                    Icons.layers_outlined, 
                    AppLocale.phasesCount.getStringWithVariables(context, {'count': '$totalPhases'}),
                  ),
                  _buildCounterBadge(
                    Icons.task_alt, 
                    AppLocale.tasksCount.getStringWithVariables(context, {'count': '$totalTasks'}),
                  ),
                  _buildCounterBadge(
                    Icons.assignment_ind_outlined, 
                    AppLocale.requestsCount.getStringWithVariables(context, {'count': '$totalRequests'}),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildActionButton(context, Icons.folder_open, AppLocale.deliverables.getString(context), Colors.indigo.shade500, () => onShowFiles(project, 'Entregables')),
                  _buildActionButton(context, Icons.assignment, AppLocale.tracking.getString(context), Colors.indigo.shade500, () => onShowFiles(project, 'Seguimiento')),
                  _buildActionButton(context, Icons.assignment_add, AppLocale.general.getString(context), Colors.indigo.shade500, () => onShowFiles(project, 'General')),
                  if (AccessControl.isAdmin || AccessControl.isProject)
                    _buildActionButton(context, Icons.calendar_today, AppLocale.calendar.getString(context), Colors.teal.shade500, () {
                      if (MediaQuery.of(context).size.width < 600) {
                        context.push('/project-calendar', extra: project);
                      } else {
                        showDialog(
                          context: context,
                          builder: (context) => ProjectCalendarDialog(project: project),
                        );
                      }
                    }),
                  if (AccessControl.isAdmin)
                    _buildActionButton(context, Icons.list_alt, AppLocale.requests.getString(context), Colors.teal.shade500, () {
                      context.push('/project-requests', extra: {'projectId': projId, 'showAllGroups': true});
                    }),
                  if (AccessControl.isAdmin)
                    _buildActionButton(context, Icons.info_outline, AppLocale.information.getString(context), Colors.blue.shade500, () {
                      showDialog(
                        context: context,
                        builder: (context) => ProjectInfoDialog(project: project),
                      );
                    }),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                  decoration: BoxDecoration(
                    color: uniformColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: uniformColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isExpanded ? AppLocale.hideDetails.getString(context) : AppLocale.viewDetails.getString(context),
                        style: TextStyle(
                          color: uniformColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: uniformColor,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          children: [
            Container(
              color: Colors.grey[50]?.withOpacity(0.5),
              child: Column(
                children: [
                   Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            AppLocale.projectStructure.getString(context),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          if (AccessControl.canCreateProjectItems && !isArchived)
                            TextButton.icon(
                              icon: const Icon(Icons.add, size: 18),
                              label: Text(AppLocale.newPhase.getString(context), style: const TextStyle(fontSize: 13)),
                              style: TextButton.styleFrom(
                                backgroundColor: uniformColor.withOpacity(0.08),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => PhaseCreateDialog(onSave: (data) => onCreatePhase(projId, data)),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  if (phases.isEmpty && directTasks.isEmpty)
                    const Padding(padding: EdgeInsets.all(24.0), child: Text('No hay fases ni tareas registradas.', style: TextStyle(color: Colors.grey))),
                  const SizedBox(height: 8),
                  ...phases.map((phase) => PhaseItem(phase: phase, initiallyExpanded: false, statusIdMap: statusIdMap, priorityMap: priorityMap, onRefresh: onRefresh, onEdit: onEdit, onCreateTask: onCreateTask, isArchived: isArchived, projectId: projId)),
                  ...directTasks.map((task) => TaskItem(task: task, initiallyExpanded: false, statusIdMap: statusIdMap, priorityMap: priorityMap, onRefresh: onRefresh, onEdit: onEdit, isArchived: isArchived, projectId: projId)),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildActionButton(BuildContext context, IconData icon, String label, Color color, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      hoverColor: color.withOpacity(0.1),
      splashColor: color.withOpacity(0.2),
      highlightColor: color.withOpacity(0.05),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCounterBadge(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.blueGrey)),
        ],
      ),
    );
  }
}

class _HorizontalActionButtons extends StatefulWidget {
  final List<Widget> children;

  const _HorizontalActionButtons({required this.children});

  @override
  State<_HorizontalActionButtons> createState() => _HorizontalActionButtonsState();
}

class _HorizontalActionButtonsState extends State<_HorizontalActionButtons> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollRight = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_checkScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScroll());
  }

  void _checkScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    
    final canScrollRight = currentScroll < maxScroll - 5;
    if (canScrollRight != _canScrollRight) {
      setState(() {
        _canScrollRight = canScrollRight;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_checkScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: widget.children,
          ),
        ),
        if (_canScrollRight && MediaQuery.of(context).size.width < 600)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                width: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Theme.of(context).colorScheme.surface.withOpacity(0.0),
                      Theme.of(context).colorScheme.surface.withOpacity(0.8),
                      Theme.of(context).colorScheme.surface,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), size: 20),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
