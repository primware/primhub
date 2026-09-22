import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:primhub/api/api_http.dart' as http;
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/api/admin_view_mode.dart';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart';
import 'package:primhub/api/access_control.dart';

import 'package:primhub/api/global_cache.dart';

class HomeController extends ChangeNotifier {
  bool isLoading = true;
  bool validationLoading = true;
  bool _isDisposed = false;


  String username = '';
  int? cBPartnerID;
  String? partnerName;
  String? projectPartnerName;

  bool hasSupport = false;
  bool hasProject = false;

  List<dynamic> projects = [];
  List<int> selectedProjectIds = [];
  Map<int, Map<String, dynamic>> projectStats = {};

  List<Map<String, dynamic>> recentRequests = [];
  List<dynamic> allRequests = [];
  Map<int, Map<String, dynamic>> requestsStatsByBp = {};

  List<Map<String, dynamic>> supportProductChips = [];

  List<Map<String, dynamic>> supportBPartners = [];
  List<int> selectedSupportBpIds = [];

  static List<int> savedSelectedProjectIds = [];
  static List<int> savedSelectedSupportBpIds = [];

  HomeController() {
    selectedProjectIds = List.from(savedSelectedProjectIds);
    selectedSupportBpIds = List.from(savedSelectedSupportBpIds);
    _loadCurrentUser();
    GlobalCache.backgroundSyncNotifier.addListener(_onBackgroundSyncChanged);
  }

  @override
  void dispose() {
    GlobalCache.backgroundSyncNotifier.removeListener(_onBackgroundSyncChanged);
    _isDisposed = true;
    super.dispose();
  }

  bool get isSyncingBackground => isLoading;

