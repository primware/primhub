import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/api/access_control.dart';

import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_skeleton.dart';
import 'package:primhub/ui/Shared_Custom/treemap_filter_bar.dart';
import 'package:primhub/ui/Shared_Custom/request_mobile_card.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart' as request_functions;
import 'package:treemap/treemap.dart';

class ClientWorkloadPage extends StatefulWidget {
  const ClientWorkloadPage({super.key});

  @override
  State<ClientWorkloadPage> createState() => _ClientWorkloadPageState();
}

class _ClientWorkloadPageState extends State<ClientWorkloadPage> {
  bool _isLoading = true;
  String _timeFilter = 'all'; // all, this_week, next_15_days, this_month
  
  int? _selectedBpId;
  List<Map<String, dynamic>> _availableBps = [];
  
  // Datos agrupados por Tercero
  // Formato: { "Nombre del Tercero": [ request1, request2... ] }
  Map<String, List<Map<String, dynamic>>> _groupedRequests = {};
  List<String> _sortedBps = [];
  
  String? _selectedSalesRep;
  List<String> _availableReps = [];
  
  int? _selectedProjectId;
  List<Map<String, dynamic>> _availableProjects = [];
  
  int? _selectedChipId;
  String? _selectedRequestCategory;
  List<String> _availableCategories = [];
  
  final Map<String, Color> _assignedColors = {};
  int _nextColorIndex = 0;

  final List<Color> repColors = [
    Colors.deepPurple, Colors.blue.shade700, Colors.teal, 
    Colors.orange.shade700, Colors.pink, Colors.indigo, 
    Colors.brown, Colors.cyan.shade700, Colors.red.shade700,
    Colors.green.shade700
  ];

