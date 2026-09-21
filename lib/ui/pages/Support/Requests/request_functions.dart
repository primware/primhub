import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:primhub/api/api_http.dart' as http;
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/ImagesManagment/post_attachments.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/api/global_cache.dart';


import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ImagesManagment/fetch_attachments.dart';
import 'package:primhub/ImagesManagment/download_attachments.dart';
import 'package:primhub/ui/pages/Projects/Projects_Widgets/file_preview_manager.dart';


// --- MAPAS DE REFERENCIA ---

// ignore: constant_identifier_names
const Map<int, String> SUPPORT_STATUS_MAPPING = {
  1000003: 'Recibida',
  1000016: 'Asignada',
  1000019: 'Archivada',
  1000000: 'En proceso',
  1000009: 'En espera del cliente',
  1000017: 'En pruebas de calidad',
  1000001: 'Por entregar',
  1000030: 'En evaluacion del cliente',
  1000002: 'Aprobada por el cliente',
  1000018: 'Implementada en produccion',
  1000015: 'Anulada',
};

const Map<String, String> priorityMap = {'Urgente': '1', 'Alta': '3', 'Media': '5', 'Baja': '7', 'Muy baja': '9'};

// --- UTILIDADES DE FORMATO ---

String extractTime(String? val) {
  if (val == null || val.isEmpty) return '';
  String t = val;
  if (t.contains('T')) {
    t = t.split('T')[1];
  }
  return t.replaceAll('Z', '');
}

String ensureIsoDate(String val) {
  if (val.isEmpty) return "";
  if (val.contains('T')) return val;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(val)) {
    return "${val}T00:00:00Z";
  }
  return val;
}

String ensureIsoTime(String? dateContext, String time) {
  if (time.isEmpty) return '';

  // 1. Get a clean time part (HH:mm:ss)
  String timePart = time;
  if (time.contains('T')) {
    timePart = time.split('T')[1];
  }
  timePart = timePart.replaceAll('Z', '');
  if (timePart.length == 5) timePart = "$timePart:00";

  // 2. Return format specifically expected by iDempiere for Time fields (HH:mm:ss'Z')
  return "${timePart}Z";
}

String? getDropdownValue(dynamic rawValue) {
  final extracted = DocumentsLogic.extractValue(rawValue);
  return extracted == 'N/A' ? null : extracted;
}

String stripHtmlTags(String htmlString) {
  RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
  return htmlString
      .replaceAll(exp, ' ')
      .replaceAll('&#34;', '"')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Limpia los nombres de estado eliminando prefijos numéricos como '10_' y sufijos únicos
String cleanStatusName(String name) {
  name = name.replaceAll(RegExp(r'^\d+_'), '').trim();
  name = name.replaceAll(RegExp(r'#_\d+$'), '').trim();
  return name;
}

double? tryGetDouble(Map<String, dynamic> map, List<String> keys) {
  for (var key in keys) {
    if (map.containsKey(key) && map[key] != null) {
      final val = map[key];
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val);
    }
  }
  return null;
}

/// Extrae el ID de la ficha de producto de forma robusta.
int? extractProductChipId(Map<String, dynamic> req) {
  final raw = (req['C_BPartner_Product_Chip_ID'] is Map 
      ? req['C_BPartner_Product_Chip_ID']['id'] 
      : (req['C_BPartner_Product_Chip_ID'] ?? 
         req['C_BPartner_ProductChip_ID'] ?? 
         req['C_BPartner_Product_Chip'] ??
         req['C_BPartner_Product_Chip_ID_ID'] ?? 
         req['Product_Chip_ID']));
  
  if (raw == null) return null;
  if (raw is int) return raw;
  return int.tryParse(raw.toString());
}

String? _getBestChipName(Map map) {
  final desc = map['Description']?.toString().trim();
  if (desc != null && desc.isNotEmpty) return desc;
  
  final name = map['Name']?.toString().trim();
  if (name != null && name.isNotEmpty && double.tryParse(name) == null) return name;
  
  final identifier = map['identifier']?.toString().trim();
  if (identifier != null && identifier.isNotEmpty && double.tryParse(identifier) == null) return identifier;
  
  return name ?? identifier ?? desc;
}

String? extractProductChipName(Map<String, dynamic> req) {
  // Primero extraemos el ID numérico y buscamos la ficha completa en caché (tiene más datos como Description)
  int? chipId = extractProductChipId(req);
  if (chipId != null) {
    final chip = GlobalCache.productChips.firstWhere((c) {
      final cId = int.tryParse(c['id']?.toString() ?? '') ?? int.tryParse(c['C_BPartner_Product_Chip_ID']?.toString() ?? '');
      return cId == chipId;
    }, orElse: () => {});
    if (chip.isNotEmpty) {
      final cacheName = _getBestChipName(chip);
      if (cacheName != null && cacheName.isNotEmpty && double.tryParse(cacheName) == null) {
        return cacheName; // Solo retornamos del caché si no es un simple número
      }
    }
  }

  // Si falló el caché o devolvió un número, intentamos extraer de los mapas anidados
  String? mapFallback;
  if (req['T_ProductChip_ID'] is Map) mapFallback ??= _getBestChipName(req['T_ProductChip_ID'] as Map);
  if (req['C_BPartner_Product_Chip'] is Map) mapFallback ??= _getBestChipName(req['C_BPartner_Product_Chip'] as Map);
  if (req['C_BPartner_Product_Chip_ID'] is Map) mapFallback ??= _getBestChipName(req['C_BPartner_Product_Chip_ID'] as Map);
  if (req['C_BPartner_ProductChip_ID'] is Map) mapFallback ??= _getBestChipName(req['C_BPartner_ProductChip_ID'] as Map);
  if (req['Product_Chip_ID'] is Map) mapFallback ??= _getBestChipName(req['Product_Chip_ID'] as Map);

  if (mapFallback != null && mapFallback.isNotEmpty) {
    // Si el map tiene un nombre válido (no numérico), lo usamos
    if (double.tryParse(mapFallback) == null) return mapFallback;
  }

  // Fallback final a las llaves que contienen el string Name directamente
  final stringFallback = (req['T_ProductChip_ID_Name'] ?? 
          req['C_BPartner_Product_Chip_ID_Name'] ?? 
          req['C_BPartner_ProductChip_ID_Name'] ?? 
          req['Product_Chip_ID_Name'] ?? 
          req['C_BPartner_Product_Chip_Name'])?.toString();
          
  if (stringFallback != null && stringFallback.isNotEmpty && double.tryParse(stringFallback) == null) {
    return stringFallback;
  }
  
  // Si todo falla, al menos devolvemos el ID o el mapFallback (que podría ser numérico)
  return mapFallback ?? stringFallback ?? chipId?.toString();
}

