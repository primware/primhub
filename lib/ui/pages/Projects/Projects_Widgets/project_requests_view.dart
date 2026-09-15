import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/ui/Shared_Custom/custom_skeleton.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/pages/Support/Requests/edit_request_dialog.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/requests_data_table_core.dart'; // Usar el componente core

import 'package:primhub/ui/pages/Projects/Projects_Widgets/project_request_filter_modal.dart';
import 'package:flutter_localization/flutter_localization.dart';

class ProjectRequestsView extends StatefulWidget {
  final String? filterType;
  final String? filterStatus;
  final String? filterCompliance;
  final int? projectId;
  final List<String>? taskUUIDs;
  final bool showAllGroups;

  const ProjectRequestsView({
    super.key,
    this.filterType,
    this.filterStatus,
    this.filterCompliance,
    this.projectId,
    this.taskUUIDs,
    this.showAllGroups = false,
  });

  @override
  State<ProjectRequestsView> createState() => _ProjectRequestsViewState();
}

class _ProjectRequestsViewState extends State<ProjectRequestsView> {
  List<Map<String, dynamic>> _allProjectRequests = [];
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  Map<String, int> _statusIdMap = {};
  List<dynamic> _users = [];
  final TextEditingController _searchController = TextEditingController();
  String _projectName = '';

  ProjectRequestFilterModel _filters = const ProjectRequestFilterModel();
  // ignore: unused_field
  final bool _isAscending = false;

