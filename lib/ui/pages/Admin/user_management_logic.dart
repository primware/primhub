import 'dart:convert';
import 'package:primhub/api/api_http.dart' as http;
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';

class UserManagementLogic {
  static bool isTruthy(dynamic val) {
    if (val == null) return false;
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is Map) return isTruthy(val['id'] ?? val['value']);
    final str = val.toString().trim().toUpperCase();
    return str == 'Y' || str == 'TRUE' || str == '1';
  }

  static Future<List<Map<String, dynamic>>> _fetchAllPaginated(String baseUrl) async {
    List<Map<String, dynamic>> allRecords = [];
    int skip = 0;
    const int pageSize = 100;
    bool hasMore = true;

    while (hasMore) {
      final sep = baseUrl.contains('?') ? '&' : '?';
      final url = '$baseUrl$sep\$skip=$skip&\$top=$pageSize';
      final res = await http.get(Uri.parse(url), headers: {
        'Content-Type': 'application/json',
        'Authorization': Token.token,
      });

      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        final records = (decoded['records'] as List?) ?? [];
        allRecords.addAll(records.map((e) => Map<String, dynamic>.from(e)));
        if (records.length < pageSize) {
          hasMore = false;
        } else {
          skip += pageSize;
        }
      } else {
        hasMore = false;
      }
    }
    return allRecords;
  }

  static Future<List<Map<String, dynamic>>> _fetchBPartnersForTeams() async {
    try {
      // Misma consulta que en "Crear proyecto": IsCustomer eq true and IsActive eq true
      final url = '${Endpoint.cBPartner}?\$filter=IsCustomer eq true and IsActive eq true&\$orderby=Name';
      final records = await _fetchAllPaginated(url);
      if (records.isNotEmpty) {
        return records;
      }
    } catch (_) {}

    if (GlobalCache.bPartners.isNotEmpty) {
      return GlobalCache.bPartners;
    }
    final raw = await ProjectsLogic().fetchBPartners();
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> fetchFullUsersAndTeams() async {
    try {
      final bPartnersFuture = _fetchBPartnersForTeams();

      final results = await Future.wait([
        _fetchAllPaginated('${Endpoint.primConfig}?\$filter=IsActive eq true'),
        _fetchAllPaginated('${Endpoint.adUserRoles}?\$filter=IsActive eq true'),
        _fetchAllPaginated('${Endpoint.primDevTeam}?\$filter=IsActive eq true'),
        _fetchAllPaginated('${Endpoint.adUser}?\$select=AD_User_ID,Name,EMail,IsActive,C_BPartner_ID,AD_User_UU,Password'),
        bPartnersFuture,
      ]);

      final configRecords = results[0];
      final userRolesRecords = results[1];
      final devTeamRecords = results[2];
      final adUserRecords = results[3];
      final rawBPartners = List<Map<String, dynamic>>.from(results[4]);

      // Asegurar inclusión de la empresa administradora (La Casa del Software) si está en caché
      if (GlobalCache.bPartners.isNotEmpty) {
        final adminComp = GlobalCache.bPartners.cast<Map<String, dynamic>?>().firstWhere(
          (b) {
            final name = (b?['Name'] ?? '').toString().toUpperCase();
            final uuid = b?['C_BPartner_UU'] ?? b?['Record_UU'] ?? b?['UUID'] ?? b?['uuid'];
            return name.contains('LA CASA DEL SOFTWARE') || uuid == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95';
          },
          orElse: () => null,
        );
        if (adminComp != null) {
          final adminId = (adminComp['id'] as num? ?? adminComp['C_BPartner_ID'] as num?)?.toInt();
          if (adminId != null && !rawBPartners.any((b) => (b['id'] ?? b['C_BPartner_ID']) == adminId)) {
            rawBPartners.add(adminComp);
          }
        }
      }

      // 1. Roles config y extracción de nombres por foreign keys
      Set<int> validRoles = {};
      Map<int, String> roleNames = {};
      Map<int, String> primhubRoles = {};
      
      for (var conf in configRecords) {
        final rData = conf['AD_Role_ID'];
        if (rData != null) {
          final rId = ((rData is Map ? rData['id'] : rData) as num?)?.toInt();
          if (rId != null) {
            validRoles.add(rId);
            if (rData is Map && rData['identifier'] != null) {
              final name = rData['identifier'].toString();
              roleNames[rId] = name;
              primhubRoles[rId] = name;
            }
          }
        }
      }

      // 2. AD_User_Roles
      Map<int, List<Map<String, dynamic>>> userToRolesDetails = {};
      for (var ur in userRolesRecords) {
        if (!isTruthy(ur['IsActive'])) continue;
        final rData = ur['AD_Role_ID'];
        final uData = ur['AD_User_ID'];
        if (rData != null && uData != null) {
          if (rData is Map && rData['identifier'] == '~.~') continue; // Filtramos roles inactivos o inválidos en el sistema
          
          final rId = ((rData is Map ? rData['id'] : rData) as num?)?.toInt();
          final uId = ((uData is Map ? uData['id'] : uData) as num?)?.toInt();
          
          if (rId != null && uId != null) {
            if (rData is Map && rData['identifier'] != null) {
              roleNames[rId] = rData['identifier'].toString();
            }

            final rUuid = ur['uid'] ?? ur['AD_User_Roles_UU'] ?? ur['uuid'] ?? ur['UU'];
            userToRolesDetails.putIfAbsent(uId, () => []).add({'roleId': rId, 'uuid': rUuid});
          }
        }
      }

      // 3. Filtrar terceros para la visual de los equipos:
      // Deben llegar todos los terceros activos que son al menos clientes y que definitivamente NO son colaborador ni representante comercial.
      final List<Map<String, dynamic>> filteredBPartners = rawBPartners.where((bp) {
        final name = (bp['Name']?.toString() ?? '').trim();
        if (name.startsWith('~')) return false;

        final isSpecificAdmin =
            name.toUpperCase().contains('LA CASA DEL SOFTWARE') ||
            bp['C_BPartner_UU'] == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95' ||
            bp['Record_UU'] == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95' ||
            bp['UUID'] == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95' ||
            bp['uuid'] == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95';

        if (isSpecificAdmin) return true;

        // Debe estar activo
        final rawActive = bp['IsActive'] ?? bp['isActive'];
        final isActiveStr = rawActive?.toString().trim().toLowerCase();
        final isActive = rawActive == null || isActiveStr == 'true' || isActiveStr == 'y';
        if (!isActive) return false;

        // Debe ser al menos cliente
        final rawCustomer = bp['IsCustomer'] ?? bp['isCustomer'];
        final isCustomerStr = rawCustomer?.toString().trim().toLowerCase();
        final isCustomer = isCustomerStr == 'true' || isCustomerStr == 'y';
        if (!isCustomer) return false;

        // Definitivamente NO colaborador (IsEmployee)
        final rawEmployee = bp['IsEmployee'] ?? bp['isEmployee'];
        final isEmployeeStr = rawEmployee?.toString().trim().toLowerCase();
        final isEmployee = isEmployeeStr == 'true' || isEmployeeStr == 'y';
        if (isEmployee) return false;

        // Definitivamente NO representante comercial (IsSalesRep)
        final rawSalesRep = bp['IsSalesRep'] ?? bp['isSalesRep'];
        final isSalesRepStr = rawSalesRep?.toString().trim().toLowerCase();
        final isSalesRep = isSalesRepStr == 'true' || isSalesRepStr == 'y';
        if (isSalesRep) return false;

        return true;
      }).toList();

      filteredBPartners.sort((a, b) =>
          (a['Name']?.toString() ?? '').toLowerCase().compareTo((b['Name']?.toString() ?? '').toLowerCase()));

      // 4. BPartners map para asociaciones rápidas
      Map<int, Map<String, dynamic>> bpMap = {};
      for (var bp in filteredBPartners) {
        final rawId = bp['id'] ?? (bp['C_BPartner_ID'] is Map ? bp['C_BPartner_ID']['id'] : bp['C_BPartner_ID']);
        final id = (rawId as num?)?.toInt();
        if (id != null) {
          bp['id'] = id;
          bp['C_BPartner_ID'] = id;
          bpMap[id] = bp;
        }
      }

      // 5. Teams
      Map<int, List<Map<String, dynamic>>> bpToUsersInTeam = {};
      Map<int, List<String>> userToTeams = {};
      for (var dt in devTeamRecords) {
        if (!isTruthy(dt['IsActive'])) continue;
        final bpData = dt['C_BPartner_ID'];
        final uData = dt['AD_User_ID'];
        if (bpData != null && uData != null) {
          final bpId = ((bpData is Map ? bpData['id'] : bpData) as num?)?.toInt();
          final uId = ((uData is Map ? uData['id'] : uData) as num?)?.toInt();
          final teamId = dt['PRIM_Dev_Team_ID'] ?? dt['id'];
          
          if (bpId != null && uId != null) {
            bpToUsersInTeam.putIfAbsent(bpId, () => []).add({'uId': uId, 'teamId': teamId});
            String bpName = bpMap[bpId]?['Name'] ?? (bpData is Map ? (bpData['identifier'] ?? bpData['Name'] ?? 'ID $bpId') : 'ID $bpId');
            userToTeams.putIfAbsent(uId, () => []).add('Equipo de $bpName');
          }
        }
      }

      // 6. Final Users List
      List<Map<String, dynamic>> finalUsers = [];
      Map<int, Map<String, dynamic>> userMap = {};
      
      for (var u in adUserRecords) {
        final rawUId = u['id'] ?? (u['AD_User_ID'] is Map ? u['AD_User_ID']['id'] : u['AD_User_ID']);
        final uId = (rawUId as num?)?.toInt();
        if (uId == null) continue;

        final bpData = u['C_BPartner_ID'];
        final bpId = ((bpData is Map ? bpData['id'] : bpData) as num?)?.toInt();
        
        final bpInfo = bpId != null ? bpMap[bpId] : null;
        final bpName = bpInfo?['Name'] ?? (bpData is Map ? (bpData['identifier'] ?? bpData['Name']) : null) ?? 'Ninguna';

        List<Map<String, dynamic>> uRolesDetails = userToRolesDetails[uId] ?? [];
        uRolesDetails.sort((a, b) {
          final aValid = validRoles.contains(a['roleId']) ? 0 : 1;
          final bValid = validRoles.contains(b['roleId']) ? 0 : 1;
          return aValid.compareTo(bValid);
        });
        
        List<int> uRoles = uRolesDetails.map((e) => e['roleId'] as int).toList();
        List<String> uRoleNames = uRoles.map((rId) => roleNames[rId] ?? 'Rol $rId').toList();
        bool hasValidRole = uRoles.any((r) => validRoles.contains(r));

        final userData = {
          'AD_User_ID': uId,
          'uuid': (u['uid'] ?? u['AD_User_UU'] ?? u['uuid'] ?? u['UU'] ?? '').toString().trim(),
          'Name': (u['Name'] ?? '').toString(),
          'EMail': (u['EMail'] ?? '').toString(),
          'IsActive': isTruthy(u['IsActive']),
          'C_BPartner_ID': bpId,
          'Company': bpName,
          'IsCustomer': bpInfo?['IsCustomer'] == true,
          'IsSalesRep': bpInfo?['IsSalesRep'] == true,
          'IsEmployee': bpInfo?['IsEmployee'] == true,
          'RoleNames': uRoleNames.join(', '),
          'RoleIds': uRoles,
          'RolesDetails': uRolesDetails,
          'HasValidRole': hasValidRole,
          'HasPassword': u['Password'] != null && u['Password'].toString().trim().isNotEmpty,
          'Teams': userToTeams[uId]?.join(', ') ?? 'Sin equipo',
        };
        finalUsers.add(userData);
        userMap[uId] = userData;
      }

      finalUsers.sort((a, b) => a['Name'].compareTo(b['Name']));

      // Build ThirdParty teams list
      List<Map<String, dynamic>> teamsList = [];
      for (var bpEntry in bpToUsersInTeam.entries) {
        final bpId = bpEntry.key;
        final bpInfo = bpMap[bpId];
        if (bpInfo == null) continue;
        
        final usersInTeam = bpEntry.value.map((uData) {
          final u = userMap[uData['uId']];
          if (u != null) {
            final copy = Map<String, dynamic>.from(u);
            copy['DevTeamID'] = uData['teamId'];
            return copy;
          }
          return null;
        }).where((u) => u != null).toList();
        teamsList.add({
          'C_BPartner_ID': bpId,
          'Name': 'Equipo de ${bpInfo['Name'] ?? 'ID $bpId'}',
          'Users': usersInTeam,
        });
      }
      teamsList.sort((a, b) => (a['Name'] as String).compareTo(b['Name'] as String));

      return {
        'users': finalUsers,
        'roles': roleNames,
        'primhubRoles': primhubRoles,
        'bPartners': filteredBPartners,
        'teams': teamsList,
      };
    } catch (e) {
      // [Mantenimiento] Log removido: CurrentLogMessage.add('Error armando gestión de usuarios: $e', level: 'ERROR');
      return {'users': [], 'roles': {}, 'primhubRoles': {}, 'bPartners': [], 'teams': []};
    }
  }

  static Future<bool> saveUser({
    required String? uuid,
    int? userId,
    required String name,
    required String email,
    required List<int> rolesToAdd,
    required List<String> rolesToRemove,
    required int bPartnerId,
    required String? password,
    required bool isActive,
  }) async {
    try {
      final isEditing = uuid != null && uuid.isNotEmpty;
      final uri = isEditing 
          ? Uri.parse('${Endpoint.baseUrl}/api/v1/models/AD_User/$uuid')
          : Uri.parse('${Endpoint.baseUrl}/api/v1/models/AD_User');

      final payload = {
        'Name': name,
        'EMail': email,
        'C_BPartner_ID': bPartnerId,
        'IsActive': isActive,
      };

      if (password != null && password.isNotEmpty) {
        payload['Password'] = password;
      }

      final response = isEditing 
          ? await http.put(uri, body: json.encode(payload), headers: {'Authorization': Token.token, 'Content-Type': 'application/json'})
          : await http.post(uri, body: json.encode(payload), headers: {'Authorization': Token.token, 'Content-Type': 'application/json'});

      if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 204) {
        Map<String, dynamic> responseData = {};
        if (response.bodyBytes.isNotEmpty) {
          try {
            responseData = json.decode(utf8.decode(response.bodyBytes));
          } catch (_) {}
        }
        final effectiveUserId = (responseData['id'] ?? responseData['AD_User_ID'] as num?)?.toInt() ?? userId;

        if (effectiveUserId != null) {
          // Agregar roles nuevos
          for (var rId in rolesToAdd) {
            final roleUri = Uri.parse('${Endpoint.baseUrl}/api/v1/models/AD_User_Roles');
            await http.post(roleUri, body: json.encode({
              'AD_User_ID': effectiveUserId,
              'AD_Role_ID': rId,
            }), headers: {'Authorization': Token.token, 'Content-Type': 'application/json'});
          }
          // Eliminar roles
          for (var rUuid in rolesToRemove) {
            final roleUri = Uri.parse('${Endpoint.baseUrl}/api/v1/models/AD_User_Roles/$rUuid');
            await http.delete(roleUri, headers: {'Authorization': Token.token});
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      // [Mantenimiento] Log removido: CurrentLogMessage.add('Error guardando usuario: $e', level: 'ERROR');
      return false;
    }
  }

  static Future<bool> resetPassword({
    required String uuid,
    required String newPassword,
  }) async {
    try {
      final uri = Uri.parse('${Endpoint.baseUrl}/api/v1/models/AD_User/$uuid');
      final payload = {'Password': newPassword};
      final response = await http.put(
        uri,
        body: json.encode(payload),
        headers: {
          'Authorization': Token.token,
          'Content-Type': 'application/json',
        },
      );
      return response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 204;
    } catch (e) {
      // [Mantenimiento] Log removido: CurrentLogMessage.add('Error restableciendo contraseña: $e', level: 'ERROR');
      return false;
    }
  }
  
  static Future<bool> toggleUserActiveStatus(String uuid, bool isActive) async {
    try {
      final uri = Uri.parse('${Endpoint.baseUrl}/api/v1/models/AD_User/$uuid');
      final payload = {'IsActive': isActive};
      final response = await http.put(uri, body: json.encode(payload), headers: {
        'Authorization': Token.token,
        'Content-Type': 'application/json',
      });
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      // [Mantenimiento] Log removido: CurrentLogMessage.add('Error cambiando estado: $e', level: 'ERROR');
      return false;
    }
  }

  // --- Lógica de Terceros (C_BPartner) ---
  
  static Future<bool> updateTeamLeader(int bPartnerId, int newSalesRepId) async {
    try {
      final uri = Uri.parse('${Endpoint.baseUrl}/api/v1/models/C_BPartner/$bPartnerId');
      final payload = {'SalesRep_ID': newSalesRepId};
      final response = await http.put(uri, body: json.encode(payload), headers: {
        'Authorization': Token.token,
        'Content-Type': 'application/json',
      });
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }
  
  static Future<List<Map<String, dynamic>>> fetchBPGroups() async {
    try {
      final uri = Uri.parse('${Endpoint.baseUrl}/api/v1/models/C_BP_Group?\$select=C_BP_Group_ID,Name&\$filter=IsActive eq true');
      final response = await http.get(uri, headers: {'Authorization': Token.token});
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return List<Map<String, dynamic>>.from(data['records'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchTaxIdTypes() async {
    try {
      final uri = Uri.parse('${Endpoint.baseUrl}/api/v1/models/LCO_TaxIdType?\$select=LCO_TaxIdType_ID,Name&\$filter=IsActive eq true');
      final response = await http.get(uri, headers: {'Authorization': Token.token});
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return List<Map<String, dynamic>>.from(data['records'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> checkUserExists(String query) async {
    try {
      final filter = "(contains(tolower(EMail), '${query.toLowerCase()}') or contains(tolower(Name), '${query.toLowerCase()}'))";
      final uri = Uri.parse('${Endpoint.adUser}?\$filter=$filter&\$top=10&\$select=AD_User_ID,Name,EMail,C_BPartner_ID');
      final response = await http.get(uri, headers: {'Authorization': Token.token});
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return List<Map<String, dynamic>>.from(data['records'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> checkBPartnerExists(String query) async {
    try {
      // Busca por Value o Name
      final filter = "(contains(tolower(Value), '${query.toLowerCase()}') or contains(tolower(Name), '${query.toLowerCase()}'))";
      final uri = Uri.parse('${Endpoint.cBPartner}?\$filter=$filter&\$top=10&\$select=C_BPartner_ID,Name,Value');
      final response = await http.get(uri, headers: {'Authorization': Token.token});
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return List<Map<String, dynamic>>.from(data['records'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> saveBPartner(Map<String, dynamic> payload) async {
    try {
      final uri = Uri.parse(Endpoint.cBPartner);
      final response = await http.post(uri, body: json.encode(payload), headers: {'Authorization': Token.token, 'Content-Type': 'application/json'});
      return (response.statusCode == 200 || response.statusCode == 201);
    } catch (e) {
      return false;
    }
  }

  // --- Lógica de Equipos (PRIM_Dev_Team) ---

  static Future<bool> saveTeam(int bPartnerId, List<int> usersToAdd, List<int> idsToRemove) async {
    try {
      bool success = true;

      // 1. Delete users
      for (var id in idsToRemove) {
        final uri = Uri.parse('${Endpoint.primDevTeam}/$id');
        final res = await http.delete(uri, headers: {'Authorization': Token.token});
        if (res.statusCode >= 400) {
          final putRes = await http.put(
            uri,
            body: json.encode({'IsActive': false}),
            headers: {
              'Authorization': Token.token,
              'Content-Type': 'application/json',
            },
          );
          if (putRes.statusCode >= 400) success = false;
        }
      }
      
      // 2. Add users
      for (var uId in usersToAdd) {
        final uri = Uri.parse(Endpoint.primDevTeam);
        final res = await http.post(uri, body: json.encode({
          'C_BPartner_ID': bPartnerId,
          'AD_User_ID': uId,
        }), headers: {
          'Authorization': Token.token,
          'Content-Type': 'application/json',
        });
        if (res.statusCode >= 400) success = false;
      }
      return success;
    } catch (e) {
      return false;
    }
  }
}
