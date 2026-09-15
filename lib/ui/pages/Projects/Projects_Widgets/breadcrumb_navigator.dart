import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';

class BreadcrumbNavigator extends StatelessWidget {
  final List<String> currentPath;
  final Function(int index) onNavigate;
  final Function(int index, Map data)? onDropToRoot;

  const BreadcrumbNavigator({super.key, required this.currentPath, required this.onNavigate, this.onDropToRoot});

  IconData _getIconForCrumb(int index, String name) {
    if (index == 0) return Icons.layers_outlined; // Mis Proyectos
    if (index == 1) return Icons.work_outline; // Nombre del Proyecto
    if (index == 2) {
      // Tipos de vista
      if (name == 'Entregables') return Icons.folder_special;
      if (name == 'Seguimiento') return Icons.topic;
      return Icons.snippet_folder; // General
    }
    return Icons.folder_open; // Subcarpetas
  }

  Color _getCrumbColor(BuildContext context, int index, String name) {
    final theme = Theme.of(context);
    if (index == 0) return Colors.grey;
    if (index == 1) return theme.colorScheme.primary;
    if (index == 2) {
      if (name == 'Entregables') return Colors.amber.shade700;
      if (name == 'Seguimiento') return Colors.blue.shade700;
      if (name == 'General') return Colors.green.shade700;
    }
    return Colors.amber.shade600; // Subcarpetas
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> crumbs = [];
    for (int i = 0; i < currentPath.length; i++) {
      final isLast = i == currentPath.length - 1;
      final color = _getCrumbColor(context, i, currentPath[i]);

      Widget crumb = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: InkWell(
          onTap: isLast ? null : () => onNavigate(i),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: isLast ? color.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isLast ? Border.all(color: color.withOpacity(0.3)) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_getIconForCrumb(i, currentPath[i]), size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  _localizedCrumb(context, currentPath[i].split('.').first),
                  style: TextStyle(
                    color: color,
                    fontWeight: isLast ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (!isLast && i >= 2 && onDropToRoot != null) {
        crumb = _BreadcrumbDropTarget(
          index: i,
          baseCrumb: crumb,
          onDropToRoot: onDropToRoot,
        );
      }

      crumbs.add(crumb);
      if (!isLast) {
        crumbs.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.0),
            child: Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 16),
          ),
        );
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: crumbs),
    );
  }

  String _localizedCrumb(BuildContext context, String value) {
    return switch (value) {
      'Mis Proyectos' => AppLocale.myProjects.getString(context),
      'Mis Documentos' => AppLocale.documents.getString(context),
      'Entregables' => AppLocale.deliverables.getString(context),
      'Seguimiento' => AppLocale.tracking.getString(context),
      'General' => AppLocale.general.getString(context),
      _ => value,
    };
  }
}

class _BreadcrumbDropTarget extends StatefulWidget {
  final int index;
  final Widget baseCrumb;
  final Function(int, Map)? onDropToRoot;

  const _BreadcrumbDropTarget({

    required this.index,
    required this.baseCrumb,
    this.onDropToRoot,
  });

  @override
  State<_BreadcrumbDropTarget> createState() => _BreadcrumbDropTargetState();
}

class _BreadcrumbDropTargetState extends State<_BreadcrumbDropTarget> {
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: Formats.standardFormats,
      onDropEnter: (event) => setState(() => _isDragOver = true),
      onDropLeave: (event) => setState(() => _isDragOver = false),
      onDropOver: (event) {
        if (event.session.items.isEmpty) return DropOperation.none;
        return DropOperation.move;
      },
      onPerformDrop: (event) async {
        setState(() => _isDragOver = false);
        final item = event.session.items.first;
        if (item.localData is Map) {
          widget.onDropToRoot?.call(widget.index, item.localData as Map);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isDragOver ? Colors.blue.withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: _isDragOver ? Border.all(color: Colors.blue.shade500, width: 2) : null,
        ),
        child: widget.baseCrumb,
      ),
    );
  }
}
