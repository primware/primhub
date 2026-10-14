import 'dart:convert';
import 'package:primhub/api/api_http.dart' as http;
import 'package:primhub/api/token.dart';
import 'package:primhub/endpoint/endpoint.dart';

class UserManagementLogic {
  static Future<Map<String, dynamic>> fetchFullUsersAndTeams() async {
    try {
      final results = await Future.wait([
        http.get(Uri.parse('${Endpoint.primConfig}?\$limit=100'), headers: {'Authorization': Token.token}),
        http.get(Uri.parse('${Endpoint.adUserRoles}?\$limit=5000'), headers: {'Authorization': Token.token}),
        http.get(Uri.parse('${Endpoint.primDevTeam}?\$limit=5000'), headers: {'Authorization': Token.token}),
        http.get(Uri.parse('${Endpoint.adUser}?\$limit=5000&\$select=AD_User_ID,Name,EMail,IsActive,C_BPartner_ID,AD_User_UU,Password'), headers: {'Authorization': Token.token}),
        http.get(Uri.parse('${Endpoint.cBPartner}?\$limit=5000&\$select=C_BPartner_ID,Name,IsCustomer,IsSalesRep,IsEmployee,SalesRep_ID'), headers: {'Authorization': Token.token}),
      ]);

      final configRecords = (json.decode(utf8.decode(results[0].bodyBytes))['records'] as List?) ?? [];
      final userRolesRecords = (json.decode(utf8.decode(results[1].bodyBytes))['records'] as List?) ?? [];
      final devTeamRecords = (json.decode(utf8.decode(results[2].bodyBytes))['records'] as List?) ?? [];
      final adUserRecords = (json.decode(utf8.decode(results[3].bodyBytes))['records'] as List?) ?? [];
      final bPartnerRecords = (json.decode(utf8.decode(results[4].bodyBytes))['records'] as List?) ?? [];

      // 1. Roles config y extracción de nombres por foreign keys
      Set<int> validRoles = {};
      Map<int, String> roleNames = {};
      Map<int, String> primhubRoles = {};
      
      for (var conf in configRecords) {
        final rData = conf['AD_Role_ID'];
        if (rData != null) {
          final rId = rData is Map ? (rData['id'] as num).toInt() : (rData as num).toInt();
          validRoles.add(rId);
          if (rData is Map && rData['identifier'] != null) {
            final name = rData['identifier'].toString();
            roleNames[rId] = name;
            primhubRoles[rId] = name;
          }
        }
      }

      // 2. AD_User_Roles
      Map<int, List<Map<String, dynamic>>> userToRolesDetails = {};
      for (var ur in userRolesRecords) {
        if (ur['IsActive'] == false) continue;
        final rData = ur['AD_Role_ID'];
        final uData = ur['AD_User_ID'];
        if (rData != null && uData != null) {
          if (rData is Map && rData['identifier'] == '~.~') continue; // Filtramos roles inactivos o inválidos en el sistema
          
          final rId = rData is Map ? (rData['id'] as num).toInt() : (rData as num).toInt();
          final uId = uData is Map ? (uData['id'] as num).toInt() : (uData as num).toInt();
          
          if (rData is Map && rData['identifier'] != null) {
            roleNames[rId] = rData['identifier'].toString();
          }

          final rUuid = ur['uid'] ?? ur['AD_User_Roles_UU'] ?? ur['uuid'] ?? ur['UU'];
          userToRolesDetails.putIfAbsent(uId, () => []).add({'roleId': rId, 'uuid': rUuid});
        }
      }

      // 3. BPartners map
      Map<int, Map<String, dynamic>> bpMap = {};
      for (var bp in bPartnerRecords) {
        final id = bp['id'] ?? bp['C_BPartner_ID'];
        if (id != null) {
          bpMap[(id as num).toInt()] = bp;
        }
      }

      // 4. Teams
      Map<int, List<Map<String, dynamic>>> bpToUsersInTeam = {};
      Map<int, List<String>> userToTeams = {};
      for (var dt in devTeamRecords) {
        if (dt['IsActive'] == false) continue;
        final bpData = dt['C_BPartner_ID'];
        final uData = dt['AD_User_ID'];
        if (bpData != null && uData != null) {
          final bpId = bpData is Map ? (bpData['id'] as num).toInt() : (bpData as num).toInt();
          final uId = uData is Map ? (uData['id'] as num).toInt() : (uData as num).toInt();
          final teamId = dt['PRIM_Dev_Team_ID'] ?? dt['id'];
          
          bpToUsersInTeam.putIfAbsent(bpId, () => []).add({'uId': uId, 'teamId': teamId});
          String bpName = bpMap[bpId]?['Name'] ?? 'ID $bpId';
          userToTeams.putIfAbsent(uId, () => []).add('Equipo de $bpName');
        }
      }

      // 5. Final Users List
      List<Map<String, dynamic>> finalUsers = [];
      Map<int, Map<String, dynamic>> userMap = {};
      
      for (var u in adUserRecords) {
        final uId = (u['id'] ?? u['AD_User_ID'] as num?)?.toInt();
        if (uId == null) continue;

        final bpData = u['C_BPartner_ID'];
        final bpId = bpData is Map ? (bpData['id'] as num?)?.toInt() : (bpData as num?)?.toInt();
        
        final bpInfo = bpId != null ? bpMap[bpId] : null;

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
          'IsActive': u['IsActive'] == true,
          'C_BPartner_ID': bpId,
          'Company': bpInfo?['Name'] ?? 'Ninguna',
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
          if (u != null) u['DevTeamID'] = uData['teamId'];
          return u;
        }).where((u) => u != null).toList();
        teamsList.add({
          'C_BPartner_ID': bpId,
          'Name': 'Equipo de ${bpInfo['Name'] ?? 'ID $bpId'}',
          'Users': usersInTeam,
        });
      }
      teamsList.sort((a, b) => a['Name'].compareTo(b['Name']));

      return {
        'users': finalUsers,
        'roles': roleNames,
        'primhubRoles': primhubRoles,
        'bPartners': bpMap.values.toList(),
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
        if (res.statusCode >= 400) success = false;
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
