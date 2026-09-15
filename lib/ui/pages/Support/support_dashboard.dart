import 'package:primhub/ui/Shared_Custom/admin_mode_views.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';

import 'package:go_router/go_router.dart';
import 'package:primhub/api/access_control.dart';

import 'package:primhub/api/token.dart';
import 'package:primhub/api/admin_view_mode.dart';

import 'package:primhub/ui/Shared_Custom/custom_container.dart';
import 'package:primhub/ui/Shared_Custom/custom_table.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/widgets/project_sidebar.dart';
import '../../widgets/custom_drawer.dart';
import 'package:primhub/ui/widgets/duration_formatter.dart';
import 'Requests/request_functions.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/widgets/project_bottom_nav.dart';
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/ui/Shared_Custom/custom_skeleton.dart';
import 'package:primhub/ui/Shared_Custom/user_info_leading.dart';
import 'package:primhub/ui/pages/Support/Request_Widgets/support_summary_premium.dart';
import 'package:primhub/ui/pages/Support/Request_Widgets/bpartner_attachments_preview.dart';
import 'package:primhub/ui/Shared_Custom/help_icon.dart';
import 'package:primhub/ImagesManagment/fetch_attachments.dart';
import 'package:primhub/ImagesManagment/post_attachments.dart';
import 'package:primhub/ImagesManagment/download_attachments.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/api/api_http.dart' as http;
import 'package:primhub/ui/pages/Projects/Projects_Widgets/file_preview_manager.dart';
import 'package:primhub/ui/pages/Support/Requests/export_functions.dart';
import 'package:primhub/ui/Shared_Custom/animated_copy_widget.dart';
import 'package:flutter_localization/flutter_localization.dart';

class SupportDashboardPage extends StatefulWidget {
  const SupportDashboardPage({super.key});

  @override
  State<SupportDashboardPage> createState() => _SupportDashboardPageState();
}

class _SupportDashboardPageState extends State<SupportDashboardPage> {
  List<Map<String, dynamic>> _supportRecords = [];
  bool _isLoading = true;
  bool _isLoadingChips = true;
  bool _isLoadingBPartners = false;
  double _totalConsumedHours = 0.0;
  double? _contractedHours;
  double _inProgressHours = 0.0;

  List<Map<String, dynamic>> _processedChips = [];

  bool _isInit = true;

  // Filtro de Tercero
  List<Map<String, dynamic>> _bPartners = [];
  Map<String, int> _statusIdMap = {};
  int? _selectedBpId;
  List<Map<String, dynamic>> _productChips = []; // Fichas crudas del API
  List<Map<String, dynamic>> _allRequests = []; // Todas las solicitudes procesadas
  int? _selectedSummaryChipId; // Chip seleccionado para el resumen superior
  final _adminViewModeManager = AdminViewModeManager();
  bool _showInactiveChips = false;

  // Paginación y Filtros
  final TextEditingController _searchController = TextEditingController();
  int _currentPage = 0;
  int _rowsPerPage = 25;
  bool _isAscending = false;
  List<int> _selectedYears = [DateTime.now().year];
  String _searchType = 'all';

  @override
  void initState() {
    super.initState();
    _adminViewModeManager.addListener(_onViewModeChanged);
    GlobalCache.backgroundSyncNotifier.addListener(_onBackgroundSyncChanged);
    _searchController.addListener(() => setState(() => _currentPage = 0));
  }

  int get _activeFilterCount {
    int count = 0;
    // Ya no contamos el BPartner aquí porque tiene su selector global arriba
    if (_searchController.text.isNotEmpty) count++;
    if (_selectedYears.isNotEmpty && (_selectedYears.length > 1 || (_selectedYears.first != DateTime.now().year))) {
      count++;
    }
    return count;
  }

