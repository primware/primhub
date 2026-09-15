import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_container.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/Shared_Custom/custom_skeleton.dart';
import 'package:primhub/ui/Shared_Custom/responsive_data_table.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/widgets/duration_formatter.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart' as documents_logic;
import 'package:flutter_html/flutter_html.dart';
import 'package:primhub/ui/Shared_Custom/animated_copy_widget.dart';
import 'package:flutter_localization/flutter_localization.dart';

class RecentRequestsTable extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final bool isLoading;
  final Function(Map<String, dynamic>) onEdit;
  final List<int>? selectedBpIds;

  const RecentRequestsTable({super.key, required this.requests, required this.isLoading, required this.onEdit, this.selectedBpIds});

  @override
  Widget build(BuildContext context) {
    return CustomContainer(
      title: AppLocale.recentRequests.getString(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 1000),
            child: isLoading
                ? const SkeletonTable() // Muestra el esqueleto mientras carga
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Punto de quiebre para cambiar a vista de tarjetas
                      if (constraints.maxWidth < 800) {
                        return _MobileRequestList(requests: requests, onEdit: onEdit);
                      } else {
                        return _DesktopRequestTable(requests: requests, onEdit: onEdit);
                      }
                    },
                  ),
          ),
          const SizedBox(height: 20),
          Center(
            child: CustomButton(text: AppLocale.viewAllRequests.getString(context), onPressed: () => context.push('/my-requests', extra: {
              if (selectedBpIds != null && selectedBpIds!.isNotEmpty)
                'bpIds': selectedBpIds,
            })),
          ),
        ],
      ),
    );
  }
}

