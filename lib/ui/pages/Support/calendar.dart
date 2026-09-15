import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localization/flutter_localization.dart';

class CalendarContent extends StatefulWidget {
  final List<dynamic> requests;
  final Function(String)? onGoToRequest;
  final DateTime? initialDate;
  final Function(DateTime)? onDateChanged;
  
  const CalendarContent({
    super.key, 
    required this.requests, 
    this.onGoToRequest,
    this.initialDate,
    this.onDateChanged,
  });

  @override
  State<CalendarContent> createState() => _CalendarContentState();
}

class _CalendarContentState extends State<CalendarContent> {
  DateTime _focusedMonth = DateTime.now();
  List<Map<String, dynamic>> _processedRequests = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      _focusedMonth = widget.initialDate!;
    }
    _processRequests();
  }

  DateTime? _parseDateSafely(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    if (dateStr.length >= 10) {
      String datePart = dateStr.substring(0, 10);
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(datePart)) {
        return DateTime.tryParse(datePart);
      }
    }
    String cleanStr = dateStr.replaceAll(' ', 'T');
    return DateTime.tryParse(cleanStr);
  }

  @override
  void didUpdateWidget(CalendarContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.requests != oldWidget.requests) {
      _processRequests();
    }
    if (widget.initialDate != oldWidget.initialDate && widget.initialDate != null) {
      // Si la fecha cambia externamente y el mes/año es diferente, actualizamos la vista
      if (widget.initialDate!.year != _focusedMonth.year || widget.initialDate!.month != _focusedMonth.month) {
        setState(() {
          _focusedMonth = widget.initialDate!;
        });
      }
    }
  }

  void _processRequests() {
    _processedRequests = [];
    for (var rawReq in widget.requests) {
      final req = Map<String, dynamic>.from(rawReq);
      String? startStr = req['DateStartPlan'];
      if (startStr == null || startStr.isEmpty) startStr = req['StartDate'];
      if (startStr == null || startStr.isEmpty) startStr = req['Created'];

      if (startStr != null && startStr.isNotEmpty) {
        DateTime? start = _parseDateSafely(startStr);
        if (start != null) {
          String? endStr = req['DateCompletePlan'];
          DateTime end = (endStr != null && endStr.isNotEmpty) ? (_parseDateSafely(endStr) ?? start) : start;
          start = DateTime(start.year, start.month, start.day);
          end = DateTime(end.year, end.month, end.day);
          if (end.isBefore(start)) end = start;
          req['_parsedStart'] = start;
          req['_parsedEnd'] = end;
          _processedRequests.add(req);
        }
      }
    }
    setState(() {});
  }

  String _getMonthName(int month) {
    const months = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return months[month - 1];
  }

  void _showDayDetails(BuildContext context, DateTime date, List<Map<String, dynamic>> dayRequests) async {
    int currentIndex = 0;
    final colorScheme = Theme.of(context).colorScheme;
    final ScrollController scrollController = ScrollController();
    
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return CustomModal(
              title: 'Solicitudes del ${date.day} de ${_getMonthName(date.month)}',
              width: 500,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dayRequests.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32.0),
                      child: Column(
                        children: [
                          Icon(Icons.event_busy, size: 48, color: colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(AppLocale.noActivitiesToday.getString(context), style: TextStyle(color: colorScheme.outline)),
                        ],
                      ),
                    )
                  else ...[
                    if (dayRequests.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${dayRequests.length} Solicitudes', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.chevron_left),
                                  onPressed: currentIndex > 0 ? () {
                                    setStateDialog(() => currentIndex--);
                                    if (scrollController.hasClients) scrollController.jumpTo(0);
                                  } : null,
                                ),
                                Text('${currentIndex + 1} / ${dayRequests.length}'),
                                IconButton(
                                  icon: const Icon(Icons.chevron_right),
                                  onPressed: currentIndex < dayRequests.length - 1 ? () {
                                    setStateDialog(() => currentIndex++);
                                    if (scrollController.hasClients) scrollController.jumpTo(0);
                                  } : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _buildDetailCard(dayRequests[currentIndex], colorScheme, scrollController),
                    ),
                  ],
                ],
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocale.close.getString(context)))],
            );
          },
        );
      },
    );
    scrollController.dispose();
  }

  Widget _buildDetailCard(Map<String, dynamic> req, ColorScheme colorScheme, ScrollController scrollController) {
    final statusName = cleanStatusName(req['status'] ?? req['R_Status_Name'] ?? (req['R_Status_ID'] is Map ? (req['R_Status_ID']['identifier'] ?? req['R_Status_ID']['Name']) : null) ?? 'Sin estado');
    final priority = req['level'] ?? (req['Priority'] is Map ? (req['Priority']['identifier'] ?? req['Priority']['Name']) : req['Priority']) ?? 'Media';
    final rawSummary = req['Summary'] ?? 'Sin asunto';
    final description = req['description'] ?? req['Summary'] ?? 'Sin descripción';
    
    // Convert HTML summary to plain text for the short title
    String plainSummary = stripHtmlTags(rawSummary);
    if (plainSummary.length > 80) plainSummary = '${plainSummary.substring(0, 80)}...';
    
    return Container(
      key: ValueKey(req['id']),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getPriorityColor(priority).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  priority.toUpperCase(),
                  style: TextStyle(color: _getPriorityColor(priority), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              Text(
                'Ticket: ${req['DocumentNo'] ?? req['id']?.toString() ?? ''}',
                style: TextStyle(color: colorScheme.outline, fontSize: 12),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 20),
                tooltip: 'Ver detalles de solicitud',
                onPressed: () {
                  Navigator.of(context).pop();
                  final searchVal = req['DocumentNo']?.toString() ?? req['id']?.toString() ?? '';
                  if (widget.onGoToRequest != null) {
                    widget.onGoToRequest!(searchVal);
                  } else {
                    context.pushReplacement('/my-requests', extra: {'search': searchVal});
                  }
                },
                color: colorScheme.primary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(plainSummary, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('${AppLocale.status.getString(context)}: $statusName', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w500)),
          const Divider(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: Scrollbar(
              thumbVisibility: true,
              controller: scrollController,
              child: SingleChildScrollView(
                controller: scrollController,
                child: Html(
                  data: description,
                  style: {
                    "body": Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                      fontSize: FontSize(14),
                      color: colorScheme.onSurface,
                    )
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  List<Map<String, dynamic>> _getRequestsForDay(DateTime currentDayDate) {
    return _processedRequests.where((req) {
      if (req['_parsedEnd'] == null) return false;
      DateTime end = req['_parsedEnd'];
      return currentDayDate.isAtSameMomentAs(end);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getMonthName(_focusedMonth.month),
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                  Text(
                    '${_focusedMonth.year}',
                    style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.outline),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1));
                  widget.onDateChanged?.call(_focusedMonth);
                },
              ),
              OutlinedButton(
                onPressed: () {
                  setState(() => _focusedMonth = DateTime.now());
                  widget.onDateChanged?.call(_focusedMonth);
                },
                child: Text(AppLocale.today.getString(context)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1));
                  widget.onDateChanged?.call(_focusedMonth);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Days of Week
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM']
                .map((day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(color: colorScheme.outline, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Grid
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4)),
              ],
              border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: _buildCalendarGrid(),
            ),
          ),
        ),
        // Legend
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildLegendItem(Colors.deepPurple, AppLocale.urgent.getString(context)),
              _buildLegendItem(Colors.red.shade700, AppLocale.high.getString(context)),
              _buildLegendItem(Colors.orange.shade800, AppLocale.medium.getString(context)),
              _buildLegendItem(Colors.blue.shade700, AppLocale.low.getString(context)),
              _buildLegendItem(Colors.teal.shade600, AppLocale.veryLow.getString(context)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    final daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final weekdayOffset = firstDayOfMonth.weekday - 1;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: isMobile ? 0.6 : 1.0,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
      ),
      itemCount: 42,
      itemBuilder: (context, index) {
        if (index < weekdayOffset || index >= daysInMonth + weekdayOffset) {
          return Container(color: colorScheme.surfaceContainerHighest.withOpacity(0.2));
        }

        final day = index - weekdayOffset + 1;
        final date = DateTime(_focusedMonth.year, _focusedMonth.month, day);
        final isToday = DateUtils.isSameDay(date, DateTime.now());
        final dayRequests = _getRequestsForDay(date);

        return InkWell(
          onTap: () => _showDayDetails(context, date, dayRequests),
          hoverColor: colorScheme.primary.withOpacity(0.08),
          splashColor: colorScheme.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.3), width: 0.5),
              color: isToday ? colorScheme.primary.withOpacity(0.05) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(6.0),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: isToday ? BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle) : null,
                    child: Text(
                      day.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isToday || dayRequests.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                        color: isToday ? colorScheme.onPrimary : (dayRequests.isNotEmpty ? colorScheme.onSurface : colorScheme.outline),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const Spacer(),
                if (dayRequests.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                    child: isMobile
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: dayRequests.take(3).map((r) => _buildDot(_getPriorityColor(r['Priority'] is Map ? r['Priority']['identifier'] : (r['Priority'] ?? 'Media')))).toList(),
                          )
                        : Column(
                            children: [
                              ...dayRequests.take(2).map((r) => _buildPill(r, colorScheme)),
                              if (dayRequests.length > 2)
                                Text('+${dayRequests.length - 2}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                            ],
                          ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDot(Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'Urgente': return Colors.deepPurple;
      case 'Alta': return Colors.red.shade700;
      case 'Media': return Colors.orange.shade800;
      case 'Baja': return Colors.blue.shade700;
      case 'Muy baja': return Colors.teal.shade600;
      default: return Colors.blueGrey;
    }
  }

  Widget _buildPill(Map<String, dynamic> req, ColorScheme colorScheme) {
    final priority = req['Priority'] is Map ? req['Priority']['identifier'] : (req['Priority'] ?? 'Media');
    final color = _getPriorityColor(priority);
    
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 2, left: 2, right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        stripHtmlTags(req['Summary'] ?? 'Solicitud'),
        style: const TextStyle(
          fontSize: 10, 
          color: Colors.white, 
          fontWeight: FontWeight.bold,
          letterSpacing: -0.2,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}