  // Pagination state
  int _currentPageSize = 25;
  int _currentSkip = 0;
  int _totalRecords = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => _applyFilters());
    _initData();
  }

  Future<void> _initData({bool showLoading = true, bool resetPage = true}) async {
    if (!mounted) return;
    if (showLoading) setState(() => _isLoading = true);

    _users =
        GlobalCache.users; // Assuming GlobalCache.users is already populated
    _statusIdMap = GlobalCache.statuses;

    await _loadRequests(resetPage: resetPage);
  }

  Future<void> _loadRequests({bool resetPage = true}) async {
    // --- DEBUG LOGS ---

    List<String> taskUUIDs = [];
    Map<String, String> uuidToTaskName = {};
    Map<String, String> uuidToPhaseName = {};
    Map<String, String> taskIdToTaskName = {};
    Map<String, String> taskIdToPhaseName = {};
    Map<String, String> idToPhaseName = {};

    // 1. Mapear la estructura del proyecto para obtener todos los UUIDs de tareas
    if (widget.projectId != null) {
      final project = GlobalCache.projects.firstWhere(
        (p) => p['id']?.toString() == widget.projectId?.toString(),
        orElse: () => <String, dynamic>{},
      );

      if (project.isNotEmpty) {
        _projectName = project['Name'] ?? '';

        final phases = List<dynamic>.from(
          project['C_ProjectPhase'] as List? ?? [],
        );
        final directTasks = List<dynamic>.from(
          project['C_ProjectTask'] as List? ?? [],
        );

        // 1.1 Procesar tareas de las fases
        for (var phase in phases) {
          final phaseName = phase['Name'] ?? 'Fase';
          final phaseIdStr = phase['id']?.toString();
          if (phaseIdStr != null) {
            idToPhaseName[phaseIdStr] = phaseName;
          }
          final tasks = List<dynamic>.from(
            phase['C_ProjectTask'] as List? ?? [],
          );
          for (var task in tasks) {
            final taskName = task['Name'] ?? 'Tarea';
            final taskIdStr = task['id']?.toString();
            if (taskIdStr != null) {
              taskUUIDs.add(taskIdStr.toLowerCase());
              taskIdToTaskName[taskIdStr] = taskName;
              taskIdToPhaseName[taskIdStr] = phaseName;
            }
            final uuidList = [
              task['C_ProjectTask_UU'],
              task['Record_UU'],
              task['UUID'],
              task['uuid'],
              task['uid'],
            ];
            for (var uu in uuidList) {
              if (uu != null && uu.toString().trim().isNotEmpty) {
                final uStr = uu.toString().toLowerCase();
                taskUUIDs.add(uStr);
                uuidToTaskName[uStr] = taskName;
                uuidToPhaseName[uStr] = phaseName;
              }
            }
          }
        }

        // 1.2 Procesar tareas directas del proyecto
        for (var task in directTasks) {
          final taskName = task['Name'] ?? 'Tarea';
          final taskIdStr = task['id']?.toString();
          if (taskIdStr != null) {
            taskUUIDs.add(taskIdStr.toLowerCase());
            taskIdToTaskName[taskIdStr] = taskName;
            taskIdToPhaseName[taskIdStr] = 'General / Proyecto';
          }
          final uuidList = [
            task['C_ProjectTask_UU'],
            task['Record_UU'],
            task['UUID'],
            task['uuid'],
            task['uid'],
          ];
          for (var uu in uuidList) {
            if (uu != null && uu.toString().trim().isNotEmpty) {
              final uStr = uu.toString().toLowerCase();
              taskUUIDs.add(uStr);
              uuidToTaskName[uStr] = taskName;
              uuidToPhaseName[uStr] = 'General / Proyecto';
            }
          }
        }
      }
    }

    // 2. Carga Mixta: Cache + Fondo
    if (widget.projectId != null) {
      final projectId = widget.projectId!;
      final cached = GlobalCache.projectRequestsCache[projectId];
      
      if (cached != null && cached.isNotEmpty) {
        _processRawRequests(cached, uuidToTaskName, uuidToPhaseName, taskIdToTaskName, taskIdToPhaseName, idToPhaseName, resetPage: resetPage);
        
        // Refrescar en fondo igual por si hay cambios o faltan años
        GlobalCache.loadProjectRequestsInBackground(
          projectId,
          taskUUIDs: taskUUIDs,
          onUpdate: (newList) {
            if (mounted) _processRawRequests(newList, uuidToTaskName, uuidToPhaseName, taskIdToTaskName, taskIdToPhaseName, idToPhaseName, resetPage: false);
          }
        );
      } else {
        
        // Lanzar carga gradual en fondo inmediatamente
        GlobalCache.loadProjectRequestsInBackground(
          projectId,
          taskUUIDs: taskUUIDs,
          onUpdate: (newList) {
            if (mounted) {
              _processRawRequests(newList, uuidToTaskName, uuidToPhaseName, taskIdToTaskName, taskIdToPhaseName, idToPhaseName, resetPage: false);
            }
          }
        );

        // Opcional: Esperar un poco a la primera ráfaga para no quitar el skeleton demasiado rápido
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _allProjectRequests.isEmpty && !GlobalCache.projectLoadingStatus[projectId]!) {
            setState(() => _isLoading = false);
          }
        });
      }
    }
  }

  void _processRawRequests(
    List<Map<String, dynamic>> rawFound,
    Map<String, String> uuidToTaskName,
    Map<String, String> uuidToPhaseName,
    Map<String, String> taskIdToTaskName,
    Map<String, String> taskIdToPhaseName,
    Map<String, String> idToPhaseName, {
    bool resetPage = false,
  }) async {
    final processed = await processRequests(rawFound, _statusIdMap);
    List<Map<String, dynamic>> finalReqs = [];

    for (var req in (processed['requests'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final reqUU = req['recordUU']?.toString().toLowerCase();
      final rawReq = req['original'] ?? req;
      
      // Priorizar los campos de fase/tarea directos del registro si existen
      final rTaskId = (rawReq['C_ProjectTask_ID'] is Map ? rawReq['C_ProjectTask_ID']['id'] : rawReq['C_ProjectTask_ID'])?.toString();
      final rPhaseId = (rawReq['C_ProjectPhase_ID'] is Map ? rawReq['C_ProjectPhase_ID']['id'] : rawReq['C_ProjectPhase_ID'])?.toString();
      final rProjectId = (rawReq['C_Project_ID'] is Map ? rawReq['C_Project_ID']['id'] : rawReq['C_Project_ID'])?.toString();

      // FILTRO ESTRICTO: Solo mostrar si pertenece a este proyecto o a una de sus tareas/UUIDs
      bool belongsToProject = rProjectId == widget.projectId.toString() || 
                             (reqUU != null && uuidToTaskName.containsKey(reqUU)) ||
                             (rTaskId != null && taskIdToTaskName.containsKey(rTaskId));
                             
      if (!belongsToProject) continue;

      String taskName = 'General / Proyecto';
      String phaseName = '-';

      // 1. Intentar por UUID (Lógica heredada para casos específicos)
      if (reqUU != null && uuidToTaskName.containsKey(reqUU)) {
        taskName = uuidToTaskName[reqUU]!;
        phaseName = uuidToPhaseName[reqUU] ?? '-';
      } 
      // 2. Intentar por ID de Tarea mapeado
      else if (rTaskId != null && taskIdToTaskName.containsKey(rTaskId)) {
        taskName = taskIdToTaskName[rTaskId]!;
        phaseName = taskIdToPhaseName[rTaskId] ?? '-';
      } 
      // 3. Fallback a los datos expandidos del registro
      else {
        if (rPhaseId != null && idToPhaseName.containsKey(rPhaseId)) {
          phaseName = idToPhaseName[rPhaseId]!;
        } else if (rawReq['C_ProjectPhase_ID'] is Map) {
          phaseName = rawReq['C_ProjectPhase_ID']['identifier'] ?? rawReq['C_ProjectPhase_ID']['Name'] ?? '-';
        }
        
        if (rawReq['C_ProjectTask_ID'] is Map) {
          taskName = rawReq['C_ProjectTask_ID']['identifier'] ?? rawReq['C_ProjectTask_ID']['Name'] ?? 'General / Proyecto';
        }
      }

      req['taskName'] = taskName;
      req['phaseName'] = phaseName;
      finalReqs.add(req);
    }

    if (mounted) {
      setState(() {
        _allProjectRequests = finalReqs;
        if (resetPage) _currentSkip = 0;
        _applyFilters();
        _isLoading = false;
      });
    }
  }

  void _applyFilters({bool resetPage = false}) {
    if (resetPage) _currentSkip = 0;
    
    final filtered = _allProjectRequests.where((req) {
      bool match = true;

      if (_filters.types.isNotEmpty) {
        bool m = _filters.types.contains(req['type']);
        if (!m) match = false;
      }
      if (match && _filters.statuses.isNotEmpty) {
        bool m = _filters.statuses.contains(req['status']);
        if (!m) match = false;
      }
      if (match && _filters.levels.isNotEmpty) {
        String val = (req['level']?.toString().trim() ?? 'N/A').toLowerCase();
        bool m = _filters.levels.any((f) => f.toLowerCase().trim() == val);
        if (!m) match = false;
      }
      if (match && _filters.phases.isNotEmpty) {
        String val = (req['phaseName']?.toString().trim() ?? '-').toLowerCase();
        bool m = _filters.phases.any((f) => f.toLowerCase().trim() == val);
        if (!m) match = false;
      }
      if (match && _filters.tasks.isNotEmpty) {
        String val = (req['taskName']?.toString().trim() ?? '').toLowerCase();
        bool m = _filters.tasks.any((f) => f.toLowerCase().trim() == val);
        if (!m) match = false;
      }
      if (match && _filters.categories.isNotEmpty) {
        String val = (req['category']?.toString().trim() ?? 'Sin categoría').toLowerCase();
        bool m = _filters.categories.any((f) => f.toLowerCase().trim() == val);
        if (!m) match = false;
      }
      if (match && _filters.salesRepIds.isNotEmpty) {
        bool m = _filters.salesRepIds.contains(req['salesRepId']);
        if (!m) match = false;
      }
      if (match && _filters.userIds.isNotEmpty) {
        bool m = _filters.userIds.contains(req['userId']);
        if (!m) match = false;
      }

      if (match && _searchController.text.isNotEmpty) {
        final search = _searchController.text.toLowerCase();
        bool m = req['id'].toString().toLowerCase().contains(search) ||
            (req['descriptionClean'] ?? '').toString().toLowerCase().contains(search);
        if (!m) match = false;
      }

      return match;
    }).toList();

    _totalRecords = filtered.length;

    // Apply Local Pagination
    final endIndex = (_currentSkip + _currentPageSize < _totalRecords) 
        ? _currentSkip + _currentPageSize 
        : _totalRecords;
        
    final paginated = filtered.sublist(_currentSkip, endIndex);

    setState(() {
      _requests = paginated;
    });
  }

  Widget _buildPaginationControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Filas:'),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _currentPageSize,
                underline: const SizedBox(),
                items: [10, 25, 50, 100].map((size) {
                  return DropdownMenuItem<int>(
                    value: size,
                    child: Text(size.toString()),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _currentPageSize = val;
                      _currentSkip = 0;
                      _applyFilters();
                    });
                  }
                },
              ),
            ],
          ),
          Text(
            '${_totalRecords == 0 ? 0 : _currentSkip + 1} - ${(_currentSkip + _currentPageSize < _totalRecords) ? _currentSkip + _currentPageSize : _totalRecords} de $_totalRecords',
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentSkip == 0
                    ? null
                    : () {
                        setState(() {
                          _currentSkip -= _currentPageSize;
                          if (_currentSkip < 0) _currentSkip = 0;
                          _applyFilters();
                        });
                      },
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: (_currentSkip + _currentPageSize >= _totalRecords)
                    ? null
                    : () {
                        setState(() {
                          _currentSkip += _currentPageSize;
                          _applyFilters();
                        });
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _projectName.isNotEmpty
              ? '${AppLocale.projectRequestsLabel.getString(context)}$_projectName'
              : 'Solicitudes de Proyecto',
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () {
            setState(() => _isLoading = true);
            GlobalCache.forceFullSyncWithProgress(context, onSyncAction: _initData);
          }),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchAndFilters(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _isLoading
                    ? const SkeletonTable()
                    : _requests.isEmpty
                        ? Center(
                            child: Text(AppLocale.noLinkedRequestsFound.getString(context)),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: RequestsDataTableCore(
                              requests: _requests,
                              statusIdMap: _statusIdMap,
                              priorityMap: priorityMap,
                              onEdit: (req) => _editRequest(req),
                              onRefresh: () => _initData(showLoading: false),
                              showProjectContext: true,
                              serverSidePagination: true,
                              paginationControls: _buildPaginationControls(),
                              useSimpleStatus: true,
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _activeFilterCount => _filters.activeFilterCount;

  Future<void> _showFilterModal() async {
    final phases = _allProjectRequests
        .map((e) => e['phaseName']?.toString().trim() ?? '-')
        .where((e) => e != '-' && e != 'null' && e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Obtener el Tercero del proyecto para filtrar usuarios
    final project = GlobalCache.projects.firstWhere(
      (p) => p['id']?.toString() == widget.projectId?.toString(),
      orElse: () => <String, dynamic>{},
    );
    
    final int? projectBpId = project['C_BPartner_ID'] is Map 
        ? (project['C_BPartner_ID']['id'] as num?)?.toInt()
        : (project['C_BPartner_ID'] is num ? (project['C_BPartner_ID'] as num).toInt() : null);

    final filteredUsers = projectBpId != null 
        ? _users.where((u) {
            final userBpData = u['C_BPartner_ID'];
            final userBpId = (userBpData is Map)
                ? (userBpData['id'] as num?)?.toInt()
                : (userBpData is num ? userBpData.toInt() : null);
            return userBpId == projectBpId;
          }).toList()
        : _users;

    final result = await showDialog<ProjectRequestFilterModel>(
      context: context,
      builder: (context) {
        return ProjectRequestFilterModal(
          initialFilter: _filters,
          availablePhases: phases,
          allProjectRequests: _allProjectRequests,
          users: filteredUsers,
          statusIdMap: _statusIdMap,
        );
      },
    );

    if (result != null) {
      setState(() {
        _filters = result;
      });
      _applyFilters(resetPage: true);
    }
  }

  Widget _buildSearchAndFilters() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: SizedBox(
              width: double.infinity,
              child: CustomTextField(
                controller: _searchController,
                hintText: AppLocale.searchByIdOrSummary.getString(context),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          Wrap(
            spacing: 16.0,
            runSpacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CustomButton(
                text: AppLocale.filters.getString(context),
                onPressed: _showFilterModal,
                icon: Icons.filter_list,
                backgroundColor: _activeFilterCount > 0
                    ? theme.colorScheme.primaryContainer
                    : null,
                textColor: _activeFilterCount > 0
                    ? theme.colorScheme.onPrimaryContainer
                    : null,
              ),
              if (_activeFilterCount > 0)
                Chip(
                  label: Text('$_activeFilterCount'),
                  backgroundColor: theme.colorScheme.primary,
                  labelStyle: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  padding: const EdgeInsets.all(4),
                  visualDensity: VisualDensity.compact,
                ),
              IconButton(
                icon: const Icon(Icons.filter_alt_off),
                tooltip: AppLocale.clearFilters.getString(context),
                onPressed: () {
                  setState(() {
                    _filters = const ProjectRequestFilterModel();
                  });
                  _searchController.clear();
                  _applyFilters(resetPage: true);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRequest(dynamic id) async {
    if (!AccessControl.canManageRequests) {
      ToastMessage.show(
        context: context,
        message: AppLocale.noPermissionsToDelete.getString(context),
        type: ToastType.failure,
      );
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => CustomModal(
        title: AppLocale.confirmDeletion.getString(context),
        content: Text(
          AppLocale.confirmDeleteRequest.getString(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocale.cancel.getString(context)),
          ),
          CustomButton(
            text: AppLocale.delete.getString(context),
            backgroundColor: Colors.red,
            onPressed: () => Navigator.pop(context, true),
          ),
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
          ToastMessage.show(context: context, message: AppLocale.errorDeletingRequest.getString(context), type: ToastType.failure);
        }
      }
    }
  }

  void _editRequest(Map<String, dynamic> req) {
    // Use _allProjectRequests instead of _rawRequests
    final processedReq = _allProjectRequests.firstWhere(
      (p) => p['realId'] == req['realId'],
      orElse: () => req,
    );

    showDialog(
      context: context,
      builder: (context) => EditRequestDialog(
        request: processedReq,
        statusIdMap: _statusIdMap,
        priorityMap: priorityMap,
        onSave: () => _initData(showLoading: false),
        onDelete: () =>
            _deleteRequest(processedReq['realId'] ?? processedReq['id']),
      ),
    );
  }
}