/// Vista de tabla para Escritorio
class _DesktopRequestTable extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final Function(Map<String, dynamic>) onEdit;

  const _DesktopRequestTable({required this.requests, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final List<ResponsiveDataColumn> fixedColumns = [
      ResponsiveDataColumn(label: AppLocale.actions.getString(context)),
      const ResponsiveDataColumn(label: 'Ticket'),
      ResponsiveDataColumn(label: AppLocale.status.getString(context)),
      if (AccessControl.isAdmin || AccessControl.isSupport) ResponsiveDataColumn(label: AppLocale.requestType.getString(context)),
    ];

    final List<ResponsiveDataColumn> scrollableColumns = [
      ResponsiveDataColumn(label: AppLocale.category.getString(context)),
      ResponsiveDataColumn(label: AppLocale.subject.getString(context)),
      ResponsiveDataColumn(label: AppLocale.priority.getString(context)),
      if (AccessControl.isAdmin) ResponsiveDataColumn(label: AppLocale.businessPartner.getString(context)),
      if (AccessControl.isAdmin) ResponsiveDataColumn(label: AppLocale.user.getString(context)),
      if (AccessControl.isAdmin) ResponsiveDataColumn(label: AppLocale.salesRepresentative.getString(context)),
      ResponsiveDataColumn(label: AppLocale.description.getString(context)),
      ResponsiveDataColumn(label: AppLocale.hours.getString(context)),
      ResponsiveDataColumn(label: AppLocale.productSheet.getString(context)),
    ];

    return ResponsiveDataTable<Map<String, dynamic>>(
      items: requests,
      fixedColumns: fixedColumns,
      scrollableColumns: scrollableColumns,
      getId: (item) => item['original']['id'],
      onRowTap: onEdit,
      fixedCellBuilder: (alert) => [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Ir a Mis Solicitudes',
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => context.push('/my-requests', extra: {'search': alert['code']}),
              ),
              IconButton(
                tooltip: AccessControl.canAddUpdates ? 'Responder' : 'Ver Actualizaciones',
                icon: Icon(AccessControl.canAddUpdates ? Icons.reply : Icons.forum),
                onPressed: () => GoRouter.of(context).push('/request-updates/${Uri.encodeComponent((alert['realId'] ?? alert['original']['id']).toString())}', extra: {'docNo': alert['code']}),
              ),
              IconButton(
                tooltip: AppLocale.viewAttachments.getString(context),
                icon: const Icon(Icons.attach_file),
                onPressed: () => showDialog(
                  context: context,
                  builder: (context) => documents_logic.RequestAttachmentsDialog(requestId: alert['realId'] ?? alert['original']['id'], documentNo: alert['code'] ?? ''),
                ),
              ),
            ],
          ),
        ),
        DataCell(
          AnimatedCopyWidget(
            textToCopy: alert['code']?.toString() ?? '',
            snackBarMessage: AppLocale.ticketCopiedShort.getString(context),
            leadingText: Text(alert['code']?.toString() ?? ''),
          ),
        ),
        DataCell(Text(documents_logic.cleanStatusName(alert['status']?.toString() ?? 'Sin Estado'))),
        if (AccessControl.isAdmin || AccessControl.isSupport) DataCell(Text(alert['situation']?.toString() ?? 'Sin tipo')),
      ],
      scrollableCellBuilder: (alert) {
        final original = alert['original'] as Map<String, dynamic>? ?? {};

        final catData = original['R_Category_ID'];
        String catName = '';
        int? catId;
        if (catData is Map) {
          catId = (catData['id'] as num?)?.toInt();
        } else if (catData is num) {
          catId = catData.toInt();
        }

        if (catId != null) {
          final catInCache = GlobalCache.rawCategories.firstWhere(
            (c) => (c['id'] as num?)?.toInt() == catId, 
            orElse: () => <String, dynamic>{},
          );
          if (catInCache.isNotEmpty && catInCache['showinprimhub'] == true) {
            catName = catInCache['Name']?.toString() ?? catInCache['identifier']?.toString() ?? '';
          }
        }
        
        final asunto = alert['emailSubject']?.toString() ?? original['Summary']?.toString() ?? '';

        final repData = original['SalesRep_ID'];
        final repName = repData is Map ? (repData['Name'] ?? repData['identifier'] ?? '') : '';

        final chipId = alert['productChipId'];
        String chipDesc = 'N/A';
        if (chipId != null) {
          final found = GlobalCache.productChips.firstWhere(
            (c) {
              final cId = int.tryParse(c['id']?.toString() ?? '') ?? int.tryParse(c['C_BPartner_Product_Chip_ID']?.toString() ?? '');
              return cId == chipId;
            },
            orElse: () => <String, dynamic>{},
          );
          if (found.isNotEmpty) {
            chipDesc = found['Description']?.toString() ?? found['Name']?.toString() ?? 'Ficha $chipId';
          }
        }

        return [
          DataCell(Text(catName.toString())),
          DataCell(Text(asunto.toString())),
          DataCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: alert['levelBgColor'] ?? Colors.grey.shade200,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                alert['level']?.toString() ?? 'N/A',
                style: TextStyle(
                  color: alert['levelColor'] ?? Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (AccessControl.isAdmin) DataCell(Text(alert['bpName']?.toString() ?? '')),
          if (AccessControl.isAdmin) DataCell(Text(alert['userName']?.toString() ?? '')),
          if (AccessControl.isAdmin) DataCell(Text(repName.toString())),
          DataCell(
            Tooltip(
              message: alert['descriptionClean'] ?? '',
              waitDuration: const Duration(milliseconds: 500),
              child: SizedBox(
                width: 250,
                child: Html(
                  data: (alert['description'] ?? alert['descriptionClean'] ?? '').toString(),
                  style: {
                    "body": Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                      fontSize: FontSize(12),
                      maxLines: 2,
                      textOverflow: TextOverflow.ellipsis,
                    ),
                  },
                ),
              ),
            ),
          ),
          DataCell(Text(DurationFormatter.format((alert['qtySpent'] as num?)?.toDouble() ?? 0.0))),
          DataCell(Text(chipDesc)),
        ];
      },
      mobileCardBuilder: (req) => _RecentRequestCard(request: req, onEdit: onEdit),
    );
  }
}