  @override
  void initState() {
    super.initState();
    if (!AccessControl.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/');
      });
      return;
    }
    _loadData();
    GlobalCache.backgroundSyncNotifier.addListener(_onSyncChanged);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GlobalCache.performSmartSync(context, () async {
        if (mounted) _loadData();
      });
    });
  }

  @override
  void dispose() {
    GlobalCache.backgroundSyncNotifier.removeListener(_onSyncChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    if (mounted) _loadData();
  }

  void _openTreemapNodeModal({
    required BuildContext context,
    required String title,
    required List<Map<String, dynamic>> rawRequests,
    required Map<String, dynamic> extras,
  }) async {
    showDialog(
       context: context, 
       barrierDismissible: false,
       builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    
    final result = await request_functions.processRequests(rawRequests, GlobalCache.statuses);
    final mappedRequests = List<Map<String, dynamic>>.from(result['requests']);
    
    if (!mounted) return;
    Navigator.pop(context); // Quitar indicador de carga

    showDialog(
      context: context,
      builder: (context) => CustomModal(
        title: title,
        width: 600,
        height: MediaQuery.of(context).size.height * 0.8,
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                AppLocale.showingRequestsFrom.getStringWithVariables(context, {'count': '${mappedRequests.length}', 'source': title}),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            ...mappedRequests.map((req) => RequestMobileCard(
                  request: req,
                  onEdit: (r) {
                    Navigator.pop(context);
                    final pushExtras = Map<String, dynamic>.from(extras);
                    pushExtras['metrics_source'] = '/client-workload';
                    if (req['id'] != null) pushExtras['search'] = req['id'].toString();
                    if (req['isClosed'] == true) pushExtras['showHistory'] = true;
                    context.pushReplacement('/my-requests', extra: pushExtras);
                  },
                  onGoToUpdates: () {
                    Navigator.pop(context);
                    final pushExtras = Map<String, dynamic>.from(extras);
                    pushExtras['metrics_source'] = '/client-workload';
                    if (req['id'] != null) pushExtras['search'] = req['id'].toString();
                    if (req['isClosed'] == true) pushExtras['showHistory'] = true;
                    context.pushReplacement('/my-requests', extra: pushExtras);
                  },
                  onShowAttachments: () {
                    Navigator.pop(context);
                    final pushExtras = Map<String, dynamic>.from(extras);
                    pushExtras['metrics_source'] = '/client-workload';
                    if (req['id'] != null) pushExtras['search'] = req['id'].toString();
                    if (req['isClosed'] == true) pushExtras['showHistory'] = true;
                    context.pushReplacement('/my-requests', extra: pushExtras);
                  },
                  isReadOnly: true,
                )),
          ],
        ),
        actions: [
          CustomButton(
            text: AppLocale.close.getString(context),
            backgroundColor: Colors.grey.shade600,
            onPressed: () => Navigator.pop(context),
          ),
          CustomButton(
            text: AppLocale.expandToRequests.getString(context),
            icon: Icons.open_in_new,
            onPressed: () {
              Navigator.pop(context);
              final pushExtras = Map<String, dynamic>.from(extras);
              pushExtras['metrics_source'] = '/client-workload';
              context.pushReplacement('/my-requests', extra: pushExtras);
            },
          ),
        ],
      ),
    );
  }

  void _loadData() {
    setState(() => _isLoading = true);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    DateTime? minDate;
    DateTime? maxDate;

    if (_timeFilter == 'this_week') {
      final currentWeekday = today.weekday;
      minDate = today.subtract(Duration(days: currentWeekday - 1));
      maxDate = minDate.add(const Duration(days: 6));
    } else if (_timeFilter == 'this_month') {
      minDate = DateTime(today.year, today.month, 1);
      maxDate = DateTime(today.year, today.month + 1, 0);
    } else if (_timeFilter == 'next_15_days') {
      final currentWeekday = today.weekday;
      minDate = today.subtract(Duration(days: currentWeekday - 1));
      maxDate = minDate.add(const Duration(days: 13));
    }

    final rawRequests = GlobalCache.requests;
    Map<String, List<Map<String, dynamic>>> tempGrouped = {};

    for (var req in rawRequests) {
      // Filtrar siempre por el año actual
      String? createdStr = req['Created'] ?? req['DateStartPlan'] ?? req['StartDate'];
      if (createdStr != null && createdStr.length >= 4) {
        final year = int.tryParse(createdStr.substring(0, 4));
        if (year != now.year) continue;
      }
      int statusId = -1;
      final statusObj = req['R_Status_ID'];
      bool isOpen = false;
      String statusStr = (req['status'] ?? req['R_Status_Name'] ?? '').toString().toLowerCase();
      
      if (statusObj is Map) {
         statusId = (statusObj['id'] as num?)?.toInt() ?? -1;
         statusStr = (statusObj['Name'] ?? statusObj['identifier'] ?? statusStr).toString().toLowerCase();
         final rawIsOpen = statusObj['IsOpen'];
         final isOpenStr = rawIsOpen?.toString().trim().toLowerCase();
         if (rawIsOpen != null) {
            isOpen = isOpenStr == 'true' || isOpenStr == 'y' || rawIsOpen == true;
         } else {
            isOpen = GlobalCache.statusIsOpenMap[statusId] ?? false;
         }
      } else if (statusObj is num) {
         statusId = statusObj.toInt();
         statusStr = GlobalCache.statuses.keys.firstWhere((k) => GlobalCache.statuses[k] == statusObj, orElse: () => statusStr).toLowerCase();
         isOpen = GlobalCache.statusIsOpenMap[statusId] ?? false;
      } else if (statusObj == null && req['status'] != null) {
         statusId = GlobalCache.statuses[req['status']] ?? -1;
         isOpen = GlobalCache.statusIsOpenMap[statusId] ?? false;
      }
      
      if (!isOpen) {
        continue;
      }

      // Filtrar por fecha (Filtro superior)
      bool passDate = true;
      if (minDate != null && maxDate != null) {
        String? startStr = req['DateStartPlan'] ?? req['StartDate'] ?? req['Created'];
        if (startStr != null && startStr.isNotEmpty) {
          DateTime? reqDate = DateTime.tryParse(startStr.replaceAll(' ', 'T'));
          if (reqDate != null) {
            reqDate = DateTime(reqDate.year, reqDate.month, reqDate.day);
            if (reqDate.isBefore(minDate) || reqDate.isAfter(maxDate)) {
              passDate = false;
            }
          }
        }
      }
      if (!passDate) continue;

      // Filtrar por Tercero
      if (_selectedBpId != null) {
        final bpData = req['C_BPartner_ID'];
        int? reqBpId;
        if (bpData is Map) {
          reqBpId = (bpData['id'] as num?)?.toInt();
        } else if (bpData is num) {
          reqBpId = bpData.toInt();
        }
        if (reqBpId != _selectedBpId) {
          continue;
        }
      }

      // Agrupar por Representante
      final repData = req['SalesRep_ID'];
      String repName = '';
      if (repData is Map) {
        repName = (repData['Name'] ?? repData['identifier'] ?? '').toString().trim();
      } else if (repData != null) {
        final found = GlobalCache.users.where((u) => u['id'] == repData).toList();
        if (found.isNotEmpty) {
           repName = (found.first['Name'] ?? '').toString().trim();
        } else {
           final foundRep = GlobalCache.salesReps.where((r) => r['id'] == repData).toList();
           if (foundRep.isNotEmpty) {
              repName = (foundRep.first['Name'] ?? '').toString().trim();
           }
        }
      }
      
      if (repName.isEmpty) repName = 'Sin Asignar';

      // Filtro por Representante Comercial
      if (_selectedSalesRep != null && _selectedSalesRep != 'Todos' && repName != _selectedSalesRep) {
        continue;
      }

      // Filtrar por Ficha de Producto
      if (_selectedChipId != null) {
        final chipData = req['T_ProductChip_ID'];
        int? reqChipId;
        if (chipData is Map) {
          reqChipId = (chipData['id'] as num?)?.toInt();
        } else if (chipData is num) {
          reqChipId = chipData.toInt();
        }
        if (reqChipId != _selectedChipId) {
          continue;
        }
      }

      // Filtrar por Categoría de Solicitud (Soporte, Proyecto, Otras)
      if (_selectedRequestCategory != null && _selectedRequestCategory != 'Todas') {
        int statusId = -1;
        final statusObj = req['R_Status_ID'];
        if (statusObj is Map) {
          statusId = (statusObj['id'] as num?)?.toInt() ?? -1;
        } else if (statusObj is num) {
          statusId = statusObj.toInt();
        } else if (statusObj == null && req['status'] != null) {
           statusId = GlobalCache.statuses[req['status']] ?? -1;
        }

        int? statusCat = GlobalCache.statusCategoryMap[statusId];
        String rawCatName = statusCat != null 
             ? (GlobalCache.statusCategoryNameMap[statusCat] ?? '') 
             : '';

        String reqCatName = 'Otras Solicitudes';
        String rawLower = rawCatName.toLowerCase();
        
        if (rawLower.contains('soporte tecnico') || rawLower.contains('soporte técnico')) {
           reqCatName = 'Soporte Técnico';
        } else if (rawLower.contains('post venta') || rawLower.contains('post-venta')) {
           reqCatName = 'Solicitudes de Proyecto';
        }

        if (reqCatName != _selectedRequestCategory) {
          continue;
        }
      }

      // Filtrar por Proyecto
      if (_selectedProjectId != null) {
        final projData = req['C_Project_ID'];
        int? reqProjId;
        if (projData is Map) {
          reqProjId = (projData['id'] as num?)?.toInt();
        } else if (projData is num) {
          reqProjId = projData.toInt();
        }
        if (reqProjId != _selectedProjectId) {
          continue;
        }
      }

      final bpData = req['C_BPartner_ID'];
      final bpName = bpData is Map ? (bpData['identifier'] ?? bpData['Name'] ?? 'Sin Tercero').toString() : 'Sin Tercero';

      if (!tempGrouped.containsKey(bpName)) {
        tempGrouped[bpName] = [];
      }
      tempGrouped[bpName]!.add(req);
    }

    // Actualizar lista de terceros disponibles para el filtro

    if (_availableReps.isEmpty) {
      Set<String> repsSet = {};
      for (var rep in GlobalCache.salesReps) {
        String repN = (rep['Name'] ?? rep['identifier'] ?? '').toString().trim();
        if (repN.isNotEmpty) {
          repsSet.add(repN);
        }
      }
      _availableReps = ['Todos', ...repsSet];
      _availableReps.sort((a, b) {
        if (a == 'Todos') return -1;
        if (b == 'Todos') return 1;
        return a.compareTo(b);
      });
    }
    
    _availableBps = List<Map<String, dynamic>>.from(GlobalCache.bPartners);
    _availableProjects = List<Map<String, dynamic>>.from(GlobalCache.projects);
    
    // Categorías disponibles fijas según lógica de Primhub
    _availableCategories = ['Todas', 'Soporte Técnico', 'Solicitudes de Proyecto', 'Otras Solicitudes'];
    
    // Ordenar terceros disponibles (opcional)
    _availableBps.sort((a, b) {
      String nameA = (a['Name'] ?? a['identifier'] ?? '').toString().toLowerCase();
      String nameB = (b['Name'] ?? b['identifier'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    List<String> bps = tempGrouped.keys.toList();
    bps.sort((a, b) {
      if (a == 'Sin Tercero') return 1;
      if (b == 'Sin Tercero') return -1;
      return tempGrouped[b]!.length.compareTo(tempGrouped[a]!.length);
    });

    // Asignar colores de manera secuencial para una distribución perfecta
    for (var bp in bps) {
      if (!_assignedColors.containsKey(bp)) {
        _assignedColors[bp] = repColors[_nextColorIndex % repColors.length];
        _nextColorIndex++;
      }
    }

    if (mounted) {
      setState(() {
        _groupedRequests = tempGrouped;
        _sortedBps = bps;
        _isLoading = false;
      });
    }
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;


    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: AppLocale.back.getString(context),
            onPressed: () => context.go('/metrics'),
          ),
        ),
        title: Text(AppLocale.partnerWorkload.getString(context)),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            tooltip: AppLocale.treemapInformation.getString(context),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => CustomModal(
                  title: AppLocale.treemapInformation.getString(context),
                  width: 500,
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocale.treemapIntro.getString(context), style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 16),
                      Text(AppLocale.features.getString(context), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      ListTile(
                        leading: const Icon(Icons.group_rounded, color: Colors.deepPurple),
                        title: Text(AppLocale.filterByPartnerFeature.getString(context)),
                        subtitle: Text(AppLocale.filterByPartnerFeatureHelp.getString(context)),
                        contentPadding: EdgeInsets.zero,
                      ),
                      ListTile(
                        leading: const Icon(Icons.filter_alt_rounded, color: Colors.deepPurple),
                        title: Text(AppLocale.filterByRepresentativeFeature.getString(context)),
                        subtitle: Text(AppLocale.filterByRepresentativeFeatureHelp.getString(context)),
                        contentPadding: EdgeInsets.zero,
                      ),
                      ListTile(
                        leading: const Icon(Icons.article_rounded, color: Colors.deepPurple),
                        title: Text(AppLocale.requestDetail.getString(context)),
                        subtitle: Text(AppLocale.requestDetailHelp.getString(context)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  actions: [
                    CustomButton(
                      text: 'Entendido',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refrescar',
            onPressed: () {
              setState(() => _isLoading = true);
              GlobalCache.forceFullSyncWithProgress(context, onSyncAction: () async {
                _loadData();
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isMobile = constraints.maxWidth < 800;
            
            Widget treemapBoard = (!GlobalCache.isFullyLoaded || _isLoading)
                ? Padding(
                    padding: const EdgeInsets.all(24.0).copyWith(top: 8.0),
                    child: const CustomSkeleton(),
                  )
                      : _sortedBps.isEmpty
                          ? Center(child: Text(AppLocale.noRequestsWithCurrentFilters.getString(context)))
                          : Padding(
                              padding: const EdgeInsets.all(24.0).copyWith(top: 8.0),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  List<TreeNode> bpNodes = [];
                                  
                                  for (String bp in _sortedBps) {
                                    final requests = _groupedRequests[bp]!;
                                    if (requests.isEmpty) continue;
                                    
                                    // Agrupar por Representante (Sales Rep) dentro de este Tercero
                                    Map<String, int> repCounts = {};
                                    Map<String, int?> repIds = {};
                                    for (var req in requests) {
                                      final repData = req['SalesRep_ID'];
                                      String repN = '';
                                      int? rId;
                                      if (repData is Map) {
                                        repN = (repData['Name'] ?? repData['identifier'] ?? '').toString().trim();
                                        rId = (repData['id'] as num?)?.toInt();
                                      } else if (repData != null) {
                                        rId = (repData as num).toInt();
                                        final found = GlobalCache.users.where((u) => u['id'] == repData).toList();
                                        if (found.isNotEmpty) {
                                           repN = (found.first['Name'] ?? '').toString().trim();
                                        } else {
                                           final foundRep = GlobalCache.salesReps.where((r) => r['id'] == repData).toList();
                                           if (foundRep.isNotEmpty) {
                                              repN = (foundRep.first['Name'] ?? '').toString().trim();
                                           }
                                        }
                                      }
                                      if (repN.isEmpty) repN = 'Sin Asignar';
                                      
                                      repCounts[repN] = (repCounts[repN] ?? 0) + 1;
                                      
                                      if (!repIds.containsKey(repN)) {
                                        repIds[repN] = rId;
                                      }
                                    }
                                    
                                    Color baseColor = _assignedColors[bp] ?? repColors[0];
                                    
                                    List<TreeNode> repInnerNodes = [];
                                    repCounts.forEach((repNameInner, count) {
                                      repInnerNodes.add(
                                        TreeNode.leaf(
                                          value: count,
                                          margin: const EdgeInsets.all(2), // Margen entre reps del mismo cliente
                                          options: TreeNodeOptions(
                                            color: baseColor,
                                            border: Border.all(color: Colors.black12, width: 1),
                                            onTap: () {
                                              int? bpId;
                                              if (requests.isNotEmpty) {
                                                final bpData = requests.first['C_BPartner_ID'];
                                                if (bpData is Map) {
                                                  bpId = (bpData['id'] as num?)?.toInt();
                                                } else if (bpData != null) {
                                                  bpId = (bpData as num).toInt();
                                                }
                                              }

                                              final extras = <String, dynamic>{};
                                              if (bpId != null) extras['bpId'] = bpId;
                                              if (repIds[repNameInner] != null) extras['salesRepId'] = repIds[repNameInner];
                                              
                                              _openTreemapNodeModal(
                                                context: context,
                                                title: '${AppLocale.client.getString(context)}: $bp, ${AppLocale.representativeShort.getString(context)}: $repNameInner',
                                                rawRequests: requests.where((r) {
                                                   final repData = r['SalesRep_ID'];
                                                   final rRepName = repData is Map ? (repData['Name'] ?? repData['identifier'] ?? 'Sin Asignar').toString() : 'Sin Asignar';
                                                   return rRepName == repNameInner;
                                                }).toList(),
                                                extras: extras,
                                              );
                                            },
                                            child: Tooltip(
                                              message: 'Cliente: $bp\nRepresentante: $repNameInner\nSolicitudes: $count',
                                              child: LayoutBuilder(
                                                builder: (context, constraints) {
                                                  // Si el recuadro es microscópico, no intentamos dibujar texto
                                                  if (constraints.maxHeight < 30 || constraints.maxWidth < 30) {
                                                    return const SizedBox.shrink();
                                                  }
                                                  // Si es mediano/pequeño, solo mostramos el número o limitamos el texto
                                                  final bool isSmall = constraints.maxHeight < 60;
                                                  
                                                  return Container(
                                                    padding: const EdgeInsets.all(4),
                                                    alignment: Alignment.center,
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        if (!isSmall)
                                                          Flexible(
                                                            child: Text(
                                                              repNameInner, 
                                                              style: const TextStyle(
                                                                color: Colors.white, 
                                                                fontSize: 11, 
                                                                fontWeight: FontWeight.w600, // SemiBold para mejor lectura
                                                                shadows: [Shadow(blurRadius: 2, color: Colors.black54)]
                                                              ), 
                                                              textAlign: TextAlign.center, 
                                                              maxLines: constraints.maxHeight < 90 ? 2 : 3, 
                                                              overflow: TextOverflow.ellipsis
                                                            ),
                                                          ),
                                                        if (!isSmall) const SizedBox(height: 4),
                                                        Text(
                                                          '$count', 
                                                          style: TextStyle(
                                                            color: Colors.white, 
                                                            fontSize: isSmall ? 12 : 16, 
                                                            fontWeight: FontWeight.w800, // Bold fuerte para el número
                                                            shadows: const [Shadow(blurRadius: 2, color: Colors.black54)]
                                                          )
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }
                                              ),
                                            ),
                                          ),
                                        )
                                      );
                                    });
                                    
                                    if (repInnerNodes.isNotEmpty) {
                                      bpNodes.add(
                                        TreeNode.node(
                                          children: repInnerNodes,
                                          margin: const EdgeInsets.all(4), // Margen exterior entre bloques
                                          padding: const EdgeInsets.only(top: 24), // Padding interior para el título
                                          options: TreeNodeOptions(
                                            color: Colors.transparent,
                                            border: Border.all(color: Colors.white24, width: 1),
                                            child: Align(
                                              alignment: Alignment.topLeft,
                                              child: Container(
                                                height: 24,
                                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                                alignment: Alignment.centerLeft,
                                                color: baseColor, // Usar el mismo color del bloque para la pestaña
                                                child: LayoutBuilder(
                                                  builder: (context, constraints) {
                                                    if (constraints.maxWidth < 40) return const SizedBox.shrink();
                                                    return Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            '$bp (${requests.length})',
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontWeight: FontWeight.w600,
                                                              fontSize: 12,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        InkWell(
                                                          onTap: () {
                                                            int? groupBpId;
                                                            if (requests.isNotEmpty) {
                                                              final bpData = requests.first['C_BPartner_ID'];
                                                              if (bpData is Map) {
                                                                groupBpId = (bpData['id'] as num?)?.toInt();
                                                              } else if (bpData != null) {
                                                                groupBpId = (bpData as num).toInt();
                                                              }
                                                            }
                                                            _openTreemapNodeModal(
                                                              context: context,
                                                              title: 'Solicitudes: $bp',
                                                              rawRequests: requests,
                                                              extras: {
                                                                'bpId': groupBpId,
                                                                'from_metrics': true
                                                              },
                                                            );
                                                          },
                                                          child: const Padding(
                                                            padding: EdgeInsets.only(left: 4.0),
                                                            child: Icon(Icons.open_in_new, color: Colors.white, size: 14),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  }
                                                ),
                                              ), // Container
                                            ), // Align
                                          ) // TreeNodeOptions
                                        ) // TreeNode.node
                                      );
                                    }
                                  }

                                  if (bpNodes.isEmpty) {
                                    return Center(child: Text(AppLocale.noDataForTreemap.getString(context)));
                                  }

                                  return TreeMapLayout(
                                    tile: const Squarify(),
                                    children: bpNodes,
                                  );
                                },
                              ),
                            );

            Widget content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: TreemapFilterBar(
                    selectedBpId: _selectedBpId,
                    selectedProjectId: _selectedProjectId,
                    selectedSalesRep: _selectedSalesRep,
                    selectedChipId: _selectedChipId,
                    selectedRequestCategory: _selectedRequestCategory,
                    timeFilter: _timeFilter,
                    availableBps: _availableBps,
                    availableProjects: _availableProjects,
                    availableReps: _availableReps,
                    availableCategories: _availableCategories,
                    totalCount: _groupedRequests.values.fold<int>(0, (sum, list) => sum + list.length),
                    totalHours: _groupedRequests.values.fold<double>(0.0, (sum, list) {
                       return sum + list.fold<double>(0.0, (reqSum, req) {
                         final val = req['PrimHub_Estimated_development_hours'];
                         return reqSum + ((val as num?)?.toDouble() ?? 0.0);
                       });
                    }),
                    onBpSelected: (val) {
                      if (val != null) {
                        setState(() => _selectedBpId = val == -1 ? null : val);
                        _loadData();
                      }
                    },
                    onProjectSelected: (val) {
                      if (val != null) {
                        setState(() => _selectedProjectId = val == -1 ? null : val);
                        _loadData();
                      }
                    },
                    onRepSelected: (val) {
                      if (val != null) {
                        setState(() => _selectedSalesRep = val == 'Todos' ? null : val);
                        _loadData();
                      }
                    },
                    onChipSelected: (val) {
                      setState(() => _selectedChipId = val);
                      _loadData();
                    },
                    onCategorySelected: (val) {
                      if (val != null) {
                        setState(() => _selectedRequestCategory = val == 'Todas' ? null : val);
                        _loadData();
                      }
                    },
                    onTimeFilterChanged: (val) {
                      setState(() => _timeFilter = val);
                      _loadData();
                    },
                    onClearFilters: () {
                      setState(() {
                        _selectedBpId = null;
                        _selectedProjectId = null;
                        _selectedChipId = null;
                        _selectedRequestCategory = null;
                        _selectedSalesRep = null;
                      });
                      _loadData();
                    },
                  ),
                ),
                isMobile ? SizedBox(height: 800, child: treemapBoard) : Expanded(child: treemapBoard),
              ],
            );

            return isMobile ? SingleChildScrollView(child: content) : content;
          },
        ),
      ),
    );
  }
}