  void _onBackgroundSyncChanged() async {
    await loadRecentRequests();
    await loadSupportProductChips();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  void _loadCurrentUser() {
    try {
      final payload = Token.decodePayload(Token.token);
      username = payload['sub'] ?? '';
      notifyListeners();
    } catch (_) {
      // Ignore error
    }
  }

  Future<void> initData({bool forceRefresh = false}) async {
    validationLoading = true;
    isLoading = true;
    notifyListeners();

    // Fast path: Data is loaded, not forcing refresh, and background sync (Phase 2) is complete.
    if (GlobalCache.isDataLoaded && !forceRefresh && !GlobalCache.backgroundSyncNotifier.value) {
      await loadValidationData();
      await loadSupportBPartners();
      await loadDocumentStats();
      await loadSupportProductChips();
      await loadRecentRequests();
      validationLoading = false;
      isLoading = false;
      notifyListeners();
      return;
    }

    try {
      await GlobalCache.syncData(force: forceRefresh);

      await loadValidationData();
      
      final bool isAdmin = AccessControl.isAdmin;
      final bool isSupport = AccessControl.isSupport;
      final bool isProject = AccessControl.isProject;

      await loadSupportBPartners();

      if (isAdmin || isProject) {
        await loadDocumentStats();
      }
      
      if (isAdmin || isSupport) {
        List<int> bpsToFetch = [];
        if (isAdmin && selectedSupportBpIds.isNotEmpty) {
          bpsToFetch = selectedSupportBpIds;
        } else if (!isAdmin && User.cBPartnerID != null) {
          bpsToFetch = [User.cBPartnerID!];
        }

        if (bpsToFetch.isNotEmpty) {
          List<Future<void>> fetches = [];
          for (var id in bpsToFetch) {
            fetches.add(GlobalCache.loadSupportBpRequestsInBackground(id));
          }
          await Future.wait(fetches);
        }

        await loadRecentRequests();
        await loadSupportProductChips();
      }

      validationLoading = false;
      notifyListeners();

    } catch (_) {
      // Ignored: Fail silently
    }



    isLoading = false;
    notifyListeners();
  }

  Future<void> loadSupportBPartners() async {
    supportBPartners = GlobalCache.bPartners;
    notifyListeners();
  }

  Future<void> loadValidationData() async {

    final bool isAdmin = AccessControl.isAdmin;

    int? partnerID = User.cBPartnerID;
    String? pName;
    String? projPName;

    if (partnerID != null || isAdmin) {
      try {
        if (partnerID != null) {
          final found = GlobalCache.bPartners.firstWhere((bp) => bp['id'] == partnerID, orElse: () => <String, dynamic>{});
          if (found.isNotEmpty) pName = found['Name'];
        }

        List<dynamic> allProjects = GlobalCache.projects;

        if (AccessControl.isRealProject && partnerID != null) {
          // El backend ya filtró los proyectos por C_BPartner_ID para los usuarios reales de proyecto.
          projects = List.from(allProjects);
        } else {
          if (AdminViewModeManager().isViewingMine) {
            projects = allProjects.where((p) {
              final rawBp = p['C_BPartner_ID'];
              final rawRep = p['SalesRep_ID'];
              
              final bpId = rawBp is Map ? (rawBp['id'] as num?)?.toInt() : (rawBp as num?)?.toInt();
              final repId = rawRep is Map ? (rawRep['id'] as num?)?.toInt() : (rawRep as num?)?.toInt();
              
              return (partnerID != null && bpId == partnerID) || (User.userID != null && repId == User.userID);
            }).toList();
          } else {
            projects = List.from(allProjects);
          }
        }

        if (projects.isNotEmpty) {
          projPName = projects[0]['C_BPartner_ID'] is Map ? projects[0]['C_BPartner_ID']['identifier'] : null;

          final validProjectIds = projects.map<int>((p) => p['id'] is int ? p['id'] as int : int.tryParse(p['id'].toString()) ?? 0).toSet();
          if (selectedProjectIds.isEmpty) {
            selectedProjectIds = validProjectIds.toList();
          } else {
            selectedProjectIds = selectedProjectIds.where((id) => validProjectIds.contains(id)).toList();
            if (selectedProjectIds.isEmpty) {
              selectedProjectIds = validProjectIds.toList();
            }
          }
        }
      } catch (e) {
        // Ignore error
      }
    }

    hasProject = projects.isNotEmpty;
    cBPartnerID = partnerID;
    partnerName = pName;
    projectPartnerName = projPName;
  }

  Future<void> loadRecentRequests() async {
    List<Map<String, dynamic>> allBPartnerRequests = [];
    List<int>? bpIdsForQuery;

    if (AccessControl.isAdmin) {
      bpIdsForQuery = selectedSupportBpIds;
    } else {
      if (User.cBPartnerID != null) {
        bpIdsForQuery = [User.cBPartnerID!];
      }
    }

    if (bpIdsForQuery != null && bpIdsForQuery.isNotEmpty) {
      allBPartnerRequests = GlobalCache.requests.where((r) {
        final rBpIdRaw = r['C_BPartner_ID'] is Map ? r['C_BPartner_ID']['id'] : r['C_BPartner_ID'];
        final int? rBpId = (rBpIdRaw as num?)?.toInt();
        return rBpId != null && bpIdsForQuery!.contains(rBpId);
      }).toList();
    } else if (AccessControl.isAdmin) {
      setStateForEmptyRequests();
      return;
    }

    bpIdsForQuery?.forEach((id) {
      requestsStatsByBp[id] ??= {'closed': 0, 'inProgress': 0, 'consumedHours': 0.0, 'inProgressHours': 0.0, 'acquiredHours': 0.0};
      requestsStatsByBp[id]!['closed'] = 0;
      requestsStatsByBp[id]!['inProgress'] = 0;
      requestsStatsByBp[id]!['consumedHours'] = 0.0;
      requestsStatsByBp[id]!['inProgressHours'] = 0.0;
    });

    for (var req in allBPartnerRequests) {
      // Eliminamos el filtro de Record_UU para que el Home muestre TODAS las solicitudes recientes del tercero.
      // Anteriormente: if (recordUU != null && recordUU.toString().trim().isNotEmpty) continue;
      
      // Eliminamos el filtro de R_RequestType_ID y de año para incluir todos los tipos de soporte y el historial completo.

      final bpIdRaw = req['C_BPartner_ID']?['id'] ?? req['C_BPartner_ID'];
      final int? bpId = (bpIdRaw as num?)?.toInt();
      if (bpId == null || !requestsStatsByBp.containsKey(bpId)) continue;

      final statusId = req['R_Status_ID'] is Map ? req['R_Status_ID']['id'] : req['R_Status_ID'];
      final statusIdentifier = req['R_Status_ID'] is Map ? req['R_Status_ID']['identifier'] : '';
      final statusNameLower = (req['R_Status_Name'] ?? '').toLowerCase();

      bool isClosed = false;
      if (statusId != null && GlobalCache.statusIsFinalCloseMap.containsKey(statusId)) {
        isClosed = GlobalCache.statusIsFinalCloseMap[statusId]!;
      } else {
        isClosed = statusId == 1000019 || statusId == 1000015 || statusId == 1000018 ||
                        statusId == 103 ||
                        statusIdentifier == '100_Archivada' || statusIdentifier == '90_Anulada' || 
                        statusNameLower.contains('archivada') || statusNameLower.contains('anulada') || 
                        statusNameLower.contains('implementada en produccion') || statusNameLower.contains('implementada en producción') ||
                        statusNameLower == '9_final close' || statusNameLower.contains('cerrada');
      }
      
      double spent = (req['QtySpent'] as num?)?.toDouble() ?? 0.0;

      if (isClosed) {
        requestsStatsByBp[bpId]!['consumedHours'] = (requestsStatsByBp[bpId]!['consumedHours']! as num) + spent;
        requestsStatsByBp[bpId]!['closed'] = (requestsStatsByBp[bpId]!['closed']! as int) + 1;
      } else {
        requestsStatsByBp[bpId]!['inProgressHours'] = (requestsStatsByBp[bpId]!['inProgressHours']! as num) + spent;
        requestsStatsByBp[bpId]!['inProgress'] = (requestsStatsByBp[bpId]!['inProgress']! as int) + 1;
      }
    }

    final filteredRequests = allBPartnerRequests.where((r) {
      final recordUU = r['Record_UU'];
      bool isBitacora = recordUU != null && recordUU.toString().trim().isNotEmpty;
      if (isBitacora) return false;

      if (extractProductChipId(r) == null) return false;

      final statusId = r['R_Status_ID'] is Map ? r['R_Status_ID']['id'] : r['R_Status_ID'];
      final statusIdentifier = r['R_Status_ID'] is Map ? r['R_Status_ID']['identifier'] : '';
      final statusNameLower = (r['R_Status_Name'] ?? '').toLowerCase();

      bool isArchived = false;
      if (statusId != null && GlobalCache.statusIsFinalCloseMap.containsKey(statusId)) {
        isArchived = GlobalCache.statusIsFinalCloseMap[statusId]!;
      } else {
        isArchived = statusId == 1000019 || statusId == 1000015 || statusId == 1000018 ||
                        statusId == 103 ||
                        statusIdentifier == '100_Archivada' || statusIdentifier == '90_Anulada' || 
                        statusNameLower.contains('archivada') || statusNameLower.contains('anulada') || 
                        statusNameLower.contains('implementada en produccion') || statusNameLower.contains('implementada en producción') ||
                        statusNameLower == '9_final close' || statusNameLower.contains('cerrada');
      }

      return !isArchived;
    }).toList();

    filteredRequests.sort((a, b) {
      final hasChipA = (extractProductChipId(a) != null) ? 1 : 0;
      final hasChipB = (extractProductChipId(b) != null) ? 1 : 0;

      if (hasChipA != hasChipB) {
        return hasChipB.compareTo(hasChipA);
      }

      final dateA = DateTime.tryParse(a['Created'] ?? '') ?? DateTime(0);
      final dateB = DateTime.tryParse(b['Created'] ?? '') ?? DateTime(0);
      return dateB.compareTo(dateA);
    });

    allRequests = filteredRequests;

    _applyFilters();
    notifyListeners();
  }

  void _applyFilters() {
    var filtered = List<dynamic>.from(allRequests);
    recentRequests = filtered.take(5).map((r) {
      final categoryId = r['R_Category_ID'] is Map ? (r['R_Category_ID']['id'] as num?)?.toInt() : (r['R_Category_ID'] as num?)?.toInt();
      final catInCache = GlobalCache.rawCategories.firstWhere(
        (c) => (c['id'] as num?)?.toInt() == categoryId, 
        orElse: () => {}
      );

      String level = 'Media';
      Color baseColor = Colors.green;
      bool resolvedFromCategory = false;

      if (catInCache.isNotEmpty) {
        final rawPriorityVal = catInCache['Priority'] is Map 
            ? catInCache['Priority']['id'] 
            : catInCache['Priority'];
        
        int? priorityInt;
        if (rawPriorityVal != null) {
          if (rawPriorityVal is num) {
            priorityInt = rawPriorityVal.toInt();
          } else {
            final parsedNum = num.tryParse(rawPriorityVal.toString());
            if (parsedNum != null) {
              priorityInt = parsedNum.toInt();
            }
          }
        }

        if (priorityInt != null) {
          resolvedFromCategory = true;
          if (priorityInt == 1) {
            level = 'Urgente';
            baseColor = Colors.purple;
          } else if (priorityInt == 3) {
            level = 'Alta';
            baseColor = Colors.red;
          } else if (priorityInt == 5) {
            level = 'Media';
            baseColor = Colors.amber.shade800;
          } else if (priorityInt == 7) {
            level = 'Baja';
            baseColor = Colors.green;
          } else if (priorityInt == 9) {
            level = 'Muy baja';
            baseColor = Colors.grey;
          } else {
            level = priorityInt.toString();
            baseColor = Colors.green;
          }
        }
      }

      if (!resolvedFromCategory) {
        dynamic priorityVal = r['Priority'];
        if (priorityVal is Map) {
          level = priorityVal['identifier'] ?? priorityVal['Name'] ?? 'Media';
        } else if (priorityVal != null) {
          String pStr = priorityVal.toString();
          if (pStr == '1') {
            level = 'Urgente';
          } else if (pStr == '3') {
            level = 'Alta';
          } else if (pStr == '5') {
            level = 'Media';
          } else if (pStr == '7') {
            level = 'Baja';
          } else if (pStr == '9') {
            level = 'Muy baja';
          }
        }

        if (level == 'Urgente') {
          baseColor = Colors.purple;
        } else if (level == 'Alta') {
          baseColor = Colors.red;
        } else if (level == 'Media') {
          baseColor = Colors.amber.shade800;
        } else if (level == 'Muy baja') {
          baseColor = Colors.grey;
        } else if (level == 'Baja') {
          baseColor = Colors.green;
        }
      }

      String formattedTime = r['Created'] ?? '';
      try {
        if (formattedTime.isNotEmpty) {
          final DateTime date = DateTime.parse(formattedTime).toLocal();
          formattedTime = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
        }
      } catch (_) {
        // Ignore error
      }

      String situation = r['R_RequestType_ID'] is Map ? (r['R_RequestType_ID']['identifier'] ?? r['R_RequestType_ID']['Name'] ?? r['R_RequestType_Name'] ?? 'Solicitud') : (r['R_RequestType_Name'] ?? 'Solicitud');
      String status = r['R_Status_ID'] is Map ? (r['R_Status_ID']['identifier'] ?? r['R_Status_ID']['Name'] ?? '1_Open') : (r['R_Status_Name'] ?? '1_Open');
      status = cleanStatusName(status);

      String bpName = '';
      if (r['C_BPartner_ID'] is Map) {
        bpName = r['C_BPartner_ID']['identifier'] ?? r['C_BPartner_ID']['Name'] ?? '';
      }
      String userName = '';
      if (r['AD_User_ID'] is Map) {
        userName = r['AD_User_ID']['identifier'] ?? r['AD_User_ID']['Name'] ?? '';
      }

      return {
        'code': r['DocumentNo'] ?? r['id'].toString(),
        'situation': situation,
        'emailSubject': r['CDS_EmailSubject'] ?? '',
        'description': r['Summary'] ?? '',
        'descriptionClean': stripHtmlTags(r['Summary'] ?? ''),
        'time': formattedTime,
        'level': level,
        'levelColor': baseColor,
        'levelBgColor': baseColor.withOpacity(0.2),
        'status': status,
        'bpName': bpName,
        'userName': userName,
        'productChipId': extractProductChipId(r),
        'qtySpent': r['QtySpent'],
        'original': r,
      };
    }).toList();
  }

  Future<void> loadSupportProductChips() async {
    List<int>? bpIdsForQuery;

    if (AccessControl.isAdmin) {
      if (selectedSupportBpIds.isEmpty) {
        supportProductChips = [];
        hasSupport = false;
        notifyListeners();
        return;
      }
      bpIdsForQuery = selectedSupportBpIds;
    } else {
      if (User.cBPartnerID != null) {
        bpIdsForQuery = [User.cBPartnerID!];
      }
    }

    if (bpIdsForQuery == null || bpIdsForQuery.isEmpty) {
      supportProductChips = [];
      hasSupport = false;
      notifyListeners();
      return;
    }

    // Obtener todas las fichas activas de los BPs seleccionados
    final allFetchedChips = GlobalCache.productChips.where((c) {
      final rawBp = c['C_BPartner_ID'];
      final chipBpId = rawBp is Map ? (rawBp['id'] as num?)?.toInt() : (rawBp as num?)?.toInt();
      
      final isActive = c['IsActive'] == 'Y' || c['IsActive'] == true;
      return bpIdsForQuery!.contains(chipBpId) && isActive;
    }).toList();

    // Ordenar por fecha de inicio de servicio (y si no existe, fecha de creación) (FIFO) para distribuir horas y orden visual
    allFetchedChips.sort((a, b) {
      final dateAStr = (a['service_start_date']?.toString().isNotEmpty == true) 
          ? a['service_start_date'].toString() 
          : (a['Created']?.toString() ?? '');
          
      final dateBStr = (b['service_start_date']?.toString().isNotEmpty == true) 
          ? b['service_start_date'].toString() 
          : (b['Created']?.toString() ?? '');

      final dateA = DateTime.tryParse(dateAStr) ?? DateTime(0);
      final dateB = DateTime.tryParse(dateBStr) ?? DateTime(0);
      return dateA.compareTo(dateB);
    });

    // Resetear stats agregadas (aunque ahora usaremos datos por chip)
    for (var id in bpIdsForQuery) {
      requestsStatsByBp[id] ??= {'closed': 0, 'inProgress': 0, 'consumedHours': 0.0, 'inProgressHours': 0.0, 'acquiredHours': 0.0};
      requestsStatsByBp[id]!['acquiredHours'] = 0.0;
    }

    List<Map<String, dynamic>> processedChips = [];

    // Agrupar fichas por BP para distribuir sus consumos locales
    Map<int, List<Map<String, dynamic>>> chipsByBp = {};
    for (var chip in allFetchedChips) {
      final rawBp = chip['C_BPartner_ID'];
      final bpId = rawBp is Map ? (rawBp['id'] as num?)?.toInt() : (rawBp as num?)?.toInt();
      if (bpId != null) (chipsByBp[bpId] ??= []).add(Map<String, dynamic>.from(chip));
    }

    final List<Map<String, dynamic>> allSupportRequests = GlobalCache.requests.where((req) {
      final recordUU = req['Record_UU'];
      if (recordUU != null && recordUU.toString().trim().isNotEmpty) return false;
      // Eliminamos el filtro estricto de R_RequestType_ID para incluir todos los tipos de soporte (ej. RFQ)
      return true;
    }).toList();

    // Mapas para acumular consumo por chip
    Map<int, double> chipConsumedHoursMap = {};
    Map<int, double> chipInProgressHoursMap = {};
    Map<int, int> chipClosedCountMap = {};
    Map<int, int> chipInProgressCountMap = {};
    


    // Usamos processRequests para obtener datos normalizados
    final processedResult = await processRequests(allSupportRequests, GlobalCache.statuses);
    final List<Map<String, dynamic>> processedRequests = List<Map<String, dynamic>>.from(processedResult['requests']);
    

    for (var req in processedRequests) {
      final int? reqBpId = (req['bpId'] as num?)?.toInt();
      if (reqBpId == null || !bpIdsForQuery.contains(reqBpId)) continue;

      final int? linkedChipId = int.tryParse(req['productChipId']?.toString() ?? '');
      final bool isClosed = req['isClosed'] ?? false;
      final double qtySpent = (req['qtySpent'] as num?)?.toDouble() ?? 0.0;

      if (linkedChipId != null) {
        if (isClosed) {
          chipConsumedHoursMap[linkedChipId] = (chipConsumedHoursMap[linkedChipId] ?? 0.0) + qtySpent;
          chipClosedCountMap[linkedChipId] = (chipClosedCountMap[linkedChipId] ?? 0) + 1;
        } else {
          chipInProgressHoursMap[linkedChipId] = (chipInProgressHoursMap[linkedChipId] ?? 0.0) + qtySpent;
          chipInProgressCountMap[linkedChipId] = (chipInProgressCountMap[linkedChipId] ?? 0) + 1;
        }
      } else {
        // No vinculado: Ya no lo acumulamos para distribuir FIFO, ya que el usuario indica que si no tiene ficha no debe contarse.
      }
    }

    // Ahora procesamos cada ficha y distribuimos consumos no vinculados (FIFO)
    for (var chip in allFetchedChips) {
      final rawBp = chip['C_BPartner_ID'];
      final bpId = rawBp is Map ? (rawBp['id'] as num?)?.toInt() : (rawBp as num?)?.toInt();
      if (bpId == null) continue;

      final chipIdRaw = chip['C_BPartner_Product_Chip_ID'] ?? chip['id'];
      final int? chipId = int.tryParse(chipIdRaw?.toString() ?? '');
      if (chipId == null) continue;
      

      
      // Consumo directo
      double consumed = chipConsumedHoursMap[chipId] ?? 0.0;
      double estimated = chipInProgressHoursMap[chipId] ?? 0.0;
      int closedCount = chipClosedCountMap[chipId] ?? 0;
      int inProgressCount = chipInProgressCountMap[chipId] ?? 0;

      // Según la nueva instrucción, ignoramos consumos no vinculados (FIFO eliminada)
      // Solo cuentan las solicitudes que tengan la ficha vinculada directamente.

      chip['closedRequestsCount'] = closedCount;
      chip['inProgressRequestsCount'] = inProgressCount;
      chip['consumedHours'] = consumed;
      chip['inProgressHours'] = estimated;
      
      processedChips.add(chip);
    }

    supportProductChips = processedChips;
    hasSupport = allFetchedChips.isNotEmpty;

    notifyListeners();
  }

  Future<void> loadDocumentStats() async {
    if (projects.isEmpty) return;

    Map<int, Map<String, dynamic>> stats = {};
    List<Future<void>> futures = [];

    for (var project in projects) {
      futures.add(() async {
        try {
          final projectId = project['id'] is int ? project['id'] as int : int.tryParse(project['id'].toString()) ?? 0;
          int pEt = 0;
          int pSg = 0;
          int pGn = 0;
          bool hasMetrics = false;

          try {
            var response = await http.get(Uri.parse('${Endpoint.primDocuments}?\$filter=C_Project_ID eq $projectId&\$expand=PRIM_Documents_Related'), headers: {'Content-Type': 'application/json', 'Authorization': Token.token});
            if (response.statusCode == 401) {
              final refreshed = await handleTokenRefresh();
              if (refreshed) {
                response = await http.get(Uri.parse('${Endpoint.primDocuments}?\$filter=C_Project_ID eq $projectId&\$expand=PRIM_Documents_Related'), headers: {'Content-Type': 'application/json', 'Authorization': Token.token});
              }
            }

            if (response.statusCode == 200) {
              final data = json.decode(utf8.decode(response.bodyBytes));
              final records = data['records'] as List;

              void countRecursive(List<dynamic> docs, String? inheritedType) {
                for (var doc in docs) {
                  dynamic typeVal = doc['Type'];
                  String typeCode = '';
                  if (typeVal is Map) {
                    typeCode = typeVal['id']?.toString() ?? '';
                  } else if (typeVal != null) {
                    typeCode = typeVal.toString();
                  }
                  if (typeCode.isEmpty && inheritedType != null) {
                    typeCode = inheritedType;
                  }
                  final isFolder = doc['IsSummary'] == true;
                  if (!isFolder) {
                    if (typeCode == 'ET') pEt++;
                    if (typeCode == 'SG') pSg++;
                    if (typeCode == 'GN') pGn++;
                  }
                  final children = doc['PRIM_Documents_Related'] as List? ?? [];
                  if (children.isNotEmpty) {
                    countRecursive(children, typeCode.isNotEmpty ? typeCode : inheritedType);
                  }
                }
              }

              countRecursive(records, null);
            }
          } catch (e) {
            // Ignore error
          }

          try {
            var metricsRes = await http.get(Uri.parse('${Endpoint.request}?\$filter=C_Project_ID eq $projectId&\$top=1&\$select=R_Request_ID'), headers: {'Content-Type': 'application/json', 'Authorization': Token.token});
            if (metricsRes.statusCode == 200) {
              final mData = json.decode(utf8.decode(metricsRes.bodyBytes));
              hasMetrics = (mData['records'] as List).isNotEmpty;
            }
          } catch (_) {
            // Ignore error
          }

          stats[projectId] = {'et': pEt, 'sg': pSg, 'gn': pGn, 'hasMetrics': hasMetrics};
        } catch (e) {
          // Ignore error
        }
      }());
    }

    await Future.wait(futures);
    projectStats = stats;
    notifyListeners();
  }

  void updateSelectedProjects(List<int> ids) {
    selectedProjectIds = ids;
    savedSelectedProjectIds = List.from(ids);
    notifyListeners();
  }

  void updateSelectedSupportBps(List<int> ids) async {
    validationLoading = true;
    notifyListeners();
    selectedSupportBpIds = ids;
    savedSelectedSupportBpIds = List.from(ids);
    
    // Asegurarse de que el BPartner esté en la lista para que el Dropdown no diga "Tercero no encontrado"
    for (var id in ids) {
      if (!supportBPartners.any((bp) => bp['id'] == id)) {
        final found = GlobalCache.allBPartners.firstWhere(
          (bp) => bp['id'] == id, 
          orElse: () => <String, dynamic>{}
        );
        if (found.isNotEmpty) {
          supportBPartners.add(found);
        }
      }
    }

    // Cargar historial específico desde el servidor para cada tercero seleccionado
    List<Future> fetches = [];
    for (var id in ids) {
      fetches.add(GlobalCache.loadSupportBpRequestsInBackground(id));
    }
    if (fetches.isNotEmpty) await Future.wait(fetches);

    await loadRecentRequests();
    await loadSupportProductChips();
    validationLoading = false;
    notifyListeners();
  }

  void setStateForEmptyRequests() {
    requestsStatsByBp.clear();
    allRequests = [];
    recentRequests = [];
    recentRequests = [];
    notifyListeners();
  }

  void updateRequestLocally(Map<String, dynamic> updatedReq) {
    notifyListeners();
  }
}

