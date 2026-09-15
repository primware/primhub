import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter/rendering.dart';



import 'package:primhub/ui/Shared_Custom/admin_mode_views.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/Shared_Custom/help_icon.dart';

import 'package:primhub/api/admin_view_mode.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/api/validation_manager.dart';

import 'package:primhub/ui/pages/Support/calendar_gantt_wrapper.dart';
import 'package:primhub/ui/pages/Support/Request_Widgets/request_filter_modal.dart';
import 'package:primhub/ui/pages/Support/Requests/create_request_dialog.dart';
import 'package:primhub/ui/pages/Support/Requests/edit_request_dialog.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart';
import 'package:primhub/ui/pages/Support/Requests/export_functions.dart';
import 'package:primhub/ui/pages/Support/Request_Widgets/request_stats_card.dart';
import 'package:primhub/ui/pages/Support/Request_Widgets/request_filter_bar.dart';
import 'package:primhub/ui/Shared_Custom/requests_data_table_core.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';

import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/widgets/project_sidebar.dart';
import '../../../widgets/custom_drawer.dart';


import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/widgets/project_bottom_nav.dart';
import 'package:primhub/api/api_utils.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:primhub/ui/Shared_Custom/custom_skeleton.dart';

import 'package:primhub/ui/Shared_Custom/user_info_leading.dart';
import 'package:flutter_localization/flutter_localization.dart';

class MyRequestsPage extends StatefulWidget {
  const MyRequestsPage({super.key});

  @override
  State<MyRequestsPage> createState() => _MyRequestsPageState();
}

class _MyRequestsPageState extends State<MyRequestsPage> {
  List<Map<String, dynamic>> _requests = [];
  List<dynamic> _rawRequests = [];
  bool _isLoading = true;
  bool _isAscending = false;
  bool _showHistory = false;
  ChipFilterMode _chipFilterMode = ChipFilterMode.mixed;
  bool _isInit = true;
  double? _contractedHours;
  double _consumedHours = 0.0;
  double _estimatedHours = 0.0;
  Map<String, int> _statusIdMap = {};
  String? _metricsSource;
  int _currentPage = 0;
  int _rowsPerPage = 25;
  int _totalRecords = 0;
  final TextEditingController _searchController = TextEditingController();
  List<int> _selectedYears = [DateTime.now().year];
  RequestFilterModel _filters = const RequestFilterModel();
  final Map<int, String> _bpNameCache = {};
  List<Map<String, dynamic>> _sortedRequests = [];

  int? _bpId;
  List<Map<String, dynamic>> _bPartners = [];
  List<dynamic> _users = [];


  final _adminViewModeManager = AdminViewModeManager();
  Timer? _skeletonTimer;
  bool _isHistorySkeletonActive = false;

  bool _showCalendar =
      false; // Nuevo estado para controlar la vista del calendario
  Timer? _historySkeletonTimer;

  // Optimización de rendimiento para evitar reconstruir la tabla en cada scroll de la página.
  Widget? _cachedTable;
  List<Map<String, dynamic>>? _lastSortedRequests;
  bool? _lastIsLoading;
  bool? _lastIsHistorySkeletonActive;
  int? _lastRowsPerPage;
  int? _lastCurrentPage;
  bool? _lastShowHistory;

  final ScrollController _outerScrollController = ScrollController();