// --- LLAMADAS A LA API ---

/// Obtiene las solicitudes usando paginación para asegurar que se traigan todos los registros.
Future<List<Map<String, dynamic>>> fetchRequest({String? model = 'R_Request', String? filter, int? top, int? initialSkip, String? select, String? orderBy, String? expand}) async {
  List<Map<String, dynamic>> allRecords = [];
  int skip = initialSkip ?? 0;
  // Si se especifica 'top', se usa como tamaño de página y no se pagina más.
  // Si no, se usa un tamaño de página estándar para la paginación completa.
  final int pageSize = top ?? 100;
  bool hasMore = true;

  try {
    while (hasMore) {
      final queryParams = {'\$skip': skip.toString(), '\$top': pageSize.toString(), '\$limit': pageSize.toString(), '\$orderBy': orderBy ?? 'Created desc'};

      if (filter != null && filter.isNotEmpty) {
        queryParams['\$filter'] = filter;
      }
      if (select != null && select.isNotEmpty) {
        queryParams['\$select'] = select;
      }
      if (expand != null && expand.isNotEmpty) {
        queryParams['\$expand'] = expand;
      }

      final endpoint = '${Endpoint.baseUrl}/api/v1/models/$model';
      final uri = Uri.parse(endpoint).replace(queryParameters: queryParams);
      var response = await http.get(uri, headers: {'Content-Type': 'application/json; charset=UTF-8', 'Authorization': Token.token});

      if (response.statusCode == 401) {
        final refreshed = await handleTokenRefresh();
        if (refreshed) {
          response = await http.get(uri, headers: {'Content-Type': 'application/json; charset=UTF-8', 'Authorization': Token.token});
        } else {
          return [];
        }
      }

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        final records = jsonResponse['records'] as List;

        if (records.isEmpty) {
          hasMore = false;
        } else {
          // Mapeo básico para asegurar que las llaves existan
          final mapped = records.map((r) => Map<String, dynamic>.from(r)).toList();
          allRecords.addAll(mapped);

          // Si se especificó un 'top', solo hacemos una página. Si no, paginamos hasta el final.
          if (records.length < pageSize || top != null) {
            hasMore = false;
          } else {
            skip += pageSize;
          }
        }
      } else {
        hasMore = false;
        if (allRecords.isEmpty) throw Exception('Error API: ${response.statusCode}');
      }
    }
  } catch (_) {
      // Ignored: Fail silently
    }
  return allRecords;
}

/// Obtiene UNA página de solicitudes y opcionalmente el total de registros
Future<Map<String, dynamic>> fetchRequestPaginated({
  String? model = 'R_Request',
  String? filter,
  required int skip,
  required int top,
  String? select,
  String? orderBy,
  String? expand,
  bool fetchCount = false,
}) async {
  List<Map<String, dynamic>> recordsList = [];
  int totalRecords = -1;

  try {
    final queryParams = {
      '\$skip': skip.toString(),
      '\$top': top.toString(),
      '\$limit': top.toString(),
      '\$orderBy': orderBy ?? 'Created desc'
    };

    if (filter != null && filter.isNotEmpty) {
      queryParams['\$filter'] = filter;
    }
    if (select != null && select.isNotEmpty) {
      queryParams['\$select'] = select;
    }
    if (expand != null && expand.isNotEmpty) {
      queryParams['\$expand'] = expand;
    }
    
    if (fetchCount) {
      queryParams['\$inlinecount'] = 'allpages'; // OData common way to get count
    }

    final endpoint = '${Endpoint.baseUrl}/api/v1/models/$model';
    final uri = Uri.parse(endpoint).replace(queryParameters: queryParams);
    
    var response = await http.get(uri, headers: {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': Token.token
    });

    if (response.statusCode == 401) {
      final refreshed = await handleTokenRefresh();
      if (refreshed) {
        response = await http.get(uri, headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': Token.token
        });
      } else {
        return {'records': [], 'totalCount': 0};
      }
    }

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      List? records;
      if (jsonResponse is Map) {
        records = (jsonResponse['records'] ?? jsonResponse['value']) as List?;
      } else if (jsonResponse is List) {
        records = jsonResponse;
      }
      
      if (records != null) {
        recordsList = records.map((r) => Map<String, dynamic>.from(r)).toList();
      }
      
      // Intentar extraer el conteo total de varias formas comunes en OData
      if (jsonResponse is Map) {
        if (jsonResponse.containsKey('@odata.count')) {
          totalRecords = int.tryParse(jsonResponse['@odata.count'].toString()) ?? -1;
        } else if (jsonResponse.containsKey('inlinecount')) {
          totalRecords = int.tryParse(jsonResponse['inlinecount'].toString()) ?? -1;
        } else if (jsonResponse.containsKey('totalCount')) {
          totalRecords = int.tryParse(jsonResponse['totalCount'].toString()) ?? -1;
        } else if (jsonResponse.containsKey('count')) {
          totalRecords = int.tryParse(jsonResponse['count'].toString()) ?? -1;
        }
      }
    }
  } catch (_) {
      // Ignored: Fail silently
    }

  // Si fetchCount es true pero la API no lo retornó en la respuesta principal,
  // hacemos una petición manual muy rápida sin expand para contar.
  if (fetchCount && totalRecords == -1) {
    totalRecords = await fetchRequestCount(model: model, filter: filter);
  }

  return {
    'records': recordsList,
    'totalCount': totalRecords == -1 ? recordsList.length : totalRecords
  };
}

