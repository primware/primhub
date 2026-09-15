import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:flutter_localization/flutter_localization.dart';

class ProjectSelector extends StatelessWidget {
  final List<int> selectedProjectIds;
  final List<dynamic> projects;
  final ValueChanged<List<int>> onSelectionChanged;

  const ProjectSelector({
    super.key,
    required this.selectedProjectIds,
    required this.projects,
    required this.onSelectionChanged,
  });

  void _showMultiSelectProjects(BuildContext context) async {
    final List<int> tempSelectedProjectIds = List.from(selectedProjectIds);
    List<dynamic> sortedProjects = List.from(projects);
    sortedProjects.sort((a, b) => (a['Name'] ?? '').compareTo(b['Name'] ?? ''));

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return CustomModal(
          title: AppLocale.projects.getString(context),
          width: 500,
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return SizedBox(
                height: 350,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Builder(
                      builder: (context) {
                        bool? isAllSelected;
                        if (tempSelectedProjectIds.length ==
                                sortedProjects.length &&
                            sortedProjects.isNotEmpty) {
                          isAllSelected = true;
                        } else if (tempSelectedProjectIds.isEmpty) {
                          isAllSelected = false;
                        }

                        return CheckboxListTile(
                          title: Text(
                            AppLocale.allProjects.getString(context),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          tristate: true,
                          value: isAllSelected,
                          onChanged: (bool? value) {
                            setState(() {
                              if (isAllSelected == true) {
                                tempSelectedProjectIds.clear();
                              } else {
                                tempSelectedProjectIds.clear();
                                tempSelectedProjectIds.addAll(
                                  sortedProjects.map<int>(
                                    (p) => p['id'] as int,
                                  ),
                                );
                              }
                            });
                          },
                        );
                      },
                    ),
                    const Divider(),
                    Expanded(
                      child: SingleChildScrollView(
                        child: ListBody(
                          children: sortedProjects.map((project) {
                            final bool isSelected = tempSelectedProjectIds
                                .contains(project['id']);
                            return CheckboxListTile(
                              title: Text(
                                project['Name'] ?? 'Proyecto sin nombre',
                              ),
                              value: isSelected,
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    tempSelectedProjectIds.add(project['id']);
                                  } else {
                                    tempSelectedProjectIds.remove(
                                      project['id'],
                                    );
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocale.cancel.getString(context)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            CustomButton(
              text: AppLocale.filter.getString(context),
              onPressed: () {
                onSelectionChanged(tempSelectedProjectIds);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String displayText;

    if (selectedProjectIds.isEmpty) {
      if (projects.isEmpty) return const SizedBox.shrink();
      displayText = AppLocale.noProjectSelected.getString(context);
    } else if (selectedProjectIds.length == 1) {
      final project = projects.firstWhere(
        (p) => p['id'] == selectedProjectIds.first,
        orElse: () => {'Name': AppLocale.projectNotFound.getString(context)},
      );
      displayText = project['Name'] ?? AppLocale.unnamedProject.getString(context);
    } else if (selectedProjectIds.length == projects.length) {
      displayText = AppLocale.allProjectsSelected.getString(context);
    } else {
      displayText = AppLocale.projectsSelectedCount.getString(context).replaceAll('{count}', selectedProjectIds.length.toString());
    }

    final color = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: projects.length > 1
          ? () => _showMultiSelectProjects(context)
          : null,
      borderRadius: BorderRadius.circular(8.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(Icons.filter_list_alt, size: 20, color: color),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                displayText,
                style: TextStyle(
                  fontSize: 16,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProjectFullCard extends StatelessWidget {
  final Map<String, dynamic> project;
  final Map<String, dynamic> stats;
  final VoidCallback onCalendarTap;
  final VoidCallback onMetricsTap;
  final bool hasMetrics;

  const ProjectFullCard({
    super.key,
    required this.project,
    required this.stats,
    required this.onCalendarTap,
    required this.onMetricsTap,
    this.hasMetrics = false,
  });

  @override
  Widget build(BuildContext context) {
    final String projectName = project['Name'] ?? 'Sin Nombre';
    final bool isComplete =
        project['IsComplete'] == true || project['IsComplete'] == 'Y';
    final String status = isComplete ? 'Cerrado' : AppLocale.current.getString(context);

    String dateRange = AppLocale.noDatesAvailable.getString(context);
    String durationText = '0 días';
    String durationSubtitle = AppLocale.toBeDefined.getString(context);

    if (project['DateContract'] != null) {
      final start = DateTime.tryParse(project['DateContract'])?.toLocal();
      if (start != null) {
        final startDay = DateTime(start.year, start.month, start.day);
        final today = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        );
        DateTime? endDay;

        if (project['DateFinish'] != null) {
          final end = DateTime.tryParse(project['DateFinish'])?.toLocal();
          if (end != null) endDay = DateTime(end.year, end.month, end.day);
        }

        if (endDay != null) {
          dateRange =
              '${startDay.day}/${startDay.month}/${startDay.year} - ${endDay.day}/${endDay.month}/${endDay.year}';
        } else {
          dateRange =
              'Desde ${startDay.day}/${startDay.month}/${startDay.year}';
        }

        if (today.isBefore(startDay)) {
          durationText = '0 días';
          durationSubtitle = 'Planificado';
        } else if (endDay != null) {
          if (isComplete || !today.isBefore(endDay)) {
            durationText = '${endDay.difference(startDay).inDays} días';
            durationSubtitle = 'Duración total';
          } else {
            durationText = '${today.difference(startDay).inDays} días';
            durationSubtitle = 'En progreso';
          }
        } else {
          durationText = '${today.difference(startDay).inDays} días';
          durationSubtitle = 'En progreso';
        }
      }
    }

    const Color lightPurpleBg = Color(0xFFEEF2FF);
    const Color darkPurpleIcon = Color(0xFF4F46E5);
    const Color statusGreenBg = Color(0xFFDCFCE7);
    const Color statusGreenText = Color(0xFF166534);
    const Color statusGrayBg = Color(0xFFF3F4F6);
    const Color statusGrayText = Color(0xFF4B5563);
    const Color docIconColor = Color(0xFFD97708);

    bool isClosed = status.toLowerCase() == 'cerrado';
    final int projId = project['id'] is int
        ? project['id'] as int
        : int.tryParse(project['id'].toString()) ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Stack(
              children: [
                // AJUSTE: Altura de 140 para dar aire al título y evitar overflow
                SizedBox(
                  width: double.infinity,
                  height: 140,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 95.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: lightPurpleBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.business_center_outlined,
                            color: darkPurpleIcon,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isClosed ? statusGrayBg : statusGreenBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: isClosed
                                  ? statusGrayText
                                  : statusGreenText,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          projectName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          dateRange,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 14,
                              color: darkPurpleIcon,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              durationText,
                              style: const TextStyle(
                                color: darkPurpleIcon,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        durationSubtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // SECCIÓN DE DOCUMENTOS
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            decoration: const BoxDecoration(
              color: Color.fromARGB(255, 252, 248, 230),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      color: docIconColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocale.projectFiles.getString(context),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _buildStat(
                      context,
                      stats['et']?.toString() ?? '0',
                      AppLocale.deliverables.getString(context),
                      () => context.push(
                        '/deliverables',
                        extra: {'projectId': projId, 'view': 'Entregables'},
                      ),
                    ),
                    _buildStat(
                      context,
                      stats['sg']?.toString() ?? '0',
                      AppLocale.tracking.getString(context),
                      () => context.push(
                        '/deliverables',
                        extra: {'projectId': projId, 'view': 'Seguimiento'},
                      ),
                    ),
                    _buildStat(
                      context,
                      stats['gn']?.toString() ?? '0',
                      AppLocale.general.getString(context),
                      () => context.push(
                        '/deliverables',
                        extra: {'projectId': projId, 'view': 'General'},
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // BOTONES
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onCalendarTap,
                    icon: const Icon(
                      Icons.format_list_bulleted,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        AppLocale.calendarGantt.getString(context),
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: hasMetrics ? onMetricsTap : null,
                    icon: const Icon(
                      Icons.bar_chart,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        AppLocale.charts.getString(context),
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasMetrics
                          ? const Color(0xFFA855F7)
                          : Colors.grey.shade400,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // El método _buildStat se mantiene igual que en tu código anterior
  Widget _buildStat(
    BuildContext context,
    String value,
    String label,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: _HoverStatCard(value: value, label: label, onTap: onTap),
    );
  }
}

class _HoverStatCard extends StatefulWidget {
  final String value;
  final String label;
  final VoidCallback onTap;

  const _HoverStatCard({
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  State<_HoverStatCard> createState() => _HoverStatCardState();
}

class _HoverStatCardState extends State<_HoverStatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered ? const Color(0xFFFEF3C7) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? const Color(0xFFD97708)
                  : const Color.fromARGB(255, 230, 220, 180),
              width: 1.5,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD97708),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
