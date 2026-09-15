import 'package:primhub/ui/Shared_Custom/custom_toast.dart' hide ColorTheme;
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/ui/pages/Metrics/custom_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/ui/Shared_Custom/custom_container.dart';
import 'package:primhub/ui/widgets/project_sidebar.dart';
import '../../../theme/colors.dart';
import '../../widgets/custom_drawer.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/api/admin_view_mode.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart';
import 'package:primhub/ui/Shared_Custom/admin_mode_views.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/api/contract_api.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/widgets/project_bottom_nav.dart';
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/ui/Shared_Custom/custom_skeleton.dart';
import 'package:primhub/ui/Shared_Custom/user_info_leading.dart';
import 'package:primhub/ui/Shared_Custom/help_icon.dart';

// Importante: Asegúrate de que esta ruta sea la correcta para tu clase GraphicsFunctions
import 'graphic_functions.dart';

class MetricsPage extends StatefulWidget {
  const MetricsPage({super.key});
  @override
  State<MetricsPage> createState() => _MetricsPageState();
}

class _MetricsPageState extends State<MetricsPage> {
  bool _isLoading = true;
  bool _isProjectsLoading = false;

  int? _selectedProjectId;
  List<dynamic> _projects = [];
  final ValueNotifier<int> _projectsLoadNotifier = ValueNotifier<int>(0);
  final _adminViewModeManager = AdminViewModeManager();
  String _supportProductChipFilter = 'mixto';
  int? _supportSpecificChipId;

  bool _isInit = true;

  bool _isLoadingSupport = true;
  List<double> _supportPriorityValues = [];
  List<String> _supportPriorityLabels = [];
  List<double> _supportStatusValues = [];
  List<String> _supportStatusLabels = [];

  final int _supportSelectedYear = DateTime.now().year;
  int? _supportSelectedBpId;
  List<Map<String, dynamic>> _supportBPartners = [];

  // Datos para los gráficos
  List<double> _statusValues = [];
  List<String> _statusLabels = [];
  List<double> _complianceValues = [];
  List<String> _complianceLabels = [];
  List<double> _modulePercentageValues = [];
  List<String> _moduleLabels = [];
  List<String> _moduleFullLabels = [];
  List<double> _moduleTerminadaValues = [];
  List<double> _modulePendienteValues = [];
  List<double> _moduleEsperaValues = [];
  List<double> _moduleEvaluacionValues = [];

  @override
  void initState() {
    super.initState();
    _adminViewModeManager.addListener(_onViewModeChanged);
    _initializeData();
    GlobalCache.backgroundSyncNotifier.addListener(_onBackgroundSyncChanged);
  }

  Future<void> _initializeData() async {
    if (_isInit) {
      setState(() {
        _isLoading = true;
        _isLoadingSupport = true;
      });
    }

    // Asegurar sincronización básica
    await GlobalCache.syncData();

    // Esperar a que la Fase 2 (carga completa) termine antes de continuar.
    // Esto asegura que el skeleton se muestre hasta que los datos históricos estén listos.
    try {
      if (GlobalCache.phase2SyncFuture != null) {
        await GlobalCache.phase2SyncFuture;
      }
    } catch (_) {
      // Ignored: Fail silently
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      if (AccessControl.canViewProjectCharts) {
        _loadProjects();
      }
      if (AccessControl.canViewSupportCharts) {
        _loadSupportBPartners();
        _loadSupportMetrics();
      }
    }
  }

