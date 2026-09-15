import 'package:flutter/widgets.dart';
import 'package:primhub/navigation/modules/home_module.dart' as home;
import 'package:primhub/navigation/modules/metrics_module.dart' as metrics;
import 'package:primhub/navigation/modules/projects_module.dart' as projects;
import 'package:primhub/navigation/modules/reset_password_module.dart' as reset_password;
import 'package:primhub/navigation/modules/secondary_module.dart' as secondary;
import 'package:primhub/navigation/modules/support_module.dart' as support;

abstract final class DeferredRegistry {
  static Future<void> loadHome() async {}
  static Future<void> loadSupport() async {}
  static Future<void> loadProjects() async {}
  static Future<void> loadMetrics() async {}
  static Future<void> loadSecondary() async {}
  static Future<void> loadResetPassword() async {}

  static void preloadHome() {}
  static void preloadForConfiguration(String? configuration) {}

  static Widget homePage() => home.buildHomePage();
  static Widget splashPage() => home.buildSplashPage();
  static Widget supportPage() => support.buildSupportPage();
  static Widget myRequestsPage() => support.buildMyRequestsPage();
  static Widget requestUpdatesPage(int id, String docNo) =>
      support.buildRequestUpdatesPage(id, docNo);
  static Widget deliverablesPage() => projects.buildDeliverablesPage();
  static Widget projectRequestsPage(
    int? projectId,
    String? filterStatus,
    String? filterType,
    String? filterCompliance,
    bool showAllGroups,
  ) =>
      projects.buildProjectRequestsPage(
        projectId,
        filterStatus,
        filterType,
        filterCompliance,
        showAllGroups,
      );
  static Widget projectCalendarPage(Map<String, dynamic> project) =>
      projects.buildProjectCalendarPage(project);
  static Widget metricsPage() => metrics.buildMetricsPage();
  static Widget repWorkloadPage() => metrics.buildRepWorkloadPage();
  static Widget clientWorkloadPage() => metrics.buildClientWorkloadPage();
  static Widget metricRequestsPage(
    int? projectId,
    String? filterStatus,
    String? filterType,
  ) =>
      metrics.buildMetricRequestsPage(projectId, filterStatus, filterType);
  static Widget knowledgeBasePage() => secondary.buildKnowledgeBasePage();
  static Widget marketplacePage() => secondary.buildMarketplacePage();
  static Widget profilePage() => secondary.buildProfilePage();
  static Widget bPartnerDocumentsPage(String viewType) =>
      secondary.buildBPartnerDocumentsPage(viewType);
  static Widget resetPasswordPage() => reset_password.buildResetPasswordPage();
}