/// Función auxiliar para obtener el conteo de registros para un filtro dado.
Future<int> fetchRequestCount({String? model = 'R_Request', String? filter}) async {
  try {
    final queryParams = {
      '\$top': '1',
      '\$limit': '1',
      '\$select': 'id',
      '\$inlinecount': 'allpages',
    };
    if (filter != null && filter.isNotEmpty) {
      queryParams['\$filter'] = filter;
    }
    
    final endpoint = '${Endpoint.baseUrl}/api/v1/models/$model';
    final uri = Uri.parse(endpoint).replace(queryParameters: queryParams);
    
    final response = await http.get(uri, headers: {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': Token.token
    });

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      
      if (jsonResponse is Map) {
        if (jsonResponse.containsKey('@odata.count')) {
          return int.tryParse(jsonResponse['@odata.count'].toString()) ?? 0;
        }
        if (jsonResponse.containsKey('inlinecount')) {
          return int.tryParse(jsonResponse['inlinecount'].toString()) ?? 0;
        }
        if (jsonResponse.containsKey('totalCount')) {
          return int.tryParse(jsonResponse['totalCount'].toString()) ?? 0;
        }
        if (jsonResponse.containsKey('count')) {
          return int.tryParse(jsonResponse['count'].toString()) ?? 0;
        }
        
        final records = jsonResponse['records'] as List?;
        if (records != null) return records.length;
        
        final value = jsonResponse['value'] as List?;
        if (value != null) return value.length;
      } else if (jsonResponse is List) {
        return jsonResponse.length;
      }
    }
  } catch (_) {
      // Ignored: Fail silently
    }
  return 0;
}

Future<List<Map<String, dynamic>>> fetchProjectAndTaskRequests(int projectId, {List<String>? taskUUIDs, String? additionalFilter, String? select, String? expand}) async {
  List<Map<String, dynamic>> allReqs = [];

  taskUUIDs ??= await ProjectsLogic().fetchProjectTaskUUIDs(projectId);

  String baseFilter = "C_Project_ID eq $projectId";

  // 1. Solicitudes vinculadas a nivel de proyecto (Cabecera)
  final pReqs = await fetchRequest(filter: baseFilter, select: select, expand: expand ?? 'C_Order_ID(\$select=DocumentNo),R_Status_ID,R_RequestType_ID,R_Category_ID,Priority');
  allReqs.addAll(pReqs);

  // 2. Solicitudes vinculadas a nivel de Tareas (Record_UU) particionadas de a 10
  if (taskUUIDs.isNotEmpty) {
    for (var i = 0; i < taskUUIDs.length; i += 10) {
      final chunk = taskUUIDs.sublist(i, i + 10 > taskUUIDs.length ? taskUUIDs.length : i + 10);
      String chunkFilter = chunk.map((u) => "Record_UU eq '$u'").join(' or ');
      chunkFilter = "($chunkFilter)";
      if (additionalFilter != null && additionalFilter.isNotEmpty) {
        chunkFilter = "$chunkFilter and $additionalFilter";
      }
      final tReqs = await fetchRequest(filter: chunkFilter, select: select, expand: expand);
      allReqs.addAll(tReqs);
    }
  }

  // 3. Deduplicación por si hay un ticket que tiene tanto C_Project_ID como Record_UU
  final uniqueReqsMap = <int, Map<String, dynamic>>{};
  for (var r in allReqs) {
    if (r['id'] != null) uniqueReqsMap[r['id']] = r;
  }
  return uniqueReqsMap.values.toList();
}

Future<Map<String, dynamic>> fetchStatusesWithMetadata() async {
  try {
    final response = await http.get(
      Uri.parse('${Endpoint.baseUrl}/api/v1/models/R_Status?\$limit=100'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': Token.token,
      },
    );
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      List<dynamic> records = List<dynamic>.from(jsonResponse['records'] ?? []);

      records.sort((a, b) {
        final seqA = (a['SeqNo'] as num?)?.toInt() ?? 9999;
        final seqB = (b['SeqNo'] as num?)?.toInt() ?? 9999;
        return seqA.compareTo(seqB);
      });

      final Map<String, int> nameToId = {};
      final Map<int, bool> idToIsFinalClose = {};
      final Map<int, bool> idToIsOpen = {};
      final Map<int, int> idToCategoryId = {};
      final Map<int, String> categoryIdToName = {};
      final Map<int, int> categoryCounters = {};
      
      int noCategoryCounter = 1;
      
      for (var r in records) {
        final originalName = r['Name']?.toString().trim() ?? '';
        if (originalName.isEmpty) continue;
        final id = (r['id'] as num).toInt();
        final rawIsClosed = r['IsClosed'] ?? r['isClosed'];
        final isClosedStr = rawIsClosed?.toString().trim().toLowerCase();
        bool isClosed = isClosedStr == 'true' || isClosedStr == 'y' || rawIsClosed == true;
        
        final rawIsFinalClose = r['IsFinalClose'] ?? r['isFinalClose'];
        final isFinalCloseStr = rawIsFinalClose?.toString().trim().toLowerCase();
        bool isFinalClose = isFinalCloseStr == 'true' || isFinalCloseStr == 'y' || rawIsFinalClose == true || isClosed;

        final rawIsOpen = r['IsOpen'] ?? r['isOpen'];
        final isOpenStr = rawIsOpen?.toString().trim().toLowerCase();
        bool isOpen = isOpenStr == 'true' || isOpenStr == 'y' || rawIsOpen == true;
        
        final categoryIdRaw = r['R_StatusCategory_ID'] ?? r['r_StatusCategory_ID'] ?? r['r_statuscategory_id'];
        int? categoryId;
        String? categoryName;
        if (categoryIdRaw is Map) {
          categoryId = (categoryIdRaw['id'] as num?)?.toInt();
          categoryName = categoryIdRaw['identifier']?.toString();
        } else if (categoryIdRaw is num) {
          categoryId = categoryIdRaw.toInt();
        }
        
        int currentCounter;
        if (categoryId != null) {
          currentCounter = (categoryCounters[categoryId] ?? 0) + 1;
          categoryCounters[categoryId] = currentCounter;
        } else {
          currentCounter = noCategoryCounter++;
        }
        
        final formattedName = "$currentCounter. $originalName#_$id";
        nameToId[formattedName] = id;
        idToIsFinalClose[id] = isFinalClose;
        idToIsOpen[id] = isOpen;
        if (categoryId != null) {
          idToCategoryId[id] = categoryId;
          if (categoryName != null) {
            categoryIdToName[categoryId] = categoryName;
          }
        }
      }
      return {'nameToId': nameToId, 'idToIsFinalClose': idToIsFinalClose, 'idToIsOpen': idToIsOpen, 'idToCategoryId': idToCategoryId, 'categoryIdToName': categoryIdToName};
    }
  } catch (_) {
      // Ignored: Fail silently
    }
  return {'nameToId': <String, int>{}, 'idToIsFinalClose': <int, bool>{}, 'idToIsOpen': <int, bool>{}, 'idToCategoryId': <int, int>{}};
}