  void _onBackgroundSyncChanged() {
    if (mounted) {
      setState(() {});
      // Si terminó la carga de fondo y no tenemos proyectos, intentamos cargar solo si no estamos ya en proceso
      if (!GlobalCache.backgroundSyncNotifier.value &&
          _projects.isEmpty &&
          !_isProjectsLoading) {
        _loadProjects();
      }
    }
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

      if (extra is Map && extra['projectId'] != null) {
        _selectedProjectId = extra['projectId'];
      }
      _isInit = false;
    }
  }

  @override
  void dispose() {
    _adminViewModeManager.removeListener(_onViewModeChanged);
    GlobalCache.backgroundSyncNotifier.removeListener(_onBackgroundSyncChanged);
    super.dispose();
  }

  void _onViewModeChanged() {
    setState(() {});
    if (AccessControl.canViewProjectCharts) {
      _loadProjects();
    }
    if (AccessControl.canViewSupportCharts) {
      _loadSupportBPartners();
      _loadSupportMetrics();
    }
  }

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

  void _showProjectFilterSelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return CustomModal(
          title: 'Filtrar Proyectos',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Mis Proyectos'),
                trailing: _adminViewModeManager.isViewingMine
                    ? Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  _adminViewModeManager.setViewingMine(true);
                  Navigator.pop(dialogContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.group),
                title: Text(AppLocale.allProjects.getString(context)),
                trailing: !_adminViewModeManager.isViewingMine
                    ? Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  _adminViewModeManager.setViewingMine(false);
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

  List<Widget> _buildAdminAppBarActions(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      return [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'admin_mode') _showAdminModeSelectionDialog(context);
            if (value == 'project_filter') {
              _showProjectFilterSelectionDialog(context);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'admin_mode',
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: Text(
                  'Modo: ${_adminViewModeManager.currentMode == AdminViewMode.support ? 'Soporte' : (_adminViewModeManager.currentMode == AdminViewMode.project ? 'Proyecto' : 'Mixto')}',
                ),
              ),
            ),
            PopupMenuItem<String>(
              value: 'project_filter',
              child: ListTile(
                leading: Icon(
                  _adminViewModeManager.isViewingMine
                      ? Icons.person
                      : Icons.group,
                ),
                title: Text(
                  _adminViewModeManager.isViewingMine
                      ? 'Mis Proyectos'
                      : 'Todos',
                ),
              ),
            ),
          ],
        ),
      ];
    }
    return [const AdminModeViews(), _buildProjectFilterPopupMenu()];
  }

  Future<void> _loadSupportBPartners() async {
    if (AccessControl.isAdmin) {
      // Aprovechamos los terceros ya cacheados si están disponibles
      if (GlobalCache.isDataLoaded && GlobalCache.bPartners.isNotEmpty) {
        if (mounted) {
          setState(() {
            _supportBPartners = GlobalCache.bPartners
                .map<Map<String, dynamic>>(
                  (e) => {
                    'id': e['id'] ?? e['C_BPartner_ID'],
                    'Name': e['Name'] ?? 'Sin Nombre',
                  },
                )
                .toList();
          });
        }
      } else {
        final bps = await ContractApi.getBPartnersWithProductChips();
        if (mounted) {
          setState(() {
            _supportBPartners = bps;
          });
          try {
            final extraBps = await ProjectsLogic().fetchBPartners();
            if (mounted) {
              setState(() {
                _supportBPartners = extraBps
                    .map<Map<String, dynamic>>(
                      (e) => {
                        'id': e['id'] ?? e['C_BPartner_ID'],
                        'Name': e['Name'] ?? 'Sin Nombre',
                      },
                    )
                    .toList();
              });
            }
          } catch (_) {
      // Ignored: Fail silently
    }
        }
      }
    }
  }

  Future<void> _loadProjects() async {
    if (_isProjectsLoading) return; // Evitar llamadas dobles

    setState(() {
      _isProjectsLoading = true;
    });
    _projectsLoadNotifier.value++;

    try {
      int? bPartnerIdForQuery;
      if (AccessControl.isAdmin) {
        bPartnerIdForQuery = _adminViewModeManager.isViewingMine
            ? (User.cBPartnerID ?? -1)
            : null;
      } else if (AccessControl.isProject) {
        bPartnerIdForQuery = User.cBPartnerID;
      }

      // Llamada a la API y Filtrado Null Safety
      final rawProjects = await ProjectsLogic().fetchProjectsForDropdown(
        bPartnerId: bPartnerIdForQuery,
      );

      // Solo incluimos proyectos con datos válidos
      final projects = rawProjects.where((p) {
        return p != null &&
            p['id'] != null &&
            p['Name'] != null &&
            p['Name'].toString().trim().isNotEmpty;
      }).toList();


      if (mounted) {
        setState(() {
          _projects = projects;
          _isProjectsLoading = false;

          // Solo mantenemos la selección si el proyecto aún existe en la nueva lista.
          if (_selectedProjectId != null &&
              !_projects.any((p) => p['id'] == _selectedProjectId)) {
            _selectedProjectId = null;
          }
        });
        _projectsLoadNotifier.value++;

        if (_selectedProjectId != null) {
          _loadMetrics();
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ToastMessage.show(context: context, message: AppLocale.errorLoadingProjectList.getStringWithVariables(context, {'error': e.toString()}), type: ToastType.help);
        setState(() {
          _isLoading = false;
          _isProjectsLoading = false;
          _projects = [];
        });
        _projectsLoadNotifier.value++;
      }
    }
  }

  Future<void> _loadMetrics() async {
    if (_selectedProjectId == null) return;
    setState(() => _isLoading = true);

    try {
      // 0. Prioritize project Data to get UUID
      final projData = _projects.firstWhere(
        (p) => p['id'] == _selectedProjectId,
        orElse: () => <String, dynamic>{},
      );

      final projectUU = projData['uuid'];
      if (projectUU != null && projectUU.toString().isNotEmpty) {
        // Garantizar carga de datos jerárquicos
        await GlobalCache.loadProjectRequestsInBackground(_selectedProjectId!);
      }

      // 1. Obtener los datos crudos
      final requests = await GraphicsFunctions.fetchMetricsData(
        projectId: _selectedProjectId!,
      );

      if (requests.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusLabels = [];
            _statusValues = [];
            _complianceLabels = [];
            _complianceValues = [];
            _moduleLabels = [];
            _moduleFullLabels = [];
            _moduleTerminadaValues = [];
            _modulePendienteValues = [];
            _moduleEsperaValues = [];
            _moduleEvaluacionValues = [];
            _modulePercentageValues = [];
          });
          ToastMessage.show(context: context, message: AppLocale.insufficientMetricsData.getString(context), type: ToastType.warning);
        }
        return;
      }

      // 2. Calcular las métricas
      final metrics = ProjectMetricsCalculator.calculate(requests);

      if (mounted) {
        setState(() {
          _statusLabels = metrics.statusData.labels;
          _statusValues = metrics.statusData.values;

          _complianceLabels = metrics.complianceData.labels;
          _complianceValues = metrics.complianceData.values;

          _moduleLabels = metrics.moduleStatusData.labels;
          _moduleFullLabels = metrics.moduleStatusData.fullLabels;
          _moduleTerminadaValues = metrics.moduleStatusData.seriesValues[0];
          _modulePendienteValues = metrics.moduleStatusData.seriesValues[1];
          _moduleEsperaValues = metrics.moduleStatusData.seriesValues[2];
          _moduleEvaluacionValues = metrics.moduleStatusData.seriesValues.length > 3 ? metrics.moduleStatusData.seriesValues[3] : [];

          _modulePercentageValues = metrics.modulePercentageData.values;

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastMessage.show(context: context, message: AppLocale.errorCalculatingMetrics.getStringWithVariables(context, {'error': e.toString()}), type: ToastType.failure);
      }
    }
  }

  Future<void> _loadSupportMetrics() async {
    setState(() => _isLoadingSupport = true);
    try {
      List<Map<String, dynamic>> rawRequests = [];

      if (GlobalCache.isDataLoaded) {
        // Extraer desde la caché pre-cargada
        rawRequests = GlobalCache.requests.where((req) {
          int? bpId = req['C_BPartner_ID'] is Map
              ? req['C_BPartner_ID']['id']
              : req['C_BPartner_ID'];

          if (!AccessControl.isAdmin && User.cBPartnerID != null) {
            if (bpId != User.cBPartnerID) return false;
          } else if (AccessControl.isAdmin && _supportSelectedBpId != null) {
            if (bpId != _supportSelectedBpId) return false;
          }
          bool hasChip = req['productChipId'] != null || req['C_BPartner_Product_Chip_ID'] != null;
          if (_supportProductChipFilter == 'con_ficha' && !hasChip) {
            return false;
          }
          if (_supportProductChipFilter == 'sin_ficha' && hasChip) {
            return false;
          }
          if (_supportSpecificChipId != null) {
            int? reqChipId = req['productChipId'] is Map ? req['productChipId']['id'] : req['productChipId'];
            reqChipId ??= req['C_BPartner_Product_Chip_ID'] is Map ? req['C_BPartner_Product_Chip_ID']['id'] : req['C_BPartner_Product_Chip_ID'];
            if (reqChipId != _supportSpecificChipId) return false;
          }
          
          return true;
        }).toList();
      } else {
        List<String> conditions = [];
        conditions.add("(C_Project_ID eq null and Record_UU eq null)");
        
        if (!AccessControl.isAdmin && User.cBPartnerID != null) {
          conditions.add("(C_BPartner_ID eq ${User.cBPartnerID})");
        } else if (AccessControl.isAdmin && _supportSelectedBpId != null) {
          conditions.add("(C_BPartner_ID eq $_supportSelectedBpId)");
        }
        
        String filter = conditions.join(" and ");
        String expand =
            "R_Status_ID(\$select=Name,IsOpen),Priority(\$select=Name)";
        final fetchedRequests = await fetchRequest(
          filter: filter,
          expand: expand,
        );
        rawRequests = fetchedRequests.where((req) {
          bool hasChip = req['productChipId'] != null || req['C_BPartner_Product_Chip_ID'] != null;
          if (_supportProductChipFilter == 'con_ficha' && !hasChip) return false;
          if (_supportProductChipFilter == 'sin_ficha' && hasChip) return false;
          if (_supportSpecificChipId != null) {
            int? reqChipId = req['productChipId'] is Map ? req['productChipId']['id'] : req['productChipId'];
            reqChipId ??= req['C_BPartner_Product_Chip_ID'] is Map ? req['C_BPartner_Product_Chip_ID']['id'] : req['C_BPartner_Product_Chip_ID'];
            if (reqChipId != _supportSpecificChipId) return false;
          }
          return true;
        }).toList();
      }

      final Map<String, double> priorityCounts = {
        'Urgente': 0,
        'Alta': 0,
        'Media': 0,
        'Baja': 0,
        'Muy baja': 0,
      };
      final Map<String, double> statusCounts = {};

      for (var req in rawRequests) {
        // Excluir solicitudes vinculadas a proyectos (tareas)
        if (req['Record_UU'] != null && req['Record_UU'].toString().isNotEmpty) {
          continue;
        }

        // Filtro local por Año
        String created = req['Created'] ?? '';
        if (created.length >= 4) {
          int? year = int.tryParse(created.substring(0, 4));
          if (year != _supportSelectedYear) continue;
        }

        // Extracción robusta de Estado
        final statusObj = req['R_Status_ID'];
        final statusData = statusObj is Map ? statusObj : null;
        String rawStatusName = req['R_Status_Name'] ?? '';

        if (statusData != null) {
          rawStatusName =
              statusData['Name'] ?? statusData['identifier'] ?? rawStatusName;
        }

        if (rawStatusName.isEmpty && statusObj is int) {
          // Buscar en caché global si solo llega el ID entero
          rawStatusName = GlobalCache.statuses.keys.firstWhere(
            (k) => GlobalCache.statuses[k] == statusObj,
            orElse: () => 'Desconocido',
          );
        }

        String lowerStatus = rawStatusName.toLowerCase();
        
        // Excluir Anuladas
        if (lowerStatus.contains('anulada')) continue;

        final int? statusId = statusObj is Map ? (statusObj['id'] as num?)?.toInt() : (statusObj is num ? statusObj.toInt() : null);

        bool isOpen = false;
        if (statusData != null && statusData['IsOpen'] != null) {
          final rawIsOpen = statusData['IsOpen'];
          final isOpenStr = rawIsOpen?.toString().trim().toLowerCase();
          isOpen = (isOpenStr == 'true' || isOpenStr == 'y' || rawIsOpen == true);
        } else if (statusId != null) {
          isOpen = GlobalCache.statusIsOpenMap[statusId] ?? false;
        }

        if (!isOpen) continue;

        // Comprobar si pertenece a la categoría de estado "Soporte Técnico"
        bool isSoporteTecnico = false;
        if (statusId != null) {
          final statusCategoryId = GlobalCache.statusCategoryMap[statusId];
          if (statusCategoryId != null) {
            final categoryName = GlobalCache.statusCategoryNameMap[statusCategoryId]?.toLowerCase() ?? '';
            if (categoryName.contains('soporte técnico') || categoryName.contains('soporte tecnico')) {
               isSoporteTecnico = true;
            }
          }
        }

        if (!isSoporteTecnico) {
          continue;
        }

        // Comprobar si es de tipo "Soporte Lirion"
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

        if (!isSoporteLirion) {
          continue;
        }

        String cleanStatus = rawStatusName.contains('_')
            ? rawStatusName.split('_').last.trim()
            : rawStatusName.trim();


        // Prioridad robusta - Siempre leer desde la Categoría para tickets de Soporte
        dynamic rawPriority;
        final categoryId = req['R_Category_ID'] is Map ? req['R_Category_ID']['id'] : req['R_Category_ID'];
        if (categoryId != null) {
          final cat = GlobalCache.rawCategories.firstWhere((c) => c['id'] == categoryId, orElse: () => {});
          if (cat.isNotEmpty) {
            rawPriority = cat['Priority'] is Map ? cat['Priority']['id'] : cat['Priority'];
          }
        }

        String priorityStr = rawPriority != null ? rawPriority.toString() : '5';

        String priority = 'Media';
        final pLower = priorityStr.toLowerCase();
        if (pLower.contains('urgente') || priorityStr == '1') {
          priority = 'Urgente';
        } else if (pLower.contains('alta') || priorityStr == '3') {
          priority = 'Alta';
        } else if (pLower.contains('media') || priorityStr == '5') {
          priority = 'Media';
        } else if (pLower.contains('muy baja') || pLower.contains('menor') || priorityStr == '9') {
          priority = 'Muy baja';
        } else if (pLower.contains('baja') || priorityStr == '7') {
          priority = 'Baja';
        } else {
          priority = priorityStr;
        }

        priorityCounts[priority] = (priorityCounts[priority] ?? 0) + 1;
        statusCounts[cleanStatus] = (statusCounts[cleanStatus] ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          _supportPriorityLabels = [
            'Urgente',
            'Alta',
            'Media',
            'Baja',
            'Muy baja',
          ].where((p) => priorityCounts.containsKey(p)).toList();
          _supportPriorityValues = _supportPriorityLabels
              .map((p) => priorityCounts[p]!)
              .toList();
          _supportStatusLabels = statusCounts.keys.toList();
          _supportStatusValues = statusCounts.values.toList();
          _isLoadingSupport = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingSupport = false);
    }
  }

  void _showBPartnerSearchModal() {
    showDialog(
      context: context,
      builder: (context) {
        String searchQuery = "";
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredBps = _supportBPartners.where((bp) {
              final name = (bp['Name'] ?? '').toString().toLowerCase();
              return name.contains(searchQuery.toLowerCase());
            }).toList();

            return CustomModal(
              title: AppLocale.selectPartnerTitle.getString(context),
              width: 500,
              content: SizedBox(
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: AppLocale.searchPartnerDots.getString(context),
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (val) =>
                          setModalState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filteredBps.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Text(
                                  "no se encontraron terceros validos para mostrar graficos",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredBps.length + 1,
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        title: Text(
                                          AppLocale.allPartners.getString(context),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        onTap: () {
                                          setState(
                                            () => _supportSelectedBpId = null,
                                          );
                                          _loadSupportMetrics();
                                          Navigator.pop(context);
                                        },
                                      ),
                                      const Divider(),
                                    ],
                                  );
                                }
                                final bp = filteredBps[index - 1];
                                return ListTile(
                                  title: Text(bp['Name'] ?? 'Sin Nombre'),
                                  onTap: () {
                                    setState(
                                      () => _supportSelectedBpId = bp['id'],
                                    );
                                    _loadSupportMetrics();
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showProjectSearchModal() {
    showDialog(
      context: context,
      builder: (context) {
        String searchQuery = "";
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return AnimatedBuilder(
              animation: _projectsLoadNotifier,
              builder: (context, child) {
                // Escuchamos cambios del padre si es necesario (aproximación simple)
                final bool isLoading = _isProjectsLoading;
                final projectsList = _projects;

                final filteredProjects = projectsList.where((p) {
                  final name = (p['Name'] ?? 'Sin Nombre')
                      .toString()
                      .toLowerCase();
                  return name.contains(searchQuery.toLowerCase());
                }).toList();

                return CustomModal(
                  title: 'Seleccionar Proyecto',
                  width: 500,
                  content: SizedBox(
                    height: 450,
                    child: Column(
                      children: [
                        TextField(
                          decoration: InputDecoration(
                            hintText: AppLocale.searchProject.getString(context),
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: isLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (val) =>
                              setModalState(() => searchQuery = val),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: isLoading && projectsList.isEmpty
                              ? const Center(child: CircularProgressIndicator())
                              : projectsList.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.folder_off_outlined,
                                        size: 48,
                                        color: Colors.grey.withOpacity(0.5),
                                      ),
                                      const SizedBox(height: 16),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 24.0,
                                        ),
                                        child: Text(
                                          "no se encontro ningun proyecto relacionado a tu tercero actual",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton(
                                        onPressed: () async {
                                          await _loadProjects();
                                          setModalState(
                                            () {},
                                          ); // Forzar rebuild del modal
                                        },
                                        child: const Text("Reintentar"),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: filteredProjects.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final p = filteredProjects[index];
                                    return ListTile(
                                      title: Text(p['Name'] ?? 'Sin Nombre'),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      onTap: () {
                                        setState(
                                          () => _selectedProjectId = p['id'],
                                        );
                                        _loadMetrics();
                                        Navigator.pop(context);
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }



  Widget _buildProjectFilterPopupMenu() {
    return PopupMenuButton<bool>(
      tooltip: AppLocale.filterProjectsHelp.getString(context),
      onSelected: (bool viewingMine) {
        _selectedProjectId = null;
        _projects = [];
        _adminViewModeManager.setViewingMine(viewingMine);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _adminViewModeManager.isViewingMine ? Icons.person : Icons.group,
            ),
            const SizedBox(width: 8),
            Text(
              _adminViewModeManager.isViewingMine
                  ? 'Mis Proyectos'
                  : AppLocale.allProjects.getString(context),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
      itemBuilder: (BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;
        final isViewingMine = _adminViewModeManager.isViewingMine;
        PopupMenuItem<bool> buildItem(
          bool isMineOption,
          String text,
          IconData icon,
        ) {
          final isSelected = isViewingMine == isMineOption;
          return PopupMenuItem<bool>(
            value: isMineOption,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                  if (isSelected) const Spacer(),
                  if (isSelected)
                    Icon(Icons.check, size: 18, color: colorScheme.primary),
                ],
              ),
            ),
          );
        }

        return [
          buildItem(true, 'Mis Proyectos', Icons.person),
          buildItem(false, AppLocale.allProjects.getString(context), Icons.group),
        ];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width >= 1100;


    return Scaffold(
      appBar: AppBar(
        leadingWidth: !AccessControl.isAdmin ? 180 : null,
        leading: !AccessControl.isAdmin
            ? const UserInfoLeading()
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: AppLocale.mainMenu.getString(context),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        title: Text(AppLocale.indicators.getString(context)),
        actions: [
          if (AccessControl.isAdmin) ..._buildAdminAppBarActions(context),
          const HelpIcon(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              GlobalCache.forceFullSyncWithProgress(context, onSyncAction: () async {
                if (AccessControl.canViewProjectCharts) await _loadMetrics();
                if (AccessControl.canViewSupportCharts) {
                  await _loadSupportMetrics();
                }
              });
            },
          ),
          if (!AccessControl.isAdmin)
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.red),
              tooltip: AppLocale.logout.getString(context),
              onPressed: () => showLogoutConfirmation(context),
            ),
        ],
      ),
      drawer: AccessControl.isAdmin
          ? const CustomDrawer(currentRoute: '/metrics')
          : null,
      bottomNavigationBar:
          (MediaQuery.of(context).size.width < 900 && !AccessControl.isAdmin)
          ? const ProjectBottomNav(currentRoute: '/metrics')
          : null,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (MediaQuery.of(context).size.width >= 900 &&
                !AccessControl.isAdmin)
            const ProjectSideBar(currentRoute: '/metrics'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // --- SECCIÓN PROYECTOS ---
                  if (AccessControl.canViewProjectCharts) ...[
                    _buildSectionHeader(
                      context,
                      AppLocale.projectMetrics.getString(context),
                      Icons.insights_rounded,
                    ),
                    _buildControlCenterContainer(
                      context,
                      child: _buildProjectFilters(),
                    ),
                    const SizedBox(height: 24),

                    if (_selectedProjectId == null)
                      _buildWaitingForSelection(
                        context,
                        AppLocale.selectProjectMetrics.getString(context),
                      )
                    else if (_isLoading)
                      _buildSkeletonGrid()
                    else ...[
                      _buildProjectKPIRow(context),
                      const SizedBox(height: 24),
                      _buildDashboardGrid(isLargeScreen),
                    ],
                  ],

                  if (AccessControl.canViewProjectCharts &&
                      AccessControl.canViewSupportCharts)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Divider(thickness: 1.5, color: Colors.black12),
                    ),

                  // --- SECCIÓN SOPORTE ---
                  if (AccessControl.canViewSupportCharts) ...[
                    _buildSectionHeader(
                      context,
                      AppLocale.supportMetrics.getString(context),
                      Icons.support_agent_rounded,
                    ),
                    _buildControlCenterContainer(
                      context,
                      child: _buildSupportFilters(),
                    ),
                    const SizedBox(height: 24),

                    if (!_isLoadingSupport) _buildSupportKPIRow(context),
                    const SizedBox(height: 24),

                    _isLoadingSupport
                        ? _buildSkeletonGrid()
                        : _buildSupportDashboardGrid(isLargeScreen),
                  ],

                  // --- SECCIÓN INDICADORES INTERNOS ---
                  if (AccessControl.isAdmin) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Divider(thickness: 1.5, color: Colors.black12),
                    ),
                    _buildSectionHeader(
                      context,
                      AppLocale.internalIndicators.getString(context),
                      Icons.admin_panel_settings_rounded,
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final double cardWidth = constraints.maxWidth < 600 ? constraints.maxWidth : (constraints.maxWidth - 24) / 2;
                        return Wrap(
                          spacing: 24,
                          runSpacing: 24,
                          children: [
                            SizedBox(
                              width: cardWidth,
                              child: _buildInternalIndicatorCard(
                                context,
                                title: AppLocale.representativeWorkload.getString(context),
                                description: AppLocale.representativeWorkloadHelp.getString(context),
                                icon: Icons.person_pin_circle_rounded,
                                color: Colors.deepPurple,
                                route: '/rep-workload',
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _buildInternalIndicatorCard(
                                context,
                                title: AppLocale.partnerWorkload.getString(context),
                                description: AppLocale.partnerWorkloadHelp.getString(context),
                                icon: Icons.business_rounded,
                                color: Colors.teal,
                                route: '/client-workload',
                              ),
                            ),
                          ],
                        );
                      }
                    ),
                  ],

                  if (!AccessControl.canViewProjectCharts &&
                      !AccessControl.canViewSupportCharts)
                    _buildNoDataView(context),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildInternalIndicatorCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String route,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => context.push(route),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  AppLocale.viewDetail.getString(context),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, color: color, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlCenterContainer(
    BuildContext context, {
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildProjectKPIRow(BuildContext context) {
    // Calculamos el total basado en los datos de cumplimiento (mismo que el gráfico de dona)
    final totalComp = _complianceValues.isEmpty
        ? 0
        : _complianceValues.reduce((a, b) => a + b).toInt();

    double completedPct = 0;
    int completedIdx = _complianceLabels.indexOf('TERMINADA');
    if (completedIdx != -1 && totalComp > 0) {
      completedPct = (_complianceValues[completedIdx] / totalComp) * 100;
    }

    int pendingCount = 0;
    int pendingIdx = _complianceLabels.indexOf('PENDIENTE');
    if (pendingIdx != -1) pendingCount = _complianceValues[pendingIdx].toInt();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth;
        if (constraints.maxWidth < 480) {
          cardWidth = constraints.maxWidth;
        } else if (constraints.maxWidth < 750) {
          cardWidth = (constraints.maxWidth - 16) / 2;
        } else {
          cardWidth = (constraints.maxWidth - 32) / 3;
        }

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _KPICard(
              title: AppLocale.totalRequests.getString(context),
              value: totalComp.toString(),
              icon: Icons.assignment_rounded,
              color: Colors.blue,
              width: cardWidth,
            ),
            _KPICard(
              title: AppLocale.compliance.getString(context),
              value: '${completedPct.toStringAsFixed(1)}%',
              icon: Icons.check_circle_outline_rounded,
              color: ColorTheme.success,
              width: cardWidth,
            ),
            _KPICard(
              title: AppLocale.pending.getString(context),
              value: pendingCount.toString(),
              icon: Icons.pending_actions_rounded,
              color: ColorTheme.atention,
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildSupportKPIRow(BuildContext context) {
    final total = _supportStatusValues.isEmpty
        ? 0
        : _supportStatusValues.reduce((a, b) => a + b).toInt();

    int urgentCount = 0;
    int urgentIdx = _supportPriorityLabels.indexOf('Urgente');
    if (urgentIdx != -1) {
      urgentCount += _supportPriorityValues[urgentIdx].toInt();
    }
    int altaIdx = _supportPriorityLabels.indexOf('Alta');
    if (altaIdx != -1) {
      urgentCount += _supportPriorityValues[altaIdx].toInt();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth;
        if (constraints.maxWidth < 480) {
          cardWidth = constraints.maxWidth;
        } else {
          cardWidth = (constraints.maxWidth - 16) / 2;
        }

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _KPICard(
              title: AppLocale.totalRequests.getString(context),
              value: total.toString(),
              icon: Icons.confirmation_number_rounded,
              color: Colors.indigo,
              width: cardWidth,
              tooltip: 'Muestra el total histórico de tus solicitudes activas vinculadas a fichas de horas.',
              onTap: () {
                context.push(
                  '/metric-requests',
                  extra: {
                    'filterType': 'Solicitudes Totales', // Or whatever name looks good in the app bar
                  },
                );
              },
            ),
            _KPICard(
              title: AppLocale.criticalTickets.getString(context),
              value: urgentCount.toString(),
              icon: Icons.warning_amber_rounded,
              color: Colors.red,
              width: cardWidth,
              tooltip: 'Muestra el total de solicitudes activas de prioridad Urgente o Alta vinculadas a fichas de horas.',
              onTap: () {
                context.push(
                  '/metric-requests',
                  extra: {
                    'filterPriority': 'Críticos',
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildSkeletonGrid() => Column(
    children: [
      Row(
        children: [
          Expanded(child: CustomSkeleton(height: 300, borderRadius: 16)),
          const SizedBox(width: 20),
          Expanded(child: CustomSkeleton(height: 300, borderRadius: 16)),
        ],
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          Expanded(child: CustomSkeleton(height: 300, borderRadius: 16)),
          const SizedBox(width: 20),
          Expanded(child: CustomSkeleton(height: 300, borderRadius: 16)),
        ],
      ),
    ],
  );

  Widget _buildNoDataView(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(64.0),
      child: Column(
        children: [
          Icon(
            Icons.bar_chart_rounded,
            size: 64,
            color: Colors.grey.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            "No hay métricas disponibles para la vista actual.",
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    ),
  );

  Widget _buildWaitingForSelection(BuildContext context, String message) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.ads_click_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildDashboardGrid(bool isLargeScreen) {
    final List<Color> pieColors = [
      const Color(0xFF42A5F5),
      const Color(0xFF66BB6A),
      const Color(0xFFFFA726),
      const Color(0xFFAB47BC),
      const Color(0xFFEF5350),
      const Color(0xFF26A69A),
      const Color(0xFFEC407A),
      const Color(0xFFFFCA28),
      const Color(0xFF5C6BC0),
      const Color(0xFF8D6E63),
    ];

    int? hoveredStackedSeriesIndex;

    final List<Color> mappedComplianceColors = _complianceLabels.map((l) {
      if (l == 'CERRADA' || l == 'TERMINADA') return const Color(0xFFFF9800); // Naranja (como en iDempiere)
      if (l == 'ABIERTA' || l == 'PENDIENTE') return const Color(0xFF42A5F5); // Azul Claro (como en iDempiere)
      if (l == 'ESPERA DE CLIENTE') return const Color(0xFF5C6BC0); // Indigo
      if (l == 'EN EVALUACIÓN DE CLIENTE') return const Color(0xFF66BB6A); // Verde
      return Colors.blue;
    }).toList();

    Widget complianceChart = _buildChartCard(
      AppLocale.compliancePercentage.getString(context),
      300,
      _complianceValues.isEmpty
          ? _buildEmptyView(context)
          : _buildDonutWithLegend(
              _complianceValues,
              _complianceLabels,
              mappedComplianceColors,
              onSliceTapped: (label) {
                context.push(
                  '/metric-requests',
                  extra: {
                    'projectId': _selectedProjectId,
                    'filterCompliance': label,
                  },
                );
              },
            ),
    );

    Widget statusChart = _buildChartCard(
      AppLocale.requestStatus.getString(context),
      300,
      _statusValues.isEmpty
          ? _buildEmptyView(context)
          : _buildDonutWithLegend(
              _statusValues,
              _statusLabels,
              pieColors,
              onSliceTapped: (label) {
                context.push(
                  '/metric-requests',
                  extra: {
                    'projectId': _selectedProjectId,
                    'filterStatus': label,
                  },
                );
              },
            ),
    );

    bool hasModuleStatusData = _modulePercentageValues.isNotEmpty &&
        _moduleTerminadaValues.any((v) => v > 0) ||
        _modulePendienteValues.any((v) => v > 0) ||
        _moduleEsperaValues.any((v) => v > 0) ||
        _moduleEvaluacionValues.any((v) => v > 0);

    Widget moduleStackedChart = _buildChartCard(
      AppLocale.requestStatusByModule.getString(context),
      300,
      !hasModuleStatusData
          ? _buildEmptyView(context)
          : StatefulBuilder(
              builder: (context, setStateLegend) {
                return Column(
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildInteractiveLegendDot(
                          context,
                          'Terminada',
                          ColorTheme.success,
                          hoveredStackedSeriesIndex == 0,
                          hoveredStackedSeriesIndex != null,
                          () => setStateLegend(
                            () => hoveredStackedSeriesIndex = 0,
                          ),
                          () => setStateLegend(
                            () => hoveredStackedSeriesIndex = null,
                          ),
                          () => context.push(
                            '/metric-requests',
                            extra: {
                              'projectId': _selectedProjectId,
                              'filterCompliance': 'TERMINADA',
                            },
                          ),
                        ),
                        _buildInteractiveLegendDot(
                          context,
                          'Pendiente',
                          ColorTheme.atention,
                          hoveredStackedSeriesIndex == 1,
                          hoveredStackedSeriesIndex != null,
                          () => setStateLegend(
                            () => hoveredStackedSeriesIndex = 1,
                          ),
                          () => setStateLegend(
                            () => hoveredStackedSeriesIndex = null,
                          ),
                          () => context.push(
                            '/metric-requests',
                            extra: {
                              'projectId': _selectedProjectId,
                              'filterCompliance': 'PENDIENTE',
                            },
                          ),
                        ),
                        _buildInteractiveLegendDot(
                          context,
                          'Espera de Cliente',
                          Colors.blue,
                          hoveredStackedSeriesIndex == 2,
                          hoveredStackedSeriesIndex != null,
                          () => setStateLegend(
                            () => hoveredStackedSeriesIndex = 2,
                          ),
                          () => setStateLegend(
                            () => hoveredStackedSeriesIndex = null,
                          ),
                          () => context.push(
                            '/metric-requests',
                            extra: {
                              'projectId': _selectedProjectId,
                              'filterCompliance': 'ESPERA DE CLIENTE',
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: CustomStackedBarChart(
                        labels: _moduleLabels,
                        fullLabels: _moduleFullLabels,
                        seriesValues: [
                          _moduleTerminadaValues,
                          _modulePendienteValues,
                          _moduleEsperaValues,
                          _moduleEvaluacionValues,
                        ],
                        seriesNames: const [
                          'Terminada',
                          'Pendiente',
                          'Espera de Cliente',
                          'En Evaluación',
                        ],
                        colors: const [
                          ColorTheme.success,
                          ColorTheme.atention,
                          Colors.blue,
                          ColorTheme.success,
                        ],
                        hoveredSeriesIndex: hoveredStackedSeriesIndex,
                        onBarTapped: (category, series) {
                          context.push(
                            '/metric-requests',
                            extra: {
                              'projectId': _selectedProjectId,
                              'filterType': category,
                              'filterCompliance': series.toUpperCase(),
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
    );

    bool hasModulePercentageData = _modulePercentageValues.isNotEmpty &&
        _modulePercentageValues.any((v) => v > 0);

    Widget modulePctChart = _buildChartCard(
      AppLocale.projectProgressByModule.getString(context),
      300,
      !hasModulePercentageData
          ? _buildEmptyView(context)
          : CustomBarChart(
              labels: _moduleLabels,
              fullLabels: _moduleFullLabels,
              values: _modulePercentageValues,
              colors: const [Color(0xFF673AB7)],
              leftAxisSuffix: '%',
              tooltipSuffix: '%',
              onBarTapped: (label) {
                context.push(
                  '/metric-requests',
                  extra: {'projectId': _selectedProjectId, 'filterType': label},
                );
              },
            ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLargeScreen)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: complianceChart),
              const SizedBox(width: 20),
              Expanded(child: statusChart),
            ],
          )
        else ...[
          complianceChart,
          const SizedBox(height: 20),
          statusChart,
        ],
        const SizedBox(height: 20),
        if (isLargeScreen)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: moduleStackedChart),
              const SizedBox(width: 20),
              Expanded(child: modulePctChart),
            ],
          )
        else ...[
          moduleStackedChart,
          const SizedBox(height: 20),
          modulePctChart,
        ],
      ],
    );
  }

  Widget _buildSupportDashboardGrid(bool isLargeScreen) {
    final List<Color> donutColors2 = [
      const Color(0xFF5C6BC0),
      const Color(0xFF8D6E63),
      const Color(0xFFEC407A),
      const Color(0xFFFFCA28),
      const Color(0xFF29B6F6),
      const Color(0xFF9CCC65),
    ];

    Widget statusChart = _buildChartCard(
      AppLocale.requestStatus.getString(context),
      300,
      _supportStatusValues.isEmpty
          ? _buildEmptyView(context)
          : _buildDonutWithLegend(
              _supportStatusValues,
              _supportStatusLabels,
              donutColors2,
              initialHiddenLabels: const ['Archivada'],
              onSliceTapped: (label) {
                context.push(
                  '/metric-requests',
                  extra: {
                    'filterStatus': label,
                    'filterProductChip': _supportProductChipFilter,
                    'filterSpecificChipId': _supportSpecificChipId,
                  },
                );
              },
            ),
      action: const Tooltip(
        message: 'Muestra el estado histórico de tus solicitudes activas vinculadas a fichas de horas. Puedes hacer clic en los estados de la leyenda para ocultarlos o mostrarlos.',
        child: Icon(Icons.info_outline, color: Colors.grey, size: 20),
      ),
    );

    final List<Color> priorityColors = _supportPriorityLabels.map((p) {
      if (p == 'Urgente') return ColorTheme.error;
      if (p == 'Alta') return Colors.orange;
      if (p == 'Media') return ColorTheme.atention;
      if (p == 'Baja') return Colors.blue;
      return Colors.grey;
    }).toList();

    Widget priorityChart = _buildChartCard(
      AppLocale.requestsByPriority.getString(context),
      300,
      _supportPriorityValues.isEmpty
          ? _buildEmptyView(context)
          : CustomBarChart(
              labels: _supportPriorityLabels.map(_localizedPriority).toList(),
              values: _supportPriorityValues,
              colors: priorityColors,
              tooltipSuffix: 'sol.',
              onBarTapped: (label) {
                final localizedLabels = _supportPriorityLabels
                    .map(_localizedPriority)
                    .toList();
                final index = localizedLabels.indexOf(label);
                final rawLabel = index >= 0 ? _supportPriorityLabels[index] : label;
                context.push(
                  '/metric-requests',
                  extra: {
                    'filterPriority': rawLabel,
                    'filterProductChip': _supportProductChipFilter,
                    'filterSpecificChipId': _supportSpecificChipId,
                  },
                );
              },
            ),
      action: const Tooltip(
        message: 'Muestra la prioridad de tus solicitudes activas vinculadas a fichas de horas.',
        child: Icon(Icons.info_outline, color: Colors.grey, size: 20),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLargeScreen)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: statusChart),
              const SizedBox(width: 20),
              Expanded(child: priorityChart),
            ],
          )
        else ...[
          statusChart,
          const SizedBox(height: 20),
          priorityChart,
        ],
      ],
    );
  }

  String _localizedPriority(String priority) {
    return switch (priority) {
      'Urgente' => AppLocale.urgent.getString(context),
      'Alta' => AppLocale.high.getString(context),
      'Media' => AppLocale.medium.getString(context),
      'Baja' => AppLocale.low.getString(context),
      'Muy baja' => AppLocale.veryLow.getString(context),
      _ => priority,
    };
  }

  Widget _buildDonutWithLegend(
    List<double> values,
    List<String> labels,
    List<Color> colors, {
    String suffix = 'sol.',
    Function(String label)? onSliceTapped,
    List<String> initialHiddenLabels = const [],
  }) {
    return _DonutWithLegendWidget(
      values: values,
      labels: labels,
      colors: colors,
      suffix: suffix,
      onSliceTapped: onSliceTapped,
      initialHiddenLabels: initialHiddenLabels,
    );
  }

  Widget _buildChartCard(String title, double height, Widget child, {Widget? action}) =>
      CustomContainer(
        title: title,
        action: action,
        child: SizedBox(height: height, child: child),
      );

  Widget _buildEmptyView(BuildContext context) => Center(
    child: Text(
      AppLocale.insufficientChartData.getString(context),
      style: const TextStyle(color: Colors.grey),
    ),
  );

  Widget _buildInteractiveLegendDot(
    BuildContext context,
    String text,
    Color color,
    bool isHovered,
    bool isAnyHovered,
    VoidCallback onEnter,
    VoidCallback onExit,
    VoidCallback onTap,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          decoration: BoxDecoration(
            color: isHovered ? color.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isHovered ? 14 : 10,
                height: isHovered ? 14 : 10,
                decoration: BoxDecoration(
                  color: isAnyHovered && !isHovered
                      ? Colors.grey.withOpacity(0.3)
                      : color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
                  color: isAnyHovered && !isHovered
                      ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)
                      : Theme.of(context).colorScheme.onSurface,
                ),
                child: Text(text),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectFilters() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        
        final filterContent = InkWell(
          onTap: _showProjectSearchModal,
          child: InputDecorator(
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
              suffixIcon: _isProjectsLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _selectedProjectId == null
                        ? AppLocale.selectProject.getString(context)
                        : (_projects.firstWhere(
                                (p) => p['id'] == _selectedProjectId,
                                orElse: () => {'Name': 'Desconocido'},
                              )['Name'] ??
                              'Sin Nombre'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.search, color: Colors.grey),
              ],
            ),
          ),
        );

        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${AppLocale.project.getString(context)}:', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              filterContent,
            ],
          );
        } else {
          return Row(
            children: [
              Text('${AppLocale.project.getString(context)}:', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 15),
              Expanded(child: filterContent),
            ],
          );
        }
      },
    );
  }

  Widget _buildSupportFilters() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        final List<Widget> filters = [
          if (AccessControl.isAdmin)
            InkWell(
              onTap: _supportBPartners.isEmpty
                  ? null
                  : _showBPartnerSearchModal,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Tercero',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _supportSelectedBpId == null
                            ? AppLocale.allPartners.getString(context)
                            : (_supportBPartners.firstWhere(
                                    (bp) => bp['id'] == _supportSelectedBpId,
                                    orElse: () => {'Name': 'Desconocido'},
                                  )['Name'] ??
                                  'Sin Nombre'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.search, color: Colors.grey),
                  ],
                ),
              ),
            ),
          CustomDropdown<String>(
            label: AppLocale.sheetCondition.getString(context),
            value: _supportProductChipFilter,
            items: [
              DropdownMenuItem<String>(
                value: 'mixto',
                child: Text(AppLocale.mixedAll.getString(context)),
              ),
              DropdownMenuItem<String>(
                value: 'con_ficha',
                child: Text('Con Ficha Asociada'),
              ),
              DropdownMenuItem<String>(
                value: 'sin_ficha',
                child: Text('Sin Ficha Asociada'),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _supportProductChipFilter = val;
                  if (val == 'sin_ficha') _supportSpecificChipId = null;
                });
                _loadSupportMetrics();
              }
            },
          ),
          CustomDropdown<int?>(
            label: AppLocale.specificSheet.getString(context),
            value: _supportSpecificChipId,
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text(AppLocale.anySheet.getString(context)),
              ),
              ...GlobalCache.productChips.where((c) {
                if (c['IsActive'] != true && c['IsActive'] != 'Y') return false;
                
                int? chipBpId;
                if (c['C_BPartner_ID'] is Map) {
                  chipBpId = c['C_BPartner_ID']['id'];
                } else if (c['C_BPartner_ID'] is int) {
                  chipBpId = c['C_BPartner_ID'];
                }

                if (AccessControl.isAdmin && _supportSelectedBpId != null) {
                  if (chipBpId != _supportSelectedBpId) return false;
                } else if (!AccessControl.isAdmin && User.cBPartnerID != null) {
                  if (chipBpId != User.cBPartnerID) return false;
                }
                
                return true;
              }).map((chip) {
                return DropdownMenuItem<int?>(
                  value: chip['id'],
                  child: Text(
                    chip['Description'] ?? chip['Name'] ?? chip['identifier'] ?? 'Ficha ${chip['id']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
            onChanged: _supportProductChipFilter == 'sin_ficha' ? null : (val) {
              setState(() {
                _supportSpecificChipId = val;
                if (val != null && _supportProductChipFilter == 'mixto') {
                  _supportProductChipFilter = 'con_ficha';
                }
              });
              _loadSupportMetrics();
            },
          ),
        ];

        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: filters.expand((f) => [f, const SizedBox(height: 16)]).toList()..removeLast(),
          );
        } else {
          return Row(
            children: filters.expand((f) => [Expanded(child: f), const SizedBox(width: 16)]).toList()..removeLast(),
          );
        }
      },
    );
  }
}

class _DonutWithLegendWidget extends StatefulWidget {
  final List<double> values;
  final List<String> labels;
  final List<Color> colors;
  final String suffix;
  final Function(String label)? onSliceTapped;
  final List<String> initialHiddenLabels;

  const _DonutWithLegendWidget({
    required this.values,
    required this.labels,
    required this.colors,
    this.suffix = 'sol.',
    this.onSliceTapped,
    this.initialHiddenLabels = const [],
  });

  @override
  State<_DonutWithLegendWidget> createState() => _DonutWithLegendWidgetState();
}

class _DonutWithLegendWidgetState extends State<_DonutWithLegendWidget> {
  int? _hoveredIndex;
  final ScrollController _scrollController = ScrollController();
  bool _showTopArrow = false;
  bool _showBottomArrow = false;
  late Set<String> _hiddenLabels;

  @override
  void initState() {
    super.initState();
    _hiddenLabels = Set<String>.from(widget.initialHiddenLabels);
    _scrollController.addListener(_updateArrows);
    // Evaluar las flechas justo después del primer renderizado
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void didUpdateWidget(covariant _DonutWithLegendWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateArrows);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;

    final showTop = position.pixels > 0;
    final showBottom = position.pixels < position.maxScrollExtent;

    if (_showTopArrow != showTop || _showBottomArrow != showBottom) {
      setState(() {
        _showTopArrow = showTop;
        _showBottomArrow = showBottom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 450;

        final List<double> visibleValues = [];
        final List<String> visibleLabels = [];
        final List<Color> visibleColors = [];
        int? hoveredVisibleIndex;
    
        for (int i = 0; i < widget.labels.length; i++) {
          if (!_hiddenLabels.contains(widget.labels[i])) {
            if (_hoveredIndex == i) {
              hoveredVisibleIndex = visibleLabels.length;
            }
            visibleValues.add(widget.values[i]);
            visibleLabels.add(widget.labels[i]);
            visibleColors.add(widget.colors[i % widget.colors.length]);
          }
        }

        final donutWidget = SizedBox(
          height: isNarrow ? 140 : double.infinity,
          child: CustomDonutChart(
            values: visibleValues,
            labels: visibleLabels,
            colors: visibleColors,
            onSliceTapped: widget.onSliceTapped,
            hoveredIndex: hoveredVisibleIndex,
          ),
        );

        final legendWidget = Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (notification) {
                  _updateArrows();
                  return false;
                },
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(widget.labels.length, (i) {
                      final isHidden = _hiddenLabels.contains(widget.labels[i]);
                      final val = widget.values[i];
                      final total = visibleValues.isEmpty ? 0.0 : visibleValues.reduce((a, b) => a + b);
                      final pct = (!isHidden && total > 0) ? (val / total * 100) : 0.0;

                      final isHovered = _hoveredIndex == i;
                      final isAnyHovered = _hoveredIndex != null;

                      return Tooltip(
                        message: '${widget.labels[i]}\n${val.toInt()} ${widget.suffix} (${pct.toStringAsFixed(1)}%)',
                        waitDuration: const Duration(milliseconds: 500),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _hoveredIndex = i),
                          onExit: (_) => setState(() => _hoveredIndex = null),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                if (_hiddenLabels.contains(widget.labels[i])) {
                                  _hiddenLabels.remove(widget.labels[i]);
                                } else {
                                  _hiddenLabels.add(widget.labels[i]);
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                vertical: 6.0,
                                horizontal: 8.0,
                              ),
                              margin: const EdgeInsets.only(bottom: 4.0),
                              decoration: BoxDecoration(
                                color: isHovered && !isHidden
                                    ? widget.colors[i % widget.colors.length].withOpacity(0.1)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: isHovered && !isHidden ? 16 : 12,
                                    height: isHovered && !isHidden ? 16 : 12,
                                    decoration: BoxDecoration(
                                      color: isHidden
                                          ? Colors.grey.withOpacity(0.3)
                                          : (isAnyHovered && !isHovered
                                              ? Colors.grey.withOpacity(0.3)
                                              : widget.colors[i % widget.colors.length]),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 200),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isHovered && !isHidden
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isHidden
                                            ? Colors.grey
                                            : (isAnyHovered && !isHovered
                                                ? Colors.grey
                                                : Theme.of(context).colorScheme.onSurface),
                                        decoration: isHidden ? TextDecoration.lineThrough : null,
                                      ),
                                      child: Text(
                                        '${widget.labels[i]}\n${val.toInt()} ${widget.suffix} (${pct.toStringAsFixed(1)}%)',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
            if (_showTopArrow)
              Positioned(
                top: 0,
                right: 10,
                child: _buildScrollArrow(Icons.keyboard_arrow_up_rounded),
              ),
            if (_showBottomArrow)
              Positioned(
                bottom: 0,
                right: 10,
                child: _buildScrollArrow(Icons.keyboard_arrow_down_rounded),
              ),
          ],
        );

        if (isNarrow) {
          return Column(
            children: [
              donutWidget,
              const SizedBox(height: 12),
              Expanded(
                child: legendWidget,
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              flex: 5,
              child: donutWidget,
            ),
            Expanded(
              flex: 6,
              child: legendWidget,
            ),
          ],
        );
      },
    );
  }

  Widget _buildScrollArrow(IconData icon) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.85),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _KPICard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final double width;
  final String? tooltip;
  final VoidCallback? onTap;

  const _KPICard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.width,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: color.withOpacity(0.15)),
              borderRadius: BorderRadius.circular(16),
            ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tooltip != null) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: tooltip!,
                        child: Icon(Icons.info_outline, size: 14, color: colorScheme.onSurface.withOpacity(0.4)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
          ),
        ),
      ),
    );
  }
}
