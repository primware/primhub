import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http_client;
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/api/session_manager.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/navigation/navigation_service.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:universal_html/html.dart' as html;

class ConnectivityManager {
  static final ConnectivityManager _instance = ConnectivityManager._internal();
  factory ConnectivityManager() => _instance;
  ConnectivityManager._internal();

  static final ValueNotifier<int> connectionRestoredNotifier = ValueNotifier<int>(0);

  final ValueNotifier<bool> isDisconnectedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> countdownNotifier = ValueNotifier<int>(5);
  final ValueNotifier<bool> isReconnectingNotifier = ValueNotifier<bool>(false);

  Timer? _countdownTimer;
  bool _isChecking = false;
  bool _isVerifying = false;
  bool _isInitialized = false;

  void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    if (kIsWeb) {
      try {
        html.window.addEventListener('offline', (_) {
          notifyConnectionError('Navegador sin conexión');
        });
        html.window.addEventListener('online', (_) {
          retryNow();
        });
      } catch (_) {}
    }
  }

  void notifyConnectionError(Object error) {
    // Si no hay sesión iniciada, no bloqueamos la interfaz
    if (Token.auth == null || Token.auth!.trim().isEmpty) return;

    // Si ya está activo el bloqueo o ya se está verificando/reconectando, evitamos duplicados
    if (isDisconnectedNotifier.value || _isVerifying || _isChecking) return;

    // En Web, si el navegador reporta explícitamente estar offline:
    if (kIsWeb) {
      try {
        if (html.window.navigator.onLine == false) {
          isDisconnectedNotifier.value = true;
          _startCountdown();
          return;
        }
      } catch (_) {}
    }

    // Antes de bloquear la interfaz, verificar si realmente el servidor/red no responde,
    // o si fue un fallo puntual en una petición (error 500, proceso lento, etc.)
    _verifyAndNotify();
  }

  Future<void> _verifyAndNotify() async {
    if (_isVerifying) return;
    _isVerifying = true;
    try {
      final pingUri = Uri.parse('${Endpoint.baseUrl}/');
      final pingRes = await http_client
          .get(pingUri)
          .timeout(const Duration(milliseconds: 2500));
      if (pingRes.statusCode > 0) {
        // El servidor está en línea y respondió. NO bloquear la interfaz por un fallo puntual.
        return;
      }
    } catch (_) {
      // El ping falló, confirmando que la red o el servidor están caídos.
      if (!isDisconnectedNotifier.value) {
        isDisconnectedNotifier.value = true;
        _startCountdown();
      }
    } finally {
      _isVerifying = false;
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    countdownNotifier.value = 5;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdownNotifier.value > 1) {
        countdownNotifier.value--;
      } else {
        countdownNotifier.value = 5;
        attemptReconnection();
      }
    });
  }

  Future<void> retryNow() async {
    if (_isChecking) return;
    _startCountdown();
    await attemptReconnection();
  }

  Future<void> attemptReconnection() async {
    if (_isChecking) return;
    _isChecking = true;
    isReconnectingNotifier.value = true;

    try {
      // 1. Verificación de conectividad general con el servidor (endpoint raíz)
      bool serverReachable = false;
      try {
        final pingUri = Uri.parse('${Endpoint.baseUrl}/');
        final pingRes = await http_client
            .get(pingUri)
            .timeout(const Duration(seconds: 4));
        if (pingRes.statusCode > 0) {
          serverReachable = true;
        }
      } catch (_) {
        serverReachable = false;
      }

      if (!serverReachable) {
        // La red o el servidor siguen caídos. Mantener bloqueo y reiniciar cuenta regresiva.
        return;
      }

      // 2. El servidor responde. Validar si el token de sesión sigue activo.
      bool isJwtExpired = false;
      if (Token.auth != null && Token.auth!.isNotEmpty) {
        try {
          final payload = Token.decodePayload(Token.auth!);
          if (payload.containsKey('exp')) {
            final exp = payload['exp'] as int;
            final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            if (now >= exp) {
              isJwtExpired = true;
            }
          }
        } catch (_) {}
      }

      bool isSessionValid = false;

      if (!isJwtExpired && Token.auth != null && Token.auth!.isNotEmpty) {
        // El token no ha vencido por reloj. Validar con un modelo ligero que sí acepta el token de sesión.
        try {
          final verifyUri = Uri.parse('${Endpoint.baseUrl}/api/v1/models/R_Status?\$top=1');
          final verifyRes = await http_client.get(
            verifyUri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': Token.token,
            },
          ).timeout(const Duration(seconds: 4));

          if (verifyRes.statusCode == 200) {
            isSessionValid = true;
          } else if (verifyRes.statusCode == 401) {
            isSessionValid = false;
          } else {
            // Respuestas diferentes a 401 confirman que el token fue autenticado por el backend
            isSessionValid = true;
          }
        } catch (_) {
          // En Web, si el backend devuelve 401, el navegador puede arrojar error de CORS
          isSessionValid = false;
        }
      }

      // 3. Si el token expiró (o fue rechazado por el backend), solicitar uno nuevo automáticamente
      if (!isSessionValid) {
        final refreshed = await handleTokenRefresh();
        if (refreshed) {
          isSessionValid = true;
        }
      }

      if (isSessionValid) {
        // Caso A: El Wi-Fi/red volvió y la sesión sigue viva o fue renovada con éxito.
        _countdownTimer?.cancel();
        _countdownTimer = null;
        isDisconnectedNotifier.value = false;
        connectionRestoredNotifier.value++;

        final context = NavigationService.navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ToastMessage.show(
            context: context,
            message: 'Conexión restablecida con éxito',
            type: ToastType.success,
          );
        }
      } else {
        // Caso B: El Wi-Fi volvió, pero la sesión expiró Y no se pudo renovar con autoLogin.
        _countdownTimer?.cancel();
        _countdownTimer = null;
        isDisconnectedNotifier.value = false;

        SessionManager().showSessionExpiredDialog();
      }
    } finally {
      isReconnectingNotifier.value = false;
      _isChecking = false;
    }
  }

  void reset() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    isDisconnectedNotifier.value = false;
    isReconnectingNotifier.value = false;
    countdownNotifier.value = 5;
    _isChecking = false;
  }
}
