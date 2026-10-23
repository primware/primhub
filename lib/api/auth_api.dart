import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:primhub/api/api_http.dart';
import 'package:primhub/api/session_manager.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/api/contract_api.dart';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';

Future<Map<String, dynamic>> loginStep1(String username, String password) async {
  try {
    final response = await post(Uri.parse(Endpoint.authTokens), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'userName': username, 'password': password}));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    // Manejar respuestas HTML (como errores 404/500 del servidor web)
    if (response.body.toLowerCase().contains('<html')) {
      return {'error': 'Error ${response.statusCode}: Servicio no disponible o ruta incorrecta.'};
    }
    return {'error': 'Error ${response.statusCode}: ${response.body}'};
  } catch (e) {
    return {'error': e.toString()};
  }
}

// Obtener Roles disponibles
Future<List<dynamic>> getRoles(int clientId, String token) async {
  try {
    final response = await get(Uri.parse('${Endpoint.authRoles}?client=$clientId'), headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['roles'] ?? [];
    }
  } catch (_) {
      // Ignored: Fail silently
    }
  return [];
}

// Obtener Organizaciones disponibles
Future<List<dynamic>> getOrgs(int clientId, int roleId, String token) async {
  try {
    final response = await get(Uri.parse('${Endpoint.authOrgs}?client=$clientId&role=$roleId'), headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['organizations'] ?? [];
    }
  } catch (_) {
      // Ignored: Fail silently
    }
  return [];
}

// Obtener Almacenes (Opcional)
Future<List<dynamic>> getWarehouses(int clientId, int roleId, int orgId, String token) async {
  try {
    final response = await get(Uri.parse('${Endpoint.authWarehouses}?client=$clientId&role=$roleId&organization=$orgId'), headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['warehouses'] ?? [];
    }
  } catch (_) {
      // Ignored: Fail silently
    }
  return [];
}

//Confirmar login con parámetros de sesión
Future<bool> finalizeLogin(String username, String password, Map<String, dynamic> contextParams, BuildContext context) async {
  try {
    final body = {"userName": username, "password": password, "parameters": contextParams};

    final response = await post(Uri.parse(Endpoint.authTokens), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);
      Token.auth = responseBody['token'];
      Token.refreshToken = responseBody['refresh_token'];
      Token.userName = username;
      Token.password = password;
      await saveLastTokenGeneratedAt();
      
      User.name = username; // Establecer User.name con el nombre de usuario

      User.userID = responseBody['userId'];
      User.cBPartnerID = await getPartnerID(userId: User.userID!);

      bool hasSupport = false;
      bool hasProject = false;

      final bool config = await getPrimConfig(rolId: Token.rol!, context: context);

      if (config == false && !AccessControl.hasHardcodedRole(Token.rol)) {
        Token.primConfig = null;
        Token.primConfigId = null;
        ToastMessage.show(context: context, message: 'El Rol no tiene configuración.', type: ToastType.failure);
        Token.clear();
        User.userID = null;
        User.cBPartnerID = null;

        return false;
      }

      if (AccessControl.isAdmin || AccessControl.isRealSupport) {
        // Admin/Soporte: detectar dinámicamente si hay fichas de soporte
        final chips = await ContractApi.getSupportProductChips();
        hasSupport = chips.isNotEmpty;
        hasProject = true;
      } else if (User.cBPartnerID != null) {
        // Para otros usuarios (como Proyecto)
        final chips = await ContractApi.getSupportProductChips(bPartnerId: User.cBPartnerID);
        hasSupport = chips.isNotEmpty;
        hasProject = await checkProjects();
      } else {
        hasSupport = false;
        hasProject = false;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_support', hasSupport);
      await prefs.setBool('has_project', hasProject);
      
      // Guardar datos de sesión para refrescar página
      await prefs.remove('hasShownAdminModeTutorial');
      await prefs.setString('auth_token', Token.auth ?? '');
      await prefs.setString('refresh_token', Token.refreshToken ?? '');
      await prefs.setInt('user_id', User.userID ?? 0);
      await prefs.setInt('cbpartner_id', User.cBPartnerID ?? 0);
      await prefs.setString('user_name', User.name ?? '');
      await prefs.setInt('token_rol', Token.rol ?? 0);
      await prefs.setInt('token_client', Token.client ?? 0);
      await prefs.setString('token_role_uu', Token.roleUU ?? '');
      await prefs.setInt('token_organitation', Token.organitation ?? 0);
      await prefs.setInt('token_warehouse', Token.warehouseID ?? 0);
      if (Token.primConfig != null) await prefs.setString('token_primconfig', Token.primConfig!);
      if (Token.primConfigId != null) await prefs.setInt('token_primconfig_id', Token.primConfigId!);

      SessionManager().startKeepAliveTimer();

      // Éxito, el token y datos de usuario ya se guardaron.
      return true;
    }
  } catch (e) {
      // Ignore error
    }
  return false;
}