Future<Map<String, int>> fetchStatuses() async {
  final data = await fetchStatusesWithMetadata();
  return data['nameToId'] as Map<String, int>;
}

Future<Map<String, dynamic>> fetchRequestTypesWithMetadata() async {
  try {
    final response = await http.get(
      Uri.parse('${Endpoint.baseUrl}/api/v1/models/R_RequestType'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': Token.token,
      },
    );
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      final records = jsonResponse['records'] as List;
      
      final Map<String, int> nameToId = {};
      final Map<int, int> idToCategoryId = {};
      
      for (var r in records) {
        final name = r['Name'].toString().trim();
        final id = r['id'] as int;
        nameToId[name] = id;
        
        final categoryIdRaw = r['R_StatusCategory_ID'];
        if (categoryIdRaw is Map) {
          idToCategoryId[id] = (categoryIdRaw['id'] as num).toInt();
        } else if (categoryIdRaw is num) {
          idToCategoryId[id] = categoryIdRaw.toInt();
        }
      }
      return {'nameToId': nameToId, 'idToCategoryId': idToCategoryId};
    }
  } catch (_) {
      // Ignored: Fail silently
    }
  return {'nameToId': <String, int>{}, 'idToCategoryId': <int, int>{}};
}

Future<Map<String, int>> fetchRequestTypes() async {
  final data = await fetchRequestTypesWithMetadata();
  return data['nameToId'] as Map<String, int>;
}

Future<List<Map<String, dynamic>>> fetchCategories({bool? isPrimhub}) async {
  try {
    final url = Uri.parse('${Endpoint.baseUrl}/api/v1/models/R_Category');
    
    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': Token.token,
      },
    );
    
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      final List records = jsonResponse['records'] ?? [];
      
      return records.map((r) {
        final map = Map<String, dynamic>.from(r);
        // Extraer ID de prioridad si viene como objeto
        if (map['Priority'] is Map) {
          map['Priority'] = map['Priority']['id'];
        }
        // Asegurar que showinprimhub sea booleano, ignorando mayúsculas y minúsculas
        final rawShow = map.entries
            .firstWhere((e) => e.key.toLowerCase() == 'showinprimhub',
                orElse: () => const MapEntry('showinprimhub', null))
            .value;
        map['showinprimhub'] = rawShow == true || rawShow?.toString().toLowerCase() == 'true';
        return map;
      }).toList();
    } else {
    }
  } catch (_) {
      // Ignored: Fail silently
    }
  return [];
}

Future<Map<String, int>> fetchGroups() async {
  try {
    final response = await http.get(
      Uri.parse('${Endpoint.baseUrl}/api/v1/models/R_Group'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': Token.token,
      },
    );
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      final records = jsonResponse['records'] as List;
      return {for (var r in records) r['Name'].toString().trim(): r['id'] as int};
    }
  } catch (_) {
      // Ignored: Fail silently
    }
  return {};
}

