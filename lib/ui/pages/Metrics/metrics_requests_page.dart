import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:go_router/go_router.dart';

import 'package:primhub/ui/pages/Support/Requests/request_functions.dart'; 
import 'package:primhub/api/access_control.dart';
import 'package:primhub/api/token.dart';

import 'package:primhub/ui/pages/Support/Requests/edit_request_dialog.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/pages/Metrics/graphic_functions.dart';
import 'package:primhub/ui/Shared_Custom/requests_data_table_core.dart'; 
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/Shared_Custom/custom_skeleton.dart';
import 'package:flutter_localization/flutter_localization.dart';

class ProjectRequestsPage extends StatefulWidget {
  final String? filterType;
  final String? filterStatus;
  final String? filterCompliance;
  final String? filterPriority;
  final String? filterProductChip;
  final int? filterSpecificChipId;
  final int? projectId;
  final List<String>? taskUUIDs;

  const ProjectRequestsPage({super.key, this.filterType, this.filterStatus, this.filterCompliance, this.filterPriority, this.filterProductChip, this.filterSpecificChipId, this.projectId, this.taskUUIDs});

  @override
  State<ProjectRequestsPage> createState() => _ProjectRequestsPageState();
}

class _ProjectRequestsPageState extends State<ProjectRequestsPage> {
  List<Map<String, dynamic>> _allRequests = []; 
  List<Map<String, dynamic>> _paginatedRequests = []; 
  bool _isLoading = true;
  Map<int, String> _statusNameMap = {};
  Map<String, int> _statusIdMap = {};

  String? _filterType;
  String? _filterStatus;
  String? _filterCompliance;
  String? _filterPriority;
  String? _filterProductChip;
  int? _filterSpecificChipId;
  int? _projectId;
  List<String>? _taskUUIDs;
  bool _isInit = true;

  int _currentPage = 0;
  int _rowsPerPage = 10;

  @override
  void initState() {
    super.initState();
    GlobalCache.backgroundSyncNotifier.addListener(_onBackgroundSyncChanged);
  }

  void _onBackgroundSyncChanged() {
    if (!GlobalCache.backgroundSyncNotifier.value && mounted) {
      _initData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      _filterType = widget.filterType;
      _filterStatus = widget.filterStatus;
      _filterCompliance = widget.filterCompliance;
      _projectId = widget.projectId;
      _taskUUIDs = widget.taskUUIDs;

      try {
        final extra = GoRouterState.of(context).extra;
        if (extra is Map) {
          if (extra.containsKey('filterType')) _filterType = extra['filterType'];
          if (extra.containsKey('filterStatus')) _filterStatus = extra['filterStatus'];
          if (extra.containsKey('filterCompliance')) _filterCompliance = extra['filterCompliance'];
          if (extra.containsKey('filterPriority')) _filterPriority = extra['filterPriority'];
          if (extra.containsKey('filterProductChip')) _filterProductChip = extra['filterProductChip'];
          if (extra.containsKey('filterSpecificChipId')) _filterSpecificChipId = extra['filterSpecificChipId'];
          if (extra.containsKey('projectId')) _projectId = extra['projectId'];
          if (extra.containsKey('taskUUIDs')) _taskUUIDs = extra['taskUUIDs'];
        }
      } catch (_) {
      // Ignored: Fail silently
    }

      _isInit = false;
      _initData();
    }
  }

  Future<void> _initData({bool showLoading = true}) async {
    if (showLoading && _allRequests.isEmpty) setState(() => _isLoading = true);
    await _fetchStatusesMap();
    // Corrected method name to match the definition below
    await _loadRequests(); 
    _applyPagination(); 
  }

  Future<void> _fetchStatusesMap() async {
    if (GlobalCache.isDataLoaded && GlobalCache.statuses.isNotEmpty) {
      if (mounted) {
        setState(() {
          _statusIdMap = GlobalCache.statuses;
          _statusNameMap = GlobalCache.statuses.map((key, value) => MapEntry(value, key));
        });
      }
    } else {
      final statuses = await fetchStatuses();
      if (mounted) {
        setState(() {
          _statusIdMap = statuses;
          _statusNameMap = statuses.map((key, value) => MapEntry(value, key));
        });
      }
    }
  }