  Widget _buildTableWidget() {
    final bool currentSkeleton = (_showHistory && _isHistorySkeletonActive);
    if (_cachedTable != null &&
        _lastSortedRequests == _sortedRequests &&
        _lastIsLoading == _isLoading &&
        _lastIsHistorySkeletonActive == currentSkeleton &&
        _lastRowsPerPage == _rowsPerPage &&
        _lastCurrentPage == _currentPage &&
        _lastShowHistory == _showHistory) {
      return _cachedTable!;
    }

    _lastSortedRequests = _sortedRequests;
    _lastIsLoading = _isLoading;
    _lastIsHistorySkeletonActive = currentSkeleton;
    _lastRowsPerPage = _rowsPerPage;
    _lastCurrentPage = _currentPage;
    _lastShowHistory = _showHistory;

    if (_isLoading || currentSkeleton) {
      _cachedTable = const SkeletonTable();
    } else {
      _cachedTable = RequestsDataTableCore(
        key: ValueKey(
          'requests_table_${_currentPage}_${_rowsPerPage}_${_sortedRequests.length}',
        ),
        requests: _sortedRequests,
        onEdit: _editRequest,
        onRefresh: () => _refreshRequest(fetchNetwork: true),
        statusIdMap: _statusIdMap,
        priorityMap: priorityMap,
        serverSidePagination: true,
        paginationControls: _buildPaginationControls(),
        useSimpleStatus: false,
      );
    }
    return _cachedTable!;
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        setState(() => _currentPage = 0);
        _refreshRequest(fetchNetwork: false);
      }
    });
    _adminViewModeManager.addListener(_onViewModeChanged);
    GlobalCache.backgroundSyncNotifier.addListener(_onBackgroundSyncChanged);
  }

  void _onBackgroundSyncChanged() {
    if (mounted) {
      _refreshRequest(fetchNetwork: false);
    }
  }

  void _onViewModeChanged() {
    _initData();
  }

  void _startHistorySkeleton() {
    // Ya no usamos un temporizador fijo de 8 segundos.
    // El skeleton se controla ahora por el estado real de carga (_isLoading).
    _isHistorySkeletonActive = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      Object? extra;
      try {
        extra = GoRouterState.of(context).extra;
      } catch (_) {
      // Ignored: Fail silently
    }

      final args = extra ?? ModalRoute.of(context)?.settings.arguments;

      if (args is Map) {
        if (args['showHistory'] == true) _showHistory = true;
        if (args['bpId'] != null) _bpId = args['bpId'];
        if (args['metrics_source'] != null) _metricsSource = args['metrics_source'];

        List<String> initialStatuses = [];
        if (args['selectedStatus'] != null &&
            args['selectedStatus'] is String) {
          initialStatuses.add(args['selectedStatus']);
        } else if (args['selectedStatuses'] != null &&
            args['selectedStatuses'] is List) {
          initialStatuses.addAll(List<String>.from(args['selectedStatuses']));
        }

        _filters = RequestFilterModel(
          statuses: initialStatuses,
          levels: args['selectedLevel'] != null ? [args['selectedLevel']] : [],
          productChipIds: args['chipId'] != null ? [args['chipId']] : [],
          bpIds: args['bpIds'] != null ? List<int>.from(args['bpIds']) : (args['bpId'] != null ? [args['bpId']] : []),
          salesRepIds: args['salesRepId'] != null ? [args['salesRepId']] : [],
        );

        if (args['search'] != null) {
          _searchController.text = args['search'];
          
          // Inteligencia para detectar si la solicitud buscada está en el histórico
          try {
            final searchQuery = args['search'].toString();
            final req = GlobalCache.requests.firstWhere(
              (r) => r['id'].toString() == searchQuery || r['DocumentNo'].toString() == searchQuery,
              orElse: () => <String, dynamic>{},
            );
            
            if (req.isNotEmpty) {
              final statusData = req['R_Status_ID'];
              bool isArchived = false;

              int? statusIdFromReq;
              if (statusData is Map) {
                statusIdFromReq = (statusData['id'] as num?)?.toInt();
              } else if (statusData != null) {
                statusIdFromReq = int.tryParse(statusData.toString());
              }

              if (statusIdFromReq != null &&
                  GlobalCache.statusIsFinalCloseMap.containsKey(statusIdFromReq)) {
                isArchived = GlobalCache.statusIsFinalCloseMap[statusIdFromReq]!;
              } else {
                final statusName = statusData is Map
                    ? (statusData['Name'] ?? '').toString()
                    : '';
                isArchived = statusName.toLowerCase().contains('archivada') ||
                    statusName.toLowerCase().contains('anulada') ||
                    statusName.toLowerCase().contains('final close') ||
                    statusName.toLowerCase().contains('cerrada');
              }
              
              if (isArchived) {
                 _showHistory = true;
              }
            }
          } catch (e) {
            // Ignorar errores
          }
        }

        // Si se filtra por un estado cerrado, forzar la vista de bitácora
        if (_filters.statuses.isNotEmpty || _filters.statusIds.isNotEmpty) {
          final lowerStatuses = _filters.statuses
              .map((s) => s.toLowerCase())
              .toList();

          bool hasArchivedStatus = lowerStatuses.any(
            (s) =>
                s.contains('close') ||
                s.contains('cerrad') ||
                s.contains('archivada'),
          );

          if (!hasArchivedStatus && _filters.statusIds.isNotEmpty) {
            hasArchivedStatus = _filters.statusIds.any(
              (id) => [1000019, 1000015, 1000018, 103].contains(id),
            );
          }

          if (hasArchivedStatus) _showHistory = true;
        }
      }

      if (_showHistory) _startHistorySkeleton();

      _isInit = false;
      _initData();
    }
  }

  @override
  void dispose() {
    _outerScrollController.dispose();
    _historySkeletonTimer?.cancel();
    _skeletonTimer?.cancel();
    _searchController.dispose();
    _adminViewModeManager.removeListener(_onViewModeChanged);
    GlobalCache.backgroundSyncNotifier.removeListener(_onBackgroundSyncChanged);
    super.dispose();
  }

  Future<void> _initData() async {
    if (_isInit) {
      setState(() {
        _isLoading = true;
      });
    }

    await GlobalCache.syncData();

    // Esperar a que la Fase 2 (carga del año actual) termine antes de continuar.
    // Esto asegura que el skeleton se muestre hasta que los datos estén listos.
    try {
      if (GlobalCache.phase2SyncFuture != null) {
        await GlobalCache.phase2SyncFuture;
      }
    } catch (_) {
      // Ignored: Fail silently
    }

    if (mounted) {
      setState(() {
        _bPartners = GlobalCache.bPartners;
        _users = GlobalCache.users;
        _isLoading = false;
        _isInit = false;
      });
    }

    _statusIdMap = GlobalCache.statuses;

    // 3. Procesar la data (con consulta a la red para asegurar datos frescos al inicio)
    await _refreshRequest(fetchNetwork: true);
  }

  int get _activeFilterCount => _filters.activeFilterCount;

  Widget _buildActiveFilterChips() {
    final List<Widget> chips = [];
    final theme = Theme.of(context);

    void addChip(String label, ActiveFilterType type) {
      final isCurrentYearChip = type == ActiveFilterType.year && label == 'Año: Año Actual';
      if (isCurrentYearChip) return; // Se renderiza en RequestFilterBar
      
      Widget chipWidget = InputChip(
        label: Text(label),
        onDeleted: () => _removeFilter(type),
        deleteButtonTooltipMessage: 'Quitar',
        deleteIcon: const Icon(Icons.close, size: 18),
        labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
      );
      chips.add(chipWidget);
    }

    if (_selectedYears.isNotEmpty) {
      String yearLabel = _selectedYears.length == 1
          ? _selectedYears.first.toString()
          : '${_selectedYears.length} años';
      if (_selectedYears.length == 1 &&
          _selectedYears.first == DateTime.now().year) {
        yearLabel = 'Año Actual';
      }
      addChip('Año: $yearLabel', ActiveFilterType.year);
    }
    for (final bpId in _filters.bpIds) {
      String? bpName = _bpNameCache[bpId];
      if (bpName == null) {
        var found = _bPartners.firstWhere(
          (bp) => (bp['id'] as num?)?.toInt() == bpId,
          orElse: () => <String, dynamic>{},
        );
        if (found.isEmpty) {
          found = GlobalCache.allBPartners.firstWhere(
            (bp) => (bp['id'] as num?)?.toInt() == bpId,
            orElse: () => <String, dynamic>{},
          );
        }
        if (found.isNotEmpty) {
          bpName = found['Name'] ?? 'ID: $bpId';
          _bpNameCache[bpId] = bpName!;
        } else {
          bpName = _isLoading ? 'Cargando...' : 'ID: $bpId';
        }
      }
      addChip('Tercero: $bpName', ActiveFilterType.bp);
    }

    if (_filters.levels.isNotEmpty) {
      addChip(
        'Nivel: ${_filters.levels.length == 1 ? _filters.levels.first : "${_filters.levels.length} seleccionados"}',
        ActiveFilterType.level,
      );
    }
    if (_filters.statusIds.isNotEmpty || _filters.statuses.isNotEmpty) {
      final total = _filters.statusIds.length + _filters.statuses.length;
      String label = '';
      if (total == 1) {
        if (_filters.statusIds.isNotEmpty) {
          final id = _filters.statusIds.first;
          label =
              SUPPORT_STATUS_MAPPING[id] ??
              _statusIdMap.entries
                  .firstWhere(
                    (e) => e.value == id,
                    orElse: () => const MapEntry('ID: 0', 0),
                  )
                  .key;
          if (label == 'ID: 0') label = 'ID: $id';
        } else {
          label = _filters.statuses.first;
        }
      } else {
        label = "$total seleccionados";
      }
      addChip('Estado: $label', ActiveFilterType.status);
    }
    if (_filters.requestTypeIds.isNotEmpty) {
      String label = '';
      if (_filters.requestTypeIds.length == 1) {
        final id = _filters.requestTypeIds.first;
        label = GlobalCache.requestTypes.entries
            .firstWhere(
              (e) => e.value == id,
              orElse: () => const MapEntry('Tipo Desconocido', 0),
            )
            .key;
      } else {
        label = "${_filters.requestTypeIds.length} seleccionados";
      }
      addChip('Tipo: $label', ActiveFilterType.situation);
    }
    if (_filters.productChipIds.isNotEmpty) {
      final chipId = _filters.productChipIds.first;
      final found = GlobalCache.productChips.firstWhere(
        (c) => (c['id'] as num?)?.toInt() == chipId,
        orElse: () => <String, dynamic>{},
      );
      final chipName = found.isNotEmpty
          ? (found['Description'] ?? 'Ficha $chipId')
          : 'Ficha $chipId';
      addChip(
        'Ficha: ${_filters.productChipIds.length == 1 ? chipName : "${_filters.productChipIds.length} seleccionadas"}',
        ActiveFilterType.productChip,
      );
    }
    if (_filters.categoryIds.isNotEmpty) {
      String label = '';
      if (_filters.categoryIds.length == 1) {
        final id = _filters.categoryIds.first;
        label = GlobalCache.categories.entries
            .firstWhere(
              (e) => e.value == id,
              orElse: () => const MapEntry('Categoría Desconocida', 0),
            )
            .key;
      } else {
        label = "${_filters.categoryIds.length} seleccionados";
      }
      addChip('Categoría: $label', ActiveFilterType.search);
    }
    for (final repId in _filters.salesRepIds) {
      final found = GlobalCache.salesReps.firstWhere(
        (rep) => ((rep['AD_User_ID'] ?? rep['id']) as num?)?.toInt() == repId,
        orElse: () => <String, dynamic>{},
      );
      final repName = found.isNotEmpty
          ? (found['Name'] ?? 'ID: $repId')
          : 'ID: $repId';
      addChip('Rep. Comercial: $repName', ActiveFilterType.salesRep);
    }
    for (final userId in _filters.userIds) {
      final found = _users.firstWhere(
        (u) => ((u['AD_User_ID'] ?? u['id']) as num?)?.toInt() == userId,
        orElse: () => <String, dynamic>{},
      );
      final uName = found.isNotEmpty
          ? (found['Name'] ?? 'ID: $userId')
          : 'ID: $userId';
      addChip('Usuario: $uName', ActiveFilterType.user);
    }
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Wrap(spacing: 8.0, runSpacing: 8.0, children: chips),
    );
  }

  /// Elimina un filtro específico y actualiza la UI.
  void _removeFilter(ActiveFilterType type) {
    setState(() {
      switch (type) {
        case ActiveFilterType.bp:
          _filters = _filters.copyWith(bpIds: []);
          _bpId = null; // También limpia el ID del tercero
          break;
        case ActiveFilterType.level:
          _filters = _filters.copyWith(levels: []);
          break;
        case ActiveFilterType.status:
          _filters = _filters.copyWith(statuses: [], statusIds: []);
          break;
        case ActiveFilterType.situation:
          _filters = _filters.copyWith(situations: [], requestTypeIds: []);
          break;
        case ActiveFilterType.salesRep:
          _filters = _filters.copyWith(salesRepIds: []);
          break;
        case ActiveFilterType.user:
          _filters = _filters.copyWith(userIds: []);
          break;
        case ActiveFilterType.search:
          _filters = _filters.copyWith(categoryIds: []);
          _searchController.clear();
          break;
        case ActiveFilterType.year:
          _selectedYears = [];
          break;
        case ActiveFilterType.productChip:
          _filters = _filters.copyWith(productChipIds: []);
          break;
      }
      _currentPage = 0; // Reinicia la paginación
    });
    // Si se cambió el tercero, necesitamos reinicializar los datos para obtener los contratos correctos.
    // De lo contrario, solo actualizamos las estadísticas localmente.
    if (type == ActiveFilterType.bp) {
      _initData();
    } else {
      _refreshRequest(fetchNetwork: false);
    }
  }

  Future<void> _showYearFilterModal() async {
    final List<int> availableYears = List.generate(
      10,
      (i) => DateTime.now().year - i,
    );
    final List<int>? result = await showDialog<List<int>>(
      context: context,
      builder: (context) {
        List<int> tempSelection = List.from(_selectedYears);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return CustomModal(
              title: 'Seleccionar Años',
              content: SizedBox(
                height: 300,
                child: ListView(
                  children: availableYears.map((year) {
                    return CheckboxListTile(
                      title: Text(year.toString()),
                      value: tempSelection.contains(year),
                      onChanged: (bool? selected) {
                        setDialogState(() {
                          if (selected == true) {
                            tempSelection.add(year);
                          } else {
                            tempSelection.remove(year);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancelar'),
                ),
                CustomButton(
                  text: 'Aplicar',
                  onPressed: () => Navigator.pop(context, tempSelection),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    setState(() {
      _selectedYears = result..sort((a, b) => b.compareTo(a));
      _currentPage = 0;
    });
    _refreshRequest(fetchNetwork: true);
  }

  Future<void> _showFilterModal() async {
    final originalBPs = Set.from(_filters.bpIds);

    final appliedFilters = await showDialog<RequestFilterModel>(
      context: context,
      builder: (context) {
        return RequestFilterModal(
          initialFilter: _filters,
          bPartners: _bPartners, // Lista de clientes para el filtro "Tercero"
          allBPartners: GlobalCache
              .allBPartners, // Lista completa para el filtro "Rep. Comercial"
          users: _users,
          requests: _requests,
          statusIdMap: _statusIdMap,
        );
      },
    );

    if (appliedFilters != null) {
      setState(() {
        _filters = appliedFilters;
        _currentPage = 0;
      });

      final currentBPs = Set.from(_filters.bpIds);
      if (!setEquals(originalBPs, currentBPs)) {
        _bpNameCache.clear();
        setState(() => _isLoading = true);
        if (_filters.bpIds.isNotEmpty) {
          _bpId = _filters.bpIds.first;
        } else {
          _bpId = null;
        }
        _initData();
      } else {
        _refreshRequest(
          fetchNetwork: false,
        ); // Solo refresco local ya que los datos base (GlobalCache) son los mismos
      }
    }
  }

  /// Muestra un diálogo para seleccionar el modo de vista del administrador.
  void _showAdminModeSelectionDialog(BuildContext context) {
    final current = _adminViewModeManager.currentMode;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return CustomModal(
          title: 'Seleccionar Modo de Vista',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Modo Mixto'),
                trailing: current == AdminViewMode.mixed
                    ? Icon(Icons.check, color: colorScheme.primary)
                    : null,
                onTap: () {
                  _adminViewModeManager.saveMode(AdminViewMode.mixed);
                  Navigator.pop(dialogContext);
                },
              ),
              ListTile(
                title: const Text('Modo Soporte'),
                trailing: current == AdminViewMode.support
                    ? Icon(Icons.check, color: colorScheme.primary)
                    : null,
                onTap: () {
                  _adminViewModeManager.saveMode(AdminViewMode.support);
                  Navigator.pop(dialogContext);
                },
              ),
              ListTile(
                title: const Text('Modo Proyecto'),
                trailing: current == AdminViewMode.project
                    ? Icon(Icons.check, color: colorScheme.primary)
                    : null,
                onTap: () {
                  _adminViewModeManager.saveMode(AdminViewMode.project);
                  Navigator.pop(dialogContext);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  /// Construye las acciones específicas de la AppBar para el administrador, adaptándose a móvil.
  List<Widget> _buildAdminAppBarActions(BuildContext context) {
    final List<Widget> actions = [];
    final bool isMobile = MediaQuery.of(context).size.width < 600;


    if (isMobile) {
      actions.add(
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'Opciones de Administrador',
          onSelected: (value) {
            if (value == 'admin_mode') {
              _showAdminModeSelectionDialog(context);
            } else if (value == 'exception_dialog') {
              _showExceptionDialog();
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'admin_mode',
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: Text(
                  'Modo de Vista (${_adminViewModeManager.currentMode == AdminViewMode.support ? 'Soporte' : (_adminViewModeManager.currentMode == AdminViewMode.project ? 'Proyecto' : 'Mixto')})',
                ),
              ),
            ),
            PopupMenuItem<String>(
              value: 'exception_dialog',
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(AppLocale.hoursException.getString(context)),
              ),
            ),
          ],
        ),
      );
    } else {
      // Desktop view: existing buttons
      actions.add(const AdminModeViews());
      actions.add(_buildExceptionHoursInkWell());
    }
    return actions;
  }



  Future<void> _refreshRequest({bool fetchNetwork = true}) async {
    try {
      if (mounted) setState(() => _isLoading = true);

      // 1. Sincronizar solo si es necesario (sin forzar borrado total)
      if (fetchNetwork) {
        await GlobalCache.syncData();
      }

      _statusIdMap = GlobalCache.statuses;

      // 2. Usar los datos centralizados de la caché (Ya cargados por Fase 1 y 2)
      final List<Map<String, dynamic>> rawAll = List.from(GlobalCache.requests);

      if (rawAll.isEmpty && fetchNetwork) {
        // Fallback si por alguna razón la caché está vacía pero queremos red
        // (Aunque GlobalCache.syncData ya debería haber llenado algo)
      }

      // 3. Filtrado Local sobre datos RAW (Súper rápido)
      final List<String> selectedChipNames = _filters.productChipIds
          .map((id) {
            final found = GlobalCache.productChips.firstWhere(
              (c) => (c['id'] as num?)?.toInt() == id,
              orElse: () => <String, dynamic>{},
            );
            return (found['Description'] ?? found['Name'] ?? '')
                .toString()
                .toLowerCase()
                .trim();
          })
          .where((name) => name.isNotEmpty)
          .toList();

      final filteredRaw = rawAll.where((req) {
        // A. Filtrado por Año (si aplica)
        if (_selectedYears.isNotEmpty) {
          final createdStr = req['Created']?.toString() ?? '';
          if (createdStr.isNotEmpty) {
            final year = DateTime.tryParse(createdStr)?.year;
            if (year != null && !_selectedYears.contains(year)) return false;
          }
        }

        // B. Filtrado de Soporte vs Proyecto
        final recordUU = req['Record_UU'];
        bool isSupport = recordUU == null || recordUU.toString().trim().isEmpty;

        if (AccessControl.isSupport && !AccessControl.isProject) {
          // Modo soporte o usuario soporte real
          if (!isSupport) return false;
        } else if (!AccessControl.isSupport && AccessControl.isProject) {
          // Modo proyecto o usuario proyecto real
          if (isSupport) return false;
        }

        final statusData = req['R_Status_ID'];
        bool isArchived = false;

        int? statusIdFromReq;
        if (statusData is Map) {
          statusIdFromReq = (statusData['id'] as num?)?.toInt();
        } else if (statusData != null) {
          statusIdFromReq = int.tryParse(statusData.toString());
        }

        if (statusIdFromReq != null &&
            GlobalCache.statusIsFinalCloseMap.containsKey(statusIdFromReq)) {
          isArchived = GlobalCache.statusIsFinalCloseMap[statusIdFromReq]!;
        } else {
          // Fallback robusto en caso de que falle la caché
          final statusName = statusData is Map
              ? (statusData['Name'] ?? '').toString()
              : '';
          isArchived =
              statusName.toLowerCase().contains('archivada') ||
              statusName.toLowerCase().contains('anulada') ||
              statusName.toLowerCase().contains('final close') ||
              statusName.toLowerCase().contains('cerrada');
        }

        if (_showHistory != isArchived) return false;

        // D. Filtros de la UI (Búsqueda, BP, Usuario, etc.) sobre RAW
        if (_filters.bpIds.isNotEmpty) {
          final bpData = req['C_BPartner_ID'];
          final bpId = bpData is Map ? bpData['id'] : bpData;
          if (!_filters.bpIds.contains(bpId)) return false;
        }
        if (_filters.userIds.isNotEmpty) {
          final userData = req['AD_User_ID'];
          final userId = userData is Map ? userData['id'] : userData;
          if (!_filters.userIds.contains(userId)) return false;
        }
        if (_filters.salesRepIds.isNotEmpty) {
          final repData = req['SalesRep_ID'];
          final repId = repData is Map
              ? (repData['id'] as num?)?.toInt()
              : (repData as num?)?.toInt();

          if (rawAll.indexOf(req) < 10) {
          }

          if (repId == null || !_filters.salesRepIds.contains(repId)) {
            return false;
          }
        }
        if (_filters.statusIds.isNotEmpty) {
          final sData = req['R_Status_ID'];
          final sId = sData is Map
              ? (sData['id'] as num?)?.toInt()
              : (sData as num?)?.toInt();
          if (sId == null || !_filters.statusIds.contains(sId)) return false;
        } else if (_filters.statuses.isNotEmpty) {
          final sData = req['R_Status_ID'];
          final sName = sData is Map
              ? (sData['Name'] ?? sData['identifier'] ?? '').toString()
              : sData.toString();
          if (!_filters.statuses.contains(sName)) return false;
        }

        if (_filters.levels.isNotEmpty) {
          final priority = req['Priority'] is Map
              ? (req['Priority']['identifier'] ?? req['Priority']['Name'] ?? '')
                    .toString()
              : req['Priority']?.toString() ?? '';
          String priorityName = priority;
          if (priority == '1') {
            priorityName = 'Urgente';
          } else if (priority == '3') {
            priorityName = 'Alta';
          } else if (priority == '5') {
            priorityName = 'Media';
          } else if (priority == '7') {
            priorityName = 'Baja';
          } else if (priority == '9') {
            priorityName = 'Muy baja';
          }

          if (!_filters.levels.any(
            (l) => l.toLowerCase() == priorityName.toLowerCase(),
          )) {
            return false;
          }
        }

        if (_filters.requestTypeIds.isNotEmpty) {
          final rtData = req['R_RequestType_ID'];
          final rtId = rtData is Map
              ? (rtData['id'] as num?)?.toInt()
              : (rtData is num ? rtData.toInt() : null);
          if (rtId == null || !_filters.requestTypeIds.contains(rtId)) {
            return false;
          }
        }

        if (_filters.categoryIds.isNotEmpty) {
          final catData = req['R_Category_ID'];
          final catId = catData is Map
              ? (catData['id'] as num?)?.toInt()
              : (catData is num ? catData.toInt() : null);
          if (catId == null || !_filters.categoryIds.contains(catId)) {
            return false;
          }
        }

        // --- FILTRO DE FICHAS DE PRODUCTO ---
        if (AccessControl.isAdmin || AccessControl.isExtSupport) {
          final int? parsedChipId = extractProductChipId(req);
          if (_chipFilterMode == ChipFilterMode.onlyWithChip && parsedChipId == null) {
            return false;
          }
          if (_chipFilterMode == ChipFilterMode.onlyWithoutChip && parsedChipId != null) {
            return false;
          }
        }

        if (_filters.productChipIds.isNotEmpty) {
          final int? parsedChipId = extractProductChipId(req);
          final String? chipName = extractProductChipName(
            req,
          )?.toLowerCase().trim();

          bool matchById =
              parsedChipId != null &&
              _filters.productChipIds.contains(parsedChipId);
          bool matchByName =
              chipName != null && selectedChipNames.contains(chipName);

          // Log de diagnóstico para el primer registro
          if (rawAll.indexOf(req) == 0) {
          }

          if (!matchById && !matchByName) {
            return false;
          }
        }

        if (_searchController.text.trim().isNotEmpty) {
          final search = _searchController.text.trim().toLowerCase();
          final docNo = (req['DocumentNo'] ?? '').toString().toLowerCase();
          final summary = (req['Summary'] ?? '').toString().toLowerCase();
          final emailSubject = (req['CDS_EmailSubject'] ?? '').toString().toLowerCase();

          if (!docNo.contains(search) && !summary.contains(search) && !emailSubject.contains(search)) return false;
        }

        return true;
      }).toList();

      // Ordenar globalmente antes de paginar:
      filteredRaw.sort((a, b) {
        final hasChipA = (extractProductChipId(a) != null) ? 1 : 0;
        final hasChipB = (extractProductChipId(b) != null) ? 1 : 0;

        if (AccessControl.isAdmin || AccessControl.isExtSupport) {
          if (_chipFilterMode == ChipFilterMode.withChipFirst) {
            if (hasChipA != hasChipB) {
              return hasChipB.compareTo(hasChipA); // 1 (has chip) comes before 0
            }
          } else if (_chipFilterMode == ChipFilterMode.withoutChipFirst) {
            if (hasChipA != hasChipB) {
              return hasChipA.compareTo(hasChipB); // 0 (no chip) comes before 1
            }
          }
        }

        // Obtener fechas para el orden secundario (por defecto descendente)
        final dateA = (a['Created'] ?? a['Date'] ?? a['Updated'] ?? '')
            .toString();
        final dateB = (b['Created'] ?? b['Date'] ?? b['Updated'] ?? '')
            .toString();

        return _isAscending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
      });

      // 4. Actualizar contador total
      _totalRecords = filteredRaw.length;

      // 5. Paginación sobre la lista filtrada RAW
      int start = _currentPage * _rowsPerPage;
      if (start >= _totalRecords) {
        _currentPage = 0;
        start = 0;
      }
      int end = start + _rowsPerPage;
      if (end > _totalRecords) end = _totalRecords;

      final pageRawItems = filteredRaw.sublist(start, end);

      // 6. PROCESAR SOLO LA PÁGINA ACTUAL (25 items vs 5000+)
      // Esto es lo que devuelve el rendimiento instantáneo
      final processedData = await processRequests(pageRawItems, _statusIdMap);
      final List<Map<String, dynamic>> pageProcessed =
          List<Map<String, dynamic>>.from(processedData['requests']);

      if (mounted) {
        setState(() {
          _rawRequests = filteredRaw;
          _requests = pageProcessed;
          // Cacheamos el ordenamiento aquí para evitar hacerlo en el build
          _sortedRequests = _requests.toList()
            ..sort((a, b) {
              final hasChipA = (a['productChipId'] != null) ? 1 : 0;
              final hasChipB = (b['productChipId'] != null) ? 1 : 0;
              if (hasChipA != hasChipB) {
                return hasChipB.compareTo(hasChipA);
              }

              final timeA = a['time'] ?? '';
              final timeB = b['time'] ?? '';
              return _isAscending
                  ? timeA.compareTo(timeB)
                  : timeB.compareTo(timeA);
            });
          _isLoading = false;
        });
        _updateStatsLocally();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateStatsLocally() {
    double acquiredForStats = 0.0;
    double consumedForStats = 0.0;
    double inProgressForStats = 0.0;

    // 1. Obtener Terceros seleccionados
    final selectedBpIds = _filters.bpIds.toSet();
    if (selectedBpIds.isEmpty && !AccessControl.isAdmin) {
      if (User.cBPartnerID != null) selectedBpIds.add(User.cBPartnerID!);
    }

    // 2. Filtrar Fichas de Producto relevantes
    final relevantChips = GlobalCache.productChips.where((chip) {
      final rawBp = chip['C_BPartner_ID'];
      final chipBpId = rawBp is Map
          ? (rawBp['id'] as num?)?.toInt()
          : (rawBp as num?)?.toInt();
      final isActive = chip['IsActive'] == 'Y' || chip['IsActive'] == true;

      if (selectedBpIds.isNotEmpty && !selectedBpIds.contains(chipBpId)) {
        return false;
      }
      if (!isActive) return false;

      if (_filters.productChipIds.isNotEmpty) {
        if (!_filters.productChipIds.contains(chip['id'])) return false;
      }

      return true;
    }).toList();

    // Ordenar fichas por fecha de creación (FIFO)
    relevantChips.sort((a, b) {
      final dateA = DateTime.tryParse(a['Created'] ?? '') ?? DateTime(0);
      final dateB = DateTime.tryParse(b['Created'] ?? '') ?? DateTime(0);
      return dateA.compareTo(dateB);
    });

    acquiredForStats = relevantChips.fold(
      0.0,
      (sum, chip) => sum + ((chip['Qty'] as num?)?.toDouble() ?? 0.0),
    );

    // 3. Calcular Consumidas y En Progreso por ficha vinculada
    final Map<int, double> chipConsumedMap = {};
    final Map<int, double> chipEstimatedMap = {};

    for (var r in GlobalCache.requests) {
      final double qtySpent = (r['QtySpent'] as num?)?.toDouble() ?? 0.0;
      final statusData = r['R_Status_ID'];
      int? sId = statusData is Map ? statusData['id'] : statusData;
      final sName = statusData is Map
          ? (statusData['Name'] ?? statusData['identifier'] ?? '')
                .toString()
                .toLowerCase()
          : '';

      bool isClosed = false;
      if (sId != null && GlobalCache.statusIsFinalCloseMap.containsKey(sId)) {
        isClosed = GlobalCache.statusIsFinalCloseMap[sId]!;
      } else {
        isClosed =
            sName.contains('archivada') ||
            sName.contains('anulada') ||
            sName.contains('final close') ||
            sName.contains('cerrada') ||
            sName.contains('implementada en produccion') ||
            sName.contains('implementada en producción') ||
            sId == 1000019 ||
            sId == 1000015 ||
            sId == 1000018 ||
            sId == 103;
      }

      // Extraer ID de ficha con los múltiples nombres posibles
      final int? chipId = extractProductChipId(r);

      if (chipId != null) {
        if (isClosed) {
          chipConsumedMap[chipId] = (chipConsumedMap[chipId] ?? 0.0) + qtySpent;
        } else {
          chipEstimatedMap[chipId] =
              (chipEstimatedMap[chipId] ?? 0.0) + qtySpent;
        }
      }
    }

    consumedForStats = 0.0;
    inProgressForStats = 0.0;
    List<Map<String, dynamic>> processed = [];

    for (var chip in relevantChips) {
      final int chipId = (chip['id'] as num).toInt();
      double totalQty = (chip['Qty'] as num?)?.toDouble() ?? 0.0;
      double consumed = chipConsumedMap[chipId] ?? 0.0;
      double estimated = chipEstimatedMap[chipId] ?? 0.0;

      // Sumar solo de las fichas relevantes para este cliente/vista
      consumedForStats += consumed;
      inProgressForStats += estimated;

      processed.add({
        ...chip,
        'consumed': consumed,
        'estimated': estimated,
        'available': totalQty - consumed,
      });
    }

    if (mounted) {
      setState(() {
        _contractedHours = acquiredForStats > 0 ? acquiredForStats : null;
        _consumedHours = consumedForStats;
        _estimatedHours = inProgressForStats;
      });
    }
  }

  Future<void> _deleteRequest(dynamic id) async {
    if (!AccessControl.canManageRequests) {
      ToastMessage.show(
        context: context,
        message: 'No tienes permisos para eliminar solicitudes.',
        type: ToastType.failure,
      );
      return;
    }
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => CustomModal(
        title: 'Confirmar Eliminación',
        content: const Text(
          '¿Está seguro de que desea eliminar esta solicitud?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          CustomButton(
            text: 'Eliminar',
            backgroundColor: Theme.of(context).colorScheme.error,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await deleteRequestApi(id);
      if (mounted) {
        if (success) {
          ToastMessage.show(context: context, message: 'Solicitud eliminada correctamente', type: ToastType.help);
          _refreshRequest(fetchNetwork: false);
        } else {
          ToastMessage.show(context: context, message: 'Error al eliminar', type: ToastType.failure);
        }
      }
    }
  }

  void _showExportModal() {
    bool exportAll = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) {
          final int currentCount = _sortedRequests.length;
          final int totalCount = _rawRequests.length;
          
          Future<void> handleExport(Function exportFunc) async {
            List<Map<String, dynamic>> recordsToExport = _sortedRequests;
            
            if (exportAll) {
              showDialog(
                context: ctx,
                barrierDismissible: false,
                builder: (_) => const CustomModal(
                  title: 'Procesando Datos',
                  content: Center(child: CircularProgressIndicator()),
                  actions: [],
                ),
              );
              
              final processedData = await processRequests(_rawRequests, _statusIdMap);
              recordsToExport = List<Map<String, dynamic>>.from(processedData['requests']);
              
              if (ctx.mounted) Navigator.pop(ctx);
            }
            
            if (recordsToExport.isEmpty) {
              if (context.mounted) {
                ToastMessage.show(context: context, message: 'No hay registros para exportar', type: ToastType.help);
              }
              return;
            }
            
            if (ctx.mounted) Navigator.pop(ctx);
            exportFunc(recordsToExport, context, isMyRequests: true);
          }

          return CustomModal(
            title: AppLocale.exportRequests.getString(context),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rango de exportación:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                RadioListTile<bool>(
                  title: Text('Solo esta página ($currentCount filas)'),
                  value: false,
                  groupValue: exportAll,
                  onChanged: (val) => setStateModal(() => exportAll = val!),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<bool>(
                  title: Text('Todas las filtradas ($totalCount filas)'),
                  value: true,
                  groupValue: exportAll,
                  onChanged: (val) => setStateModal(() => exportAll = val!),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(),
                const Text('Formato:', style: TextStyle(fontWeight: FontWeight.bold)),
                ListTile(
                  leading: const Icon(Icons.grid_on, color: Colors.green),
                  title: const Text('Exportar a Excel (XLSX)'),
                  onTap: () => handleExport(ExportFunctions.exportToExcel),
                ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file, color: Colors.blue),
                  title: const Text('Exportar a CSV'),
                  onTap: () => handleExport(ExportFunctions.exportToCsv),
                ),
                ListTile(
                  leading: const Icon(Icons.description, color: Colors.red),
                  title: const Text('Exportar a PDF'),
                  onTap: () => handleExport(ExportFunctions.exportToPdf),
                ),
              ],
            ),
            actions: [
              CustomButton(
                text: 'Cancelar',
                onPressed: () => Navigator.pop(ctx),
                backgroundColor: Colors.red,
                textColor: Colors.white,
              ),
            ],
          );
        }
      ),
    );
  }

  void _editRequest(Map<String, dynamic> req) async {
    if (!AccessControl.canManageRequests) {
      // Mostrar solo lectura de los detalles para soporte
      showDialog(
        context: context,
        builder: (context) => CustomModal(
          title: 'Detalle de Solicitud ${req['id']}',
          width: 500,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomTextField(
                controller: TextEditingController(text: req['situation']),
                label: AppLocale.requestType.getString(context),
                readOnly: true,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: TextEditingController(text: req['emailSubject']),
                label: AppLocale.subject.getString(context),
                readOnly: true,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: TextEditingController(text: req['category']),
                label: AppLocale.category.getString(context),
                readOnly: true,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: TextEditingController(text: req['level']),
                label: 'Prioridad',
                readOnly: true,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: TextEditingController(text: req['status']),
                label: 'Estado',
                readOnly: true,
              ),
              const SizedBox(height: 16),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withOpacity(0.5),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Descripción',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Html(
                          data: req['description'] ?? '',
                          style: {
                            "body": Style(
                              margin: Margins.zero,
                              padding: HtmlPaddings.zero,
                              fontSize: FontSize(14),
                            ),
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0, right: 4.0),
                    child: IconButton(
                      icon: const Icon(Icons.zoom_out_map),
                      tooltip: AppLocale.viewFullDescription.getString(context),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext dialogContext) => CustomModal(
                            title: AppLocale.fullDescription.getString(context),
                            width: 600,
                            content: SizedBox(
                              height: 400,
                              child: SingleChildScrollView(
                                child: Html(
                                  data: req['description'] ?? '',
                                  style: {
                                    "body": Style(
                                      margin: Margins.zero,
                                      padding: HtmlPaddings.zero,
                                    ),
                                  },
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                child: const Text('Cerrar'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => EditRequestDialog(
        request: req,
        statusIdMap: _statusIdMap,
        priorityMap: priorityMap,
        onSave: () {
          _refreshRequest(fetchNetwork: false);
        },
        onDelete: () => _deleteRequest(req['realId']),
      ),
    );
  }

  /// Construye el PopupMenuButton para seleccionar el modo de vista del administrador.
  Future<void> _showExceptionDialog() async {
    if (!AccessControl.isAdmin) return;

    final Set<int> tempSelectedIds = Set.from(
      ValidationManager.hourValidationExceptions,
    );

    await showDialog(
      context: context,
      builder: (context) {
        String searchQuery = '';
        return CustomModal(
          title: 'Gestionar Excepciones de Horas',
          width: 500,
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              // Usamos la lista _bPartners del estado, que ya está filtrada para mostrar solo clientes.
              final filteredBps = _bPartners
                  .where(
                    (bp) => (bp['Name'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(searchQuery.toLowerCase()),
                  )
                  .toList();

              return SizedBox(
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Buscar tercero...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (val) => setState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filteredBps.isEmpty
                          ? const Center(
                              child: Text('No se encontraron terceros.'),
                            )
                          : ListView.builder(
                              itemCount: filteredBps.length,
                              itemBuilder: (context, index) {
                                final bp = filteredBps[index];
                                final rawId = bp['id'] ?? bp['C_BPartner_ID'];
                                final intId = rawId is int
                                    ? rawId
                                    : int.tryParse(rawId.toString()) ?? 0;
                                return CheckboxListTile(
                                  title: Text(bp['Name'] ?? 'Tercero $intId'),
                                  value: tempSelectedIds.contains(intId),
                                  onChanged: (bool? value) => setState(
                                    () => value == true
                                        ? tempSelectedIds.add(intId)
                                        : tempSelectedIds.remove(intId),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            CustomButton(
              text: 'Guardar',
              onPressed: () {
                ValidationManager.setExceptions(tempSelectedIds);
                Navigator.of(context).pop();
                ToastMessage.show(
                  context: context,
                  message: 'Excepciones de validación de horas actualizadas.',
                  type: ToastType.success,
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildPaginationControls() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16.0,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_totalRecords == 0 ? 0 : (_currentPage * _rowsPerPage) + 1} - ${((_currentPage + 1) * _rowsPerPage < _totalRecords) ? (_currentPage + 1) * _rowsPerPage : _totalRecords} de $_totalRecords',
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage == 0
                    ? null
                    : () {
                        setState(() {
                          _currentPage--;
                        });
                        _refreshRequest(fetchNetwork: false);
                      },
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: ((_currentPage + 1) * _rowsPerPage >= _totalRecords)
                    ? null
                    : () {
                        setState(() {
                          _currentPage++;
                        });
                        _refreshRequest(fetchNetwork: false);
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }




  Widget _buildExceptionHoursInkWell() {
    return InkWell(
      onTap: _showExceptionDialog,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined),
            const SizedBox(width: 8),
            Text(
              AppLocale.hoursException.getString(context),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appBarActions = [

      if (AccessControl.isAdmin) ..._buildAdminAppBarActions(context),
      const HelpIcon(),
      Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: IconButton(
          onPressed: () {
            setState(() => _isLoading = true);
            GlobalCache.forceFullSyncWithProgress(context, onSyncAction: () async {
              await _initData();
            });
          },
          icon: const Icon(Icons.refresh),
          tooltip: 'Refrescar',
        ),
      ),
      if (!AccessControl.isAdmin)
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.red),
          tooltip: AppLocale.logout.getString(context),
          onPressed: () => showLogoutConfirmation(context),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showCalendar
              ? AppLocale.requestsCalendar.getString(context)
              : AppLocale.supportRequests.getString(context),
        ),
        leadingWidth: !AccessControl.isAdmin ? 220 : null,
        leading: _showCalendar
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: AppLocale.back.getString(context),
                onPressed: () {
                  setState(() => _showCalendar = false);
                  if (_outerScrollController.hasClients) {
                    _outerScrollController.animateTo(
                      0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                },
              )
            : (!AccessControl.isAdmin ? const UserInfoLeading() : null),
        actions: appBarActions,
      ),
      drawer: !AccessControl.isAdmin
          ? null
          : const CustomDrawer(currentRoute: '/my-requests'),
      bottomNavigationBar:
          (MediaQuery.of(context).size.width < 900 && !AccessControl.isAdmin)
          ? const ProjectBottomNav(currentRoute: '/my-requests')
          : null,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (MediaQuery.of(context).size.width >= 900 &&
              !AccessControl.isAdmin)
            const ProjectSideBar(currentRoute: '/my-requests'),
          Expanded(
            child: SafeArea(
              bottom: false,
              child: NestedScrollView(
                controller: _outerScrollController,
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    if (_metricsSource != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                CustomButton(
                                  text: _metricsSource == '/client-workload'
                                      ? 'Volver al Treemap (Terceros)'
                                      : _metricsSource == '/rep-workload'
                                          ? 'Volver al Treemap (Representantes)'
                                          : 'Volver al Treemap',
                                  icon: Icons.arrow_back,
                                  onPressed: () => context.go(_metricsSource!),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Icon(
                                        Icons.auto_graph,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Visualizando Desglose del treemap',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurface,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 20),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: 'Descartar aviso',
                                        onPressed: () {
                                          setState(() {
                                            _metricsSource = null;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: RequestStatsCard(
                            contractedHours: _contractedHours,
                            consumedHours: _consumedHours,
                            estimatedHours: _estimatedHours,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: RequestFilterBar(
                            searchController: _searchController,
                            isAscending: _isAscending,
                            rowsPerPage: _rowsPerPage,
                            showHistory: _showHistory,
                            selectedYears: _selectedYears,
                            onExport: _showExportModal,
                            onShowYearFilter: _showYearFilterModal,
                            onShowFilters: _showFilterModal,
                            onShowCalendar: () =>
                                setState(() => _showCalendar = !_showCalendar),
                            showCalendar: _showCalendar,
                            chipFilterMode: _chipFilterMode,
                            onChipFilterChanged: (newMode) {
                              setState(() {
                                _chipFilterMode = newMode;
                                _currentPage = 0;
                              });
                              _refreshRequest(fetchNetwork: false);
                            },
                            activeFilterCount: _activeFilterCount,
                            isLoading: _isLoading || !GlobalCache.isDataLoaded,
                            onSortChanged: () {
                              setState(() {
                                _isAscending = !_isAscending;
                                _currentPage = 0;
                              });
                              _refreshRequest(fetchNetwork: false);
                            },
                            onRowsPerPageChanged: (val) {
                              setState(() {
                                _rowsPerPage = val!;
                                _currentPage = 0;
                                _cachedTable = null;
                              });
                              _refreshRequest(fetchNetwork: false);
                            },
                            onClearFilters: () {
                              setState(() {
                                _filters = const RequestFilterModel();
                                _searchController.clear();
                                _isAscending = false;
                                _currentPage = 0;
                                _bpId = null;
                                _selectedYears = [DateTime.now().year];
                                _isLoading = true;
                              });
                              _initData();
                            },
                            onAddRequest: () async {
                              if (await showDialog(
                                    context: context,
                                    builder: (context) => CreateRequestDialog(
                                      bPartners: _bPartners,
                                      selectedBPartnerId: _filters.bpIds.isNotEmpty ? _filters.bpIds.first : _bpId,
                                    ),
                                  ) ==
                                  true) {
                                _refreshRequest(fetchNetwork: false);
                              }
                            },
                            onToggleHistory: () {
                              setState(() {
                                _showHistory = !_showHistory;
                                _filters = _filters.copyWith(statuses: []);
                                _currentPage = 0;
                                if (_showHistory) {
                                  _startHistorySkeleton();
                                } else {
                                  _isHistorySkeletonActive = false;
                                }
                              });
                              _refreshRequest(fetchNetwork: false);
                            },
                            counterWidget: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4.0),
                                  child: Text(
                                    AppLocale.requestsFound.getStringWithVariables(context, {'count': '$_totalRecords'}),
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                if (_selectedYears.length == 1 &&
                                    _selectedYears.first == DateTime.now().year)
                                  Text(
                                    AppLocale.currentYearRequests.getString(context),
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 4.0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildActiveFilterChips(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ];
                },
                body: CustomScrollView(
                  slivers: [
                    SliverLayoutBuilder(
                      builder: (BuildContext context, SliverConstraints constraints) {
                        // Proveemos una altura mínima segura para que el calendario/gantt nunca arroje overflow,
                        // pero permitimos que tome todo el espacio restante si hay suficiente.
                        final double height = constraints.remainingPaintExtent > 600
                            ? constraints.remainingPaintExtent
                            : 600.0;
                        return SliverToBoxAdapter(
                          child: SizedBox(
                            height: height,
                            child: RepaintBoundary(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  child: _showCalendar
                                      ? CalendarGanttWrapper(
                                          requests: _rawRequests,
                                          onGoToRequest: (String searchVal) {
                                            setState(() {
                                              _showCalendar = false;
                                              _searchController.text = searchVal;
                                            });
                                            _refreshRequest(fetchNetwork: false);
                                          },
                                        )
                                      : Column(
                                          children: [Expanded(child: _buildTableWidget())],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
