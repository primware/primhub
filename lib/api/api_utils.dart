import 'dart:async';
import 'package:primhub/api/auth_api.dart';
import 'package:primhub/api/session_manager.dart';
import 'package:primhub/api/token.dart';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localization/flutter_localization.dart';

/// Maneja los errores 401 intentando refrescar el token.
/// Si el refresco falla, muestra un diálogo de sesión expirada.
///
/// Devuelve `true` si la sesión fue refrescada (y la llamada original puede ser reintentada),
/// `false` en caso contrario.
Completer<bool>? _refreshCompleter;

Future<bool> handleTokenRefresh() async {
  if (Token.userName == null || Token.password == null) {
    return false;
  }

  // Si ya hay un auto-login en progreso, las demás peticiones esperan a que este termine
  if (_refreshCompleter != null) {
    return await _refreshCompleter!.future;
  }

  // Bloqueamos futuras peticiones marcando que un refresco está en curso
  _refreshCompleter = Completer<bool>();

  try {
    // Hacer el Auto-Login transparente usando el usuario y contraseña guardados en memoria
    final success = await autoLogin();
    if (success) {
      _refreshCompleter!.complete(true);
      return true; // Refrescado exitosamente, se puede reintentar la llamada.
    } else {
      SessionManager().showSessionExpiredDialog();
      _refreshCompleter!.complete(false);
      return false; // El refresco falló.
    }
  } catch (e) {
    if (!_refreshCompleter!.isCompleted) {
      _refreshCompleter!.complete(false);
    }
    return false;
  } finally {
    // Liberamos el candado para que dentro de 60 minutos se pueda volver a hacer
    _refreshCompleter = null;
  }
}

Future<void> showLogoutConfirmation(BuildContext context) async {
  final bool? shouldLogout = await showDialog<bool>(
    context: context,
    builder: (context) => CustomModal(
      title: AppLocale.logout.getString(context),
      content: Text(AppLocale.logoutQuestion.getString(context)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocale.cancel.getString(context))),
        CustomButton(text: AppLocale.yesLogout.getString(context), backgroundColor: Colors.red, onPressed: () => Navigator.pop(context, true)),
      ],
    ),
  );
  if (shouldLogout == true) {
    // 1. Limpiar el token y la caché INMEDIATAMENTE.
    await Token.clear();
    GlobalCache.clear();
    SessionManager().stopKeepAliveTimer();
    // 2. Navegar al login. Ahora el router verá que no hay sesión y permitirá ir al login.
    // Usamos navigatorKey para obtener un contexto global y asegurar la navegación.
    final navContext = SessionManager.navigatorKey.currentContext;
    if (navContext != null && navContext.mounted) {
      GoRouter.of(navContext).go('/login');
    }
  }
}

const String _lastTokenGeneratedAtKey = 'last_token_generated_at';
const int _tokenReuseWindowMinutes = 40;

Future<void> saveLastTokenGeneratedAt() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_lastTokenGeneratedAtKey, DateTime.now().toIso8601String());
}

Future<DateTime?> _getLastTokenGeneratedAt() async {
  final prefs = await SharedPreferences.getInstance();
  final rawValue = prefs.getString(_lastTokenGeneratedAtKey);
  if (rawValue == null || rawValue.isEmpty) return null;
  return DateTime.tryParse(rawValue);
}

Future<bool> canReuseCurrentToken() async {
  if (Token.auth == null || Token.auth!.trim().isEmpty) return false;

  final lastGeneratedAt = await _getLastTokenGeneratedAt();
  if (lastGeneratedAt == null) return false;

  final minutesSinceLastToken = DateTime.now().difference(lastGeneratedAt).inMinutes;

  final canReuse = minutesSinceLastToken < _tokenReuseWindowMinutes;
  return canReuse;
}

// Validación preventiva desactivada (retorna inmediatamente) para dejar que el token se venza naturalmente en iDempiere
Future<void> preemptiveTokenCheck() async {
}