/// Procesa la lista cruda de la API para calcular horas y formatear la UI.
Future<Map<String, dynamic>> processRequests(List<dynamic> requests, Map<String, int> statusIdMap) async {
  List<dynamic> rawRequests = requests.map((req) {
    final newReq = Map<String, dynamic>.from(req);
    if (newReq['DateCompletePlan'] != null && newReq['DateCompletePlan'].toString().isNotEmpty) {
      newReq['DateStartPlan'] = newReq['DateCompletePlan'];
    }
    return newReq;
  }).toList();

  double consumed = 0.0;
  double inProgress = 0.0;

  // El filtrado de soporte (Record_UU) se realiza en la UI o Controller respectivo antes de llamar a processRequests.
  final visibleRequests = requests;

  List<Map<String, dynamic>> processedRequests = [];

  for (var req in visibleRequests) {
    final statusIdFromReq = req['R_Status_ID'] is Map ? req['R_Status_ID']['id'] : req['R_Status_ID'];
    final statusName = req['R_Status_ID'] is Map ? (req['R_Status_ID']['identifier'] ?? req['R_Status_ID']['Name'] ?? req['R_Status_Name'] ?? '') : (req['R_Status_Name'] ?? '');
    
    // Extraer QtyPlan y QtySpent buscando múltiples variantes de nombres de campo

    final double qtySpent = tryGetDouble(req, ['QtySpent', 'qtySpent', 'qty_spent', 'UsedQty', 'used_qty']) ?? 0.0;

    // Lógica de horas basada en metadatos de estado (IsFinalClose)
    bool isFinalCloseStatus = false;
    if (statusIdFromReq != null && GlobalCache.statusIsFinalCloseMap.containsKey(statusIdFromReq)) {
      isFinalCloseStatus = GlobalCache.statusIsFinalCloseMap[statusIdFromReq]!;
    } else {
      isFinalCloseStatus = statusName.toLowerCase().contains('archivada') ||
                           statusName.toLowerCase().contains('anulada') ||
                           statusName.toLowerCase().contains('final close') ||
                           statusName.toLowerCase().contains('cerrada');
    }

    if (isFinalCloseStatus) {
      consumed += qtySpent; // Horas ya cerradas/finalizadas
    } else {
      // Horas en solicitudes activas: se consideran "Estimadas" (inProgress)
      // Según requerimiento: usar QtySpent para que coincida con lo que el usuario revisa.
      inProgress += qtySpent;
    }

    // Lógica de Prioridad (Nivel -> Prioridad)
    String level = 'Media';
    var rawPriority = req['Priority'];

    // Si la prioridad del request es nula, intentamos obtenerla de la categoría
    if (rawPriority == null || (rawPriority is String && rawPriority.isEmpty)) {
      final categoryId = req['R_Category_ID'] is Map ? req['R_Category_ID']['id'] : req['R_Category_ID'];
      if (categoryId != null) {
        final cat = GlobalCache.rawCategories.firstWhere((c) => c['id'] == categoryId, orElse: () => {});
        if (cat.isNotEmpty) {
          rawPriority = cat['Priority'];
        }
      }
    }

    if (rawPriority is Map) {
      level = (rawPriority['identifier'] ?? rawPriority['Name'] ?? 'Media').toString();
    } else if (rawPriority != null) {
      final pStr = rawPriority.toString();
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
      } else {
        level = pStr;
      } 
    }
    String status = statusName;
    int? statusId = statusIdFromReq;

    if (statusId != null) {
      bool foundInMap = false;
      if (statusIdMap.isNotEmpty) {
        for (var entry in statusIdMap.entries) {
          if (entry.value == statusId) {
            status = cleanStatusName(entry.key);
            foundInMap = true;
            break;
          }
        }
      }
      if (!foundInMap && SUPPORT_STATUS_MAPPING.containsKey(statusId)) {
        status = cleanStatusName(SUPPORT_STATUS_MAPPING[statusId]!);
      }
    }

    Color baseColor = Colors.green;
    if (level == 'Urgente') {
      baseColor = Colors.purple;
    } else if (level == 'Alta') {
      baseColor = Colors.red;
    } else if (level == 'Media') {
      baseColor = Colors.amber.shade800;
    } else if (level == 'Muy baja') {
      baseColor = Colors.grey;
    }
    String formattedTime = req['Created'] ?? '';
    try {
      if (formattedTime.isNotEmpty) {
        final DateTime date = DateTime.parse(formattedTime).toLocal();
        formattedTime = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {
      // Ignored: Fail silently
    }

    final bpId = req['C_BPartner_ID'] is Map ? (req['C_BPartner_ID']['id'] as num?)?.toInt() : (req['C_BPartner_ID'] as num?)?.toInt();
    final userId = req['AD_User_ID'] is Map ? (req['AD_User_ID']['id'] as num?)?.toInt() : (req['AD_User_ID'] as num?)?.toInt();
    final salesRepId = req['SalesRep_ID'] is Map ? (req['SalesRep_ID']['id'] as num?)?.toInt() : (req['SalesRep_ID'] as num?)?.toInt();

    String bpName = req['C_BPartner_ID'] is Map ? (req['C_BPartner_ID']['identifier'] ?? req['C_BPartner_ID']['Name'] ?? '').toString().trim() : '';
    String bpDescription = req['C_BPartner_ID'] is Map ? (req['C_BPartner_ID']['Description'] ?? req['C_BPartner_ID']['description'] ?? '').toString().trim() : '';
    if (bpId != null) {
      final found = GlobalCache.allBPartners.firstWhere((bp) => (bp['id'] as num?)?.toInt() == bpId, orElse: () => {});
      if (found.isNotEmpty) {
        if (bpName.isEmpty) bpName = (found['Name'] ?? '').toString().trim();
        if (bpDescription.isEmpty) bpDescription = (found['Description'] ?? found['description'] ?? '').toString().trim();
      }
    }

    String userName = req['AD_User_ID'] is Map ? (req['AD_User_ID']['identifier'] ?? req['AD_User_ID']['Name'] ?? '').toString().trim() : '';
    if (userName.isEmpty && userId != null) {
      final found = GlobalCache.users.firstWhere((u) => ((u['AD_User_ID'] ?? u['id']) as num?)?.toInt() == userId, orElse: () => {});
      if (found.isNotEmpty) userName = (found['Name'] ?? '').toString().trim();
    }

    String salesRepName = req['SalesRep_ID'] is Map ? (req['SalesRep_ID']['identifier'] ?? req['SalesRep_ID']['Name'] ?? '').toString().trim() : '';
    if (salesRepName.isEmpty && salesRepId != null) {
      final found = GlobalCache.salesReps.firstWhere((r) => ((r['AD_User_ID'] ?? r['id']) as num?)?.toInt() == salesRepId, orElse: () => {});
      if (found.isNotEmpty) salesRepName = (found['Name'] ?? '').toString().trim();
    }

    final categoryId = req['R_Category_ID'] is Map ? (req['R_Category_ID']['id'] as num?)?.toInt() : (req['R_Category_ID'] as num?)?.toInt();
    String? categoryName = getDropdownValue(req['R_Category_ID']);
    
    // Identificar si es una solicitud de Proyecto (tiene Record_UU) o de Soporte
    final recordUU = req['Record_UU']?.toString().trim();
    final bool isProjectRequest = recordUU != null && recordUU.isNotEmpty;

    // Obtener metadatos de la categoría desde el caché global (ahora contiene todas)
    final catInCache = GlobalCache.rawCategories.firstWhere(
      (c) => (c['id'] as num?)?.toInt() == categoryId, 
      orElse: () => {}
    );

    if (isProjectRequest) {
      // --- LÓGICA PARA PROYECTOS ---
      // Se muestran categorías que tienen showinprimhub = false
      bool isValidProjectCategory = false;
      if (catInCache.isNotEmpty) {
        isValidProjectCategory = catInCache['showinprimhub'] == false;
      }

      if (!isValidProjectCategory) {
        categoryName = 'Sin categoría';
        // En proyectos la prioridad se mantiene tal cual viene del ERP (no hay automatización forzada)
      }
    } else {
      // --- LÓGICA PARA SOPORTE (PRIMHUB) ---
      // Se muestran categorías que tienen showinprimhub = true
      bool isPrimhubCategory = false;
      if (catInCache.isNotEmpty) {
        isPrimhubCategory = catInCache['showinprimhub'] == true;
      }
      
      if (!isPrimhubCategory) {
        categoryName = 'Sin categoría';
        level = 'N/A';
        baseColor = Colors.grey;
      } else {
        // Tomar la prioridad de la categoría (R_Category.Priority)
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
      }
    }

    processedRequests.add({
      'descriptionClean': stripHtmlTags(req['Description'] ?? req['Summary'] ?? ''),
      'id': req['DocumentNo'] ?? req['id'].toString(),
      'realId': req['id'],
      'situation': req['R_RequestType_ID'] is Map ? (req['R_RequestType_ID']['identifier'] ?? req['R_RequestType_ID']['Name'] ?? 'Solicitud') : 'Solicitud',
      'description': req['Description'] ?? req['Summary'] ?? '',
      'level': level,
      'status': status.trim(),
      'statusId': statusId,
      'time': formattedTime,
      'levelColor': baseColor,
      'levelBgColor': baseColor.withOpacity(0.2),
      'statusColor': Colors.grey,
      'dateStartPlan': req['DateStartPlan'] ?? '',
      'dateCompletePlan': req['DateCompletePlan'] ?? '',
      'startTime': extractTime(req['StartTime']),
      'endTime': extractTime(req['EndTime']),
      'qtySpent': qtySpent,
      'startDate': req['StartDate'],
      'closeDate': req['CloseDate'],
      'userName': userName,
      'bpName': bpName,
      'bpDescription': bpDescription,
      'result': req['Result'] ?? '',
      'type': getDropdownValue(req['R_RequestType_ID']),
      'category': categoryName,
      'group': getDropdownValue(req['R_Group_ID']),
      'bpId': bpId,
      'userId': userId,
      'salesRepId': salesRepId,
      'salesRepName': salesRepName,
      'emailSubject': req['CDS_EmailSubject'] ?? '',
      'salesOrderId': req['C_Order_ID'] is Map ? req['C_Order_ID']['id'] : null,
      'salesOrderNo': req['C_Order_ID'] is Map ? req['C_Order_ID']['DocumentNo'] : null,
      'recordUU': req['Record_UU'],
      'productChipId': extractProductChipId(req),
      'productChipName': extractProductChipName(req),
      'isClosed': isFinalCloseStatus,
      'PrimHub_Estimated_development_hours': req['PrimHub_Estimated_development_hours'],
      'original': req,
    });
  }

  return {'rawRequests': rawRequests, 'requests': processedRequests, 'consumedHours': consumed, 'inProgressHours': inProgress};
}

Future<List<Map<String, dynamic>>> fetchRequestUpdates(int requestId) async {
  // Usa la función genérica fetchRequest para obtener las actualizaciones
  final updates = await fetchRequest(
      model: 'R_RequestUpdate',
      filter: "R_Request_ID eq $requestId",
      orderBy: 'Created desc',
      select: 'Created,CreatedBy,Result,ConfidentialTypeEntry,AD_Image_ID,AD_Image1_ID,AD_Image2_ID,AD_Image3_ID');

  // Filtrar actualizaciones basura generadas automáticamente por el backend
  updates.removeWhere((update) {
    final resultText = (update['Result'] ?? '').toString().trim();
    final hasImages = update['AD_Image_ID'] != null ||
        update['AD_Image1_ID'] != null ||
        update['AD_Image2_ID'] != null ||
        update['AD_Image3_ID'] != null;
    
    return (resultText == 'Sin resultado.' || resultText == 'Sin resultado' || resultText.isEmpty) && !hasImages;
  });

  if (!AccessControl.isAdmin) {
    return updates.where((update) {
      final createdBy = update['CreatedBy'];
      String createdByName = '';
      if (createdBy is Map) {
        createdByName = (createdBy['identifier'] ?? createdBy['Name'] ?? '').toString();
      } else {
        createdByName = createdBy?.toString() ?? '';
      }
      final isSystem = createdByName.contains('System (deprecated)');
      
      final confId = update['ConfidentialTypeEntry']?['id']?.toString() ?? update['ConfidentialTypeEntry']?.toString() ?? '';
      final isInternal = confId == 'I';

      if (AccessControl.isSupport) {
        return !isSystem;
      }
      
      return !isSystem && !isInternal;
    }).toList();
  }

  return updates;
}

Future<Map<String, dynamic>> updateRemoteRequest({
  required dynamic id,
  String? priority,
  int? statusId,
  String? statusIdentifier,
  String? summary,
  String? dateStartPlan,
  String? dateCompletePlan,
  String? startTime,
  String? endTime,  
  double? qtySpent,
  double? estimatedDevHours,
  String? startDate,
  String? closeDate,
  String? result,
  int? requestTypeId,
  int? categoryId,
  int? groupId,
  int? salesRepId,
  int? bPartnerId,
  int? userId,
  String? emailSubject,
  int? orderId,
  int? productChipId,
}) async {
  try {
    final url = Uri.parse('${Endpoint.request}/$id');
    final Map<String, dynamic> data = {};

    if (priority != null) data['Priority'] = priorityMap[priority];
    if (summary != null) data['Summary'] = summary;

    if (emailSubject != null) data['CDS_EmailSubject'] = emailSubject;

    if (result != null) data['Result'] = result;
    if (statusId != null) {
      data['R_Status_ID'] = {'id': statusId};
    } else if (statusIdentifier != null) {
      data['R_Status_ID'] = {'identifier': statusIdentifier};
    }

    if (dateStartPlan != null && dateStartPlan.isNotEmpty) data['DateStartPlan'] = ensureIsoDate(dateStartPlan);
    if (dateCompletePlan != null && dateCompletePlan.isNotEmpty) data['DateCompletePlan'] = ensureIsoDate(dateCompletePlan);
    if (startTime != null && startTime.isNotEmpty) data['StartTime'] = ensureIsoTime(dateStartPlan, startTime);
    if (endTime != null && endTime.isNotEmpty) data['EndTime'] = endTime; // El caller ya lo manda como DateTime completo
    if (qtySpent != null) data['QtySpent'] = qtySpent;
    if (estimatedDevHours != null) data['PrimHub_Estimated_development_hours'] = estimatedDevHours;
    
    if (startDate != null) data['StartDate'] = startDate;
    if (closeDate != null) data['CloseDate'] = closeDate;

    if (requestTypeId != null) data['R_RequestType_ID'] = {'id': requestTypeId};
    if (categoryId != null) data['R_Category_ID'] = {'id': categoryId};
    if (groupId != null) data['R_Group_ID'] = {'id': groupId};
    if (salesRepId != null) data['SalesRep_ID'] = salesRepId;
    if (bPartnerId != null) data['C_BPartner_ID'] = {'id': bPartnerId};
    if (userId != null) data['AD_User_ID'] = {'id': userId};
    if (orderId != null) data['C_Order_ID'] = {'id': orderId};
    if (productChipId != null) data['C_BPartner_Product_Chip_ID'] = {'id': productChipId};

    var response = await http.put(url, headers: {'Content-Type': 'application/json', 'Authorization': Token.token}, body: jsonEncode(data));

    if (response.statusCode == 401) {
      final refreshed = await handleTokenRefresh();
      if (refreshed) {
        response = await http.put(url, headers: {'Content-Type': 'application/json', 'Authorization': Token.token}, body: jsonEncode(data));
      } else {
        return {'success': false, 'error': 'Sesión expirada'};
      }
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      return {'success': false, 'error': 'Error ${response.statusCode}'};
    }

    // Sincronizar el caché global inmediatamente para que todas las pantallas se enteren
    await GlobalCache.syncSingleRequest(id);

    return {'success': true};
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> createRequestUpdate({
  required int requestId,
  required String resultText,
  required String confidentialType,
  required List<PlatformFile?> evidences,
}) async {
  try {
    final url = Uri.parse('${Endpoint.baseUrl}/api/v1/models/R_RequestUpdate');
    final Map<String, dynamic> body = {
      "R_Request_ID": requestId,
      "Result": resultText,
      "ConfidentialTypeEntry": confidentialType
    };

    var response = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'Authorization': Token.token},
      body: jsonEncode(body),
    );

    if (response.statusCode == 401) {
      final refreshed = await handleTokenRefresh();
      if (refreshed) {
        response = await http.post(
          url,
          headers: {'Content-Type': 'application/json', 'Authorization': Token.token},
          body: jsonEncode(body),
        );
      } else {
        return {'success': false, 'message': 'Sesión expirada'};
      }
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      return {'success': false, 'message': 'Error creando actualización: ${response.body}'};
    }

    // Si llegamos aquí, se creó el registro. Ahora subimos los adjuntos si existen.
    final newRecord = jsonDecode(utf8.decode(response.bodyBytes));
    final int newRecordId = newRecord['id'];
    final String tableName = '${Endpoint.baseUrl}/api/v1/models/R_RequestUpdate';

    bool allUploadsOk = true;
    for (var file in evidences) {
      if (file != null && file.bytes != null) {
        final success = await postAttachments(
          recordID: newRecordId,
          tableName: tableName,
          convertedFile: {
            'title': file.name,
            'base64': base64Encode(file.bytes!),
          },
        );
        if (!success) allUploadsOk = false;
      }
    }

    if (!allUploadsOk) {
      return {
        'success': true, 
        'message': 'Actualización creada, pero algunos archivos no se pudieron subir.',
        'id': newRecordId
      };
    }

    return {'success': true, 'message': 'Actualización creada con éxito', 'id': newRecordId};
  } catch (e) {
    return {'success': false, 'message': e.toString()};
  }
}

Future<bool> deleteRequestApi(dynamic id) async {
  try {
    var response = await http.delete(Uri.parse('${Endpoint.request}/$id'), headers: {'Authorization': Token.token});

    if (response.statusCode == 401) {
      final refreshed = await handleTokenRefresh();
      if (refreshed) {
        response = await http.delete(Uri.parse('${Endpoint.request}/$id'), headers: {'Authorization': Token.token});
      } else {
        return false;
      }
    }

    if (response.statusCode == 200 || response.statusCode == 204) {
      int parsedId = id is int ? id : int.tryParse(id.toString()) ?? 0;
      GlobalCache.removeRequest(parsedId);
      return true;
    }
    return false;
  } catch (e) {
    return false;
  }
}

/// Diálogo para ver y gestionar adjuntos de una solicitud. Compartido entre tablas.
class RequestAttachmentsDialog extends StatefulWidget {
  final int requestId;
  final String documentNo;

  const RequestAttachmentsDialog({super.key, required this.requestId, required this.documentNo});

  @override
  State<RequestAttachmentsDialog> createState() => _RequestAttachmentsDialogState();
}

class _RequestAttachmentsDialogState extends State<RequestAttachmentsDialog> {
  List<Map<String, dynamic>> _attachments = [];
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  /// Carga los adjuntos de la solicitud desde la API.
  Future<void> _loadAttachments() async {
    setState(() => _isLoading = true);
    const tableName = 'R_Request';
    final String fullTableUrl = '${Endpoint.baseUrl}/api/v1/models/$tableName';
    final attachments = await fetchAttachments(recordID: widget.requestId, tableName: fullTableUrl);
    if (mounted) {
      setState(() {
        _attachments = attachments;
        _isLoading = false;
      });
    }
  }

  /// Permite al usuario seleccionar y subir un nuevo adjunto.
  Future<void> _uploadAttachment() async {
    if (!AccessControl.isAdmin && !AccessControl.isSupport) {
      ToastMessage.show(context: context, message: 'No tienes permisos para subir archivos.', type: ToastType.help);
      return;
    }

    if (_attachments.length >= 4) {
      ToastMessage.show(context: context, message: 'Solo se pueden subir hasta 4 adjuntos.', type: ToastType.warning);
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      ToastMessage.show(context: context, message: 'No se pudieron leer los datos del archivo.', type: ToastType.failure);
      return;
    }

    setState(() => _isUploading = true);

    const tableName = 'R_Request';
    final String fullTableUrl = '${Endpoint.baseUrl}/api/v1/models/$tableName';
    
    final convertedFile = {'title': file.name, 'base64': base64Encode(file.bytes!)};
    
    final success = await postAttachments(
      recordID: widget.requestId, 
      tableName: fullTableUrl, 
      convertedFile: convertedFile,
      shouldUpdateStatus: false,
    );

    if (mounted) {
      setState(() => _isUploading = false);
      if (success) {
        ToastMessage.show(context: context, message: 'Archivo subido correctamente', type: ToastType.success);
        _loadAttachments();
      } else {
        ToastMessage.show(context: context, message: 'Error al subir archivo', type: ToastType.failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const tableName = 'R_Request';
    final String fullTableUrl = '${Endpoint.baseUrl}/api/v1/models/$tableName';

    return CustomModal(
      title: 'Adjuntos: ${widget.documentNo}',
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
              child: Center(child: Text('No hay archivos adjuntos en esta solicitud.')),
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
                    FilePreviewManager.showPreview(context, {'id': widget.requestId, 'Status': 'N/A', 'VersionNo': 'N/A'}, fullTableUrl, att['name'] ?? '', () async {
                      try {
                        setState(() => _isLoading = true);
                        final url = Uri.parse('$fullTableUrl/${widget.requestId}/attachments/${Uri.encodeComponent(att['name'] ?? '')}');
                        final response = await http.delete(url, headers: {'Authorization': Token.token});
                        if (response.statusCode == 200 || response.statusCode == 204) {
                          if (mounted) {
                            setState(() {
                              _attachments.removeWhere((item) => item['name'] == att['name']);
                              _isLoading = false;
                            });
                            ToastMessage.show(context: context, message: 'Adjunto eliminado', type: ToastType.help);
                          }
                        } else {
                          if (mounted) {
                            setState(() => _isLoading = false);
                            ToastMessage.show(context: context, message: 'Error al eliminar adjunto', type: ToastType.failure);
                          }
                        }
                      } catch (e) {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    }, () {}, canDelete: AccessControl.isAdmin || AccessControl.isSupport);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.download, color: Color(0xFF4F47E5)),
                    tooltip: 'Descargar',
                    onPressed: () => downloadAttachment(context: context, recordID: widget.requestId, tableName: fullTableUrl, fileName: att['name']),
                  ),
                );
              },
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        if (AccessControl.isAdmin || AccessControl.isSupport) CustomButton(text: 'Subir Archivo', icon: Icons.upload_file, isLoading: _isUploading, onPressed: _uploadAttachment),
      ],
    );
  }
}

