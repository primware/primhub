import 'package:flutter/widgets.dart';
import 'package:primhub/navigation/deferred_route_page.dart';
import 'package:primhub/navigation/modules/home_module.dart' deferred as home;
import 'package:primhub/navigation/modules/metrics_module.dart' deferred as metrics;
import 'package:primhub/navigation/modules/projects_module.dart' deferred as projects;
import 'package:primhub/navigation/modules/reset_password_module.dart' deferred as reset_password;
import 'package:primhub/navigation/modules/secondary_module.dart' deferred as secondary;
import 'package:primhub/navigation/modules/support_module.dart' deferred as support;

abstract final class DeferredRegistry {
  static Future<void> loadHome() => home.loadLibrary();
  static Future<void> loadSupport() => support.loadLibrary();
  static Future<void> loadProjects() => projects.loadLibrary();
  static Future<void> loadMetrics() => metrics.loadLibrary();
  static Future<void> loadSecondary() => secondary.loadLibrary();
  static Future<void> loadResetPassword() => reset_password.loadLibrary();

  static void preloadHome() {
    loadHome();
  }

  static void preloadForConfiguration(String? configuration) {
    if (configuration == 'support') loadSupport();
    if (configuration == 'projects') loadProjects();
    if (configuration == 'metrics') loadMetrics();
  }

  static Widget homePage() => DeferredRoutePage(
    loadLibrary: home.loadLibrary,
    builder: () => home.buildHomePage(),
  );
  
  static Widget splashPage() => DeferredRoutePage(
    loadLibrary: home.loadLibrary,
    builder: () => home.buildSplashPage(),
  );

  static Widget supportPage() => DeferredRoutePage(
    loadLibrary: support.loadLibrary,
    builder: () => support.buildSupportPage(),
  );

  static Widget myRequestsPage() => DeferredRoutePage(
    loadLibrary: support.loadLibrary,
    builder: () => support.buildMyRequestsPage(),
  );

  static Widget requestUpdatesPage(int id, String docNo) => DeferredRoutePage(
    loadLibrary: support.loadLibrary,
    builder: () => support.buildRequestUpdatesPage(id, docNo),
  );

  static Widget deliverablesPage() => DeferredRoutePage(
    loadLibrary: projects.loadLibrary,
    builder: () => projects.buildDeliverablesPage(),
  );

  static Widget projectRequestsPage(
    int? projectId,
    String? filterStatus,
    String? filterType,
    String? filterCompliance,
    bool showAllGroups,
  ) => DeferredRoutePage(
    loadLibrary: projects.loadLibrary,
    builder: () => projects.buildProjectRequestsPage(
      projectId,
      filterStatus,
      filterType,
      filterCompliance,
      showAllGroups,
    ),
  );

  static Widget projectCalendarPage(Map<String, dynamic> project) => DeferredRoutePage(
    loadLibrary: projects.loadLibrary,
    builder: () => projects.buildProjectCalendarPage(project),
  );

  static Widget metricsPage() => DeferredRoutePage(
    loadLibrary: metrics.loadLibrary,
    builder: () => metrics.buildMetricsPage(),
  );

  static Widget repWorkloadPage() => DeferredRoutePage(
    loadLibrary: metrics.loadLibrary,
    builder: () => metrics.buildRepWorkloadPage(),
  );

  static Widget clientWorkloadPage() => DeferredRoutePage(
    loadLibrary: metrics.loadLibrary,
    builder: () => metrics.buildClientWorkloadPage(),
  );

  static Widget metricRequestsPage(
    int? projectId,
    String? filterStatus,
    String? filterType,
  ) => DeferredRoutePage(
    loadLibrary: metrics.loadLibrary,
    builder: () => metrics.buildMetricRequestsPage(projectId, filterStatus, filterType),
  );

  static Widget knowledgeBasePage() => DeferredRoutePage(
    loadLibrary: secondary.loadLibrary,
    builder: () => secondary.buildKnowledgeBasePage(),
  );

  static Widget marketplacePage() => DeferredRoutePage(
    loadLibrary: secondary.loadLibrary,
    builder: () => secondary.buildMarketplacePage(),
  );

  static Widget profilePage() => DeferredRoutePage(
    loadLibrary: secondary.loadLibrary,
    builder: () => secondary.buildProfilePage(),
  );

  static Widget bPartnerDocumentsPage(String viewType) => DeferredRoutePage(
    loadLibrary: secondary.loadLibrary,
    builder: () => secondary.buildBPartnerDocumentsPage(viewType),
  );

  static Widget resetPasswordPage() => DeferredRoutePage(
    loadLibrary: reset_password.loadLibrary,
    builder: () => reset_password.buildResetPasswordPage(),
  );
}
