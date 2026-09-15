import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/api/access_control.dart';
import 'package:flutter_localization/flutter_localization.dart';


class ProjectSideBar extends StatelessWidget {
  final String currentRoute;

  const ProjectSideBar({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    List<Map<String, dynamic>> items = [
      {'route': '/', 'icon': Icons.dashboard_outlined, 'selectedIcon': Icons.dashboard, 'label': AppLocale.dashboard.getString(context)},
    ];

    if (AccessControl.isSupport) {
      items.add({'route': '/my-requests', 'icon': Icons.help_outline, 'selectedIcon': Icons.help, 'label': AppLocale.myRequests.getString(context)});
      items.add({
        'isExpansion': true,
        'label': AppLocale.documents.getString(context),
        'icon': Icons.folder_shared_outlined,
        'selectedIcon': Icons.folder_shared_rounded,
        'children': [
          {'route': '/bpartner-docs/general', 'icon': Icons.insert_drive_file_outlined, 'selectedIcon': Icons.insert_drive_file, 'label': AppLocale.general.getString(context)},
          {'route': '/bpartner-docs/seguimiento', 'icon': Icons.insert_drive_file_outlined, 'selectedIcon': Icons.insert_drive_file, 'label': AppLocale.tracking.getString(context)},
        ],
      });
      items.add({'route': '/support', 'icon': Icons.schedule_outlined, 'selectedIcon': Icons.schedule, 'label': AppLocale.hours.getString(context)});
    }

    if (AccessControl.isProject) {
      items.add({'route': '/deliverables', 'icon': Icons.folder_outlined, 'selectedIcon': Icons.folder, 'label': AppLocale.projects.getString(context)});
    }

    items.add({'route': '/metrics', 'icon': Icons.bar_chart_outlined, 'selectedIcon': Icons.bar_chart, 'label': AppLocale.metrics.getString(context)});

    int selectedIndex = items.indexWhere((item) => item['route'] == currentRoute);
    if (selectedIndex == -1) selectedIndex = 0;

    return Material(
      color: theme.cardColor,
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: colorScheme.outline.withOpacity(0.1)),
          ),
        ),
        child: Column(
        children: [
          const SizedBox(height: 24),
          // Logo o Título opcional aquí
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final item = items[index];

                if (item['isExpansion'] == true) {
                  final children = item['children'] as List<Map<String, dynamic>>;
                  final isExpanded = children.any((child) => currentRoute.startsWith('/bpartner-docs'));

                  return Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: isExpanded,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      leading: Icon(
                        isExpanded ? item['selectedIcon'] : item['icon'],
                        color: isExpanded ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        item['label'],
                        style: TextStyle(
                          color: isExpanded ? colorScheme.primary : colorScheme.onSurface,
                          fontWeight: isExpanded ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14, // Same size roughly as bodyLarge but fixed for ExpansionTile
                        ),
                      ),
                      children: children.map((child) {
                        final isChildSelected = child['route'] == currentRoute;
                        return InkWell(
                          onTap: () {
                            if (!isChildSelected) context.go(child['route']);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.only(left: 48, right: 16, top: 12, bottom: 12),
                            decoration: BoxDecoration(
                              color: isChildSelected ? colorScheme.primary.withOpacity(0.1) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isChildSelected ? child['selectedIcon'] : child['icon'],
                                  color: isChildSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    child['label'],
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: isChildSelected ? colorScheme.primary : colorScheme.onSurface,
                                      fontWeight: isChildSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }

                final isSelected = selectedIndex == index && item['route'] != null;

                return InkWell(
                  onTap: () {
                    if (!isSelected && item['route'] != null) context.go(item['route']);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? colorScheme.primary.withOpacity(0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? item['selectedIcon'] : item['icon'],
                          color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            item['label'],
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ));
  }
}
