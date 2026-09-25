
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_html/flutter_html.dart';

import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart'
    as request_functions;
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/widgets/duration_formatter.dart';
import 'package:primhub/ui/pages/Support/Requests/bulk_edit_request_dialog.dart';
import 'package:primhub/ui/pages/Support/Requests/bulk_reopen_request_dialog.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'dart:math';
import 'package:primhub/ui/Shared_Custom/responsive_data_table.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart';
import 'package:primhub/ui/Shared_Custom/animated_copy_widget.dart';
import 'package:primhub/ui/Shared_Custom/request_mobile_card.dart';
import 'package:flutter_localization/flutter_localization.dart';

class RequestsDataTableCore extends StatefulWidget {
  final List<Map<String, dynamic>>
  requests; // Aquí MyRequests pasará 'paginatedAlerts'
  final Map<String, int> statusIdMap;
  final Map<String, String> priorityMap;
  final Function(Map<String, dynamic>) onEdit;
  final VoidCallback? onRefresh;
  final bool showProjectContext;
  final bool serverSidePagination;
  final Widget? paginationControls;
  final bool useSimpleStatus;

  const RequestsDataTableCore({
    super.key,
    required this.requests,
    required this.statusIdMap,
    required this.priorityMap,
    required this.onEdit,
    this.onRefresh,
    this.showProjectContext = false,
    this.serverSidePagination = false,
    this.paginationControls,
    this.useSimpleStatus = true,
  });

  @override
  State<RequestsDataTableCore> createState() => _RequestsDataTableCoreState();
}

class _RequestsDataTableCoreState extends State<RequestsDataTableCore> {
  final Set<int> _selectedIds = {};
  int? _lastSelectedIndex;

  String? _sortKey;
  bool _sortAscending = true;
  late List<Map<String, dynamic>> _sortedRequests;

  @override
  void initState() {
    super.initState();
    _sortedRequests = List.from(widget.requests);
  }

