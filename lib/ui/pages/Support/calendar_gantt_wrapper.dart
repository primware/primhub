import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/pages/Support/calendar.dart';
import 'package:primhub/ui/pages/Support/gantt_content.dart';

class CalendarGanttWrapper extends StatefulWidget {
  final List<dynamic> requests;
  final Function(String)? onGoToRequest;
  const CalendarGanttWrapper({super.key, required this.requests, this.onGoToRequest});

  @override
  State<CalendarGanttWrapper> createState() => _CalendarGanttWrapperState();
}

class _CalendarGanttWrapperState extends State<CalendarGanttWrapper> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _sharedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.outline,
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_month),
                    const SizedBox(width: 8),
                    const Text('Calendario'),
                    if (AccessControl.isAdmin) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.info_outline, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: AppLocale.calendarInfo.getString(context),
                        onPressed: () => _showInfoModal(context, 'Calendario'),
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bar_chart),
                    const SizedBox(width: 8),
                    const Text('Diagrama de Gantt'),
                    if (AccessControl.isAdmin) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.info_outline, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: AppLocale.ganttInfo.getString(context),
                        onPressed: () => _showInfoModal(context, 'Diagrama de Gantt'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              CalendarContent(
                requests: widget.requests,
                onGoToRequest: widget.onGoToRequest,
                initialDate: _sharedDate,
                onDateChanged: (date) {
                  setState(() {
                    _sharedDate = date;
                  });
                },
              ),
              GanttContent(
                requests: widget.requests,
                onGoToRequest: widget.onGoToRequest,
                initialDate: _sharedDate,
                onDateChanged: (date) {
                  setState(() {
                    _sharedDate = date;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showInfoModal(BuildContext context, String type) {
    showDialog(
      context: context,
      builder: (context) => CustomModal(
        title: 'Funcionamiento: $type',
        width: 450,
        content: Text(
          type == 'Calendario'
              ? 'El Calendario utiliza exactamente las mismas solicitudes filtradas en la tabla principal.\n\n'
                  '• Muestra las solicitudes organizadas por su fecha estimada.\n'
                  '• Si vienes del Treemap, respeta el Representante y Tercero seleccionados.\n'
                  '• Usa los colores para identificar la prioridad de cada solicitud.'
              : 'El Diagrama de Gantt utiliza exactamente las mismas solicitudes filtradas en la tabla principal.\n\n'
                  '• Muestra una línea de tiempo basada en la fecha de creación y fecha estimada.\n'
                  '• Si vienes del Treemap, respeta el Representante y Tercero seleccionados.\n'
                  '• Permite visualizar gráficamente la carga de trabajo a lo largo del tiempo.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          CustomButton(
            text: 'Entendido',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