  Future<void> _loadRequests() async {
    List<Map<String, dynamic>> rawRequests = [];
    bool isFromMetricsChart = _projectId != null && (_filterType != null || _filterStatus != null || _filterCompliance != null || _filterPriority != null) && _taskUUIDs == null;

    if (isFromMetricsChart) {
      rawRequests = await GraphicsFunctions.fetchMetricsData(projectId: _projectId!);
    } else if (GlobalCache.isDataLoaded) {
      List<String> uuidsToMatch = _taskUUIDs != null ? List.from(_taskUUIDs!) : [];

      if (_projectId != null && uuidsToMatch.isEmpty) {
        try {
          final project = GlobalCache.projects.firstWhere((p) => p['id'] == _projectId, orElse: () => null);
          if (project != null) {
            final phases = project['C_ProjectPhase'] as List? ?? [];
            for (var phase in phases) {
              final tasks = phase['C_ProjectTask'] as List? ?? [];
              for (var task in tasks) {
                final uuid = task['Record_UU'] ?? task['UUID'] ?? task['uuid'] ?? task['uid'];
                if (uuid != null) uuidsToMatch.add(uuid.toString());
              }
            }
            final directTasks = project['C_ProjectTask'] as List? ?? [];
            for (var task in directTasks) {
              final uuid = task['Record_UU'] ?? task['UUID'] ?? task['uuid'] ?? task['uid'];
              if (uuid != null) uuidsToMatch.add(uuid.toString());
            }
          }
        } catch (_) {
      // Ignored: Fail silently
    }
      }

      rawRequests = GlobalCache.requests.where((req) {
        bool isActive = req['IsActive'] == true || req['IsActive'] == 'Y';
        if (!isActive) return false;

        final statusData = req['R_Status_ID'];
        String rawStatusName = statusData is Map
            ? (statusData['Name'] ?? statusData['identifier'] ?? req['R_Status_Name'] ?? '')
            : (req['R_Status_Name'] ?? '');
        if (rawStatusName.toLowerCase().contains('anulada')) return false;

        if (!AccessControl.isAdmin && AccessControl.isProject && User.cBPartnerID != null) {
          int? reqBpId = req['C_BPartner_ID'] is Map ? req['C_BPartner_ID']['id'] : req['C_BPartner_ID'];
          if (reqBpId != User.cBPartnerID) return false;
        }

        if (_projectId != null) {
          int? reqProjectId = req['C_Project_ID'] is Map ? req['C_Project_ID']['id'] : req['C_Project_ID'];
          bool matchesProject = reqProjectId == _projectId;
          bool matchesTask = uuidsToMatch.contains(req['Record_UU']?.toString());
          return matchesProject || matchesTask;
        } else if (_taskUUIDs != null && _taskUUIDs!.isNotEmpty) {
          return _taskUUIDs!.contains(req['Record_UU']?.toString());
        } else {
          // IsOpen == true
          bool isOpen = false;
          final int? statusId = statusData is Map ? (statusData['id'] as num?)?.toInt() : (statusData is num ? statusData.toInt() : null);
          if (statusData is Map && statusData['IsOpen'] != null) {
            final rawIsOpen = statusData['IsOpen'];
            final isOpenStr = rawIsOpen?.toString().trim().toLowerCase();
            isOpen = (isOpenStr == 'true' || isOpenStr == 'y' || rawIsOpen == true);
          } else if (statusId != null) {
            isOpen = GlobalCache.statusIsOpenMap[statusId] ?? false;
          }
          if (!isOpen) return false;

          // Soporte Técnico (Categoría)
          bool isSoporteTecnico = false;
          if (statusId != null) {
            final categoryId = GlobalCache.statusCategoryMap[statusId];
            if (categoryId != null) {
              final categoryName = GlobalCache.statusCategoryNameMap[categoryId]?.toLowerCase() ?? '';
              if (categoryName.contains('soporte técnico') || categoryName.contains('soporte tecnico')) {
                 isSoporteTecnico = true;
              }
            }
          }
          if (!isSoporteTecnico) return false;

          // Soporte Lirion (Tipo)
          bool isSoporteLirion = false;
          final typeObj = req['R_RequestType_ID'];
          if (typeObj is Map) {
            String typeName = (typeObj['Name'] ?? typeObj['identifier'] ?? '').toString().toLowerCase();
            isSoporteLirion = typeName.contains('soporte lirion');
          } else if (typeObj != null) {
            int? typeId = int.tryParse(typeObj.toString());
            if (typeId != null) {
              String? name = GlobalCache.requestTypes.keys.cast<String?>().firstWhere((k) => GlobalCache.requestTypes[k] == typeId, orElse: () => null);
              if (name != null && name.toLowerCase().contains('soporte lirion')) {
                isSoporteLirion = true;
              }
            }
          }
          if (!isSoporteLirion) return false;
          
          return true;
        }
      }).toList();
    } else {
      List<String> filters = ["IsActive eq true"];
      if (!AccessControl.isAdmin && AccessControl.isProject && User.cBPartnerID != null) {
        filters.add("C_BPartner_ID eq ${User.cBPartnerID}");
      }
      String additionalFilter = filters.join(" and ");
      String expand = "R_Status_ID(\$select=Name,IsOpen),R_Group_ID(\$select=Name),R_RequestType_ID(\$select=Name),R_Category_ID(\$select=Name)";

      if (_projectId != null) {
        rawRequests = await fetchProjectAndTaskRequests(_projectId!, taskUUIDs: _taskUUIDs, additionalFilter: additionalFilter, expand: expand);
      } else if (_taskUUIDs != null && _taskUUIDs!.isNotEmpty) {
        final uuidsCondition = _taskUUIDs!.map((uuid) => "Record_UU eq '$uuid'").join(' or ');
        rawRequests = await fetchRequest(filter: "($uuidsCondition) and $additionalFilter", expand: expand);
      } else {
        rawRequests = await fetchRequest(filter: additionalFilter, expand: expand);
        rawRequests = rawRequests.where((req) {
          final statusData = req['R_Status_ID'];
          final int? statusId = statusData is Map ? (statusData['id'] as num?)?.toInt() : (statusData is num ? statusData.toInt() : null);
          // IsOpen == true
          bool isOpen = false;
          if (statusData is Map && statusData['IsOpen'] != null) {
            final rawIsOpen = statusData['IsOpen'];
            final isOpenStr = rawIsOpen?.toString().trim().toLowerCase();
            isOpen = (isOpenStr == 'true' || isOpenStr == 'y' || rawIsOpen == true);
          } else if (statusId != null) {
            isOpen = GlobalCache.statusIsOpenMap[statusId] ?? false;
          }
          if (!isOpen) return false;

          // Soporte Técnico (Categoría)
          bool isSoporteTecnico = false;
          if (statusId != null) {
            final categoryId = GlobalCache.statusCategoryMap[statusId];
            if (categoryId != null) {
              final categoryName = GlobalCache.statusCategoryNameMap[categoryId]?.toLowerCase() ?? '';
              if (categoryName.contains('soporte técnico') || categoryName.contains('soporte tecnico')) {
                 isSoporteTecnico = true;
              }
            }
          }
          if (!isSoporteTecnico) return false;

          // Soporte Lirion (Tipo)
          bool isSoporteLirion = false;
          final typeObj = req['R_RequestType_ID'];
          if (typeObj is Map) {
            String typeName = (typeObj['Name'] ?? typeObj['identifier'] ?? '').toString().toLowerCase();
            isSoporteLirion = typeName.contains('soporte lirion');
          } else if (typeObj != null) {
            int? typeId = int.tryParse(typeObj.toString());
            if (typeId != null) {
              String? name = GlobalCache.requestTypes.keys.cast<String?>().firstWhere((k) => GlobalCache.requestTypes[k] == typeId, orElse: () => null);
              if (name != null && name.toLowerCase().contains('soporte lirion')) {
                isSoporteLirion = true;
              }
            }
          }
          if (!isSoporteLirion) return false;
          
          return true;
        }).toList();
      }
    }

    final filtered = rawRequests.where((req) {
      final statusObj = req['R_Status_ID'];
      final statusData = statusObj is Map ? statusObj : null;
      String rawStatusName = req['R_Status_Name'] ?? '';

      if (statusData != null) {
        rawStatusName = statusData['Name'] ?? statusData['identifier'] ?? rawStatusName;
      }
      if (rawStatusName.isEmpty && statusObj is int) {
        rawStatusName = _statusNameMap[statusObj] ?? '';
      }
      if (rawStatusName.isEmpty) {
        rawStatusName = _statusIdMap.keys.firstWhere((k) => _statusIdMap[k] == req['R_Status_ID'], orElse: () => 'Sin Estado');
      }

      String cleanStatusName = rawStatusName.contains('_') ? rawStatusName.split('_').last.trim() : rawStatusName.trim();

      bool matchesType = true;
      if (_filterType != null && _filterType != 'Solicitudes Totales') {
        String categoryName = '';
        final categoryObj = req['R_Category_ID'];
        if (categoryObj is Map) {
          categoryName = categoryObj['Name'] ?? categoryObj['identifier'] ?? categoryObj['name'] ?? '';
        }
        if (categoryName.isEmpty) categoryName = 'Sin Módulo';
        String cleanFilter = _filterType!.replaceAll('.', '').trim();
        matchesType = categoryName == _filterType || categoryName.startsWith(cleanFilter);
      }

      bool matchesStatus = true;
      if (_filterStatus != null) {
        matchesStatus = cleanStatusName == _filterStatus;
      }

      bool matchesCompliance = true;
      if (_filterCompliance != null) {
        final category = ProjectMetricsCalculator.getComplianceCategory(req);
        matchesCompliance = category == _filterCompliance;
      }

      bool matchesPriority = true;
      if (_filterPriority != null) {
        dynamic rawPriority;
        
        final categoryId = req['R_Category_ID'] is Map ? req['R_Category_ID']['id'] : req['R_Category_ID'];
        if (categoryId != null) {
          final cat = GlobalCache.rawCategories.firstWhere((c) => c['id'] == categoryId, orElse: () => {});
          if (cat.isNotEmpty) {
            rawPriority = cat['Priority'] is Map ? cat['Priority']['id'] : cat['Priority'];
          }
        }

        String priorityStr = rawPriority != null ? rawPriority.toString() : '5';
        String mappedPriority = 'Media';
        final pLower = priorityStr.toLowerCase();
        
        if (pLower.contains('urgente') || priorityStr == '1') {
          mappedPriority = 'Urgente';
        } else if (pLower.contains('alta') || priorityStr == '3') {
          mappedPriority = 'Alta';
        } else if (pLower.contains('media') || priorityStr == '5') {
          mappedPriority = 'Media';
        } else if (pLower.contains('muy baja') || pLower.contains('menor') || priorityStr == '9') {
          mappedPriority = 'Muy baja';
        } else if (pLower.contains('baja') || priorityStr == '7') {
          mappedPriority = 'Baja';
        } else {
          mappedPriority = priorityStr;
        }

        if (_filterPriority == 'Críticos') {
          matchesPriority = mappedPriority == 'Urgente' || mappedPriority == 'Alta';
        } else {
          matchesPriority = mappedPriority == _filterPriority;
        }
      }
      
      bool matchesChip = true;
      if (_filterProductChip != null && _filterProductChip != 'mixto') {
        bool hasChip = req['productChipId'] != null || req['C_BPartner_Product_Chip_ID'] != null;
        if (_filterProductChip == 'con_ficha' && !hasChip) {
          matchesChip = false;
        } else if (_filterProductChip == 'sin_ficha' && hasChip) {
          matchesChip = false;
        }
      }
      if (_filterSpecificChipId != null) {
        int? reqChipId = req['productChipId'] is Map ? req['productChipId']['id'] : req['productChipId'];
        reqChipId ??= req['C_BPartner_Product_Chip_ID'] is Map ? req['C_BPartner_Product_Chip_ID']['id'] : req['C_BPartner_Product_Chip_ID'];
        if (reqChipId != _filterSpecificChipId) matchesChip = false;
      }

      return matchesType && matchesStatus && matchesCompliance && matchesPriority && matchesChip;
    }).toList();

    final processed = await processRequests(filtered, _statusIdMap);

    if (mounted) {
      setState(() {
        _allRequests = (processed['requests'] as List<dynamic>).cast<Map<String, dynamic>>();
        _isLoading = false;
        _currentPage = 0;
      });
    }
  }

