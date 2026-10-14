import 'dart:convert';
import 'package:http/http.dart' as http_client;
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/api/connectivity_manager.dart';
import 'package:primhub/api/session_manager.dart';
export 'package:http/http.dart' show MultipartRequest, MultipartFile, Response, StreamedResponse, Client;

/// Un wrapper alrededor de package:http/http.dart que intercepta automáticamente
/// las respuestas 401 (Unauthorized) e intenta refrescar el token de sesión.
bool _shouldSkipPreemptiveCheck(Uri url) {
  return url.path.contains('/auth/tokens');
}

bool _isNetworkOrCorsError(Object e) {
  final str = e.toString().toLowerCase();
  return str.contains('xmlhttprequest error') ||
      str.contains('failed to fetch') ||
      str.contains('clientexception') ||
      str.contains('socketexception') ||
      str.contains('timeoutexception') ||
      str.contains('connection refused') ||
      str.contains('network is unreachable') ||
      str.contains('err_failed') ||
      str.contains('err_name_not_resolved') ||
      str.contains('err_network_io_suspended') ||
      str.contains('handshakeexception') ||
      str.contains('httpexception');
}

Future<http_client.Response> get(Uri url, {Map<String, String>? headers}) async {
  final skipCheck = _shouldSkipPreemptiveCheck(url);
  if (!skipCheck) {
    await preemptiveTokenCheck();
  }
  final initialHeaders = skipCheck ? headers : (_updateAuthHeader(headers) ?? headers);
  
  try {
    var response = await http_client.get(url, headers: initialHeaders);
    if (response.statusCode == 401 && !skipCheck) {
      final refreshed = await handleTokenRefresh();
      if (refreshed) {
        final newHeaders = _updateAuthHeader(headers);
        response = await http_client.get(url, headers: newHeaders);
      } else {
        SessionManager().showSessionExpiredDialog();
      }
    }
    return response;
  } catch (e) {
    if (_isNetworkOrCorsError(e)) {
      ConnectivityManager().notifyConnectionError(e);
    }
    rethrow;
  }
}

Future<http_client.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final skipCheck = _shouldSkipPreemptiveCheck(url);
  if (!skipCheck) {
    await preemptiveTokenCheck();
  }
  final initialHeaders = skipCheck ? headers : (_updateAuthHeader(headers) ?? headers);

  try {
    var response = await http_client.post(url, headers: initialHeaders, body: body, encoding: encoding);
    if (response.statusCode == 401 && !skipCheck) {
      final refreshed = await handleTokenRefresh();
      if (refreshed) {
        final newHeaders = _updateAuthHeader(headers);
        response = await http_client.post(url, headers: newHeaders, body: body, encoding: encoding);
      } else {
        SessionManager().showSessionExpiredDialog();
      }
    }
    return response;
  } catch (e) {
    if (_isNetworkOrCorsError(e)) {
      ConnectivityManager().notifyConnectionError(e);
    }
    rethrow;
  }
}

Future<http_client.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final skipCheck = _shouldSkipPreemptiveCheck(url);
  if (!skipCheck) {
    await preemptiveTokenCheck();
  }
  final initialHeaders = skipCheck ? headers : (_updateAuthHeader(headers) ?? headers);

  try {
    var response = await http_client.put(url, headers: initialHeaders, body: body, encoding: encoding);
    if (response.statusCode == 401 && !skipCheck) {
      final refreshed = await handleTokenRefresh();
      if (refreshed) {
        final newHeaders = _updateAuthHeader(headers);
        response = await http_client.put(url, headers: newHeaders, body: body, encoding: encoding);
      } else {
        SessionManager().showSessionExpiredDialog();
      }
    }
    return response;
  } catch (e) {
    if (_isNetworkOrCorsError(e)) {
      ConnectivityManager().notifyConnectionError(e);
    }
    rethrow;
  }
}

Future<http_client.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final skipCheck = _shouldSkipPreemptiveCheck(url);
  if (!skipCheck) {
    await preemptiveTokenCheck();
  }
  final initialHeaders = skipCheck ? headers : (_updateAuthHeader(headers) ?? headers);

  try {
    var response = await http_client.delete(url, headers: initialHeaders, body: body, encoding: encoding);
    if (response.statusCode == 401 && !skipCheck) {
      final refreshed = await handleTokenRefresh();
      if (refreshed) {
        final newHeaders = _updateAuthHeader(headers);
        response = await http_client.delete(url, headers: newHeaders, body: body, encoding: encoding);
      } else {
        SessionManager().showSessionExpiredDialog();
      }
    }
    return response;
  } catch (e) {
    if (_isNetworkOrCorsError(e)) {
      ConnectivityManager().notifyConnectionError(e);
    }
    rethrow;
  }
}

Future<http_client.StreamedResponse> send(http_client.BaseRequest request) async {
  final skipCheck = _shouldSkipPreemptiveCheck(request.url);
  if (!skipCheck) {
    await preemptiveTokenCheck();
    if (Token.auth != null && Token.auth!.isNotEmpty) {
      if (request.headers.containsKey('Authorization') || request.headers.containsKey('authorization')) {
        final key = request.headers.containsKey('Authorization') ? 'Authorization' : 'authorization';
        request.headers[key] = Token.token;
      }
    }
  }

  try {
    var response = await request.send();
    if (response.statusCode == 401 && !skipCheck) {
      final refreshed = await handleTokenRefresh();
      if (!refreshed) {
        SessionManager().showSessionExpiredDialog();
      }
    }
    return response;
  } catch (e) {
    if (_isNetworkOrCorsError(e)) {
      ConnectivityManager().notifyConnectionError(e);
    }
    rethrow;
  }
}

Map<String, String>? _updateAuthHeader(Map<String, String>? headers) {
  if (headers == null) return null;
  final newHeaders = Map<String, String>.from(headers);
  // Si el header original tenía Authorization, la reemplazamos con el token actualizado
  if (newHeaders.containsKey('Authorization') || newHeaders.containsKey('authorization')) {
    final key = newHeaders.containsKey('Authorization') ? 'Authorization' : 'authorization';
    if (Token.auth != null && Token.auth!.isNotEmpty) {
      newHeaders[key] = Token.token; 
    }
  }
  return newHeaders;
}