// Auto-Login transparente para reemplazar el refresco de token fallido de iDempiere
Future<bool> autoLogin() async {
  if (Token.userName == null || Token.password == null) return false;
  try {
    final body = {
      "userName": Token.userName,
      "password": Token.password,
      "parameters": {
        "clientId": Token.client,
        "roleId": Token.rol,
        "organizationId": Token.organitation,
        "warehouseId": Token.warehouseID,
        "language": "es_PA"
      }
    };
    
    final response = await post(
      Uri.parse(Endpoint.authTokens), 
      headers: {'Content-Type': 'application/json'}, 
      body: jsonEncode(body)
    );
    
    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);
      Token.auth = responseBody['token'];
      Token.refreshToken = responseBody['refresh_token'];
      await saveLastTokenGeneratedAt();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', Token.auth ?? '');
      await prefs.setString('refresh_token', Token.refreshToken ?? '');
      return true;
    }
  } catch (e) {
    // Ignore error
  }
  return false;
}

// Refrescar Token (Original - Actualmente descartado por error 401 del servidor)
Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
  try {
    final response = await post(
      Uri.parse(Endpoint.authTokens), 
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $refreshToken'},
      body: jsonEncode({
        "clientId": Token.client,
        "roleId": Token.rol,
        "organizationId": Token.organitation,
        "warehouseId": Token.warehouseID,
        "language": "es_PA"
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      Token.auth = data['token'];
      if (data.containsKey('refresh_token')) {
        Token.refreshToken = data['refresh_token'];
      }
      // Actualizar SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', Token.auth ?? '');
      await prefs.setString('refresh_token', Token.refreshToken ?? '');
      await saveLastTokenGeneratedAt();
      
      return data;
    }
    if (response.body.toLowerCase().contains('<html')) {
      return {'error': 'Error ${response.statusCode}: Servicio no disponible.'};
    }
    return {'error': 'Error ${response.statusCode}: ${response.body}'};
  } catch (e) {
    return {'error': e.toString()};
  }
}

//Tercero
Future<int?> getPartnerID({required int userId}) async {
  try {
    final response = await get(Uri.parse('${Endpoint.adUser}?\$filter=AD_User_ID eq $userId'), headers: {'Content-Type': 'application/json', 'Authorization': Token.token});
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      final records = jsonResponse['records'] as List;
      final cBpartnerId = records.isNotEmpty ? records[0]['C_BPartner_ID']['id'] : null;
      return cBpartnerId;
    }
  } catch (e) {
      // Ignore error
    }
  return null;
}

//PrimConfig
Future<bool> getPrimConfig({required int rolId, required BuildContext context}) async {
  try {
    final response = await get(Uri.parse('${Endpoint.primConfig}?\$filter=AD_Role_ID eq $rolId'), headers: {'Content-Type': 'application/json', 'Authorization': Token.token});
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      final records = jsonResponse['records'] as List;
      if (records.isNotEmpty) {
        Token.primConfig = records[0]['ConfigurationLevel']?['id'];
        Token.primConfigId = records[0]['id'];
      } else {
        Token.primConfig = null;
        Token.primConfigId = null;
      }
      return Token.primConfig != null || Token.primConfigId != null;
    }
  } catch (e) {
      // Ignore error
    }
  return false;
}

