import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:flutter_localization/flutter_localization.dart';
 // Para priorityMap

enum ChipFilterMode {
  mixed,
  withChipFirst,
  withoutChipFirst,
  onlyWithChip,
  onlyWithoutChip,
}


class RequestFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final bool isAscending;
  final int rowsPerPage;
  final bool showHistory;
  final List<int> selectedYears;
  final VoidCallback onShowYearFilter;
  final VoidCallback onSortChanged;
  final Function(int?) onRowsPerPageChanged;
  final VoidCallback onClearFilters;
  final VoidCallback onAddRequest;
  final VoidCallback onToggleHistory;
  final VoidCallback onShowCalendar; // Nuevo callback para mostrar el calendario
  final VoidCallback onShowFilters;
  final int activeFilterCount;
  final bool isLoading;
  final bool showCalendar; // Add showCalendar
  final ChipFilterMode chipFilterMode;
  final ValueChanged<ChipFilterMode>? onChipFilterChanged;
  final VoidCallback? onExport; // Nuevo callback para exportar
  final Widget? counterWidget;

  const RequestFilterBar({
    super.key,
    required this.searchController,
    required this.isAscending,
    required this.rowsPerPage,
    required this.showHistory,
    required this.selectedYears,
    required this.onShowYearFilter,
    required this.onSortChanged,
    required this.onRowsPerPageChanged,
    required this.onClearFilters,
    required this.onAddRequest,
    required this.onToggleHistory,
    required this.onShowFilters,
    required this.activeFilterCount,
    required this.onShowCalendar,
    this.isLoading = false,
    this.showCalendar = false, // Default to false
    this.chipFilterMode = ChipFilterMode.mixed,
    this.onChipFilterChanged,
    this.onExport,
    this.counterWidget,
  });

  @override
  Widget build(BuildContext context) {

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isLargeScreen = constraints.maxWidth >= 800;
        final theme = Theme.of(context);

        Widget buildResponsiveButton({
          required String tooltip,
          required IconData icon,
          required VoidCallback? onPressed,
          Color? backgroundColor,
          Color? textColor,
        }) {
          if (!isLargeScreen) {
            return Tooltip(
              message: tooltip,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: backgroundColor ?? theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: IconButton(
                  icon: Icon(icon, color: textColor ?? theme.colorScheme.onPrimary, size: 20),
                  onPressed: onPressed,
                ),
              ),
            );
          } else {
            return CustomButton(
              text: tooltip,
              icon: icon,
              backgroundColor: backgroundColor,
              textColor: textColor,
              onPressed: onPressed,
            );
          }
        }

        final filterChips = Wrap(
          spacing: 16.0,
          runSpacing: 8.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (isLargeScreen)
              buildResponsiveButton(
                tooltip: AppLocale.filters.getString(context),
                onPressed: isLoading ? null : onShowFilters,
                icon: Icons.filter_list,
                backgroundColor: activeFilterCount > 0
                    ? theme.colorScheme.primaryContainer
                    : null,
                textColor: activeFilterCount > 0
                    ? theme.colorScheme.onPrimaryContainer
                    : null,
              ),

        if (activeFilterCount > 0)
          Chip(
            label: Text('$activeFilterCount'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
            padding: const EdgeInsets.all(4),
            visualDensity: VisualDensity.compact,
          ),
        if ((AccessControl.isAdmin || AccessControl.isExtSupport) && onChipFilterChanged != null)
          PopupMenuButton<ChipFilterMode>(
            enabled: !isLoading,
            initialValue: chipFilterMode,
            onSelected: onChipFilterChanged,
            offset: const Offset(0, 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: ChipFilterMode.mixed,
                child: Text(AppLocale.chipFilterMixed.getString(context)),
              ),
              PopupMenuItem(
                value: ChipFilterMode.withChipFirst,
                child: Text(AppLocale.chipFilterWithChipFirst.getString(context)),
              ),
              PopupMenuItem(
                value: ChipFilterMode.withoutChipFirst,
                child: Text(AppLocale.chipFilterWithoutChipFirst.getString(context)),
              ),
              PopupMenuItem(
                value: ChipFilterMode.onlyWithChip,
                child: Text(AppLocale.chipFilterOnlyWithChip.getString(context)),
              ),
              PopupMenuItem(
                value: ChipFilterMode.onlyWithoutChip,
                child: Text(AppLocale.chipFilterOnlyWithoutChip.getString(context)),
              ),
            ],
            child: Chip(
              backgroundColor: isLoading ? Theme.of(context).disabledColor.withOpacity(0.12) : null,
              side: (!isLoading && chipFilterMode != ChipFilterMode.mixed)
                  ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)
                  : null,
              labelStyle: TextStyle(
                color: isLoading
                    ? Theme.of(context).disabledColor
                    : (chipFilterMode != ChipFilterMode.mixed
                        ? Theme.of(context).colorScheme.primary
                        : null),
                fontWeight: (!isLoading && chipFilterMode != ChipFilterMode.mixed) ? FontWeight.bold : null,
              ),
              avatar: Icon(
                Icons.filter_alt, 
                size: 16,
                color: isLoading
                    ? Theme.of(context).disabledColor
                    : (chipFilterMode != ChipFilterMode.mixed
                        ? Theme.of(context).colorScheme.primary
                        : null),
              ),
              label: SizedBox(
                width: 165,
                child: Text(
                  _getChipFilterLabel(context, chipFilterMode),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),

        if (!AccessControl.isSupport)
          ActionChip(
            avatar: const Icon(Icons.calendar_today, size: 16),
            label: Text(() {
              if (selectedYears.isEmpty) return AppLocale.yearAll.getString(context);
              if (selectedYears.length == 1) {
                if (selectedYears.first == DateTime.now().year) return AppLocale.yearCurrent.getString(context);
                return AppLocale.yearLabel.getStringWithVariables(context, {'year': selectedYears.first.toString()});
              }
              return AppLocale.yearCount.getStringWithVariables(context, {'count': selectedYears.length.toString()});
            }()),
            onPressed: onShowYearFilter,
          ),
        DropdownButton<int>(
          value: rowsPerPage,
          items: [10, 25, 50, 100]
              .map((int value) => DropdownMenuItem<int>(
                    value: value,
                    child: Text(AppLocale.rows.getStringWithVariables(
                      context,
                      {'count': '$value'},
                    )),
                  ))
              .toList(),
          onChanged: isLoading ? null : onRowsPerPageChanged,
        ),
        TextButton.icon(
          icon: const Icon(Icons.filter_alt_off, size: 18),
          label: Text(AppLocale.clear.getString(context)),
          onPressed: isLoading ? null : onClearFilters,
        ),
      ],
    );

        Widget topRow = isLargeScreen
            ? SizedBox(
                width: double.infinity,
                child: Row(
                  children: [
      
                    Expanded(
                      child: CustomTextField(
                        controller: searchController,
                        hintText: AppLocale.searchRequests.getString(context),
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!AccessControl.isRealSupport)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: CustomButton(
                                text: showCalendar ? AppLocale.viewList.getString(context) : AppLocale.calendarGantt.getString(context),
                                onPressed: isLoading ? null : onShowCalendar,
                                icon: showCalendar ? Icons.list_alt : Icons.calendar_month,
                                backgroundColor: Theme.of(context).colorScheme.tertiary,
                                textColor: Theme.of(context).colorScheme.onTertiary,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: CustomButton(
                              text: showHistory ? AppLocale.viewActive.getString(context) : AppLocale.viewHistory.getString(context),
                              onPressed: isLoading ? null : onToggleHistory,
                              icon: showHistory ? Icons.list : Icons.history,
                              backgroundColor: Theme.of(context).colorScheme.secondary,
                              textColor: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                          if (AccessControl.canCreateRequests)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: CustomButton(
                                text: AppLocale.createRequest.getString(context),
                                onPressed: isLoading ? null : onAddRequest,
                                icon: Icons.add,
                              ),
                            ),
                          if (onExport != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: CustomButton(
                                text: AppLocale.exportTable.getString(context),
                                onPressed: isLoading ? null : onExport,
                                icon: Icons.download,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CustomTextField(
                          controller: searchController,
                          hintText: AppLocale.searchRequests.getString(context),
                          prefixIcon: const Icon(Icons.search),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: [
                      if (!AccessControl.isRealSupport)
                        buildResponsiveButton(
                          tooltip: showCalendar ? AppLocale.viewList.getString(context) : AppLocale.calendarGantt.getString(context),
                          onPressed: isLoading ? null : onShowCalendar,
                          icon: showCalendar ? Icons.list_alt : Icons.calendar_month,
                          backgroundColor: theme.colorScheme.tertiary,
                          textColor: theme.colorScheme.onTertiary,
                        ),
                      buildResponsiveButton(
                        tooltip: showHistory ? AppLocale.viewActive.getString(context) : AppLocale.viewHistory.getString(context),
                        onPressed: isLoading ? null : onToggleHistory,
                        icon: showHistory ? Icons.list : Icons.history,
                        backgroundColor: theme.colorScheme.secondary,
                        textColor: theme.colorScheme.onSecondary,
                      ),
                      if (onExport != null)
                        buildResponsiveButton(
                          tooltip: AppLocale.exportTable.getString(context),
                          onPressed: isLoading ? null : onExport,
                          icon: Icons.download,
                        ),
                      if (AccessControl.canCreateRequests)
                        buildResponsiveButton(
                          tooltip: AppLocale.createRequest.getString(context),
                          onPressed: isLoading ? null : onAddRequest,
                          icon: Icons.add,
                        ),
                      buildResponsiveButton(
                        tooltip: AppLocale.filters.getString(context),
                        onPressed: isLoading ? null : onShowFilters,
                        icon: Icons.filter_list,
                        backgroundColor: activeFilterCount > 0
                            ? theme.colorScheme.primaryContainer
                            : null,
                        textColor: activeFilterCount > 0
                            ? theme.colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ],
                  ),
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            topRow,
            const SizedBox(height: 12),
            if (counterWidget != null)
              isLargeScreen
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: filterChips),
                        const SizedBox(width: 16),
                        counterWidget!,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        filterChips,
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: counterWidget!,
                        ),
                      ],
                    )
            else
              filterChips,
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  String _getChipFilterLabel(BuildContext context, ChipFilterMode mode) {
    switch (mode) {
      case ChipFilterMode.mixed:
        return AppLocale.sheetStatus.getString(context);
      case ChipFilterMode.withChipFirst:
        return AppLocale.chipFilterWithChipFirst.getString(context);
      case ChipFilterMode.withoutChipFirst:
        return AppLocale.chipFilterWithoutChipFirst.getString(context);
      case ChipFilterMode.onlyWithChip:
        return AppLocale.chipFilterOnlyWithChipShort.getString(context);
      case ChipFilterMode.onlyWithoutChip:
        return AppLocale.chipFilterOnlyWithoutChipShort.getString(context);
    }
  }
}
