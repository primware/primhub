import 'dart:convert';
import 'dart:async';
import 'package:primhub/api/api_http.dart' as http;

import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/api/contract_api.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart';
import 'package:flutter_localization/flutter_localization.dart';

class GlobalCache {
  // --- Estado de la Caché ---
  static List<dynamic> projects = [];
  static List<Map<String, dynamic>> requests = [];
  static List<Map<String, dynamic>> _rawBPartners = [];
  static List<Map<String, dynamic>> get allBPartners => _rawBPartners;
  static List<Map<String, dynamic>> bPartners = [];
  static List<Map<String, dynamic>> productChips = [];
  static List<dynamic> users = [];
  static Map<String, int> statuses = {};
  static Map<int, bool> statusIsFinalCloseMap = {};
  static Map<int, bool> statusIsOpenMap = {};
  static Map<int, int> statusCategoryMap = {}; // R_Status_ID -> R_StatusCategory_ID
  static Map<int, String> statusCategoryNameMap = {}; // R_StatusCategory_ID -> Name
  static List<Map<String, dynamic>> salesReps = [];
  static List<Map<String, dynamic>> rawSalesReps = [];
  static Map<String, int> requestTypes = {};
  static Map<int, int> requestTypeCategoryMap = {}; // R_RequestType_ID -> R_StatusCategory_ID
  static Map<String, int> categories = {};
  static List<Map<String, dynamic>> rawCategories = [];
  static Map<String, int> groups = {};
  
  // Caché de solicitudes por proyecto para carga "mixta"
  static Map<int, List<Map<String, dynamic>>> projectRequestsCache = {};
  static Map<int, bool> projectLoadingStatus = {};
  
  static Set<int> extSupportBpIds = {};

  // Mail templates
  static int? newRequestMailId;
  static int? updateRequestMailId;
  static int? statusUpdateRequestMailId;

  static bool isDataLoaded = false;
  static bool isFullyLoaded = false;

  static final ValueNotifier<bool> backgroundSyncNotifier = ValueNotifier(
    false,
  );
  static final Set<int> _archivedYearsLoaded = {};
  static Completer<void>? _phase2Completer;
  static Future<void>? get phase2SyncFuture => _phase2Completer?.future;
  
  static Completer<void>? _phase2bCompleter;
  static Future<void>? get phase2bSyncFuture => _phase2bCompleter?.future;