Future<bool> sendRequestStatusEmail({
  required int requestId,
  required int bPartnerId,
  required int adUserId,
  required MailTemplateType templateType,
  String? updateText,
  String? oldStatusName,
  int? updateId,
}) async {
  try {
    // 1. Obtener detalles de la solicitud de la caché
    Map<String, dynamic>? req;
    for (var r in GlobalCache.requests) {
      if (r['id']?.toString() == requestId.toString()) {
        req = r;
        break;
      }
    }
    if (req == null) {
      for (var projList in GlobalCache.projectRequestsCache.values) {
        for (var r in projList) {
          if (r['id']?.toString() == requestId.toString()) {
            req = r;
            break;
          }
        }
        if (req != null) break;
      }
    }

    final uri = Uri.parse('${Endpoint.baseUrl}/api/v1/processes/sendmailtextcds');
  
    String targetTableName = 'R_Request';
    String targetRecordId = requestId.toString();
    
    int? finalMailTextId;
    switch (templateType) {
      case MailTemplateType.newRequest:
        finalMailTextId = GlobalCache.newRequestMailId;
        break;
      case MailTemplateType.updateRequest:
        finalMailTextId = GlobalCache.updateRequestMailId;
        break;
      case MailTemplateType.statusUpdate:
        finalMailTextId = GlobalCache.statusUpdateRequestMailId;
        break;
    }
    
    if (finalMailTextId == null) {
      CurrentLogMessage.add('sendRequestStatusEmail abortado: No se encontro el ID numerico para la plantilla de correo de tipo $templateType.', level: 'WARNING', tag: 'sendRequestStatusEmail');
      return false;
    }
    
    if ((templateType == MailTemplateType.statusUpdate || templateType == MailTemplateType.updateRequest) && updateId != null) {
      targetTableName = 'R_RequestUpdate';
      targetRecordId = updateId.toString();
    }

    // Determinar los destinatarios: Usuario de la solicitud y Representante Comercial
    Set<int> targetUsers = {};
    if (adUserId > 0) targetUsers.add(adUserId);

    // Agregar Representante Comercial si existe en la solicitud (Excepto en Cambio de Estado = updateRequest)
    if (templateType != MailTemplateType.updateRequest && req != null && req['SalesRep_ID'] != null) {
      final salesRepData = req['SalesRep_ID'];
      int salesRepId = salesRepData is Map 
          ? (salesRepData['id'] as num).toInt() 
          : (salesRepData as num).toInt();
      if (salesRepId > 0) {
        targetUsers.add(salesRepId);
      }
    }

    if (targetUsers.isEmpty) return true; // No hay a quien enviar, no es un fallo

    bool allSuccess = true;

    // Enviar el correo a cada destinatario único ejecutando el proceso de Lirion
    for (int targetUserId in targetUsers) {
      final payload = {
        'recordID': targetRecordId,
        'TableName': targetTableName,
        'AD_UserTo_ID': targetUserId.toString(),
        'R_MailText_ID': finalMailTextId.toString(),
      };

      final response = await http.post(
        uri,
        headers: {
          'Authorization': Token.token,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        CurrentLogMessage.add('sendRequestStatusEmail exitoso para usuario $targetUserId. Respuesta: ${response.body}', level: 'INFO', tag: 'sendRequestStatusEmail');
      } else {
        CurrentLogMessage.add('sendRequestStatusEmail falló para usuario $targetUserId: ${response.statusCode}, ${response.body}', level: 'ERROR', tag: 'sendRequestStatusEmail');
        allSuccess = false;
      }
    }
    return allSuccess;
  } catch (e) {
    CurrentLogMessage.add('Excepcion en sendRequestStatusEmail: $e', level: 'ERROR', tag: 'sendRequestStatusEmail');
    return false;
  }
}

enum MailTemplateType {
  newRequest,
  updateRequest,
  statusUpdate
}