  void _applyPagination() {
    final int totalItems = _allRequests.length;
    final int totalPages = (totalItems / _rowsPerPage).ceil();
    if (_currentPage >= totalPages) _currentPage = totalPages > 0 ? totalPages - 1 : 0;
    final int startIndex = _currentPage * _rowsPerPage;
    final int endIndex = (startIndex + _rowsPerPage < totalItems) ? startIndex + _rowsPerPage : totalItems;
    
    setState(() {
      _paginatedRequests = totalItems > 0 ? _allRequests.sublist(startIndex, endIndex) : <Map<String, dynamic>>[];
    });
  }

  Future<void> _deleteRequest(dynamic id) async {
    if (!AccessControl.canManageRequests) {
      ToastMessage.show(context: context, message: AppLocale.noPermissionDeleteRequests.getString(context), type: ToastType.help);
      return;
    }
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => CustomModal(
        title: AppLocale.confirmDeletion.getString(context),
        content: Text(AppLocale.confirmDeleteRequest.getString(context)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocale.cancel.getString(context))),
          CustomButton(text: AppLocale.delete.getString(context), backgroundColor: Colors.red, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );

    if (confirm == true) {
      final success = await deleteRequestApi(id);
      if (mounted) {
        if (success) {
          ToastMessage.show(context: context, message: AppLocale.requestDeletedSuccessfully.getString(context), type: ToastType.help);
          _initData(showLoading: false);
        } else {
          ToastMessage.show(context: context, message: AppLocale.deleteError.getString(context), type: ToastType.failure);
        }
      }
    }
  }