  // --- FASE 1: Carga de datos esenciales (Bloqueante para el Home) ---
  static Future<void> _loadPhase1EssentialData({ValueNotifier<double>? progressNotifier}) async {
    final bool isAdmin = AccessControl.isAdmin;
    final bool isSupport = AccessControl.isRealSupport;
    final bool isProject = AccessControl.isRealProject;

    if (!isAdmin && AccessControl.isExtSupport && User.userID != null) {
      try {
        final reqRes = await fetchRequest(
          filter: "SalesRep_ID eq ${User.userID}",
          select: "C_BPartner_ID",
        );
        for (var r in reqRes) {
          final bpField = r['C_BPartner_ID'];
          if (bpField is Map && bpField['id'] != null) {
            extSupportBpIds.add((bpField['id'] as num).toInt());
          }
        }
      } catch (_) {}
    }

    final List<Future<dynamic>> fetchFutures = [
      fetchStatusesWithMetadata(), // 0
      fetchRequestTypesWithMetadata(), // 1
      fetchCategories(), // 2
      fetchGroups(), // 3
      ProjectsLogic().fetchUsers(), // 4
      ProjectsLogic().fetchSalesReps(), // 5
      _fetchMailTemplateIds(), // 6
    ];

    // Índices para referenciar después
    int projectsIdx = -1;
    int supportPartnersIdx = -1;
    int supportChipsIdx = -1;
    int bpWithChipsIdx = -1;
    int adminCompanyIdx = -1;

    if (isAdmin || isProject) {
      projectsIdx = fetchFutures.length;
      fetchFutures.add(ProjectsLogic().fetchProjects(isViewingMine: false, showInactive: true));
    }

    if (isAdmin || isSupport) {
      supportPartnersIdx = fetchFutures.length;
      fetchFutures.add(ProjectsLogic().fetchSupportPartners());
      
      supportChipsIdx = fetchFutures.length;
      fetchFutures.add(ContractApi.getSupportProductChips(includeInactive: true));
      
      bpWithChipsIdx = fetchFutures.length;
      fetchFutures.add(ContractApi.getBPartnersWithProductChips());
    }

    if (isAdmin) {
      adminCompanyIdx = fetchFutures.length;
      fetchFutures.add(_fetchAdminCompany());
    }

    final List<Future<dynamic>> trackedFutures = [];
    if (progressNotifier != null) {
      int completed = 0;
      final total = fetchFutures.length;
      for (var f in fetchFutures) {
        trackedFutures.add(f.then((v) {
          completed++;
          progressNotifier.value = (completed / total) * 0.5;
          return v;
        }));
      }
    } else {
      trackedFutures.addAll(fetchFutures);
    }

    final List<dynamic> futures;
    try {
      futures = await Future.wait(trackedFutures);
    } catch (e) {
      rethrow;
    }

    final statusData = futures[0] as Map<String, dynamic>;
    statuses = statusData['nameToId'] as Map<String, int>;
    statusIsFinalCloseMap = statusData['idToIsFinalClose'] as Map<int, bool>;
    statusIsOpenMap = statusData['idToIsOpen'] as Map<int, bool>;
    statusCategoryMap = statusData['idToCategoryId'] as Map<int, int>;
    statusCategoryNameMap = statusData['categoryIdToName'] as Map<int, String>;
    
    final requestTypeData = futures[1] as Map<String, dynamic>;
    requestTypes = requestTypeData['nameToId'] as Map<String, int>;
    requestTypeCategoryMap = requestTypeData['idToCategoryId'] as Map<int, int>;
    
    final catList = futures[2] as List<Map<String, dynamic>>;
    rawCategories = catList;
    categories = {for (var c in catList) c['Name'].toString().trim(): c['id'] as int};

    groups = futures[3] as Map<String, int>;

    final List<Map<String, dynamic>> supportPartners = supportPartnersIdx != -1 
        ? (futures[supportPartnersIdx] as List<dynamic>).map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
        
    final List<Map<String, dynamic>> partnersWithChips = bpWithChipsIdx != -1 
        ? (futures[bpWithChipsIdx] as List<dynamic>).map((e) => Map<String, dynamic>.from(e)).toList()
        : [];

    // Unimos ambas listas sin duplicados
    final Map<int, Map<String, dynamic>> mergedMap = {};
    for (var bp in supportPartners) {
      final id = (bp['id'] as num?)?.toInt();
      if (id != null) mergedMap[id] = bp;
    }
    for (var bp in partnersWithChips) {
      final id = (bp['id'] as num?)?.toInt();
      if (id != null && !mergedMap.containsKey(id)) {
        mergedMap[id] = bp;
      }
    }

    if (adminCompanyIdx != -1) {
      final adminCompany = futures[adminCompanyIdx] as Map<String, dynamic>?;
      if (adminCompany != null) {
        final id = (adminCompany['id'] as num?)?.toInt();
        if (id != null && !mergedMap.containsKey(id)) {
          mergedMap[id] = adminCompany;
        }
      }
    }

    bPartners = mergedMap.values.toList()..sort((a, b) => (a['Name'] ?? '').compareTo(b['Name'] ?? ''));
    _rawBPartners = bPartners;
    final rawUsers = futures[4] as List<dynamic>;    
    final allProcessedUsers = rawUsers.map((u) {
      if (u is! Map) return <String, dynamic>{};
      final user = Map<String, dynamic>.from(u);
      user['Name'] = (user['Name']?.toString() ?? '').trim();
      return user;
    }).where((u) => u.isNotEmpty).toList();

    final customerBpIds = bPartners.map((bp) => bp['id'] as int).toSet();
    users = allProcessedUsers.where((u) {
      final uBpData = u['C_BPartner_ID'];
      final uBpId = (uBpData is Map)
          ? (uBpData['id'] as num?)?.toInt()
          : (uBpData is num ? uBpData.toInt() : null);
      
      // Si no es admin, filtramos solo los usuarios de su propio BPartner
      if (!isAdmin && User.cBPartnerID != null) {
        return uBpId == User.cBPartnerID;
      }
      
      return uBpId != null && customerBpIds.contains(uBpId);
    }).toList();
    
    // Mapeo de Representantes Comerciales (desde la nueva consulta dedicada)
    final localRawSalesReps = (futures[5] as List<dynamic>)
        .map((e) {
          if (e is! Map) return <String, dynamic>{};
          final bp = Map<String, dynamic>.from(e);
          bp['id'] = (bp['id'] as num?)?.toInt();
          return bp;
        })
        .where((e) => e.isNotEmpty)
        .toList();
        
    GlobalCache.rawSalesReps = localRawSalesReps;

    final repBpIds = localRawSalesReps.map((bp) => bp['id']).toSet();

    // Necesitamos encontrar los usuarios que pertenecen a estos representantes
    salesReps = allProcessedUsers.where((user) {
      try {
        final userBpData = user['C_BPartner_ID'];
        final userBpId = (userBpData is Map)
            ? (userBpData['id'] as num?)?.toInt()
            : (userBpData is num ? userBpData.toInt() : null);
        
        final isRepById = userBpId != null && repBpIds.contains(userBpId);
        
        if (!isRepById) return false;

        // Filtrar contactos adicionales (ej. esposas, asistentes) comparando el nombre del User con el del BPartner
        final bp = localRawSalesReps.firstWhere((b) => b['id'] == userBpId, orElse: () => <String, dynamic>{});
        final bpName = (bp['Name'] ?? '').toString().toLowerCase();
        final userName = (user['Name'] ?? '').toString().toLowerCase();

        if (bpName.isNotEmpty && userName.isNotEmpty) {
          final userParts = userName.split(RegExp(r'\s+')).where((p) => p.length > 2).toList();
          bool hasMatch = false;
          
          for (final p in userParts) {
            if (bpName.contains(p)) {
              hasMatch = true;
              break;
            }
          }
          
          if (!hasMatch) {
            final bpParts = bpName.split(RegExp(r'\s+')).where((p) => p.length > 2).toList();
            for (final p in bpParts) {
              if (userName.contains(p)) {
                hasMatch = true;
                break;
              }
            }
          }
          
          return hasMatch;
        }
        
        return true;
      } catch (e) {
        return true;
      }
    }).toList();

    if (salesReps.isEmpty && users.isNotEmpty) {
      salesReps = List.from(users);
    }

    projects = projectsIdx != -1 ? futures[projectsIdx] as List<dynamic> : [];
    productChips = supportChipsIdx != -1 ? futures[supportChipsIdx] as List<Map<String, dynamic>> : [];

    // Solicitudes iniciales filtradas por rol
    String? initialFilter;
    if (!isAdmin) {
      if (AccessControl.isExtSupport && User.userID != null) {
        if (extSupportBpIds.isNotEmpty) {
          initialFilter = "(${extSupportBpIds.map((id) => "C_BPartner_ID eq $id").join(' or ')})";
        } else {
          initialFilter = "C_BPartner_ID eq -1";
        }
      } else if (User.cBPartnerID != null) {
        initialFilter = "C_BPartner_ID eq ${User.cBPartnerID}";
      }
      
      if (initialFilter != null) {
        if (isProject) {
          initialFilter += " and C_Project_ID gt 0";
        } else if (isSupport) {
          initialFilter += " and Record_UU eq null";
        }
      }
    }

    final initialRequests = await fetchRequest(
      filter: initialFilter,
      top: 5,
      expand: 'C_Order_ID(\$select=DocumentNo),C_BPartner_ID(\$select=Name,Description)',
    );

    requests = List<Map<String, dynamic>>.from(initialRequests);
  }

