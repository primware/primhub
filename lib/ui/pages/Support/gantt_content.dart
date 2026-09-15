import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';

import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/Shared_Custom/animated_copy_widget.dart';
import 'package:flutter_localization/flutter_localization.dart';

class GanttContent extends StatefulWidget {
  final List<dynamic> requests;
  final Function(String)? onGoToRequest;
  final DateTime? initialDate;
  final Function(DateTime)? onDateChanged;

  const GanttContent({
    super.key,
    required this.requests,
    this.onGoToRequest,
    this.initialDate,
    this.onDateChanged,
  });

  @override
  State<GanttContent> createState() => _GanttContentState();
}

class _GanttContentState extends State<GanttContent> {
  List<Map<String, dynamic>> _processedRequests = [];
  List<Map<String, dynamic>> _allProcessedRequests = [];
  DateTime? _minDate;
  DateTime? _maxDate;
  DateTime? _baseMinDate;
  DateTime? _baseMaxDate;
  String _timeFilter = 'all';
  final double _dayWidth = 60.0;
  final double _rowHeight = 60.0;
  final double _leftPanelWidth = 200.0;

  final ScrollController _verticalController1 = ScrollController();
  final ScrollController _verticalController2 = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _processRequests();

    // Sync vertical scrolling
    _verticalController1.addListener(() {
      if (_verticalController1.offset != _verticalController2.offset) {
        _verticalController2.jumpTo(_verticalController1.offset);
      }
    });
    _verticalController2.addListener(() {
      if (_verticalController2.offset != _verticalController1.offset) {
        _verticalController1.jumpTo(_verticalController2.offset);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialDate != null && _minDate != null) {
        final initial = widget.initialDate!;
        // Verificar que initialDate esté dentro del rango del Gantt
        if (_maxDate != null &&
            (initial.isBefore(_minDate!) || initial.isAfter(_maxDate!))) {
          return;
        }
        final daysDiff = initial.difference(_minDate!).inDays;
        if (daysDiff > 0) {
          final offset = daysDiff * _dayWidth;
          if (_horizontalController.hasClients) {
            _horizontalController.jumpTo(offset);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _verticalController1.dispose();
    _verticalController2.dispose();
    _horizontalController.dispose();
    super.dispose();
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
  void didUpdateWidget(GanttContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.requests != oldWidget.requests) {
      _processRequests();
    }
  }

  void _processRequests() {
    _allProcessedRequests = [];
    DateTime? minD;
    DateTime? maxD;

    for (var rawReq in widget.requests) {
      final req = Map<String, dynamic>.from(rawReq);
      String? startStr = req['DateStartPlan'];
      if (startStr == null || startStr.isEmpty) startStr = req['StartDate'];
      if (startStr == null || startStr.isEmpty) startStr = req['Created'];

      if (startStr != null && startStr.isNotEmpty) {
        DateTime? start = _parseDateSafely(startStr);
        if (start != null) {
          String? endStr = req['DateCompletePlan'];
          DateTime end = (endStr != null && endStr.isNotEmpty)
              ? (_parseDateSafely(endStr) ?? start)
              : start;

          start = DateTime(start.year, start.month, start.day);
          end = DateTime(end.year, end.month, end.day);
          if (end.isBefore(start)) end = start;

          req['_parsedStart'] = start;
          req['_parsedEnd'] = end;

          String bpDescription = '';
          if (req['C_BPartner_ID'] is Map) {
            bpDescription =
                (req['C_BPartner_ID']['Description'] ??
                        req['C_BPartner_ID']['description'] ??
                        '')
                    .toString()
                    .trim();
          }
          if (bpDescription.isEmpty) {
            final bpId = req['C_BPartner_ID'] is Map
                ? (req['C_BPartner_ID']['id'] as num?)?.toInt()
                : (req['C_BPartner_ID'] as num?)?.toInt();
            if (bpId != null) {
              final found = GlobalCache.allBPartners.firstWhere(
                (bp) => (bp['id'] as num?)?.toInt() == bpId,
                orElse: () => {},
              );
              if (found.isNotEmpty) {
                bpDescription =
                    (found['Description'] ?? found['description'] ?? '')
                        .toString()
                        .trim();
              }
            }
          }
          req['bpDescription'] = bpDescription;

          _allProcessedRequests.add(req);

          if (minD == null || start.isBefore(minD)) minD = start;
          if (maxD == null || end.isAfter(maxD)) maxD = end;
        }
      }
    }

    if (minD == null) {
      minD = DateTime.now().subtract(const Duration(days: 7));
      maxD = DateTime.now().add(const Duration(days: 7));
    } else {
      minD = minD.subtract(const Duration(days: 3));
      maxD = maxD!.add(const Duration(days: 7));
    }

    _baseMinDate = minD;
    _baseMaxDate = maxD;

    _applyTimeFilter();
  }

  void _applyTimeFilter() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_timeFilter == 'this_week') {
      final currentWeekday = today.weekday;
      _minDate = today.subtract(Duration(days: currentWeekday - 1));
      _maxDate = _minDate!.add(const Duration(days: 6));
    } else if (_timeFilter == 'this_month') {
      _minDate = DateTime(today.year, today.month, 1);
      _maxDate = DateTime(today.year, today.month + 1, 0);
    } else if (_timeFilter == 'next_15_days') {
      final currentWeekday = today.weekday;
      _minDate = today.subtract(Duration(days: currentWeekday - 1));
      _maxDate = _minDate!.add(const Duration(days: 13));
    } else {
      _minDate = _baseMinDate;
      _maxDate = _baseMaxDate;
      if (_minDate != null && today.isBefore(_minDate!)) {
        _minDate = today.subtract(const Duration(days: 3));
      }
      if (_maxDate != null && today.isAfter(_maxDate!)) {
        _maxDate = today.add(const Duration(days: 3));
      }
    }

    _processedRequests = _allProcessedRequests.where((req) {
      if (_timeFilter == 'all') return true;
      final start = req['_parsedStart'] as DateTime;
      final end = req['_parsedEnd'] as DateTime;
      return start.compareTo(_maxDate!) <= 0 && end.compareTo(_minDate!) >= 0;
    }).toList();

    _processedRequests.sort(
      (a, b) => a['_parsedStart'].compareTo(b['_parsedStart']),
    );

    setState(() {});
  }

  void _scrollToToday() {
    if (_minDate == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (today.isBefore(_minDate!) || today.isAfter(_maxDate!)) {
      _timeFilter = 'all';
      _applyTimeFilter();
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_horizontalController.hasClients) return;
      final offsetDays = today.difference(_minDate!).inDays;
      final offsetPixels =
          (offsetDays * _dayWidth) -
          (_horizontalController.position.viewportDimension / 2) +
          (_dayWidth / 2);

      _horizontalController.animateTo(
        offsetPixels.clamp(0.0, _horizontalController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'Urgente':
        return Colors.deepPurple;
      case 'Alta':
        return Colors.red.shade700;
      case 'Media':
        return Colors.orange.shade800;
      case 'Baja':
        return Colors.blue.shade700;
      case 'Muy baja':
        return Colors.teal.shade600;
      default:
        return Colors.blueGrey;
    }
  }

  String _stripHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _showRequestDetails(BuildContext context, Map<String, dynamic> req) {
    final rawStatusName =
        req['R_Status_Name'] ??
        (req['R_Status_ID'] is Map ? req['R_Status_ID']['identifier'] : '');
    final statusName = rawStatusName.toString().replaceFirst(
      RegExp(r'^\d+_'),
      '',
    );
    final priority = req['Priority'] is Map
        ? req['Priority']['identifier']
        : (req['Priority'] ?? 'Media');
    final summary = req['Summary'] ?? 'Sin asunto';
    final description =
        req['description'] ?? req['Summary'] ?? 'Sin descripción';
    final colorScheme = Theme.of(context).colorScheme;
    final ScrollController scrollController = ScrollController();

    showDialog(
      context: context,
      builder: (context) {
        return CustomModal(
          title: 'Detalle de Solicitud',
          width: 500,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getPriorityColor(priority).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      priority.toUpperCase(),
                      style: TextStyle(
                        color: _getPriorityColor(priority),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      Navigator.pop(context); // Cerrar el modal
                      final searchVal =
                          req['DocumentNo']?.toString() ??
                          req['id']?.toString() ??
                          '';
                      if (widget.onGoToRequest != null) {
                        widget.onGoToRequest!(searchVal);
                      } else {
                        // Ir a Mis Solicitudes (reemplazando para no apilar) y pasar el search
                        context.pushReplacement(
                          '/my-requests',
                          extra: {'search': searchVal},
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.08),
                        border: Border.all(
                          color: colorScheme.primary.withOpacity(0.3),
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.open_in_new,
                            size: 12,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Ticket: ${req['DocumentNo'] ?? req['id']?.toString() ?? ''}',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (summary != description) ...[
                Text(
                  _stripHtml(summary),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                'Estado: $statusName',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Divider(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
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
                        ),
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_minDate == null || _maxDate == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalDays = _maxDate!.difference(_minDate!).inDays + 1;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            // Leyenda y Filtros
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _buildLegendItem(Colors.deepPurple, AppLocale.urgent.getString(context)),
                        _buildLegendItem(Colors.red.shade700, AppLocale.high.getString(context)),
                        _buildLegendItem(Colors.orange.shade800, AppLocale.medium.getString(context)),
                        _buildLegendItem(Colors.blue.shade700, AppLocale.low.getString(context)),
                        _buildLegendItem(Colors.teal.shade600, AppLocale.veryLow.getString(context)),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.today, size: 16),
                        label: Text(AppLocale.goToToday.getString(context)),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: _scrollToToday,
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Vista de tiempo',
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (val) {
                          if (_timeFilter != val) {
                            _timeFilter = val;
                            _applyTimeFilter();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(value: 'all', child: Text(AppLocale.allFilter.getString(context))),
                          PopupMenuItem(
                            value: 'this_week',
                            child: Text('Semanal'),
                          ),
                          PopupMenuItem(
                            value: 'next_15_days',
                            child: Text('Bi Semanal'),
                          ),
                          PopupMenuItem(
                            value: 'this_month',
                            child: Text('Mensual'),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.filter_alt_outlined, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                _timeFilter == 'all'
                                    ? AppLocale.allFilter.getString(context)
                                    : _timeFilter == 'this_week'
                                    ? 'Semanal'
                                    : _timeFilter == 'next_15_days'
                                    ? 'Bi Semanal'
                                    : 'Mensual',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  // Panel Izquierdo (Lista de Tareas)
                  SizedBox(
                    width: _leftPanelWidth,
                    child: Column(
                      children: [
                        // Encabezado Panel Izquierdo
                        Container(
                          height: 50,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withOpacity(0.3),
                            border: Border(
                              bottom: BorderSide(
                                color: colorScheme.outlineVariant.withOpacity(
                                  0.5,
                                ),
                              ),
                              right: BorderSide(
                                color: colorScheme.outlineVariant.withOpacity(
                                  0.5,
                                ),
                              ),
                            ),
                          ),
                          child: const Text(
                            'Solicitud',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        // Lista Panel Izquierdo
                        Expanded(
                          child: Scrollbar(
                            thumbVisibility: true,
                            trackVisibility: true,
                            controller: _verticalController1,
                            child: ListView.builder(
                              controller: _verticalController1,
                              itemCount: _processedRequests.length,
                              itemBuilder: (context, index) {
                                final req = _processedRequests[index];
                                return InkWell(
                                  onTap: () =>
                                      _showRequestDetails(context, req),
                                  child: Container(
                                    height: _rowHeight,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: colorScheme.outlineVariant
                                              .withOpacity(0.2),
                                        ),
                                        right: BorderSide(
                                          color: colorScheme.outlineVariant
                                              .withOpacity(0.5),
                                        ),
                                      ),
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (req['bpDescription']
                                                ?.toString()
                                                .isNotEmpty ==
                                            true)
                                          Text(
                                            '${req['bpDescription']}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                        Row(
                                          children: [
                                            AnimatedCopyWidget(
                                              textToCopy:
                                                  '${req['DocumentNo'] ?? ''}',
                                              snackBarMessage: AppLocale.ticketCopiedShort.getString(context),
                                              leadingText: Text(
                                                '${req['DocumentNo'] ?? ''}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: colorScheme.primary,
                                                ),
                                              ),
                                              iconSize: 10,
                                            ),
                                          ],
                                        ),
                                        Text(
                                          _stripHtml(req['Summary'] ?? ''),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Panel Derecho (Gráfico de Gantt)
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true,
                      trackVisibility: true,
                      controller: _horizontalController,
                      child: SingleChildScrollView(
                        controller: _horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: Column(
                          children: [
                            // Encabezado Panel Derecho (Días)
                            Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest
                                    .withOpacity(0.3),
                                border: Border(
                                  bottom: BorderSide(
                                    color: colorScheme.outlineVariant
                                        .withOpacity(0.5),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: List.generate(totalDays, (index) {
                                  final date = _minDate!.add(
                                    Duration(days: index),
                                  );
                                  final isToday = DateUtils.isSameDay(
                                    date,
                                    DateTime.now(),
                                  );
                                  final isWeekend =
                                      date.weekday == DateTime.saturday ||
                                      date.weekday == DateTime.sunday;
                                  return Container(
                                    width: _dayWidth,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(
                                          color: date.weekday == DateTime.sunday
                                              ? colorScheme.outlineVariant
                                                    .withOpacity(0.5)
                                              : colorScheme.outlineVariant
                                                    .withOpacity(0.2),
                                          width: date.weekday == DateTime.sunday
                                              ? 1.5
                                              : 1.0,
                                        ),
                                      ),
                                      color: isToday
                                          ? colorScheme.primary.withOpacity(0.1)
                                          : (isWeekend
                                                ? colorScheme
                                                      .surfaceContainerHighest
                                                      .withOpacity(0.5)
                                                : null),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _getWeekdayAbbr(date.weekday),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: isWeekend && !isToday
                                                ? colorScheme.outline
                                                : colorScheme.primary,
                                          ),
                                        ),
                                        Text(
                                          '${date.day}',
                                          style: TextStyle(
                                            fontWeight: isToday
                                                ? FontWeight.bold
                                                : FontWeight.bold,
                                            fontSize: 13,
                                            color: isWeekend && !isToday
                                                ? colorScheme.outline
                                                : null,
                                          ),
                                        ),
                                        Text(
                                          _getMonthAbbr(date.month),
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: isWeekend && !isToday
                                                ? colorScheme.outline
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ),
                            // Líneas de tiempo Panel Derecho
                            Expanded(
                              child: SizedBox(
                                width: totalDays * _dayWidth,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: GanttGridPainter(
                                          totalDays: totalDays,
                                          dayWidth: _dayWidth,
                                          lineColor: colorScheme.outlineVariant
                                              .withOpacity(0.1),
                                          minDate: _minDate!,
                                          weekendColor: colorScheme
                                              .surfaceContainerHighest
                                              .withOpacity(0.2),
                                        ),
                                      ),
                                    ),

                                    ListView.builder(
                                      controller: _verticalController2,
                                      itemCount: _processedRequests.length,
                                      itemBuilder: (context, index) {
                                        final req = _processedRequests[index];
                                        final start =
                                            req['_parsedStart'] as DateTime;
                                        final end =
                                            req['_parsedEnd'] as DateTime;

                                        final startOffset = start
                                            .difference(_minDate!)
                                            .inDays;
                                        final duration =
                                            end.difference(start).inDays + 1;
                                        final priority = req['Priority'] is Map
                                            ? req['Priority']['identifier']
                                            : (req['Priority'] ?? 'Media');
                                        final color = _getPriorityColor(
                                          priority,
                                        );

                                        String tooltipSummary = _stripHtml(
                                          req['Summary'] ?? '',
                                        );
                                        if (tooltipSummary.length > 400) {
                                          tooltipSummary =
                                              '${tooltipSummary.substring(0, 400)}...';
                                        }

                                        return Container(
                                          height: _rowHeight,
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: colorScheme
                                                    .outlineVariant
                                                    .withOpacity(0.2),
                                              ),
                                            ),
                                          ),
                                          child: Stack(
                                            children: [
                                              // Barra de Gantt
                                              Positioned(
                                                left:
                                                    startOffset * _dayWidth +
                                                    2, // Margen ligero
                                                width:
                                                    (duration * _dayWidth) -
                                                    4, // Margen ligero
                                                top: 10,
                                                bottom: 10,
                                                child: Tooltip(
                                                  message:
                                                      'Ticket: ${req['DocumentNo'] ?? ''}\n$tooltipSummary',
                                                  child: InkWell(
                                                    onTap: () =>
                                                        _showRequestDetails(
                                                          context,
                                                          req,
                                                        ),
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: color,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: color
                                                                .withOpacity(
                                                                  0.3,
                                                                ),
                                                            blurRadius: 4,
                                                            offset:
                                                                const Offset(
                                                                  0,
                                                                  2,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                          ),
                                                      child: Text(
                                                        req['bpDescription']
                                                                    ?.toString()
                                                                    .isNotEmpty ==
                                                                true
                                                            ? '${req['bpDescription']} - ${req['DocumentNo'] ?? ''}'
                                                            : '${req['DocumentNo'] ?? ''}',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthAbbr(int month) {
    const months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return months[month - 1];
  }

  String _getWeekdayAbbr(int weekday) {
    const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return days[weekday - 1];
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class GanttGridPainter extends CustomPainter {
  final int totalDays;
  final double dayWidth;
  final Color lineColor;
  final DateTime minDate;
  final Color weekendColor;

  GanttGridPainter({
    required this.totalDays,
    required this.dayWidth,
    required this.lineColor,
    required this.minDate,
    required this.weekendColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    final weekendPaint = Paint()..color = weekendColor;

    for (int i = 0; i < totalDays; i++) {
      double x = i * dayWidth;
      final date = minDate.add(Duration(days: i));

      // Dibujar fondo de fin de semana
      if (date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, dayWidth, size.height),
          weekendPaint,
        );
      }

      // Dibujar línea divisoria más fuerte al final de la semana (Domingo)
      if (date.weekday == DateTime.sunday) {
        final darkPaint = Paint()
          ..color = lineColor.withOpacity(0.4)
          ..strokeWidth = 1.5;
        canvas.drawLine(
          Offset(x + dayWidth, 0),
          Offset(x + dayWidth, size.height),
          darkPaint,
        );
      } else {
        canvas.drawLine(
          Offset(x + dayWidth, 0),
          Offset(x + dayWidth, size.height),
          linePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant GanttGridPainter oldDelegate) {
    return oldDelegate.totalDays != totalDays ||
        oldDelegate.dayWidth != dayWidth ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.minDate != minDate;
  }
}