//Ficha de Producto
Future<void> getProductChip() async {
  try {
    final response = await get(Uri.parse('${Endpoint.productChip}?\$filter=C_BPartner_ID eq ${User.cBPartnerID} and IsActive eq true&\$orderBy=Created desc'), headers: {'Content-Type': 'application/json', 'Authorization': Token.token});
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      final records = jsonResponse['records'] as List;
      ProductChip.frecuencyID = records.isNotEmpty ? records[0]['FrequencyType']['id'] : null;

      ProductChip.frecuencyName = records.isNotEmpty ? records[0]['FrequencyType']['value'] : null;

      ProductChip.mProductID = records.isNotEmpty ? records[0]['M_Product_ID']['id'] : null;

      ProductChip.iD = records.isNotEmpty ? records[0]['id'] : null;
    }
  } catch (e) {
      // Ignore error
    }
}

// Verificar si tiene proyectos
Future<bool> checkProjects() async {
  if (User.cBPartnerID == null) return false;
  try {
    final response = await get(Uri.parse('${Endpoint.project}?\$filter=C_BPartner_ID eq ${User.cBPartnerID}&\$top=1'), headers: {'Content-Type': 'application/json', 'Authorization': Token.token});
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      final records = jsonResponse['records'] as List;
      return records.isNotEmpty;
    }
  } catch (e) {
      // Ignore error
    }
  return false;
}

// Cambiar contraseña
Future<Map<String, dynamic>> changePassword({required String newPassword}) async {
  if (User.userID == null) {
    return {'success': false, 'message': 'ID de usuario no encontrado en la sesión actual.'};
  }
  
  try {
    // 1. Obtener UU del usuario
    String? userUuid;
    final userResponse = await get(
      Uri.parse('${Endpoint.adUser}/${User.userID}'), 
      headers: {'Content-Type': 'application/json', 'Authorization': Token.token}
    );
    
    if (userResponse.statusCode == 200) {
      final userJson = json.decode(utf8.decode(userResponse.bodyBytes));
      Map<String, dynamic>? userData = userJson;
      if (userJson.containsKey('records') && userJson['records'] is List && userJson['records'].isNotEmpty) {
        userData = userJson['records'][0];
      }
      
      if (userData != null) {
        userUuid = userData['uid'] ?? userData['uuid'] ?? userData['UU'] ?? userData['AD_User_UU'];
      }
    }
    
    if (userUuid == null) {
      return {'success': false, 'message': 'No se pudo obtener el UUID del usuario para el cambio de contraseña.'};
    }

    final body = {
      "Password": newPassword
    };
    
    final bodyJsonStr = jsonEncode(body);
    CurrentLogMessage.add('Payload para AD_User PUT (Cambio de Password con UU): $bodyJsonStr', level: 'INFO', tag: 'changePassword');
    
    final response = await put(
      Uri.parse('${Endpoint.adUser}/$userUuid'),
      headers: {'Content-Type': 'application/json', 'Authorization': Token.token},
      body: bodyJsonStr
    );
    
    if (response.statusCode == 200 || response.statusCode == 201) {
      final result = json.decode(utf8.decode(response.bodyBytes));
      if (result['isError'] == true) {
        return {'success': false, 'message': result['summary'] ?? 'Error al cambiar contraseña.'};
      }
      return {'success': true, 'message': 'Contraseña actualizada exitosamente.'};
    } else {
      CurrentLogMessage.add('changePassword error: ${response.statusCode}, ${response.body}', level: 'ERROR', tag: 'changePassword');
      return {'success': false, 'message': 'Error al cambiar la contraseña (Status ${response.statusCode}).'};
    }
  } catch (e) {
    CurrentLogMessage.add('Excepcion en changePassword: $e', level: 'ERROR', tag: 'changePassword');
    return {'success': false, 'message': 'Error inesperado.'};
  }
}

