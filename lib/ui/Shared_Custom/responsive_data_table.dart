import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// A data class to define columns for the responsive table.
class ResponsiveDataColumn {
  final String label;
  final bool numeric;
  final String? sortKey;
  final Widget? suffixIcon;

  const ResponsiveDataColumn({required this.label, this.numeric = false, this.sortKey, this.suffixIcon});
}

/// A responsive data table that shows a split view (fixed/scrollable) on desktop
/// and a card list view on mobile.
class ResponsiveDataTable<T> extends StatefulWidget {
  final List<T> items;
  final List<ResponsiveDataColumn> fixedColumns;
  final List<ResponsiveDataColumn> scrollableColumns;
  final List<DataCell> Function(T item) fixedCellBuilder;
  final List<DataCell> Function(T item) scrollableCellBuilder;
  final Widget Function(T item) mobileCardBuilder;
  final Function(T item)? onRowTap;
  final Set<int> selectedIds;
  final Function(int id, bool isSelected)? onSelectChanged;
  final Function(bool? selected)? onSelectAll;
  final int Function(T item) getId;
  final bool showCheckboxColumn;
  final String? sortKey;
  final bool sortAscending;
  final void Function(String)? onSort;

  const ResponsiveDataTable({super.key, required this.items, this.fixedColumns = const [], required this.scrollableColumns, required this.fixedCellBuilder, required this.scrollableCellBuilder, required this.mobileCardBuilder, this.onRowTap, this.selectedIds = const {}, this.onSelectChanged, this.onSelectAll, required this.getId, this.showCheckboxColumn = false, this.sortKey, this.sortAscending = true, this.onSort});

  @override
  State<ResponsiveDataTable<T>> createState() => _ResponsiveDataTableState<T>();
}

