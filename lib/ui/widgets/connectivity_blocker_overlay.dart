import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:primhub/api/connectivity_manager.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';

class ConnectivityBlockerOverlay extends StatelessWidget {
  final Widget child;

  const ConnectivityBlockerOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityManager().isDisconnectedNotifier,
      builder: (context, isDisconnected, _) {
        return Stack(
          children: [
            child,
            if (isDisconnected)
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: Stack(
                    children: [
                      // Fondo difuminado que absorbe los toques para no afectar pantallas ni modales inferiores
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                            child: Container(
                              color: Colors.black.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                      // Tarjeta interactiva en el centro
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: const _ConnectivityCard(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ConnectivityCard extends StatelessWidget {
  const _ConnectivityCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outline.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icono animado/destacado de desconexión
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.wifi_off_rounded,
              size: 44,
              color: Colors.amber.shade800,
            ),
          ),
          const SizedBox(height: 18),

          // Título principal
          Text(
            'Sin conexión a internet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),

          // Explicación
          Text(
            'Se detectó una interrupción temporal de red. Por seguridad, la navegación se ha pausado para proteger tus datos.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Banner de seguridad para tranquilidad del usuario
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outline.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 20, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tus formularios y cambios abiertos permanecen intactos.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Estado de reintento y cuenta regresiva
          ValueListenableBuilder<bool>(
            valueListenable: ConnectivityManager().isReconnectingNotifier,
            builder: (context, isReconnecting, _) {
              if (isReconnecting) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Reconectando con el servidor...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                );
              }

              return ValueListenableBuilder<int>(
                valueListenable: ConnectivityManager().countdownNotifier,
                builder: (context, countdown, _) {
                  return Text(
                    'Reintentando automáticamente en ${countdown}s...',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 20),

          // Botón de acción manual
          ValueListenableBuilder<bool>(
            valueListenable: ConnectivityManager().isReconnectingNotifier,
            builder: (context, isReconnecting, _) {
              return CustomButton(
                text: 'Reintentar ahora',
                icon: Icons.refresh_rounded,
                isLoading: isReconnecting,
                width: double.infinity,
                onPressed: isReconnecting
                    ? null
                    : () => ConnectivityManager().retryNow(),
              );
            },
          ),
        ],
      ),
    );
  }
}
