import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/api/session_manager.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:toastification/toastification.dart';
import 'package:primhub/navigation/deferred_registry.dart';
import 'package:primhub/navigation/navigation_service.dart';
import 'package:primhub/theme/theme.dart';
import 'package:primhub/ui/pages/Metrics/client_workload_page.dart';
import 'package:primhub/ui/pages/Login/login.dart';
import 'package:primhub/ui/pages/Login/login_selection_page.dart';
import 'package:primhub/ui/pages/Login/login_selection_args.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';

final ValueNotifier<bool> sessionHydrated = ValueNotifier(false);

Map<String, dynamic> _extraMap(Object? extra) =>
    extra is Map ? Map<String, dynamic>.from(extra) : <String, dynamic>{};
int? _projectId(Map<String, dynamic> extra) {
  final value = extra['projectId'];
  return value is int ? value : int.tryParse(value?.toString() ?? '');
}

final router = GoRouter(
  navigatorKey: NavigationService.navigatorKey,
  initialLocation: '/login',
  refreshListenable: sessionHydrated,
  redirect: (context, state) {
    final isLoggedIn = Token.auth?.isNotEmpty ?? false;
    final path = state.uri.path;
    final isAuthRoute =
        path == '/login' ||
        path == '/login-selection' ||
        path == '/reset-password';
    if (!isLoggedIn && !isAuthRoute) return '/login';
    if (isLoggedIn && isAuthRoute) return '/splash';
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.homePage(),
      ),
    ),
    GoRoute(
      path: '/splash',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.splashPage(),
      ),
    ),
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) =>
          NoTransitionPage(key: state.pageKey, child: const LoginPage()),
    ),
    GoRoute(
      path: '/login-selection',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: LoginSelectionPage(
          args: state.extra is LoginSelectionArgs
              ? state.extra! as LoginSelectionArgs
              : null,
        ),
      ),
    ),
    GoRoute(
      path: '/reset-password',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.resetPasswordPage(),
      ),
    ),
    GoRoute(
      path: '/support',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.supportPage(),
      ),
    ),
    GoRoute(
      path: '/my-requests',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.myRequestsPage(),
      ),
    ),
    GoRoute(
      path: '/request-updates/:id',
      pageBuilder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '');
        if (id == null) {
          return NoTransitionPage(
            key: state.pageKey,
            child: DeferredRegistry.homePage(),
          );
        }
        final extra = _extraMap(state.extra);
        return NoTransitionPage(
          key: state.pageKey,
          child: DeferredRegistry.requestUpdatesPage(
            id,
            extra['docNo']?.toString() ?? '...',
          ),
        );
      },
    ),
    GoRoute(
      path: '/knowledge-base',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.knowledgeBasePage(),
      ),
    ),
    GoRoute(
      path: '/deliverables',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.deliverablesPage(),
      ),
    ),
    GoRoute(
      path: '/metrics',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.metricsPage(),
      ),
    ),
    GoRoute(
      path: '/rep-workload',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.repWorkloadPage(),
      ),
    ),
    GoRoute(
      path: '/client-workload',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: const ClientWorkloadPage(),
      ),
    ),
    GoRoute(
      path: '/metric-requests',
      pageBuilder: (context, state) {
        final extra = _extraMap(state.extra);
        return NoTransitionPage(
          key: state.pageKey,
          child: DeferredRegistry.metricRequestsPage(
            _projectId(extra),
            extra['filterStatus'] as String?,
            extra['filterType'] as String?,
          ),
        );
      },
    ),
    GoRoute(
      path: '/project-requests',
      pageBuilder: (context, state) {
        final extra = _extraMap(state.extra);
        return NoTransitionPage(
          key: state.pageKey,
          child: DeferredRegistry.projectRequestsPage(
            _projectId(extra),
            extra['filterStatus'] as String?,
            extra['filterType'] as String?,
            extra['filterCompliance'] as String?,
            extra['showAllGroups'] as bool? ?? false,
          ),
        );
      },
    ),
    GoRoute(
      path: '/marketplace',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.marketplacePage(),
      ),
    ),
    GoRoute(
      path: '/profile',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.profilePage(),
      ),
    ),
    GoRoute(
      path: '/project-calendar',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.projectCalendarPage(_extraMap(state.extra)),
      ),
    ),
    GoRoute(
      path: '/bpartner-docs/general',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.bPartnerDocumentsPage('General'),
      ),
    ),
    GoRoute(
      path: '/bpartner-docs/seguimiento',
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: DeferredRegistry.bPartnerDocumentsPage('Seguimiento'),
      ),
    ),
  ],
);

class MainApp extends StatefulWidget {
  final String initialLanguageCode;

  const MainApp({super.key, this.initialLanguageCode = 'es'});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final FlutterLocalization _localization = FlutterLocalization.instance;

  @override
  void initState() {
    super.initState();
    _localization.init(
      mapLocales: const [
        MapLocale('es', AppLocale.es),
        MapLocale('en', AppLocale.en),
      ],
      initLanguageCode: widget.initialLanguageCode,
    );
    _localization.onTranslatedLanguage = _onLanguageChanged;
  }

  void _onLanguageChanged(Locale? locale) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemes.themeModeNotifier,
      builder: (context, themeMode, child) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => SessionManager().resetInactivityTimer(),
          onPointerMove: (_) => SessionManager().resetInactivityTimer(),
          child: MaterialApp.router(
            routerConfig: router,
            title: 'PrimHub',
            debugShowCheckedModeBanner: false,
            theme: AppThemes.lightTheme,
            darkTheme: AppThemes.darkTheme,
            themeMode: themeMode,
            localizationsDelegates: [
              ..._localization.localizationsDelegates,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: _localization.supportedLocales,
            locale: _localization.currentLocale,
            builder: (context, child) {
              return ToastificationWrapper(child: child!);
            },
          ),
        );
      },
    );
  }
}