  void _editRequest(Map<String, dynamic> req) {
    if (!AccessControl.canManageRequests) return;
    showDialog(
      context: context,
      builder: (context) => EditRequestDialog(
        request: req,
        statusIdMap: _statusIdMap,
        priorityMap: priorityMap,
        onSave: () async {
          _initData(showLoading: false);
        },
        onDelete: () => _deleteRequest(req['realId']),
      ),
    );
  }

  @override
  void dispose() {
    GlobalCache.backgroundSyncNotifier.removeListener(_onBackgroundSyncChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {    
    final int totalItems = _allRequests.length;
    final int totalPages = (totalItems / _rowsPerPage).ceil();
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Solicitudes: ${_filterType ?? _filterStatus ?? _filterCompliance ?? _filterPriority ?? "Detalle"}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocale.refreshData.getString(context),
            onPressed: () {
              setState(() => _isLoading = true);
              GlobalCache.forceFullSyncWithProgress(context, onSyncAction: () async {
                await _initData();
              });
            },
          ),
        ],
      ),

      body: SafeArea(
        child: _isLoading
            ? const SkeletonTable()
            : _allRequests.isEmpty
                ? const Center(child: Text('No se encontraron solicitudes para este tipo.'))
                : Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: RequestsDataTableCore(
                            requests: _paginatedRequests,
                            statusIdMap: _statusIdMap,
                            priorityMap: priorityMap,
                            onEdit: _editRequest,
                            onRefresh: () => _initData(showLoading: false),
                            showProjectContext: AccessControl.isProject,
                          ),
                        ),
                      ),
                      if (totalPages > 1) 
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 16.0,
                            children: [
                              DropdownButton<int>(
                                value: _rowsPerPage,
                                items: const [10, 25, 50, 100].map((int value) => DropdownMenuItem<int>(value: value, child: Text('$value filas'))).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _rowsPerPage = val;
                                      _currentPage = 0;
                                    });
                                    _applyPagination();
                                  }
                                },
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: _currentPage > 0 ? () => setState(() { _currentPage--; _applyPagination(); }) : null),
                                  Text(
                                    AppLocale.pageOf.getStringWithVariables(context, {'page': '${_currentPage + 1}', 'total': '$totalPages'}),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: _currentPage < totalPages - 1 ? () => setState(() { _currentPage++; _applyPagination(); }) : null),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