  static bool _isSyncing = false;
  static Completer<void>? _syncCompleter;

  /// Sincroniza los datos de la caché con el servidor.
  static Future<void> syncData({bool force = false, ValueNotifier<double>? progressNotifier}) async {
    if (isDataLoaded && !force) return;

    // Si ya hay una sincronización en curso, esperamos a que termine
    if (_isSyncing) {

      await _syncCompleter?.future;
      return;
    }

    _isSyncing = true;
    _syncCompleter = Completer<void>();
    _phase2Completer = Completer<void>();
    _phase2bCompleter = Completer<void>();
    
    try {
      // Limpiar datos si es forzado para asegurar frescura total
      if (force) clear();

      await _loadPhase1EssentialData(progressNotifier: progressNotifier);
      
      // Lanzar Fase 2 (datos pesados/históricos) sin bloquear el flujo principal
      _loadPhase2HistoricalData(progressNotifier: progressNotifier);
      
      isDataLoaded = true;
      if (!(_syncCompleter?.isCompleted ?? true)) _syncCompleter?.complete();
    } catch (e) {
      if (!(_syncCompleter?.isCompleted ?? true)) _syncCompleter?.completeError(e);
      // Marcamos como cargado para no reintentar infinitamente si el error es persistente
      isDataLoaded = true;
    } finally {
      _isSyncing = false;
      _syncCompleter = null;
    }
  }