/// Vista de lista de tarjetas para Móvil
class _MobileRequestList extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final Function(Map<String, dynamic>) onEdit;

  const _MobileRequestList({required this.requests, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Center(
          child: Text(AppLocale.noRecentRequests.getString(context), style: const TextStyle(color: Colors.grey)),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final req = requests[index];
        return _RecentRequestCard(request: req, onEdit: onEdit);
      },
    );
  }
}

/// Tarjeta individual para la vista móvil de solicitudes recientes.
class _RecentRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final Function(Map<String, dynamic>) onEdit;

  const _RecentRequestCard({required this.request, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final String subject = request['emailSubject']?.toString() ?? 'Sin asunto';
    final String time = request['time'] ?? '';
    final String status = request['status'] ?? 'N/A';
    final String level = request['level'] ?? 'N/A';
    final Color levelBgColor = request['levelBgColor'] ?? Colors.transparent;
    final Color levelColor = request['levelColor'] ?? colorScheme.onSurface;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => onEdit(request),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Ticket #${request['code']}',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            AnimatedCopyWidget(
                              textToCopy: request['code'].toString(),
                              snackBarMessage: AppLocale.ticketCopiedToClipboard.getString(context),
                              iconSize: 16,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(subject, style: theme.textTheme.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'updates') {
                        GoRouter.of(context).push('/request-updates/${Uri.encodeComponent((request['realId'] ?? request['original']['id']).toString())}', extra: {'docNo': request['code']});
                      }
                      if (value == 'attachments') {
                        showDialog(
                          context: context,
                          builder: (context) => documents_logic.RequestAttachmentsDialog(requestId: request['realId'] ?? request['original']['id'], documentNo: request['code'] ?? ''),
                        );
                      }
                      if (value == 'go') {
                        GoRouter.of(context).push('/my-requests', extra: {'search': request['code']});
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'go',
                        child: ListTile(leading: const Icon(Icons.arrow_forward), title: Text(AppLocale.goToMyRequests.getString(context))),
                      ),
                      PopupMenuItem<String>(
                        value: 'updates',
                        child: ListTile(leading: Icon(AccessControl.canAddUpdates ? Icons.reply : Icons.forum), title: Text(AccessControl.canAddUpdates ? 'Responder' : 'Ver Actualizaciones')),
                      ),
                      PopupMenuItem<String>(
                        value: 'attachments',
                        child: ListTile(leading: const Icon(Icons.attach_file), title: Text(AppLocale.attachments.getString(context))),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(label: Text(status), visualDensity: VisualDensity.compact, backgroundColor: colorScheme.surfaceContainerHighest),
                  Chip(
                    label: Text(level),
                    labelStyle: TextStyle(color: levelColor, fontWeight: FontWeight.bold, fontSize: 12),
                    backgroundColor: levelBgColor,
                    visualDensity: VisualDensity.compact,
                  ),
                  if (time.isNotEmpty)
                    Chip(
                      avatar: Icon(Icons.calendar_today, size: 14, color: colorScheme.onSurfaceVariant),
                      label: Text(time),
                      labelStyle: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      backgroundColor: Colors.transparent,
                      shape: StadiumBorder(side: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
                      visualDensity: VisualDensity.compact,
                    ),
                  () {
                    final chipId = request['productChipId'];
                    if (chipId == null) return const SizedBox.shrink();
                    final found = GlobalCache.productChips.firstWhere(
                      (c) => c['id'] == chipId,
                      orElse: () => {},
                    );
                    final chipName = found.isEmpty ? '#$chipId' : (found['Description'] ?? found['Name'] ?? '#$chipId');
                    return Chip(
                      avatar: Icon(Icons.inventory_2_outlined, size: 14, color: colorScheme.primary),
                      label: Text(chipName),
                      labelStyle: theme.textTheme.bodySmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold),
                      backgroundColor: colorScheme.primaryContainer.withOpacity(0.3),
                      shape: StadiumBorder(side: BorderSide(color: colorScheme.primary.withOpacity(0.2))),
                      visualDensity: VisualDensity.compact,
                    );
                  }(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
