import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/pages/Support/calendar.dart';
import 'package:primhub/ui/pages/Support/gantt_content.dart';
import 'package:flutter_localization/flutter_localization.dart';

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
                    Text(AppLocale.calendar.getString(context)),
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
                    Text(AppLocale.ganttChart.getString(context)),
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
        title: '${AppLocale.howItWorks.getString(context)} $type',
        width: 450,
        content: Text(
          type == AppLocale.calendar.getString(context)
              ? AppLocale.calendarInfoBody.getString(context)
              : AppLocale.ganttInfoBody.getString(context),
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          CustomButton(
            text: AppLocale.gotIt.getString(context),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