  static Future<void> _loadPhase2HistoricalData({ValueNotifier<double>? progressNotifier}) async {
    try {
      final currentYear = DateTime.now().year;
      final bool isAdmin = AccessControl.isAdmin;
      final bool isProject = AccessControl.isRealProject;
      final bool isSupport = AccessControl.isRealSupport;

      String getFilterForYear(int year) {
        String filter = "Created ge '$year-01-01T00:00:00Z' and Created le '$year-12-31T23:59:59Z'";
        if (!isAdmin) {
          if (AccessControl.isExtSupport && User.userID != null) {
            if (extSupportBpIds.isNotEmpty) {
              filter += " and (${extSupportBpIds.map((id) => "C_BPartner_ID eq $id").join(' or ')})";
            } else {
              filter += " and C_BPartner_ID eq -1";
            }
          } else if (User.cBPartnerID != null) {
            filter += " and C_BPartner_ID eq ${User.cBPartnerID}";
          }
          if (isProject) {
            filter += " and C_Project_ID gt 0";
          } else if (isSupport) {
            filter += " and Record_UU eq null";
          }
        }
        return filter;
      }

      // 1. Cargar el año actual PRIMERO y desbloquear la UI (Fase 2a)
      final currentYearReqs = await fetchRequest(
        filter: getFilterForYear(currentYear),
        expand: 'C_Order_ID(\$select=DocumentNo),C_BPartner_ID(\$select=Name,Description)',
      );

      if (currentYearReqs.isNotEmpty) {
        final existingIds = requests.map((r) => r['id']).toSet();
        for (var r in currentYearReqs) {
          if (!existingIds.contains(r['id'])) {
            requests.add(Map<String, dynamic>.from(r));
          }
        }
        _archivedYearsLoaded.add(currentYear);
      }

      // Desbloquear la UI de Mis Solicitudes ahora que el año actual está listo
      if (!(_phase2Completer?.isCompleted ?? true)) _phase2Completer?.complete();
      if (progressNotifier != null) progressNotifier.value = 0.75;

      // 2. Cargar el historial (últimos 3 años) en background real (Fase 2b)
      final List<Future<List<Map<String, dynamic>>>> futures = [];
      final List<int> years = [];

      for (var year = currentYear - 1; year >= currentYear - 3; year--) {
        years.add(year);
        futures.add(fetchRequest(
          filter: getFilterForYear(year),
          expand: 'C_Order_ID(\$select=DocumentNo),C_BPartner_ID(\$select=Name,Description)',
        ).then((v) {
          if (progressNotifier != null) progressNotifier.value += (0.25 / 3);
          return v;
        }));
      }

      final List<List<Map<String, dynamic>>> results = await Future.wait(futures);

      bool newHistoryAdded = false;
      for (int i = 0; i < results.length; i++) {
        final year = years[i];
        final yearReqs = results[i];
        
        if (yearReqs.isNotEmpty) {
          final existingIds = requests.map((r) => r['id']).toSet();
          for (var r in yearReqs) {
            if (!existingIds.contains(r['id'])) {
              requests.add(Map<String, dynamic>.from(r));
              newHistoryAdded = true;
            }
          }
          _archivedYearsLoaded.add(year);
        }
      }

      isFullyLoaded = true;
      if (progressNotifier != null) progressNotifier.value = 1.0;
      if (!(_phase2bCompleter?.isCompleted ?? true)) _phase2bCompleter?.complete();
      
      if (newHistoryAdded) {
        backgroundSyncNotifier.value = !backgroundSyncNotifier.value;
      }

    } catch (e) {
      if (!(_phase2Completer?.isCompleted ?? true)) _phase2Completer?.completeError(e);
      if (!(_phase2bCompleter?.isCompleted ?? true)) _phase2bCompleter?.completeError(e);
    }
  }