  @override
  void didUpdateWidget(covariant RequestsDataTableCore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requests != widget.requests) {
      _sortedRequests = List.from(widget.requests);
      _applySort();
    }
  }

  void _applySort() {
    if (_sortKey == null) return;
    _sortedRequests.sort((a, b) {
      dynamic valA;
      dynamic valB;

      if (_sortKey == 'id') {
        valA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
        valB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
      } else if (_sortKey == 'status') {
        valA = request_functions.cleanStatusName(a['status']?.toString() ?? '');
        valB = request_functions.cleanStatusName(b['status']?.toString() ?? '');
      } else if (_sortKey == 'situation') {
        valA = a['situation']?.toString() ?? '';
        valB = b['situation']?.toString() ?? '';
      } else if (_sortKey == 'category') {
        final catA = (a['original'] as Map?)?['R_Category_ID'];
        valA = catA is Map ? (catA['Name'] ?? catA['identifier'] ?? '') : '';
        final catB = (b['original'] as Map?)?['R_Category_ID'];
        valB = catB is Map ? (catB['Name'] ?? catB['identifier'] ?? '') : '';
      } else if (_sortKey == 'subject') {
        valA =
            a['emailSubject']?.toString() ??
            (a['original'] as Map?)?['Summary']?.toString() ??
            '';
        valB =
            b['emailSubject']?.toString() ??
            (b['original'] as Map?)?['Summary']?.toString() ??
            '';
      } else if (_sortKey == 'priority') {
        valA = a['level']?.toString() ?? '';
        valB = b['level']?.toString() ?? '';
      } else if (_sortKey == 'bp') {
        valA = a['bpName']?.toString() ?? '';
        valB = b['bpName']?.toString() ?? '';
      } else if (_sortKey == 'user') {
        valA = a['userName']?.toString() ?? '';
        valB = b['userName']?.toString() ?? '';
      } else if (_sortKey == 'salesRep') {
        valA = a['salesRepName']?.toString() ?? '';
        valB = b['salesRepName']?.toString() ?? '';
      } else if (_sortKey == 'description') {
        valA = a['descriptionClean']?.toString() ?? '';
        valB = b['descriptionClean']?.toString() ?? '';
      } else if (_sortKey == 'qtySpent') {
        valA = (a['qtySpent'] as num?)?.toDouble() ?? 0.0;
        valB = (b['qtySpent'] as num?)?.toDouble() ?? 0.0;
      } else if (_sortKey == 'productChip') {
        valA = a['productChipName']?.toString() ?? '';
        valB = b['productChipName']?.toString() ?? '';
      } else if (_sortKey == 'phase') {
        valA = a['phaseName']?.toString() ?? '';
        valB = b['phaseName']?.toString() ?? '';
      } else if (_sortKey == 'task') {
        valA = a['taskName']?.toString() ?? '';
        valB = b['taskName']?.toString() ?? '';
      } else if (_sortKey == 'created') {
        valA = (a['original'] as Map?)?['Created']?.toString() ?? a['created']?.toString() ?? '';
        valB = (b['original'] as Map?)?['Created']?.toString() ?? b['created']?.toString() ?? '';
      } else if (_sortKey == 'confidentialType') {
        final rawConfA = (a['original'] as Map?)?['ConfidentialType'];
        valA = rawConfA is Map ? rawConfA['id']?.toString() ?? 'C' : rawConfA?.toString() ?? 'C';
        final rawConfB = (b['original'] as Map?)?['ConfidentialType'];
        valB = rawConfB is Map ? rawConfB['id']?.toString() ?? 'C' : rawConfB?.toString() ?? 'C';
      }

      int cmp = 0;
      if (valA is num && valB is num) {
        cmp = valA.compareTo(valB);
      } else {
        cmp = valA.toString().compareTo(valB.toString());
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  void _onSort(String key) {
    setState(() {
      if (_sortKey == key) {
        _sortAscending = !_sortAscending;
      } else {
        _sortKey = key;
        _sortAscending = true;
      }
      _applySort();
    });
  }

  int _getRealId(Map<String, dynamic> req) =>
      req['realId'] ??
      req['_rawId'] ??
      int.tryParse(req['id']?.toString() ?? '0') ??
      0;

  void _handleRowSelection(bool? selected, int index, int realId) {
    final isShiftPressed =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );
    setState(() {
      if (isShiftPressed && _lastSelectedIndex != null) {
        int start = min(_lastSelectedIndex!, index);
        int end = max(_lastSelectedIndex!, index);
        for (int i = start; i <= end; i++) {
          final id = _getRealId(_sortedRequests[i]);
          selected == true ? _selectedIds.add(id) : _selectedIds.remove(id);
        }
      } else {
        selected == true
            ? _selectedIds.add(realId)
            : _selectedIds.remove(realId);
        _lastSelectedIndex = index;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bool isLaptop = MediaQuery.of(context).size.width < 1600;
    final bool isMobile = MediaQuery.of(context).size.width < 800;

    Widget buildBulkButton({
      required String tooltip,
      required IconData icon,
      required VoidCallback onPressed,
      Color? backgroundColor,
      Color? textColor,
    }) {
      if (isMobile) {
        return Tooltip(
          message: tooltip,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: backgroundColor ?? theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: IconButton(
              icon: Icon(icon, color: textColor ?? theme.colorScheme.onPrimary, size: 20),
              onPressed: onPressed,
            ),
          ),
        );
      } else {
        return CustomButton(
          text: tooltip,
          icon: icon,
          backgroundColor: backgroundColor,
          textColor: textColor,
          onPressed: onPressed,
        );
      }
    }

    final fixedCols = [
      ResponsiveDataColumn(
        label: AppLocale.actions.getString(context),
        suffixIcon: Tooltip(
          message: AppLocale.sortingHelp.getString(context),
          child: Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
          ),
        ),
      ),
      const ResponsiveDataColumn(label: 'Ticket', sortKey: 'id'),
      if (!isLaptop) ...[
        ResponsiveDataColumn(label: AppLocale.status.getString(context), sortKey: 'status'),
        if (AccessControl.isAdmin || AccessControl.isSupport)
          ResponsiveDataColumn(
            label: AppLocale.requestType.getString(context),
            sortKey: 'situation',
          ),
      ],
    ];

    List<DataCell> buildFixedCells(Map<String, dynamic> alert) {
      return [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: AccessControl.canAddUpdates
                    ? AppLocale.reply.getString(context)
                    : AppLocale.viewUpdates.getString(context),
                icon: Icon(
                  AccessControl.canAddUpdates ? Icons.reply : Icons.forum,
                ),
                onPressed: () => GoRouter.of(context).push(
                  '/request-updates/${Uri.encodeComponent(alert['realId'].toString())}',
                  extra: {'docNo': alert['id']},
                ),
              ),
              IconButton(
                tooltip: AppLocale.viewAttachments.getString(context),
                icon: const Icon(Icons.attach_file),
                onPressed: () => showDialog(
                  context: context,
                  builder: (context) => RequestAttachmentsDialog(
                    requestId: alert['realId'],
                    documentNo: alert['id'],
                  ),
                ),
              ),
              IconButton(
                tooltip: AccessControl.canManageRequests
                    ? AppLocale.edit.getString(context)
                    : AppLocale.viewDetails.getString(context),
                icon: Icon(
                  AccessControl.canManageRequests
                      ? Icons.edit
                      : Icons.visibility,
                ),
                onPressed: () => widget.onEdit(alert),
              ),
            ],
          ),
        ),
        DataCell(
          AnimatedCopyWidget(
            textToCopy: alert['id']?.toString() ?? '',
            snackBarMessage: AppLocale.ticketCopiedShort.getString(context),
            leadingText: Text(alert['id']?.toString() ?? ''),
          ),
        ),
        if (!isLaptop) ...[
          DataCell(
            Text(
              request_functions.cleanStatusName(
                alert['status']?.toString() ?? 'Sin Estado',
              ),
            ),
          ),
          if (AccessControl.isAdmin || AccessControl.isSupport)
            DataCell(Text(alert['situation']?.toString() ?? 'Sin tipo')),
        ],
      ];
    }

    final scrollableCols = [
      if (isLaptop) ...[
        ResponsiveDataColumn(label: AppLocale.status.getString(context), sortKey: 'status'),
        if (AccessControl.isAdmin || AccessControl.isSupport)
          ResponsiveDataColumn(
            label: AppLocale.requestType.getString(context),
            sortKey: 'situation',
          ),
      ],
      ResponsiveDataColumn(label: AppLocale.category.getString(context), sortKey: 'category'),
      ResponsiveDataColumn(label: AppLocale.subject.getString(context)),
      ResponsiveDataColumn(label: AppLocale.priority.getString(context), sortKey: 'priority'),
      if (widget.showProjectContext)
        ResponsiveDataColumn(label: AppLocale.phase.getString(context), sortKey: 'phase'),
      if (widget.showProjectContext)
        ResponsiveDataColumn(label: AppLocale.task.getString(context), sortKey: 'task'),
      if (AccessControl.isAdmin)
        ResponsiveDataColumn(label: AppLocale.businessPartner.getString(context), sortKey: 'bp'),
      if (AccessControl.isAdmin)
        ResponsiveDataColumn(label: AppLocale.user.getString(context), sortKey: 'user'),
      if (AccessControl.isAdmin)
        ResponsiveDataColumn(
          label: AppLocale.salesRepresentative.getString(context),
          sortKey: 'salesRep',
        ),
      ResponsiveDataColumn(label: AppLocale.description.getString(context)),
      ResponsiveDataColumn(
        label: AppLocale.consumedHours.getString(context),
        sortKey: 'qtySpent',
        numeric: true,
      ),
      if (!widget.showProjectContext)
        ResponsiveDataColumn(
          label: AppLocale.productSheet.getString(context),
          sortKey: 'productChip',
        ),
      if (AccessControl.isAdmin)
        ResponsiveDataColumn(label: AppLocale.created.getString(context), sortKey: 'created'),
      if (AccessControl.isRealAdmin)
        ResponsiveDataColumn(label: AppLocale.confidentiality.getString(context), sortKey: 'confidentialType'),
    ];

    List<DataCell> buildScrollableCells(Map<String, dynamic> alert) {
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
          catName =
              catInCache['Name']?.toString() ??
              catInCache['identifier']?.toString() ??
              '';
        }
      }

      final String finalCatName = catName.isNotEmpty
          ? catName
          : 'Sin Categoría';



      final repData = original['SalesRep_ID'];
      final repName = repData is Map
          ? (repData['Name'] ?? repData['identifier'] ?? '')
          : '';

      final chipId =
          alert['productChipId'] ??
          (original['C_BPartner_Product_Chip_ID'] is Map
              ? original['C_BPartner_Product_Chip_ID']['id']
              : original['C_BPartner_Product_Chip_ID']);
      String chipDesc = 'N/A';
      if (chipId != null) {
        final cIdNum = (chipId as num?)?.toInt();
        if (cIdNum != null) {
          final found = GlobalCache.productChips.firstWhere((c) {
            final cId =
                int.tryParse(c['id']?.toString() ?? '') ??
                int.tryParse(c['C_BPartner_Product_Chip_ID']?.toString() ?? '');
            return cId == cIdNum;
          }, orElse: () => <String, dynamic>{});
          if (found.isNotEmpty) {
            chipDesc =
                found['Description']?.toString() ??
                found['Name']?.toString() ??
                'Ficha $cIdNum';
          } else {
            chipDesc = alert['productChipName']?.toString() ?? 'Ficha $cIdNum';
          }
        }
      }

      final createdRaw = original['Created']?.toString() ?? alert['created']?.toString() ?? '';
      String createdFormatted = createdRaw;
      if (createdRaw.isNotEmpty) {
        try {
          final dt = DateTime.parse(createdRaw);
          final day = dt.day.toString().padLeft(2, '0');
          final month = dt.month.toString().padLeft(2, '0');
          final year = dt.year.toString();
          final hour24 = dt.hour;
          final minute = dt.minute.toString().padLeft(2, '0');
          final ampm = hour24 >= 12 ? 'PM' : 'AM';
          final hour12 = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24);
          final hourStr = hour12.toString().padLeft(2, '0');
          createdFormatted = '$day/$month/$year $hourStr:$minute $ampm';
        } catch (e) {
          createdFormatted = createdRaw.length >= 19 ? createdRaw.substring(0, 19) : createdRaw;
        }
      }

      return [
        if (isLaptop) ...[
          DataCell(
            Text(
              request_functions.cleanStatusName(
                alert['status']?.toString() ?? 'Sin Estado',
              ),
            ),
          ),
          if (AccessControl.isAdmin || AccessControl.isSupport)
            DataCell(Text(alert['situation']?.toString() ?? 'Sin tipo')),
        ],
        DataCell(Text(finalCatName)),
        DataCell(
          Tooltip(
            message: alert['emailSubject']?.toString() ?? '',
            waitDuration: const Duration(milliseconds: 500),
            showDuration: const Duration(seconds: 2),
            child: Text(
              (alert['emailSubject']?.toString() ?? '').length > 25
                  ? '${(alert['emailSubject']?.toString() ?? '').substring(0, 25)}...'
                  : (alert['emailSubject']?.toString() ?? ''),
            ),
          ),
        ),
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
        if (widget.showProjectContext)
          DataCell(Text(alert['phaseName']?.toString() ?? '-')),
        if (widget.showProjectContext)
          DataCell(Text(alert['taskName']?.toString() ?? '-')),
        if (AccessControl.isAdmin)
          DataCell(Text(alert['bpName']?.toString() ?? '')),
        if (AccessControl.isAdmin)
          DataCell(Text(alert['userName']?.toString() ?? '')),
        if (AccessControl.isAdmin)
          DataCell(
            Text(
              repName.toString().isEmpty
                  ? (alert['salesRepName']?.toString() ?? '')
                  : repName.toString(),
            ),
          ),
        DataCell(
          Tooltip(
            message: alert['descriptionClean'] ?? '',
            waitDuration: const Duration(milliseconds: 500),
            child: SizedBox(
              width: 250,
              child: Html(
                data: (alert['description'] ?? alert['descriptionClean'] ?? '')
                    .toString(),
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
        DataCell(
          Text(
            DurationFormatter.format(
              (alert['qtySpent'] as num?)?.toDouble() ?? 0.0,
            ),
          ),
        ),
        if (!widget.showProjectContext) DataCell(Text(chipDesc)),
        if (AccessControl.isAdmin) DataCell(Text(createdFormatted)),
        if (AccessControl.isRealAdmin) DataCell(Text(
          (() {
            final rawConf = original['ConfidentialType'];
            final confVal = rawConf is Map ? rawConf['id']?.toString() ?? 'C' : rawConf?.toString() ?? 'C';
            return confVal == 'I' ? AppLocale.internalNote.getString(context) : (confVal == 'C' ? AppLocale.visibleToClient.getString(context) : AppLocale.publicLabel.getString(context));
          })()
        )),
      ];
    }

    final bulkActionsWidget = AccessControl.canManageRequests
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8.0,
              runSpacing: 8.0,
              children: [
                buildBulkButton(
                  tooltip: AppLocale.bulkReopen.getString(context),
                  icon: Icons.restore,
                  backgroundColor: Colors.orange.shade700,
                  textColor: Colors.white,
                  onPressed: () {
                    if (_selectedIds.isEmpty) {
                      ToastMessage.show(
                        context: context,
                        message: 'Seleccione una o mas solicitudes para empezar el proceso de: Edicion masiva o Reapertura de solicitud/es segun corresponda',
                        type: ToastType.warning,
                      );
                      return;
                    }
                    showDialog(
                      context: context,
                      builder: (context) => BulkReopenRequestDialog(
                        selectedIds: _selectedIds,
                        onSaved: () => setState(() => _selectedIds.clear()),
                      ),
                    );
                  },
                ),
                buildBulkButton(
                  tooltip: AppLocale.bulkEdit.getString(context),
                  icon: Icons.edit,
                  onPressed: () {
                    if (_selectedIds.isEmpty) {
                      ToastMessage.show(
                        context: context,
                        message: 'Seleccione una o mas solicitudes para empezar el proceso de: Edicion masiva o Reapertura de solicitud/es segun corresponda',
                        type: ToastType.warning,
                      );
                      return;
                    }
                    showDialog(
                      context: context,
                      builder: (context) => BulkEditRequestDialog(
                        selectedIds: _selectedIds,
                        onSaved: () => setState(() => _selectedIds.clear()),
                      ),
                    );
                  },
                ),
                if (_selectedIds.isNotEmpty)
                  Text(
                    '${_selectedIds.length} seleccionadas',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.serverSidePagination && widget.paginationControls != null)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 600) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (AccessControl.canManageRequests) bulkActionsWidget,
                    widget.paginationControls!,
                  ],
                );
              }
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  widget.paginationControls!,
                  if (AccessControl.canManageRequests) bulkActionsWidget,
                ],
              );
            },
          )
        else if (AccessControl.canManageRequests)
          bulkActionsWidget,
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ResponsiveDataTable<Map<String, dynamic>>(
                items: _sortedRequests,
                sortKey: _sortKey,
                sortAscending: _sortAscending,
                onSort: _onSort,
                getId: (item) => _getRealId(item),
                onRowTap: (item) => widget.onEdit(item),
                showCheckboxColumn: AccessControl.canManageRequests,
                selectedIds: _selectedIds,
                onSelectAll: (selected) {
                  setState(() {
                    selected == true
                        ? _selectedIds.addAll(
                            _sortedRequests.map((r) => _getRealId(r)),
                          )
                        : _selectedIds.clear();
                  });
                },
                onSelectChanged: (id, isSelected) {
                  final index = _sortedRequests.indexWhere(
                    (r) => _getRealId(r) == id,
                  );
                  if (index != -1) _handleRowSelection(isSelected, index, id);
                },
                fixedColumns: fixedCols,
                fixedCellBuilder: buildFixedCells,
                scrollableColumns: scrollableCols,
                scrollableCellBuilder: buildScrollableCells,
                mobileCardBuilder: (item) => RequestMobileCard(
                  request: item,
                  showCheckbox: AccessControl.canManageRequests,
                  isSelected: _selectedIds.contains(_getRealId(item)),
                  onSelectChanged: (selected) {
                    final realId = _getRealId(item);
                    final index = _sortedRequests.indexWhere((r) => _getRealId(r) == realId);
                    if (index != -1) _handleRowSelection(selected ?? false, index, realId);
                  },
                  onEdit: widget.onEdit,
                  onGoToUpdates: () {
                    GoRouter.of(context).push(
                      '/request-updates/${Uri.encodeComponent(_getRealId(item).toString())}',
                      extra: {'docNo': item['id']},
                    );
                  },
                  onShowAttachments: () {
                    showDialog(
                      context: context,
                      builder: (context) => RequestAttachmentsDialog(
                        requestId: _getRealId(item),
                        documentNo: item['id'],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Fin del archivo
