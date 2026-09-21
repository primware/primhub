import 'dart:convert';
import 'package:primhub/api/api_http.dart' as http;
import 'package:primhub/api/access_control.dart';
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/api/global_cache.dart';

class ContractApi {
  // Ahora usamos la Ficha de Producto del Tercero
  static const String productChipEndpoint = "C_BPartner_Product_Chip";

  /// Normaliza un string para búsqueda: minúsculas y sin acentos.
  static String _normalizeForSearch(String input) {
    return input
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
  }

  static Future<List<dynamic>> _fetchPaginated(String baseUrl) async {
    List<dynamic> allRecords = [];
    int skip = 0;
    int top = 100;
    bool hasMore = true;

    try {
      while (hasMore) {
        String queryUrl = "$baseUrl&\$skip=$skip&\$top=$top";
        var response = await http.get(
          Uri.parse(queryUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': Token.token,
          },
        );

        if (response.statusCode == 401) {
          final refreshed = await handleTokenRefresh();
          if (refreshed) {
            response = await http.get(
              Uri.parse(queryUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': Token.token,
              },
            );
          } else {
            return allRecords;
          }
        }

        if (response.statusCode == 200) {
          final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
          final records = jsonResponse['records'] as List;
          allRecords.addAll(records);
          if (records.length < top) {
            hasMore = false;
          } else {
            skip += top;
          }
        } else {
          hasMore = false;
        }
      }
    } catch (_) {
      // Ignored: Fail silently
    }
    return allRecords;
  }

  /// Obtiene los Product Chips (Fichas de Soporte) filtrando localmente.
  static Future<List<Map<String, dynamic>>> getSupportProductChips({
    int? bPartnerId,
    List<int>? bPartnerIds,
    bool includeInactive = false,
  }) async {
    final String endpoint =
        "${Endpoint.baseUrl}/api/v1/models/$productChipEndpoint";

    List<int> finalBpIds = [];
    if (bPartnerId != null) finalBpIds.add(bPartnerId);
    if (bPartnerIds != null) finalBpIds.addAll(bPartnerIds);

    if (finalBpIds.isEmpty &&
        !AccessControl.isAdmin &&
        !AccessControl.isRealSupport &&
        User.cBPartnerID != null) {
      finalBpIds.add(User.cBPartnerID!);
    }

    if (finalBpIds.isEmpty && AccessControl.isExtSupport && User.userID != null) {
      finalBpIds.addAll(GlobalCache.extSupportBpIds);
      if (finalBpIds.isEmpty) {
        finalBpIds.add(-1); 
      }
    }

    // Filtramos por activo o incluimos todos explícitamente si includeInactive es true
    String filter = includeInactive 
        ? "(IsActive eq 'Y' or IsActive eq 'N' or IsActive eq true or IsActive eq false)" 
        : "(IsActive eq 'Y' or IsActive eq true)";

    if (finalBpIds.isNotEmpty) {
      String bpFilter = finalBpIds
          .map((id) => "C_BPartner_ID eq $id")
          .join(' or ');
      filter = filter.isNotEmpty ? "$filter and ($bpFilter)" : "($bpFilter)";
    }

    // Expandimos M_Product_ID para obtener showinprimhub
    final String filterQuery = filter.isNotEmpty ? "\$filter=$filter&" : "";
    final String baseUrl = "$endpoint?$filterQuery\$expand=M_Product_ID";

    try {
      final records = await _fetchPaginated(baseUrl);
      
      // Filtramos localmente: debe tener showinprimhub == true
      final supportRecords = records.where((r) {
        final mProductId = r['M_Product_ID'];
        if (mProductId is Map) {
          // Buscamos la llave 'showinprimhub' ignorando mayúsculas y minúsculas
          String? showKey;
          for (var key in mProductId.keys) {
            if (key.toLowerCase() == 'showinprimhub') {
              showKey = key;
              break;
            }
          }

          if (showKey != null) {
            final val = mProductId[showKey];
            return val == true || val == 'Y';
          }

          // Fallback por nombre por si el caché o endpoint aún no retorna la columna
          final name = _normalizeForSearch((mProductId['identifier'] ?? '').toString());
          return name.contains('soport');
        }
        return false;
      }).toList();
      
      return supportRecords.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      // Ignored: Fail silently
    }
    return [];
  }