  // --- Utilidades de Gestión ---

  static void clear() {
    extSupportBpIds.clear();
    projects.clear();
    requests.clear();
    _rawBPartners.clear();
    bPartners.clear();
    productChips.clear();
    users.clear();
    salesReps.clear();
    statuses.clear();
    statusIsFinalCloseMap.clear();
    statusIsOpenMap.clear();
    statusCategoryMap.clear();
    requestTypes.clear();
    requestTypeCategoryMap.clear();
    categories.clear();
    groups.clear();
    
    isDataLoaded = false;
    isFullyLoaded = false;
    _archivedYearsLoaded.clear();
  }

  static Future<void> syncSingleRequest(int requestId) async {
    try {
      const expand =
          "R_Status_ID(\$select=Name,IsOpen,IsClosed),R_Group_ID(\$select=Name),R_RequestType_ID(\$select=Name),R_Category_ID(\$select=Name),C_Order_ID(\$select=DocumentNo),C_BPartner_ID(\$select=Name,Description)";
      final freshData = await fetchRequest(
        filter: "id eq $requestId",
        expand: expand,
      );
      if (freshData.isNotEmpty) {
        final newReq = freshData.first;
        final index = requests.indexWhere(
          (r) => r['id'].toString() == requestId.toString(),
        );
        if (index != -1) {
          requests[index] = newReq;
        } else {
          requests.insert(0, newReq);
        }
        // Notificar a los interesados que la caché ha cambiado
        backgroundSyncNotifier.value = !backgroundSyncNotifier.value;
      }
    } catch (e) {
      // Ignored: silent fail on background single sync
    }
  }

  static void removeRequest(int requestId) {
    requests.removeWhere((r) => r['id'].toString() == requestId.toString());
  }