class _ResponsiveDataTableState<T> extends State<ResponsiveDataTable<T>> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _fixedVerticalController = ScrollController();
  final ScrollController _scrollableVerticalController = ScrollController();
  
  List<DataRow>? _cachedFixedRows;
  List<DataRow>? _cachedScrollableRows;
  List<T>? _lastItems;
  Set<int>? _lastSelectedIds;
  bool? _lastShowCheckboxColumn;
  int? _lastFixedColumnsLength;
  int? _lastScrollableColumnsLength;

  @override
  void initState() {
    super.initState();
    _fixedVerticalController.addListener(() {
      if (_scrollableVerticalController.hasClients && _fixedVerticalController.offset != _scrollableVerticalController.offset) {
        _scrollableVerticalController.jumpTo(_fixedVerticalController.offset);
      }
    });
    _scrollableVerticalController.addListener(() {
      if (_fixedVerticalController.hasClients && _scrollableVerticalController.offset != _fixedVerticalController.offset) {
        _fixedVerticalController.jumpTo(_scrollableVerticalController.offset);
      }
    });
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _fixedVerticalController.dispose();
    _scrollableVerticalController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ResponsiveDataTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sortKey != widget.sortKey || oldWidget.sortAscending != widget.sortAscending) {
      _cachedFixedRows = null;
      _cachedScrollableRows = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          // Mobile View: List of cards
          return ListView.builder(
            itemCount: widget.items.length,
            itemBuilder: (context, index) {
              return widget.mobileCardBuilder(widget.items[index]);
            },
          );
        } else {
          // Desktop View: Split table
          return _buildDesktopTable();
        }
      },
    );
  }

  Widget _buildDesktopTable() {
    final theme = Theme.of(context);

    int? fixedSortColumnIndex;
    int? scrollableSortColumnIndex;
    
    int fixedOffset = widget.showCheckboxColumn ? 1 : 0;
    
    for (int i = 0; i < widget.fixedColumns.length; i++) {
       if (widget.fixedColumns[i].sortKey != null && widget.fixedColumns[i].sortKey == widget.sortKey) {
          fixedSortColumnIndex = i + fixedOffset;
       }
    }
    for (int i = 0; i < widget.scrollableColumns.length; i++) {
       if (widget.scrollableColumns[i].sortKey != null && widget.scrollableColumns[i].sortKey == widget.sortKey) {
          scrollableSortColumnIndex = i;
       }
    }

    Widget buildLabel(ResponsiveDataColumn c) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(c.label),
          if (c.suffixIcon != null) ...[
            const SizedBox(width: 4),
            c.suffixIcon!,
          ] else if (c.sortKey != null && c.sortKey != widget.sortKey) ...[
            const SizedBox(width: 4),
            Icon(Icons.unfold_more, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.5)),
          ],
        ],
      );
    }

    // --- Define Columns ---
    final List<DataColumn> allFixedColumns = [];
    if (widget.showCheckboxColumn) {
      final currentPageIds = widget.items.map((i) => widget.getId(i)).toSet();
      final bool allSelected = currentPageIds.isNotEmpty && currentPageIds.intersection(widget.selectedIds).length == currentPageIds.length;
      final bool someSelected = widget.selectedIds.isNotEmpty;
      
      allFixedColumns.add(
        DataColumn(
          label: Checkbox(value: allSelected ? true : (someSelected ? null : false), tristate: true, onChanged: widget.onSelectAll),
        ),
      );
    }
    allFixedColumns.addAll(widget.fixedColumns.map((c) => DataColumn(
      label: buildLabel(c), 
      numeric: c.numeric,
      onSort: c.sortKey != null && widget.onSort != null ? (index, _) => widget.onSort!(c.sortKey!) : null,
    )));

    final allScrollableColumns = widget.scrollableColumns.map((c) => DataColumn(
      label: buildLabel(c), 
      numeric: c.numeric,
      onSort: c.sortKey != null && widget.onSort != null ? (index, _) => widget.onSort!(c.sortKey!) : null,
    )).toList();

    // --- Build Rows ---
    final bool shouldRebuildRows = _cachedFixedRows == null ||
        _cachedScrollableRows == null ||
        _lastItems != widget.items ||
        _lastItems?.length != widget.items.length ||
        _lastShowCheckboxColumn != widget.showCheckboxColumn ||
        !setEquals(_lastSelectedIds, widget.selectedIds) ||
        _lastFixedColumnsLength != widget.fixedColumns.length ||
        _lastScrollableColumnsLength != widget.scrollableColumns.length;

    if (shouldRebuildRows) {
      _lastItems = widget.items;
      _lastSelectedIds = Set.from(widget.selectedIds);
      _lastShowCheckboxColumn = widget.showCheckboxColumn;
      _lastFixedColumnsLength = widget.fixedColumns.length;
      _lastScrollableColumnsLength = widget.scrollableColumns.length;

      _cachedFixedRows = [];
      _cachedScrollableRows = [];

      for (var item in widget.items) {
        final int realId = widget.getId(item);
        final bool isSelected = widget.selectedIds.contains(realId);

        final List<DataCell> fixedCells = [];
        if (widget.showCheckboxColumn) {
          fixedCells.add(
            DataCell(
              Checkbox(
                value: isSelected,
                onChanged: (selected) {
                  if (widget.onSelectChanged != null) {
                    widget.onSelectChanged!(realId, selected ?? false);
                  }
                },
              ),
            ),
          );
        }
        
        final builtFixed = widget.fixedCellBuilder(item);
        if (builtFixed.length != widget.fixedColumns.length) {
          // Mismatch during state transitions (e.g. logging out). Skip to avoid assertion crash.
          continue;
        }
        fixedCells.addAll(builtFixed);

        final builtScrollable = widget.scrollableCellBuilder(item);
        if (builtScrollable.length != widget.scrollableColumns.length) {
          // Mismatch during state transitions (e.g. logging out). Skip to avoid assertion crash.
          continue;
        }

        _cachedFixedRows!.add(DataRow(selected: isSelected, onSelectChanged: (_) => widget.onRowTap?.call(item), cells: fixedCells));
        _cachedScrollableRows!.add(DataRow(selected: isSelected, onSelectChanged: (_) => widget.onRowTap?.call(item), cells: builtScrollable));
      }
    }

    final List<DataRow> fixedRows = _cachedFixedRows!;
    final List<DataRow> scrollableRows = _cachedScrollableRows!;

    // --- Theme ---
    const double rowHeight = 52.0;
    final baseDataTableTheme = DataTableTheme.of(context).copyWith(
      dataRowMinHeight: rowHeight,
      dataRowMaxHeight: rowHeight,
      headingRowHeight: rowHeight,
      headingTextStyle: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
    );

    final scrollableDataTableTheme = baseDataTableTheme.copyWith(
      headingRowColor: MaterialStateProperty.all(theme.colorScheme.surfaceContainerHighest.withOpacity(0.3)),
      dataRowColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.selected)) {
          return theme.colorScheme.primary.withOpacity(0.15);
        }
        if (states.contains(WidgetState.hovered)) {
          return theme.colorScheme.primary.withOpacity(0.08);
        }
        return null;
      }),
    );

    final fixedDataTableTheme = baseDataTableTheme.copyWith(
      headingRowColor: MaterialStateProperty.all(theme.colorScheme.surfaceContainerHighest),
      dataRowColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        Color baseColor = theme.colorScheme.surfaceContainerHigh;
        if (states.contains(WidgetState.selected)) {
          return Color.alphaBlend(theme.colorScheme.primary.withOpacity(0.2), baseColor);
        }
        if (states.contains(WidgetState.hovered)) {
          return Color.alphaBlend(theme.colorScheme.primary.withOpacity(0.12), baseColor);
        }
        return baseColor;
      }),
    );

    if (widget.fixedColumns.isEmpty) {
      return Card(
        elevation: 4,
        clipBehavior: Clip.hardEdge,
        child: Scrollbar(
          controller: _horizontalScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: DataTableTheme(
              data: scrollableDataTableTheme,
              child: DataTable(
                showCheckboxColumn: widget.showCheckboxColumn, 
                onSelectAll: widget.onSelectAll, 
                columns: allScrollableColumns, 
                rows: scrollableRows,
                sortColumnIndex: scrollableSortColumnIndex,
                sortAscending: widget.sortAscending,
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 4,
      clipBehavior: Clip.hardEdge,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Fixed Part ---
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: _fixedVerticalController,
              physics: const ClampingScrollPhysics(),
              scrollDirection: Axis.vertical,
              child: RepaintBoundary(
                child: DataTableTheme(
                  data: fixedDataTableTheme,
                  child: DataTable(
                    showCheckboxColumn: false, // Handled manually
                    columns: allFixedColumns,
                    rows: fixedRows,
                    sortColumnIndex: fixedSortColumnIndex,
                    sortAscending: widget.sortAscending,
                  ),
                ),
              ),
            ),
          ),
          // --- Scrollable Part ---
          Expanded(
            child: ScrollbarTheme(
              data: ScrollbarThemeData(
                thumbColor: WidgetStateProperty.all(theme.colorScheme.onSurface.withOpacity(0.4)),
                trackColor: WidgetStateProperty.all(theme.colorScheme.surfaceContainerHighest),
                trackBorderColor: WidgetStateProperty.all(theme.colorScheme.outline.withOpacity(0.2)),
                thickness: WidgetStateProperty.all(10.0),
                trackVisibility: WidgetStateProperty.all(true),
                radius: const Radius.circular(5.0),
              ),
              child: Scrollbar(
                controller: _scrollableVerticalController,
                thumbVisibility: true,
                child: Scrollbar(
                  controller: _horizontalScrollController,
                  thumbVisibility: true,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      controller: _horizontalScrollController,
                      physics: const ClampingScrollPhysics(),
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _scrollableVerticalController,
                        physics: const ClampingScrollPhysics(),
                        scrollDirection: Axis.vertical,
                        child: RepaintBoundary(
                          child: DataTableTheme(
                            data: scrollableDataTableTheme,
                            child: DataTable(
                                showCheckboxColumn: false,
                                columns: allScrollableColumns,
                                rows: scrollableRows,
                                sortColumnIndex: scrollableSortColumnIndex,
                                sortAscending: widget.sortAscending,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