  void _onBackgroundSyncChanged() async {
    if (!GlobalCache.backgroundSyncNotifier.value && mounted) {
      // Asegurar que _refreshData se llama después del frame actual para evitar setState durante la construcción.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshData();
      });
    }
  }

  void _onViewModeChanged() async {
    // Asegurar que _initData se llama después del frame actual para evitar setState durante la construcción.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initData(forceSync: true);
    });
  }

  @override
  void dispose() {
    _adminViewModeManager.removeListener(_onViewModeChanged);
    GlobalCache.backgroundSyncNotifier.removeListener(_onBackgroundSyncChanged);
    _searchController.dispose();
    super.dispose();
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

      final args = extra as Map<String, dynamic>?;
      if (args != null) {
        if (args['bpId'] != null) _selectedBpId = args['bpId'];
        if (args['chipId'] != null) _selectedSummaryChipId = args['chipId'];
        if (args['search'] != null) _searchController.text = args['search'];
      } else {
        _selectedBpId = AccessControl.isAdmin ? null : User.cBPartnerID;
      }
      // Diferir la carga de datos hasta después del primer frame para evitar el error "setState() called during build".
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _initData();
      });
      _isInit = false;
    }
  }

  Future<void> _initData({bool forceSync = false}) async {
    if (AccessControl.isAdmin && _bPartners.isEmpty) {
      setState(() {
        _isLoadingBPartners = true;
      });
    }

    try {
      await GlobalCache.syncData(force: forceSync);

      if (AccessControl.isAdmin) {
        // Obtenemos la lista ya cacheada que solo trae clientes activos de soporte
        final allBps = GlobalCache.bPartners;

        if (mounted) {
          setState(() {
            // Aplicamos el filtro para que sean solo clientes activos y no proveedores
            _bPartners = allBps
                .where((bp) {
                  final name = bp['Name']?.toString() ?? '';

                  final rawVendor = bp['IsVendor'] ?? bp['isVendor'];
                  final isVendorStr = rawVendor?.toString().trim().toLowerCase();
                  bool isVendor = isVendorStr == 'true' || isVendorStr == 'y';

                  final rawCustomer = bp['IsCustomer'] ?? bp['isCustomer'];
                  final isCustomerStr = rawCustomer?.toString().trim().toLowerCase();
                  bool isCustomer = isCustomerStr == 'true' || isCustomerStr == 'y';
                  if (rawCustomer == null) isCustomer = true;

                  // REGLA: No debe empezar con "~" y debe ser Cliente
                  return !name.startsWith('~') && isCustomer && !isVendor; // Excluir proveedores
                })
                .map((bp) => Map<String, dynamic>.from(bp as Map))
                .toList();

            // Si el tercero seleccionado previamente ya no está en la lista filtrada, lo limpiamos
            if (_selectedBpId != null && !_bPartners.any((bp) => bp['id'] == _selectedBpId)) {
              _selectedBpId = null;
            }

            _isLoadingBPartners = false;
          });
        }
      }

      if (_selectedBpId != null) {
        await GlobalCache.loadSupportBpRequestsInBackground(_selectedBpId!);
      }
      await _fetchProductChips(); // Cargar fichas para el BP seleccionado
      _statusIdMap = await fetchStatuses();
      await _refreshData();
    } catch (_) {
      // Manejar excepciones de forma silenciosa o relanzar
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBPartners = false;
        });
      }
    }
  }

  Future<void> _refreshData() async {
    if (mounted) setState(() => _isLoading = true);
    await _loadContractedHours();
    await _loadSupportData();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchProductChips() async {
    // Usamos GlobalCache para ser consistentes con el Home
    final fetchedChips = GlobalCache.productChips.where((chip) {
      final rawBp = chip['C_BPartner_ID'];
      final chipBpId = rawBp is Map ? (rawBp['id'] as num?)?.toInt() : (rawBp as num?)?.toInt();

      final isActive = chip['IsActive'] == 'Y' || chip['IsActive'] == true;
      if (_showInactiveChips) {
        if (isActive) return false; // Solo queremos las inactivas
      } else {
        if (!isActive) return false; // Solo queremos las activas
      }

      if (_selectedBpId != null) {
        return chipBpId == _selectedBpId;
      }
      return true; // Mostrar todas las fichas si no hay un BP seleccionado
    }).toList();

    if (mounted) {
      setState(() {
        _productChips = fetchedChips;
      });
      await _loadContractedHours();
      if (mounted) {
        setState(() => _isLoadingChips = false);
      }
    }
  }

  Future<void> _loadSupportData() async {
    String filter = "";
    List<String> conditions = [];

    if (_selectedBpId != null) {
      conditions.add("(C_BPartner_ID eq $_selectedBpId)");
    } else if (!AccessControl.isAdmin && User.cBPartnerID != null) {
      conditions.add("(C_BPartner_ID eq ${User.cBPartnerID})");
    }

    filter = conditions.join(" and ");

    // Filtramos solo solicitudes que no sean de proyecto
    // Priorizamos C_Project_ID eq null y mantenemos Record_UU eq null como refuerzo
    final String supportFilter = "(C_Project_ID eq null and Record_UU eq null)";
    filter = filter.isNotEmpty ? "$filter and $supportFilter" : supportFilter;

    final rawRequests = await fetchRequest(filter: filter, expand: 'C_Order_ID(\$select=DocumentNo)');

    final processedData = await processRequests(rawRequests, _statusIdMap);
    final allRequests = (processedData['requests'] as List<Map<String, dynamic>>).where((req) => req['productChipId'] != null).toList();

    final List<Map<String, dynamic>> closedRequests = allRequests.where((req) => req['isClosed'] == true).toList();

    final searchedRequests = closedRequests.where((req) {
      if (_searchController.text.isNotEmpty) {
        final search = _searchController.text.toLowerCase();
        return req['id'].toString().toLowerCase().contains(search) ||
            (req['descriptionClean'] ?? '').toString().toLowerCase().contains(search);
      }
      return true;
    }).toList();

    if (mounted) {
      setState(() {
        _supportRecords = searchedRequests;
        _allRequests = allRequests;
        _totalConsumedHours = (processedData['consumedHours'] as num?)?.toDouble() ?? 0.0;
        _inProgressHours = (processedData['inProgressHours'] as num?)?.toDouble() ?? 0.0;
      });
      await _loadContractedHours();
    }
  }

  Future<void> _loadContractedHours() async {
    if (mounted) {
      // Ordenar fichas por fecha de creación (FIFO)
      List<Map<String, dynamic>> sortedChips = List.from(_productChips);
      sortedChips.sort((a, b) {
        final dateA = DateTime.tryParse(a['Created'] ?? '') ?? DateTime(0);
        final dateB = DateTime.tryParse(b['Created'] ?? '') ?? DateTime(0);
        return dateA.compareTo(dateB);
      });

      double totalAcquired = 0.0;
      for (var chip in sortedChips) {
        totalAcquired += (chip['Qty'] as num?)?.toDouble() ?? 0.0;
      }

      // Mapeo de consumo y estimación por ID de ficha vinculada
      final Map<int, double> chipConsumedMap = {};
      final Map<int, double> chipEstimatedMap = {};

      for (var req in _allRequests) {
        final chipId = req['productChipId'] as int?;
        final qty = (req['qtySpent'] as num?)?.toDouble() ?? 0.0;
        final bool isClosed = req['isClosed'] == true;

        if (chipId != null) {
          if (isClosed) {
            chipConsumedMap[chipId] = (chipConsumedMap[chipId] ?? 0.0) + qty;
          } else {
            chipEstimatedMap[chipId] = (chipEstimatedMap[chipId] ?? 0.0) + qty;
          }
        }
        // Las solicitudes sin chipId se ignoran para el resumen global de consumo según instrucción
      }

      // El total consumido global ahora es la suma de los consumos vinculados
      double totalConsumedLinked = chipConsumedMap.values.fold(0.0, (a, b) => a + b);
      double totalEstimatedLinked = chipEstimatedMap.values.fold(0.0, (a, b) => a + b);

      double remainingToDeduct = 0.0; // Ya no hay consumo global FIFO
      double remainingEstimatedToDeduct = 0.0;
      List<Map<String, dynamic>> processed = [];

      for (var chip in sortedChips) {
        final int chipId = chip['id'];
        double totalQty = (chip['Qty'] as num?)?.toDouble() ?? 0.0;

        // Consumo directo vinculado
        double consumedFromThis = chipConsumedMap[chipId] ?? 0.0;
        double estimatedFromThis = chipEstimatedMap[chipId] ?? 0.0;

        // Si hay saldo después del consumo directo, deducir consumo global FIFO
        double remainingCapacity = totalQty - consumedFromThis;
        double additionalConsumption = 0.0;
        double additionalEstimation = 0.0;

        if (remainingToDeduct > 0 && remainingCapacity > 0) {
          if (remainingToDeduct >= remainingCapacity) {
            additionalConsumption = remainingCapacity;
            remainingToDeduct -= remainingCapacity;
            remainingCapacity = 0;
          } else {
            additionalConsumption = remainingToDeduct;
            remainingCapacity -= remainingToDeduct;
            remainingToDeduct = 0;
          }
        }

        if (remainingEstimatedToDeduct > 0 && remainingCapacity > 0) {
          if (remainingEstimatedToDeduct >= remainingCapacity) {
            additionalEstimation = remainingCapacity;
            remainingEstimatedToDeduct -= remainingCapacity;
          } else {
            additionalEstimation = remainingEstimatedToDeduct;
            remainingEstimatedToDeduct = 0;
          }
        }

        double totalConsumed = consumedFromThis + additionalConsumption;
        double totalEstimated = estimatedFromThis + additionalEstimation;

        processed.add({...chip, 'available': totalQty - totalConsumed, 'consumed': totalConsumed, 'estimated': totalEstimated});
      }

      setState(() {
        _contractedHours = totalAcquired;
        _totalConsumedHours = totalConsumedLinked;
        _inProgressHours = totalEstimatedLinked;
        _processedChips = processed;
      });
    }
  }

  List<Map<String, dynamic>> _getFilteredRecords() {
    var filtered = _supportRecords.where((record) {
      if (_searchController.text.isNotEmpty) {
        final search = _searchController.text.toLowerCase();

        final matchId = _searchType == 'all' || _searchType == 'ticket'
            ? (record['id']?.toString().toLowerCase().contains(search) ?? false)
            : false;

        final matchDesc = _searchType == 'all' || _searchType == 'desc'
            ? (record['description']?.toString().toLowerCase().contains(search) ?? false)
            : false;

        if (!matchId && !matchDesc) {
          return false;
        }
      }

      if (_selectedSummaryChipId != null) {
        final chipId = record['productChipId'];
        if (chipId != _selectedSummaryChipId) {
          return false;
        }
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final hasChipA = (a['productChipId'] != null) ? 1 : 0;
      final hasChipB = (b['productChipId'] != null) ? 1 : 0;

      if (hasChipA != hasChipB) {
        return hasChipB.compareTo(hasChipA);
      }

      final timeA = a['time'] ?? '';
      final timeB = b['time'] ?? '';
      return _isAscending ? timeA.compareTo(timeB) : timeB.compareTo(timeA);
    });

    return filtered;
  }

  Future<void> _showYearFilterModal() async {
    final List<int> availableYears = List.generate(10, (i) => DateTime.now().year - i);
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
                  children: [
                    CheckboxListTile(
                      title: const Text('Todos los Años'),
                      value: tempSelection.isEmpty,
                      onChanged: (v) => setDialogState(() => tempSelection.clear()),
                    ),
                    const Divider(),
                    ...availableYears.map((year) {
                      return CheckboxListTile(
                        title: Text(year.toString()),
                        value: tempSelection.contains(year),
                        onChanged: (bool? selected) {
                          setDialogState(() {
                            if (selected == true) tempSelection.add(year);
                            if (selected == false) tempSelection.remove(year);
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancelar')),
                CustomButton(text: 'Aplicar', onPressed: () => Navigator.pop(context, tempSelection)),
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
    _refreshData();
  }

  void _showExportModal() {
    final recordsToExport = _getFilteredRecords();
    if (recordsToExport.isEmpty) {
      ToastMessage.show(context: context, message: AppLocale.noRecordsToExport.getString(context), type: ToastType.help);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => CustomModal(
        title: AppLocale.exportCurrentTable.getString(context),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.grid_on, color: Colors.green),
              title: const Text('Exportar a Excel (XLSX)'),
              onTap: () {
                Navigator.pop(ctx);
                ExportFunctions.exportToExcel(recordsToExport, context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.blue),
              title: const Text('Exportar a CSV'),
              onTap: () {
                Navigator.pop(ctx);
                ExportFunctions.exportToCsv(recordsToExport, context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description, color: Colors.red),
              title: const Text('Exportar a PDF'),
              onTap: () {
                Navigator.pop(ctx);
                ExportFunctions.exportToPdf(recordsToExport, context);
              },
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
      ),
    );
  }

  Future<void> _showBPartnerFilterModal() async {
    if (!AccessControl.isAdmin) return;

    final selectedId = await showDialog<int?>(
      context: context,
      builder: (context) {
        String searchQuery = '';
        List<dynamic> items = [
          {'id': null, 'Name': 'Todos los Terceros'},
          ..._bPartners,
        ];

        return CustomModal(
          title: AppLocale.filterByPartner.getString(context),
          width: 500,
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
              final filteredItems = items.where((item) {
                return (item['Name'] as String).toLowerCase().contains(searchQuery.toLowerCase());
              }).toList();

              return SizedBox(
                height: 400,
                child: Column(
                  children: [
                    CustomTextField(
                      hintText: AppLocale.searchPartner.getString(context),
                      prefixIcon: const Icon(Icons.search),
                      onChanged: (val) => setModalState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          final int? itemValue = item['id'];
                          return ListTile(
                            title: Text(item['Name']),
                            selected: itemValue == _selectedBpId,
                            onTap: () => Navigator.of(context).pop(itemValue),
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
            TextButton(onPressed: () => Navigator.of(context).pop(_selectedBpId), child: Text(AppLocale.cancel.getString(context))),
          ],
        );
      },
    );

    if (selectedId != _selectedBpId) {
      setState(() {
        _selectedBpId = selectedId;
        _isLoading = true;
        _isLoadingChips = true;
      });
      await _initData(); // Re-inicializar todos los datos para el nuevo tercero
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final filteredRecords = _getFilteredRecords();
    final int totalItems = filteredRecords.length;
    final int totalPages = (totalItems / _rowsPerPage).ceil();
    if (_currentPage >= totalPages) {
      _currentPage = totalPages > 0 ? totalPages - 1 : 0;
    }
    final int startIndex = _currentPage * _rowsPerPage;
    final int endIndex = (startIndex + _rowsPerPage < totalItems) ? startIndex + _rowsPerPage : totalItems;
    final paginatedRecords = totalItems > 0 ? filteredRecords.sublist(startIndex, endIndex) : <Map<String, dynamic>>[];

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
        title: Text(AppLocale.supportHoursDashboard.getString(context)),
        actions: [
          if (AccessControl.isAdmin) const AdminModeViews(),
          const HelpIcon(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocale.refresh.getString(context),
            onPressed: () {
              setState(() => _isLoading = true);
              GlobalCache.forceFullSyncWithProgress(context, onSyncAction: _refreshData);
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
      drawer: AccessControl.isAdmin ? const CustomDrawer(currentRoute: '/support') : null,
      bottomNavigationBar: (MediaQuery.of(context).size.width < 900 && !AccessControl.isAdmin)
          ? const ProjectBottomNav(currentRoute: '/support')
          : null,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (MediaQuery.of(context).size.width >= 900 && !AccessControl.isAdmin) const ProjectSideBar(currentRoute: '/support'),
          Expanded(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (AccessControl.isAdmin)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    InkWell(
                                      onTap: (_bPartners.isEmpty || !GlobalCache.isDataLoaded || _isLoadingBPartners)
                                          ? null
                                          : _showBPartnerFilterModal,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(
                                            (_bPartners.isEmpty || !GlobalCache.isDataLoaded || _isLoadingBPartners) ? 0.15 : 0.35,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.business_outlined,
                                              color: (_bPartners.isEmpty || !GlobalCache.isDataLoaded || _isLoadingBPartners)
                                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
                                                  : Theme.of(context).colorScheme.primary,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    AppLocale.partnerToQuery.getString(context),
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          !GlobalCache.isDataLoaded
                                                              ? 'Sincronizando información...'
                                                              : (_isLoadingBPartners
                                                                    ? 'Cargando terceros...'
                                                                    : (_selectedBpId == null
                                                                          ? AppLocale.selectPartner.getString(context)
                                                                          : (_bPartners.firstWhere(
                                                                                  (bp) => bp['id'] == _selectedBpId,
                                                                                  orElse: () => {'Name': 'Tercero Seleccionado'},
                                                                                )['Name'] ??
                                                                                'Tercero $_selectedBpId'))),
                                                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                                            fontWeight: FontWeight.w500,
                                                            color: (!GlobalCache.isDataLoaded || _isLoadingBPartners)
                                                                ? Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)
                                                                : null,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (GlobalCache.isDataLoaded && !_isLoadingBPartners)
                                              Icon(
                                                Icons.search,
                                                color: (_bPartners.isEmpty)
                                                    ? Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)
                                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                              )
                                            else
                                              SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (_isLoadingBPartners || !GlobalCache.isDataLoaded)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: SizedBox(
                                          height: 3,
                                          child: LinearProgressIndicator(
                                            backgroundColor: Colors.transparent,
                                            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Toggle para ver fichas inactivas
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    AppLocale.showInactiveSheets.getString(context),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 4),
                                  Switch(
                                    value: _showInactiveChips,
                                    onChanged: (val) {
                                      setState(() {
                                        _showInactiveChips = val;
                                        _selectedSummaryChipId = null; // Resetear selección
                                      });
                                      _fetchProductChips();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    // --- NUEVA TARJETA DE RESUMEN PREMIUM ---
                    Builder(
                      builder: (context) {
                        double contracted = _contractedHours ?? 0.0;
                        double consumed = _totalConsumedHours;
                        double inProgress = _inProgressHours;
                        double available = contracted - consumed;

                        if (_selectedSummaryChipId != null) {
                          final chip = _processedChips.firstWhere((c) => c['id'] == _selectedSummaryChipId, orElse: () => {});
                          if (chip.isNotEmpty) {
                            contracted = (chip['Qty'] as num?)?.toDouble() ?? 0.0;
                            consumed = (chip['consumed'] as num?)?.toDouble() ?? 0.0;
                            inProgress = (chip['estimated'] as num?)?.toDouble() ?? 0.0;
                            available = (chip['available'] as num?)?.toDouble() ?? 0.0;
                          }
                        } else {
                          available = contracted - consumed;
                        }

                        return SupportSummaryPremium(
                          contractedHours: contracted,
                          consumedHours: consumed,
                          inProgressHours: inProgress,
                          availableHours: available,
                          processedChips: _processedChips,
                          selectedChipId: _selectedSummaryChipId,
                          isLoading: _isLoadingChips,
                          onChipTap: (id) {
                            setState(() {
                              if (_selectedSummaryChipId == id) {
                                _selectedSummaryChipId = null;
                              } else {
                                _selectedSummaryChipId = id;
                              }
                            });
                          },
                          onRefresh: () => _initData(forceSync: true),
                          allowRename: true,
                          emptyMessage: AccessControl.isAdmin && _selectedBpId == null
                              ? (_showInactiveChips
                                    ? 'No hay fichas inactivas en el sistema'
                                    : '(Como administrador) seleccione un tercero para ver sus fichas de producto')
                              : null,
                          attachmentCarousel: (_selectedBpId != null || (!AccessControl.isAdmin && User.cBPartnerID != null))
                              ? BPartnerAttachmentsPreview(bPartnerId: _selectedBpId ?? User.cBPartnerID!)
                              : null,
                        );
                      },
                    ),
                    const SizedBox(height: 30),
                    CustomContainer(
                      title: AppLocale.consumedHoursLog.getString(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SupportDashboardFilterBar(
                            searchController: _searchController,
                            isAscending: _isAscending,
                            rowsPerPage: _rowsPerPage,
                            selectedYears: _selectedYears,
                            onShowYearFilter: _showYearFilterModal,
                            onSortChanged: () => setState(() {
                              _isAscending = !_isAscending;
                              _currentPage = 0;
                            }),
                            onRowsPerPageChanged: (val) => setState(() {
                              _rowsPerPage = val!;
                              _currentPage = 0;
                            }),
                            onClearFilters: () => setState(() {
                              _searchController.clear();
                              _isAscending = false;
                              _currentPage = 0;
                              _selectedYears = [DateTime.now().year];
                              if (AccessControl.isAdmin) _selectedBpId = null;
                              _refreshData();
                            }),
                            onShowBPartnerFilter: _showBPartnerFilterModal,
                            activeFilterCount: _activeFilterCount,
                            selectedBpId: _selectedBpId,
                            searchType: _searchType,
                            onSearchTypeChanged: (val) => setState(() {
                              _searchType = val;
                              _currentPage = 0;
                              _refreshData();
                            }),
                            onExport: _showExportModal,
                          ),
                          const Divider(),
                          // CONTROLES DE PAGINACIÓN (ARRIBA)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  '${totalItems == 0 ? 0 : (_currentPage * _rowsPerPage) + 1} - ${((_currentPage + 1) * _rowsPerPage < totalItems) ? (_currentPage + 1) * _rowsPerPage : totalItems} de $totalItems',
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 16),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.chevron_left),
                                      onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chevron_right),
                                      onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: _isLoading
                                ? const SkeletonTable()
                                : _supportRecords.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(32.0),
                                    child: Center(
                                      child: Text(
                                        'No hay registros de horas consumidas para este filtro.',
                                        style: TextStyle(color: Colors.grey, fontSize: 16),
                                      ),
                                    ),
                                  )
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      if (constraints.maxWidth < 800) {
                                        return _MobileRecordList(
                                          records: paginatedRecords,
                                          onRecordTap: (record) => _showRequestDetails(context, record),
                                        );
                                      } else {
                                        return _DesktopRecordTable(
                                          records: paginatedRecords,
                                          onRecordTap: (record) => _showRequestDetails(context, record),
                                        );
                                      }
                                    },
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
        ],
      ),
    );
  }
}

class _SupportDashboardFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final bool isAscending;
  final int rowsPerPage;
  final List<int> selectedYears;
  final VoidCallback onShowYearFilter;
  final VoidCallback onSortChanged;
  final Function(int?) onRowsPerPageChanged;
  final VoidCallback onClearFilters;
  final VoidCallback onShowBPartnerFilter;
  final int activeFilterCount;
  final int? selectedBpId;

  const _SupportDashboardFilterBar({
    required this.searchController,
    required this.isAscending,
    required this.rowsPerPage,
    required this.selectedYears,
    required this.onShowYearFilter,
    required this.onSortChanged,
    required this.onRowsPerPageChanged,
    required this.onClearFilters,
    required this.onShowBPartnerFilter,
    required this.activeFilterCount,
    this.selectedBpId,
    required this.searchType,
    required this.onSearchTypeChanged,
    required this.onExport,
  });

  final String searchType;
  final ValueChanged<String> onSearchTypeChanged;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isLargeScreen = constraints.maxWidth >= 800;

        if (isLargeScreen) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 2,
                child: CustomTextField(
                  controller: searchController,
                  hintText: searchType == 'ticket'
                      ? AppLocale.searchTicket.getString(context)
                      : (searchType == 'desc'
                            ? AppLocale.searchDescription.getString(context)
                            : AppLocale.searchTicketOrDescription.getString(context)),
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                child: CustomDropdown<String>(
                  value: searchType,
                  items: [
                    DropdownMenuItem(value: 'all', child: Text(AppLocale.both.getString(context))),
                    DropdownMenuItem(value: 'ticket', child: Text('Ticket')),
                    DropdownMenuItem(value: 'desc', child: Text(AppLocale.description.getString(context))),
                  ],
                  onChanged: (val) {
                    if (val != null) onSearchTypeChanged(val);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                flex: 3,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (!AccessControl.isSupport)
                        Padding(
                          padding: const EdgeInsets.only(right: 16.0),
                          child: ActionChip(
                            avatar: const Icon(Icons.calendar_today, size: 16),
                            label: Text(() {
                              if (selectedYears.isEmpty) return 'Año: Todos';
                              if (selectedYears.length == 1) {
                                if (selectedYears.first == DateTime.now().year) {
                                  return 'Año: Actual';
                                }
                                return 'Año: ${selectedYears.first}';
                              }
                              return 'Años: ${selectedYears.length}';
                            }()),
                            onPressed: onShowYearFilter,
                          ),
                        ),
                      ActionChip(
                        avatar: Icon(isAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                        label: Text(isAscending ? AppLocale.oldest.getString(context) : AppLocale.newest.getString(context)),
                        onPressed: onSortChanged,
                      ),
                      const SizedBox(width: 16),
                      DropdownButton<int>(
                        value: rowsPerPage,
                        items: [10, 25, 50, 100]
                            .map(
                              (int value) => DropdownMenuItem<int>(
                                value: value,
                                child: Text(AppLocale.rows.getStringWithVariables(context, {'count': '$value'})),
                              ),
                            )
                            .toList(),
                        onChanged: onRowsPerPageChanged,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.filter_alt_off),
                        onPressed: onClearFilters,
                        tooltip: AppLocale.clearFilters.getString(context),
                      ),
                      const SizedBox(width: 16),
                      CustomButton(text: AppLocale.exportCurrentTable.getString(context), onPressed: onExport, icon: Icons.download),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        // Diseño para móviles
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: CustomTextField(controller: searchController, hintText: AppLocale.searchDots.getString(context), prefixIcon: const Icon(Icons.search)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: CustomDropdown<String>(
                    value: searchType,
                    items: [
                      DropdownMenuItem(value: 'all', child: Text(AppLocale.both.getString(context))),
                      DropdownMenuItem(value: 'ticket', child: Text('Ticket')),
                      DropdownMenuItem(value: 'desc', child: Text('Desc')),
                    ],
                    onChanged: (val) {
                      if (val != null) onSearchTypeChanged(val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!AccessControl.isSupport)
                  ActionChip(
                    avatar: const Icon(Icons.calendar_today, size: 16),
                    label: Text(() {
                      if (selectedYears.isEmpty) return 'Año: Todos';
                      if (selectedYears.length == 1) {
                        if (selectedYears.first == DateTime.now().year) {
                          return 'Año: Actual';
                        }
                        return 'Año: ${selectedYears.first}';
                      }
                      return 'Años: ${selectedYears.length}';
                    }()),
                    onPressed: onShowYearFilter,
                  ),
                ActionChip(
                  avatar: Icon(isAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                  label: Text(isAscending ? AppLocale.oldest.getString(context) : AppLocale.newest.getString(context)),
                  onPressed: onSortChanged,
                ),
                DropdownButton<int>(
                  value: rowsPerPage,
                  items: [10, 25, 50, 100]
                      .map(
                        (int value) => DropdownMenuItem<int>(
                          value: value,
                          child: Text(AppLocale.rows.getStringWithVariables(context, {'count': '$value'})),
                        ),
                      )
                      .toList(),
                  onChanged: onRowsPerPageChanged,
                ),
                IconButton(
                  icon: const Icon(Icons.filter_alt_off),
                  onPressed: onClearFilters,
                  tooltip: AppLocale.clearFilters.getString(context),
                ),
                CustomButton(text: AppLocale.export.getString(context), onPressed: onExport, icon: Icons.download),
              ],
            ),
          ],
        );
      },
    );
  }
}

void _showRequestDetails(BuildContext context, Map<String, dynamic> record) {
  final double h = (record['qtySpent'] as num?)?.toDouble() ?? 0.0;
  final qtyPlanController = TextEditingController(text: DurationFormatter.format(h));

  showDialog(
    context: context,
    builder: (context) => CustomModal(
      title: 'Detalle del Ticket ${record['id']}',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomTextField(
              controller: TextEditingController(text: record['descriptionClean'] ?? ''),
              label: AppLocale.description.getString(context),
              readOnly: true,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: TextEditingController(text: record['dateStartPlan'] ?? ''),
              label: AppLocale.closingDateLabel.getString(context),
              readOnly: true,
              prefixIcon: const Icon(Icons.calendar_today),
            ),
            const SizedBox(height: 16),
            CustomTextField(controller: qtyPlanController, label: AppLocale.consumedHours.getString(context), readOnly: true),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocale.close.getString(context)))],
    ),
  );
}

class _DesktopRecordTable extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final Function(Map<String, dynamic>) onRecordTap;

  const _DesktopRecordTable({required this.records, required this.onRecordTap});

  @override
  Widget build(BuildContext context) {
    return CustomTable(
      columns: [
        const DataColumn(label: Text('Ticket')),
        DataColumn(label: Text(AppLocale.description.getString(context))),
        DataColumn(label: Text(AppLocale.status.getString(context))),
        DataColumn(label: Text(AppLocale.consumedHours.getString(context))),
        DataColumn(label: Text(AppLocale.productSheet.getString(context))),
      ],
      rows: records.map((record) {
        final double h = (record['qtySpent'] as num?)?.toDouble() ?? 0.0;
        final hours = DurationFormatter.format(h);
        return DataRow(
          onSelectChanged: (value) => onRecordTap(record),
          cells: [
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedCopyWidget(
                    textToCopy: record['id']?.toString() ?? '',
                    snackBarMessage: AppLocale.codeCopied.getString(context),
                    leadingText: Text(record['id']?.toString() ?? ''),
                    iconSize: 16,
                  ),
                ],
              ),
            ),
            DataCell(
              Tooltip(
                message: record['descriptionClean'] ?? '',
                waitDuration: const Duration(milliseconds: 500),
                child: SizedBox(width: 300, child: Text(record['descriptionClean'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis)),
              ),
            ),
            DataCell(Text(record['status'] ?? '')),
            DataCell(Text(hours, style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(
              Text(() {
                final chipId = record['productChipId'];
                if (chipId == null) return 'N/A';
                final found = GlobalCache.productChips.firstWhere((c) => c['id'] == chipId, orElse: () => {});
                if (found.isEmpty) return '#$chipId';
                return found['Description'] ?? found['Name'] ?? '#$chipId';
              }()),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _MobileRecordList extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final Function(Map<String, dynamic>) onRecordTap;

  const _MobileRecordList({required this.records, required this.onRecordTap});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        return _SupportRecordCard(record: record, onTap: () => onRecordTap(record));
      },
    );
  }
}

class _SupportRecordCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final VoidCallback onTap;

  const _SupportRecordCard({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final double h = (record['qtySpent'] as num?)?.toDouble() ?? 0.0;
    final hours = DurationFormatter.format(h);
    final subject = record['descriptionClean'] ?? 'Sin descripción';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ticket #${record['id']}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
              ),
              if (AccessControl.isAdmin) ...[
                const SizedBox(height: 8),
                Text(subject, style: theme.textTheme.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    record['status'] ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                  Chip(
                    label: Text(hours),
                    avatar: Icon(Icons.timer_outlined, size: 16, color: colorScheme.secondary),
                    backgroundColor: colorScheme.secondaryContainer.withOpacity(0.5),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BPartnerAttachmentsDialog extends StatefulWidget {
  final int bPartnerId;

  const BPartnerAttachmentsDialog({super.key, required this.bPartnerId});

  @override
  State<BPartnerAttachmentsDialog> createState() => _BPartnerAttachmentsDialogState();
}

class _BPartnerAttachmentsDialogState extends State<BPartnerAttachmentsDialog> {
  List<Map<String, dynamic>> _attachments = [];
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  Future<void> _loadAttachments() async {
    setState(() => _isLoading = true);
    const tableName = 'C_BPartner';
    final String fullTableUrl = '${Endpoint.baseUrl}/api/v1/models/$tableName';
    final attachments = await fetchAttachments(recordID: widget.bPartnerId, tableName: fullTableUrl);
    if (mounted) {
      setState(() {
        _attachments = attachments;
        _isLoading = false;
      });
    }
  }

  Future<void> _uploadAttachment() async {
    if (!AccessControl.isAdmin) {
      ToastMessage.show(context: context, message: AppLocale.noPermissionUploadFiles.getString(context), type: ToastType.help);
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      ToastMessage.show(context: context, message: AppLocale.fileReadError.getString(context), type: ToastType.failure);
      return;
    }

    setState(() => _isUploading = true);

    const tableName = 'C_BPartner';
    final String fullTableUrl = '${Endpoint.baseUrl}/api/v1/models/$tableName';

    final convertedFile = {'title': file.name, 'base64': base64Encode(file.bytes!)};

    final success = await postAttachments(
      recordID: widget.bPartnerId,
      tableName: fullTableUrl,
      convertedFile: convertedFile,
      shouldUpdateStatus: false,
    );

    if (mounted) {
      setState(() => _isUploading = false);
      if (success) {
        ToastMessage.show(context: context, message: AppLocale.fileUploadSuccess.getString(context), type: ToastType.success);
        _loadAttachments();
      } else {
        ToastMessage.show(context: context, message: AppLocale.fileUploadError.getString(context), type: ToastType.failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const tableName = 'C_BPartner';
    final String fullTableUrl = '${Endpoint.baseUrl}/api/v1/models/$tableName';

    return CustomModal(
      title: 'Adjuntos del Tercero',
      width: 500,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_attachments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Center(child: Text('No hay archivos adjuntos para este tercero.')),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              itemCount: _attachments.length,
              itemBuilder: (context, index) {
                final att = _attachments[index];
                return ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: Text(att['name'] ?? 'Sin nombre'),
                  onTap: () {
                    FilePreviewManager.showPreview(
                      context,
                      {'id': widget.bPartnerId, 'Status': 'N/A', 'VersionNo': 'N/A'},
                      fullTableUrl,
                      att['name'] ?? '',
                      () async {
                        if (!AccessControl.isAdmin) {
                          ToastMessage.show(context: context, message: AppLocale.noPermissionDeleteAttachments.getString(context), type: ToastType.help);
                          return;
                        }

                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => CustomModal(
                            title: 'Eliminar Archivo',
                            content: Text('¿Estás seguro de que deseas eliminar "${att['name'] ?? ''}"?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                              CustomButton(text: 'Eliminar', backgroundColor: Colors.red, onPressed: () => Navigator.pop(ctx, true)),
                            ],
                          ),
                        );

                        if (confirm != true) return;

                        try {
                          setState(() => _isLoading = true);
                          final url = Uri.parse('$fullTableUrl/${widget.bPartnerId}/attachments/${Uri.encodeComponent(att['name'] ?? '')}');
                          final response = await http.delete(url, headers: {'Authorization': Token.token});
                          if (response.statusCode == 200 || response.statusCode == 204) {
                            if (mounted) {
                              setState(() {
                                _attachments.removeWhere((item) => item['name'] == att['name']);
                                _isLoading = false;
                              });
                              ToastMessage.show(context: context, message: AppLocale.attachmentDeleted.getString(context), type: ToastType.help);
                              // _loadAttachments(); // Removed to avoid stale cache issues
                            }
                          } else {
                            if (mounted) {
                              setState(() => _isLoading = false);
                              ToastMessage.show(context: context, message: AppLocale.attachmentDeleteError.getString(context), type: ToastType.failure);
                            }
                          }
                        } catch (e) {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                      () {},
                      canDelete: AccessControl.isAdmin,
                    );
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.download, color: Color(0xFF4F47E5)),
                    tooltip: AppLocale.download.getString(context),
                    onPressed: () =>
                        downloadAttachment(context: context, recordID: widget.bPartnerId, tableName: fullTableUrl, fileName: att['name']),
                  ),
                );
              },
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        if (AccessControl.isAdmin)
          CustomButton(text: 'Subir Archivo', icon: Icons.upload_file, isLoading: _isUploading, onPressed: _uploadAttachment),
      ],
    );
  }
}