  static Future<bool> checkIfSyncNeeded() async {
    if (!isDataLoaded) return true;
    try {
      String? reqFilter;
      if (!AccessControl.isAdmin) {
        if (AccessControl.isExtSupport && User.userID != null) {
          if (extSupportBpIds.isNotEmpty) {
            reqFilter = "(${extSupportBpIds.map((id) => "C_BPartner_ID eq $id").join(' or ')})";
          } else {
            reqFilter = "C_BPartner_ID eq -1";
          }
        } else if (User.cBPartnerID != null) {
          reqFilter = "C_BPartner_ID eq ${User.cBPartnerID}";
        }
        if (reqFilter != null) {
          if (AccessControl.isRealProject) {
            reqFilter += " and C_Project_ID gt 0";
          } else if (AccessControl.isRealSupport) {
            reqFilter += " and Record_UU eq null";
          }
        }
      }
      final reqUri = Uri.parse(
        '${Endpoint.request}?\$top=1&\$orderby=Updated desc${reqFilter != null ? '&\$filter=$reqFilter' : ''}',
      );
      final resReq = await http.get(
        reqUri,
        headers: {
          'Authorization': Token.token,
          'Content-Type': 'application/json',
        },
      );

      if (resReq.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resReq.bodyBytes));
        final records = data['records'] as List?;
        if (records != null && records.isNotEmpty) {
          final remoteUpdate = records[0]['Updated'];
          String? localUpdate;
          for (var r in requests) {
            if (r['Updated'] != null) {
              if (localUpdate == null ||
                  r['Updated'].compareTo(localUpdate) > 0) {
                localUpdate = r['Updated'];
              }
            }
          }
          if (localUpdate != null && remoteUpdate != null) {
            return remoteUpdate.compareTo(localUpdate) > 0;
          }
          return true;
        }
      }
      return false;
    } catch (e) {
      return true;
    }
  }

  static Future<void> performSmartSync(
    BuildContext context,
    Future<void> Function() onSyncAction,
  ) async {
    ToastMessage.show(
      context: context,
      message: AppLocale.checkingNewInformation.getString(context),
      type: ToastType.help,
    );
    if (await checkIfSyncNeeded()) {
      if (context.mounted) {
        ToastMessage.show(
          context: context,
          message: AppLocale.synchronizing.getString(context),
          type: ToastType.help,
        );
      }
      await onSyncAction();
    } else {
      if (context.mounted) {
        ToastMessage.show(
          context: context,
          message: AppLocale.synchronized.getString(context),
          type: ToastType.success,
        );
      }
    }
  }

  static bool _isForceSyncing = false;

  static Future<void> forceFullSyncWithProgress(
    BuildContext context, {
    required Future<void> Function() onSyncAction,
  }) async {
    if (_isForceSyncing) {
      ToastMessage.show(
        context: context,
        message: 'Ya hay una actualización en progreso',
        type: ToastType.help,
      );
      return;
    }
    _isForceSyncing = true;
    
    final progressNotifier = ValueNotifier<double>(0.0);
    
    // We can't import custom_toast here because it might cause a circular dependency or it's not imported.
    // Wait, global_cache is in api/. Let's just import custom_toast dynamically if needed, 
    // or better yet, since CustomToast is in ui/Shared_Custom, let's just do it directly.
    // Oh, I need to make sure I add the import at the top. Let's add it in another chunk.
    final item = ToastMessage.showProgress(
      context: context,
      title: 'Actualizando Información...',
      progressNotifier: progressNotifier,
    );

    try {
      await syncData(force: true, progressNotifier: progressNotifier);
      if (phase2SyncFuture != null) await phase2SyncFuture;
      if (phase2bSyncFuture != null) await phase2bSyncFuture;

      if (context.mounted) {
        ToastMessage.dismiss(item);
        ToastMessage.show(
          context: context,
          message: 'Sincronización completa',
          type: ToastType.success,
        );
        await onSyncAction();
      }
    } catch (e) {
      if (context.mounted) {
        ToastMessage.dismiss(item);
        ToastMessage.show(
          context: context,
          message: 'Error al sincronizar: $e',
          type: ToastType.failure,
        );
      }
    } finally {
      _isForceSyncing = false;
    }
  }
  static final Map<int, Completer<void>> _activeProjectCompleters = {};

  /// Carga todas las solicitudes de un proyecto en segundo plano de forma completa.
  static Future<void> loadProjectRequestsInBackground(
    int projectId, {
    List<String>? taskUUIDs,
    Function(List<Map<String, dynamic>>)? onUpdate,
  }) async {
    // Si ya se está cargando este proyecto, devolvemos el futuro existente para que el llamante espere.
    if (_activeProjectCompleters.containsKey(projectId)) {
      return _activeProjectCompleters[projectId]!.future;
    }

    final completer = Completer<void>();
    _activeProjectCompleters[projectId] = completer;
    projectLoadingStatus[projectId] = true;

    try {      
      final currentYear = DateTime.now().year;
      final threeYearsAgo = currentYear - 3;
      
      // 1. Cargar solicitudes del AÑO ACTUAL para este Proyecto (por ID directo)
      final reqsCurrent = await fetchRequest(
        filter: "IsActive eq true and C_Project_ID eq $projectId",
        expand: 'C_Order_ID(\$select=DocumentNo),R_Status_ID(\$select=Name,IsOpen,IsClosed),R_RequestType_ID,R_Category_ID,C_BPartner_ID(\$select=Name,Description)'
      );
      
      if (reqsCurrent.isNotEmpty) {
        _updateProjectCache(projectId, reqsCurrent);
        if (onUpdate != null) onUpdate(projectRequestsCache[projectId]!);
      }

      // 2. Cargar HISTÓRICO (3 años) para este Proyecto (por ID directo)
      final filterHistory = "C_Project_ID eq $projectId and Created ge '$threeYearsAgo-01-01T00:00:00Z' and Created lt '$currentYear-01-01T00:00:00Z'";
      final reqsHistory = await fetchRequest(
        filter: filterHistory,
        expand: 'C_Order_ID(\$select=DocumentNo),R_Status_ID,R_RequestType_ID,R_Category_ID,C_BPartner_ID(\$select=Name,Description)'
      );

      if (reqsHistory.isNotEmpty) {
        _updateProjectCache(projectId, reqsHistory);
        if (onUpdate != null) onUpdate(projectRequestsCache[projectId]!);
      }

    } catch (_) {
      // Ignored: Fail silently
    } finally {
      projectLoadingStatus[projectId] = false;
      _activeProjectCompleters.remove(projectId);
      if (!completer.isCompleted) completer.complete();
    }
  }

  static void _updateProjectCache(int projectId, List<Map<String, dynamic>> newReqs) {
    final current = projectRequestsCache[projectId] ?? [];
    final Map<int, Map<String, dynamic>> map = {
      for (var r in current) r['id']: r
    };
    
    for (var r in newReqs) {
      if (r['id'] != null) map[r['id']] = r;
    }
    
    projectRequestsCache[projectId] = map.values.toList();
  }

  static final Map<int, Completer<void>> _activeSupportBpCompleters = {};

  static Future<void> loadSupportBpRequestsInBackground(int bpId) async {
    if (_activeSupportBpCompleters.containsKey(bpId)) {
      return _activeSupportBpCompleters[bpId]!.future;
    }

    final completer = Completer<void>();
    _activeSupportBpCompleters[bpId] = completer;

    try {
      final currentYear = DateTime.now().year;
      final threeYearsAgo = currentYear - 3;
      
      final filterCurrent = "C_BPartner_ID eq $bpId and Created ge '$currentYear-01-01T00:00:00Z' and Record_UU eq null";
      final reqsCurrent = await fetchRequest(
        filter: filterCurrent,
        expand: 'C_Order_ID(\$select=DocumentNo),C_BPartner_ID(\$select=Name,Description)'
      );
      
      if (reqsCurrent.isNotEmpty) {
        _mergeSupportRequests(reqsCurrent);
      }

      final filterHistory = "C_BPartner_ID eq $bpId and Created ge '$threeYearsAgo-01-01T00:00:00Z' and Created lt '$currentYear-01-01T00:00:00Z' and Record_UU eq null";
      final reqsHistory = await fetchRequest(
        filter: filterHistory,
        expand: 'C_Order_ID(\$select=DocumentNo),C_BPartner_ID(\$select=Name,Description)'
      );

      if (reqsHistory.isNotEmpty) {
        _mergeSupportRequests(reqsHistory);
      }
    } catch (e) {
      // Ignorar error temporalmente
    } finally {
      _activeSupportBpCompleters.remove(bpId);
      if (!completer.isCompleted) completer.complete();
    }
  }

  static void _mergeSupportRequests(List<Map<String, dynamic>> newReqs) {
    final existingIds = requests.map((r) => r['id']).toSet();
    for (var r in newReqs) {
      if (!existingIds.contains(r['id'])) {
        requests.add(Map<String, dynamic>.from(r));
      } else {
        final index = requests.indexWhere((req) => req['id'] == r['id']);
        if (index != -1) {
          requests[index] = Map<String, dynamic>.from(r);
        }
      }
    }
  }

  static Future<Map<String, dynamic>?> _fetchAdminCompany() async {
    try {
      final url = "${Endpoint.cBPartner}?\$filter=C_BPartner_UU eq 'e4e48cad-f8f8-4f61-954c-60f431bd5d95'";
      final response = await http.get(Uri.parse(url), headers: {'Content-Type': 'application/json', 'Authorization': Token.token});
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        final records = decoded['records'] as List;
        if (records.isNotEmpty) {
          final bp = records.first;
          return {
            'id': bp['id'],
            'Name': bp['identifier'] ?? bp['Name'] ?? 'Empresa Administradora'
          };
        }
      }
    } catch (_) {
      // Ignored: Fail silently
    }
    return null;

  }
  static Future<void> _fetchMailTemplateIds() async {
    try {
      // 1. Fetch AD_SysConfig UUIDs
      final sysUrl = "${Endpoint.adSysConfig}?\$filter=Name eq 'Prim_new_request_mail_UU' or Name eq 'Prim_update_request_mail_UU' or Name eq 'Prim_status_update_request_mail_UU'";
      final sysRes = await http.get(Uri.parse(sysUrl), headers: {'Content-Type': 'application/json', 'Authorization': Token.token});
      if (sysRes.statusCode != 200) {
        CurrentLogMessage.add('Error fetching AD_SysConfig for Mail Templates: ${sysRes.statusCode} - ${sysRes.body}', level: 'ERROR', tag: 'GlobalCache');
        return;
      }
      
      final sysDecoded = json.decode(utf8.decode(sysRes.bodyBytes));
      final sysRecords = sysDecoded['records'] as List?;
      if (sysRecords == null || sysRecords.isEmpty) {
        return;
      }
      
      String? newReqUU;
      String? updateReqUU;
      String? statusUpdateUU;
      
      for (var r in sysRecords) {
        if (r['Name'] == 'Prim_new_request_mail_UU') newReqUU = r['Value'];
        if (r['Name'] == 'Prim_update_request_mail_UU') updateReqUU = r['Value'];
        if (r['Name'] == 'Prim_status_update_request_mail_UU') statusUpdateUU = r['Value'];
      }
      
      // 2. Fetch R_MailText IDs
      final uuList = [newReqUU, updateReqUU, statusUpdateUU].where((u) => u != null && u.isNotEmpty).toList();
      if (uuList.isEmpty) return;
      
      final filterConditions = uuList.map((u) => "R_MailText_UU eq '$u'").join(' or ');
      final mailUrl = "${Endpoint.rMailText}?\$filter=$filterConditions";
      
      final mailRes = await http.get(Uri.parse(mailUrl), headers: {'Content-Type': 'application/json', 'Authorization': Token.token});
      if (mailRes.statusCode != 200) {
        CurrentLogMessage.add('Error fetching R_MailText: ${mailRes.statusCode} - ${mailRes.body}', level: 'ERROR', tag: 'GlobalCache');
        return;
      }
      
      final mailDecoded = json.decode(utf8.decode(mailRes.bodyBytes));
      final mailRecords = mailDecoded['records'] as List?;
      if (mailRecords == null || mailRecords.isEmpty) {
        return;
      }
      
      for (var r in mailRecords) {
        // En caso de que la respuesta retorne la llave en minúsculas por configuración del JSON serializador
        String? uu;
        r.forEach((key, value) {
          final k = key.toLowerCase();
          if (k == 'r_mailtext_uu' || k == 'uuid' || k == 'uid') {
            uu = value?.toString();
          }
        });
        
        final id = r['id'] as int?;
        if (id == null) continue;
        
        // Comparación quitando posibles espacios o mayúsculas
        if (uu?.trim().toLowerCase() == newReqUU?.toString().trim().toLowerCase()) newRequestMailId = id;
        if (uu?.trim().toLowerCase() == updateReqUU?.toString().trim().toLowerCase()) updateRequestMailId = id;
        if (uu?.trim().toLowerCase() == statusUpdateUU?.toString().trim().toLowerCase()) statusUpdateRequestMailId = id;
      }
      
      CurrentLogMessage.add('Loaded Mail Templates: New($newRequestMailId), Update($updateRequestMailId), Status($statusUpdateRequestMailId)', level: 'INFO', tag: 'GlobalCache');
    } catch (e) {
      CurrentLogMessage.add('Exception in _fetchMailTemplateIds: $e', level: 'ERROR', tag: 'GlobalCache');
    }
  }
}