  /// Obtiene la lista de Terceros que tienen al menos una ficha de producto activa de soporte.
  static Future<List<Map<String, dynamic>>>
  getBPartnersWithProductChips() async {
    final String endpoint =
        "${Endpoint.baseUrl}/api/v1/models/$productChipEndpoint";

    // Solo pedimos los activos y expandimos C_BPartner_ID y M_Product_ID
    String filter = "(IsActive eq 'Y' or IsActive eq true)";

    if (AccessControl.isExtSupport && User.userID != null) {
      if (GlobalCache.extSupportBpIds.isNotEmpty) {
        String bpFilter = GlobalCache.extSupportBpIds.map((id) => "C_BPartner_ID eq $id").join(' or ');
        filter = "$filter and ($bpFilter)";
      } else {
        filter = "$filter and (C_BPartner_ID eq -1)"; 
      }
    }

    final String baseUrl =
        "$endpoint?\$filter=$filter&\$expand=C_BPartner_ID(\$select=Name,IsActive),M_Product_ID";

    try {
      final records = await _fetchPaginated(baseUrl);
      final Map<int, Map<String, dynamic>> bPartners = {};

      for (var record in records) {
        // Filtrado local: debe tener showinprimhub == true
        final mProductId = record['M_Product_ID'];
        if (mProductId is! Map) continue;
        
        bool isSupport = false;
        String? showKey;
        for (var key in mProductId.keys) {
          if (key.toLowerCase() == 'showinprimhub') {
            showKey = key;
            break;
          }
        }

        if (showKey != null) {
          final val = mProductId[showKey];
          isSupport = val == true || val == 'Y';
        } else {
          // Fallback
          final prodName = _normalizeForSearch((mProductId['identifier'] ?? '').toString());
          isSupport = prodName.contains('soport');
        }
        
        if (!isSupport) continue;

        final bpInfo = record['C_BPartner_ID'];
        if (bpInfo != null && bpInfo['id'] != null) {
          // Check if IsActive is false directly in Dart to avoid backend errors
          final isActive =
              bpInfo['IsActive'] == true || bpInfo['IsActive'] == 'Y';
          if (!isActive) continue;

          final bpId = bpInfo['id'];
          bPartners[bpId] = {
            'id': bpId,
            'Name': bpInfo['identifier'] ?? bpInfo['Name'] ?? 'Tercero $bpId',
          };
        }
      }
      return bPartners.values.toList()
        ..sort((a, b) => a['Name'].compareTo(b['Name']));
    } catch (_) {
      // Ignored: Fail silently
    }
    return [];
  }

  /// Actualiza la descripción (nombre) de una ficha de producto.
  static Future<bool> updateProductChipDescription(
    int chipId,
    String newDescription, {
    String? serviceFinishDate,
  }) async {
    final String url =
        "${Endpoint.baseUrl}/api/v1/models/C_BPartner_Product_Chip/$chipId";
    final Map<String, dynamic> data = {
      "C_BPartner_Product_Chip_ID": chipId,
      "Description": newDescription,
    };
    if (serviceFinishDate != null && serviceFinishDate.isNotEmpty) {
      data["service_finish_date"] = "${serviceFinishDate}T00:00:00Z";
    }

    try {

      var response = await http.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': Token.token,
        },
        body: jsonEncode(data),
      );

      if (response.statusCode == 401) {
        final refreshed = await handleTokenRefresh();
        if (refreshed) {
          response = await http.put(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': Token.token,
            },
            body: jsonEncode(data),
          );
        } else {
          return false;
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
      }
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      return false;
    }
  }
  static Future<bool> updateProductChipActive(
    int chipId,
    bool isActive,
  ) async {
    final String url =
        "${Endpoint.baseUrl}/api/v1/models/C_BPartner_Product_Chip/$chipId";
    final Map<String, dynamic> data = {
      "C_BPartner_Product_Chip_ID": chipId,
      "IsActive": isActive,
    };

    try {
      var response = await http.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': Token.token,
        },
        body: jsonEncode(data),
      );

      if (response.statusCode == 401) {
        final refreshed = await handleTokenRefresh();
        if (refreshed) {
          response = await http.put(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': Token.token,
            },
            body: jsonEncode(data),
          );
        } else {
          return false;
        }
      }

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      return false;
    }
  }
}
