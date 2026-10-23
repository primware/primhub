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
          final records = (jsonResponse['records'] as List?) ?? [];
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

    List<String> conditions = [];

    // Siempre filtrar por el AD_Client_ID del tenant actual para evitar el error 500
    // "Cross tenant PO reading request detected" de iDempiere al existir registros de otros tenants.
    final int? clientId = Token.client ?? (() {
      try {
        final payload = Token.decodePayload(Token.token);
        return (payload['AD_Client_ID'] as num?)?.toInt() ?? (payload['clientId'] as num?)?.toInt();
      } catch (_) {
        return null;
      }
    })();

    if (clientId != null && clientId > 0) {
      conditions.add("AD_Client_ID eq $clientId");
    }

    // Filtramos por activo solo si no se solicita incluir inactivos.
    // En OData/iDempiere IsActive es boolean (Edm.Boolean), por lo que se usa 'IsActive eq true'.
    if (!includeInactive) {
      conditions.add("IsActive eq true");
    }

    if (finalBpIds.isNotEmpty) {
      String bpFilter = finalBpIds
          .map((id) => "C_BPartner_ID eq $id")
          .join(' or ');
      conditions.add("($bpFilter)");
    }

    String filter = conditions.join(" and ");

    // Expandimos M_Product_ID para obtener datos del producto
    final String filterQuery = filter.isNotEmpty ? "\$filter=$filter&" : "";
    final String baseUrl = "$endpoint?$filterQuery\$expand=M_Product_ID";

    try {
      final records = await _fetchPaginated(baseUrl);
      
      // Filtramos localmente: si M_Product_ID tiene la columna 'showinprimhub', respetamos su valor.
      // Si no viene la columna en el expand, no descartamos la ficha, ya que todas las filas
      // en C_BPartner_Product_Chip son fichas de producto registradas para Primhub.
      final supportRecords = records.where((r) {
        final mProductId = r['M_Product_ID'];
        if (mProductId is Map) {
          String? showKey;
          for (var key in mProductId.keys) {
            if (key.toLowerCase() == 'showinprimhub') {
              showKey = key;
              break;
            }
          }

          if (showKey != null) {
            final val = mProductId[showKey];
            return val == true || val == 'Y' || val == 'true';
          }
        }
        return true;
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

    List<String> conditions = [];

    final int? clientId = Token.client ?? (() {
      try {
        final payload = Token.decodePayload(Token.token);
        return (payload['AD_Client_ID'] as num?)?.toInt() ?? (payload['clientId'] as num?)?.toInt();
      } catch (_) {
        return null;
      }
    })();

    if (clientId != null && clientId > 0) {
      conditions.add("AD_Client_ID eq $clientId");
    }

    // Solo pedimos los activos y expandimos C_BPartner_ID y M_Product_ID
    conditions.add("IsActive eq true");

    if (AccessControl.isExtSupport && User.userID != null) {
      if (GlobalCache.extSupportBpIds.isNotEmpty) {
        String bpFilter = GlobalCache.extSupportBpIds.map((id) => "C_BPartner_ID eq $id").join(' or ');
        conditions.add("($bpFilter)");
      } else {
        conditions.add("C_BPartner_ID eq -1"); 
      }
    }

    String filter = conditions.join(" and ");

    final String baseUrl =
        "$endpoint?\$filter=$filter&\$expand=C_BPartner_ID(\$select=Name,IsActive),M_Product_ID";

    try {
      final records = await _fetchPaginated(baseUrl);
      final Map<int, Map<String, dynamic>> bPartners = {};

      for (var record in records) {
        final mProductId = record['M_Product_ID'];
        bool isSupport = true;
        if (mProductId is Map) {
          String? showKey;
          for (var key in mProductId.keys) {
            if (key.toLowerCase() == 'showinprimhub') {
              showKey = key;
              break;
            }
          }

          if (showKey != null) {
            final val = mProductId[showKey];
            isSupport = val == true || val == 'Y' || val == 'true';
          }
        }
        
        if (!isSupport) continue;

        final bpInfo = record['C_BPartner_ID'];
        if (bpInfo != null) {
          final int? bpId = bpInfo is Map ? (bpInfo['id'] as num?)?.toInt() : (bpInfo as num?)?.toInt();
          if (bpId != null) {
            final isActive = bpInfo is Map
                ? (bpInfo['IsActive'] == true || bpInfo['IsActive'] == 'Y' || bpInfo['IsActive'] == 'true' || bpInfo['IsActive'] == null)
                : true;
            if (!isActive) continue;

            final bpName = bpInfo is Map
                ? (bpInfo['identifier'] ?? bpInfo['Name'] ?? 'Tercero $bpId')
                : 'Tercero $bpId';

            bPartners[bpId] = {
              'id': bpId,
              'Name': bpName,
            };
          }
        }
      }
      return bPartners.values.toList()
        ..sort((a, b) => (a['Name'] ?? '').compareTo(b['Name'] ?? ''));
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
