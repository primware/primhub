import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';

class ProjectBottomNav extends StatelessWidget {
  final String currentRoute;

  const ProjectBottomNav({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    List<String> routes = ['/'];
    List<NavigationDestination> destinations = [NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: AppLocale.dashboard.getString(context))];

    if (AccessControl.isSupport) {
      routes.add('/my-requests');
      destinations.add(NavigationDestination(icon: const Icon(Icons.help_outline), selectedIcon: const Icon(Icons.help), label: AppLocale.requests.getString(context)));

      routes.add('/support');
      destinations.add(NavigationDestination(icon: const Icon(Icons.schedule_outlined), selectedIcon: const Icon(Icons.schedule), label: AppLocale.hours.getString(context)));
    }

    if (AccessControl.isProject) {
      routes.add('/deliverables');
      destinations.add(NavigationDestination(icon: const Icon(Icons.folder_outlined), selectedIcon: const Icon(Icons.folder), label: AppLocale.projects.getString(context)));
    }

    routes.add('/metrics');
    destinations.add(NavigationDestination(icon: const Icon(Icons.bar_chart_outlined), selectedIcon: const Icon(Icons.bar_chart), label: AppLocale.metrics.getString(context)));

    int selectedIndex = routes.indexOf(currentRoute);
    if (selectedIndex == -1) selectedIndex = 0;

    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        if (index != selectedIndex) {
          context.go(routes[index]);
        }
      },
      destinations: destinations,
    );
  }
}
