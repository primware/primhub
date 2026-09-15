import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart'; // Para priorityMap
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:primhub/api/token.dart';

/// Data class to hold filter state for requests.
class RequestFilterModel {
  final List<int> bpIds;
  final List<String> levels;
  final List<String> statuses;
  final List<int> statusIds;
  final List<String> situations;
  final List<int> salesRepIds;
  final List<int> userIds;
  final List<int> requestTypeIds;
  final List<int> categoryIds;
  final List<int> productChipIds;

  const RequestFilterModel({
    this.bpIds = const [],
    this.levels = const [],
    this.statuses = const [],
    this.statusIds = const [],
    this.situations = const [],
    this.salesRepIds = const [],
    this.userIds = const [],
    this.requestTypeIds = const [],
    this.categoryIds = const [],
    this.productChipIds = const [],
  });

  /// Creates a copy of this filter object with the given fields replaced with the new values.
  RequestFilterModel copyWith({
    List<int>? bpIds,
    List<String>? levels,
    List<String>? statuses,
    List<int>? statusIds,
    List<String>? situations,
    List<int>? salesRepIds,
    List<int>? userIds,
    List<int>? requestTypeIds,
    List<int>? categoryIds,
    List<int>? productChipIds,
  }) {
    return RequestFilterModel(
      bpIds: bpIds ?? this.bpIds,
      levels: levels ?? this.levels,
      statuses: statuses ?? this.statuses,
      statusIds: statusIds ?? this.statusIds,
      situations: situations ?? this.situations,
      salesRepIds: salesRepIds ?? this.salesRepIds,
      userIds: userIds ?? this.userIds,
      requestTypeIds: requestTypeIds ?? this.requestTypeIds,
      categoryIds: categoryIds ?? this.categoryIds,
      productChipIds: productChipIds ?? this.productChipIds,
    );
  }

  /// Calculates the number of active filters.
  int get activeFilterCount {
    int count = 0;
    if (bpIds.isNotEmpty) count++;
    if (levels.isNotEmpty) count++;
    if (statuses.isNotEmpty || statusIds.isNotEmpty) count++;
    if (situations.isNotEmpty) count++;
    if (salesRepIds.isNotEmpty) count++;
    if (userIds.isNotEmpty) count++;
    if (requestTypeIds.isNotEmpty) count++;
    if (categoryIds.isNotEmpty) count++;
    if (productChipIds.isNotEmpty) count++;
    return count;
  }
}

/// Enum para identificar los tipos de filtro activos.
enum ActiveFilterType { year, bp, level, status, situation, salesRep, user, search, productChip }

/// A reusable modal dialog for filtering requests.
class RequestFilterModal extends StatefulWidget {
  final RequestFilterModel initialFilter;
  final List<Map<String, dynamic>> bPartners;
  final List<Map<String, dynamic>> allBPartners;
  final List<dynamic> users;
  final List<Map<String, dynamic>> requests;
  final Map<String, int> statusIdMap;

  const RequestFilterModal({super.key, required this.initialFilter, required this.bPartners, required this.allBPartners, required this.users, required this.requests, required this.statusIdMap});

  @override
  State<RequestFilterModal> createState() => _RequestFilterModalState();
}

class _RequestFilterModalState extends State<RequestFilterModal> {
  late RequestFilterModel _tempFilter;
  bool _isLoadingMetadata = false;
  List<Map<String, dynamic>> _bPartners = [];
  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    _tempFilter = widget.initialFilter.copyWith();
    _bPartners = widget.bPartners;
    _users = widget.users;
    
    _loadMissingMetadata();
  }

  Future<void> _loadMissingMetadata() async {
    // Si ya estamos cargando globalmente, esperamos
    if (!GlobalCache.isDataLoaded) {
      setState(() => _isLoadingMetadata = true);
      await GlobalCache.syncData();
      if (mounted) {
        setState(() {
          _bPartners = GlobalCache.bPartners;
          _users = GlobalCache.users;
          _isLoadingMetadata = false;
        });
      }
      return;
    }

    bool needsBPs = _bPartners.isEmpty;
    bool needsUsers = _users.isEmpty;
    bool needsTypes = GlobalCache.requestTypes.isEmpty;
    bool needsCats = GlobalCache.categories.isEmpty;
    bool needsGroups = GlobalCache.groups.isEmpty;

    if (needsBPs || needsUsers || needsTypes || needsCats || needsGroups) {
      setState(() => _isLoadingMetadata = true);
      try {
        final logic = ProjectsLogic();
        await Future.wait([
          if (needsBPs)
            logic.fetchBPartners().then((val) {
              if (mounted) setState(() => _bPartners = List<Map<String, dynamic>>.from(val));
            }),
          if (needsUsers)
            logic.fetchUsers().then((val) {
              if (mounted) setState(() => _users = val);
            }),
          if (needsTypes)
            fetchRequestTypes().then((val) => GlobalCache.requestTypes = val),
          if (needsCats)
            fetchCategories().then((val) {
              GlobalCache.rawCategories = val;
              GlobalCache.categories = {for (var c in val) c['Name'].toString().trim(): c['id'] as int};
            }),
          if (needsGroups)
            fetchGroups().then((val) => GlobalCache.groups = val),
        ]);
      } catch (e) {
        // Ignore error
      }
      if (mounted) setState(() => _isLoadingMetadata = false);
    }
  }

  List<MapEntry<String, int>> _getFilteredStatusesForModal() {
    Set<int> targetCategories = {};
    for (int reqTypeId in _tempFilter.requestTypeIds) {
      int? catId = GlobalCache.requestTypeCategoryMap[reqTypeId];
      if (catId != null) {
        targetCategories.add(catId);
      }
    }

    return widget.statusIdMap.entries.where((e) {
      if (targetCategories.isEmpty) return true;
      
      int? statusCat = GlobalCache.statusCategoryMap[e.value];
      if (statusCat == null) return true;
      
      return targetCategories.contains(statusCat);
    }).toList();
  }

  Future<void> _openMultiSelectSearchModal({
    required String title, 
    required List<dynamic> items, 
    required List<String> currentValues, 
    required String Function(dynamic) getTitle, 
    String? Function(dynamic)? getSubtitle, 
    required String Function(dynamic) getValue, 
    String? Function(dynamic)? getGroupTab,
    required void Function(List<String>) onSelected
  }) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => MultiSelectSearchDialog(
        title: title, 
        items: items, 
        initialSelectedValues: currentValues, 
        getTitle: getTitle, 
        getSubtitle: getSubtitle, 
        getValue: getValue,
        getGroupTab: getGroupTab,
      ),
    );
    if (result != null) {
      onSelected(result);
    }
  }

  Widget _buildMultiSearchableField({required String label, required String hintText, required List<String> values, required bool isLoading, required bool isDisabled, required VoidCallback onTap}) {
    String displayText;
    if (values.isEmpty) {
      displayText = hintText;
    } else if (values.length == 1) {
      displayText = values.first;
    } else {
      displayText = '${values.length} seleccionados';
    }

    return InkWell(
      onTap: (isLoading || isDisabled) ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          suffixIcon: isLoading ? Transform.scale(scale: 0.5, child: const CircularProgressIndicator(strokeWidth: 3)) : const Icon(Icons.search),
        ),
        isEmpty: values.isEmpty,
        child: Text(
          displayText,
          style: TextStyle(fontSize: 16, color: (isLoading || isDisabled || values.isEmpty) ? Colors.grey[600] : Theme.of(context).colorScheme.onSurface),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<dynamic> modalUsers = _users;
    if (_tempFilter.bpIds.isNotEmpty) {
      final selectedBpIds = _tempFilter.bpIds.toSet();
      
      modalUsers = _users.where((u) {
        final userBpData = u['C_BPartner_ID'];
        final userBpId = (userBpData is Map)
            ? (userBpData['id'] as num?)?.toInt()
            : (userBpData is num ? userBpData.toInt() : null);
        return userBpId != null && selectedBpIds.contains(userBpId);
      }).toList();
    }

    return CustomModal(
      titleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Filtrar Solicitudes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.blue, size: 22),
            tooltip: '¿Cómo funcionan estos filtros?',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => CustomModal(
                  title: 'Interacción de Filtros',
                  width: 450,
                  content: const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Algunos filtros dependen de otros para mostrar resultados precisos:'),
                      SizedBox(height: 12),
                      Text('• Tercero → Usuarios:\n  Seleccionado: Muestra solo los usuarios de ese tercero.\n  Sin seleccionar: Muestra a todos los usuarios.'),
                      SizedBox(height: 12),
                      Text('• Tercero → Fichas de Producto:\n  Seleccionado: Muestra las fichas asociadas al tercero.\n  Sin seleccionar: Si eres administrador, esta opción se desactiva hasta elegir un tercero. Para otros roles, muestra sus fichas.'),
                      SizedBox(height: 12),
                      Text('• Tipo de Solicitud → Estado:\n  Seleccionado: Muestra solo los estados válidos para esa solicitud.\n  Sin seleccionar: Muestra todos los estados disponibles agrupados por categoría.'),
                    ],
                  ),
                  actions: [
                    CustomButton(text: 'Entendido', onPressed: () => Navigator.pop(context)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      width: 500,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (AccessControl.isAdmin) ...[
              _buildMultiSearchableField(
                label: AppLocale.partnerLabel.getString(context),
                hintText: _bPartners.isEmpty ? 'Cargando terceros...' : 'Todos los Terceros',
                values: _bPartners
                    .where((bp) => _tempFilter.bpIds.contains((bp['id'] as num?)?.toInt()))
                    .map((bp) => (bp['Name'] ?? '').toString())
                    .toList(),
                isLoading: _isLoadingMetadata && _bPartners.isEmpty,
                isDisabled: false,
                onTap: () => _openMultiSelectSearchModal(
                  title: 'Tercero',
                  items: _bPartners,
                  currentValues: _tempFilter.bpIds.map((id) => id.toString()).toList(),
                  getTitle: (item) => (item['Name'] ?? '').toString(),
                  getValue: (item) => (item['id'] as num).toInt().toString(),
                  onSelected: (vals) => setState(() => _tempFilter = _tempFilter.copyWith(
                    bpIds: vals.map((v) => int.parse(v)).toList()
                  )),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (AccessControl.isAdmin || !AccessControl.isSupport) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildMultiSearchableField(
                      label: AppLocale.commercialRep.getString(context),
                      hintText: AppLocale.allGenderNeutral.getString(context),
                      values: GlobalCache.salesReps
                          .where((rep) => _tempFilter.salesRepIds.contains(((rep['AD_User_ID'] ?? rep['id']) as num?)?.toInt()))
                          .map((rep) => (rep['Name'] ?? '').toString())
                          .toList(),
                      isLoading: false,
                      isDisabled: false,
                      onTap: () => _openMultiSelectSearchModal(
                        title: 'Representante Comercial',
                        items: GlobalCache.salesReps,
                        currentValues: _tempFilter.salesRepIds.map((id) => id.toString()).toList(),
                        getTitle: (item) => (item['Name'] ?? '').toString(),
                        getValue: (item) => ((item['AD_User_ID'] ?? item['id']) as num).toInt().toString(),
                        onSelected: (vals) => setState(() => _tempFilter = _tempFilter.copyWith(
                          salesRepIds: vals.map((v) => int.parse(v)).toList()
                        )),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMultiSearchableField(
                      label: 'Usuario',
                      hintText: _users.isEmpty ? 'Cargando...' : 'Todos',
                      values: modalUsers
                          .where((u) => _tempFilter.userIds.contains(((u['AD_User_ID'] ?? u['id']) as num?)?.toInt()))
                          .map((u) => (u['Name'] ?? '').toString())
                          .toList(),
                      isLoading: _isLoadingMetadata && _users.isEmpty,
                      isDisabled: false,
                      onTap: () => _openMultiSelectSearchModal(
                        title: 'Usuario',
                        items: modalUsers,
                        currentValues: _tempFilter.userIds.map((id) => id.toString()).toList(),
                        getTitle: (item) => (item['Name'] ?? '').toString(),
                        getValue: (item) => ((item['AD_User_ID'] ?? item['id']) as num).toInt().toString(),
                        onSelected: (vals) => setState(() => _tempFilter = _tempFilter.copyWith(
                          userIds: vals.map((v) => int.parse(v)).toList()
                        )),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                if (AccessControl.isAdmin) ...[
                  Expanded(
                    child: _buildMultiSearchableField(
                      label: 'Tipo de solicitud',
                      hintText: 'Todos',
                      values: GlobalCache.requestTypes.entries
                          .where((e) => _tempFilter.requestTypeIds.contains(e.value))
                          .map((e) => e.key)
                          .toList(),
                      isLoading: _isLoadingMetadata,
                      isDisabled: false,
                      onTap: () => _openMultiSelectSearchModal(
                        title: 'Tipo de solicitud',
                        items: GlobalCache.requestTypes.entries.toList(),
                        currentValues: _tempFilter.requestTypeIds.map((id) => id.toString()).toList(),
                        getTitle: (item) => (item as MapEntry<String, int>).key,
                        getValue: (item) => (item as MapEntry<String, int>).value.toString(),
                        onSelected: (vals) => setState(() => _tempFilter = _tempFilter.copyWith(
                          requestTypeIds: vals.map((v) => int.parse(v)).toList()
                        )),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: _buildMultiSearchableField(
                    label: 'Categoría',
                    hintText: 'Todos',
                    values: GlobalCache.rawCategories
                        .where((c) => c['showinprimhub'] == true)
                        .where((c) => _tempFilter.categoryIds.contains((c['id'] as num?)?.toInt()))
                        .map((c) => (c['Name'] ?? '').toString())
                        .toList(),
                    isLoading: _isLoadingMetadata,
                    isDisabled: false,
                    onTap: () => _openMultiSelectSearchModal(
                      title: 'Categoría',
                      items: GlobalCache.rawCategories.where((c) => c['showinprimhub'] == true).toList(),
                      currentValues: _tempFilter.categoryIds.map((id) => id.toString()).toList(),
                      getTitle: (item) => (item['Name'] ?? '').toString(),
                      getValue: (item) => ((item['id'] as num?)?.toInt()).toString(),
                      onSelected: (vals) => setState(() => _tempFilter = _tempFilter.copyWith(
                        categoryIds: vals.map((v) => int.parse(v)).toList()
                      )),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildMultiSearchableField(
                    label: 'Estado',
                    hintText: 'Todos',
                    values: widget.statusIdMap.entries
                        .where((e) => _tempFilter.statusIds.contains(e.value))
                        .map((e) => cleanStatusName(e.key))
                        .toList(),
                    isLoading: _isLoadingMetadata && widget.statusIdMap.isEmpty,
                    isDisabled: false,
                    onTap: () => _openMultiSelectSearchModal(
                      title: 'Estado',
                      items: _getFilteredStatusesForModal(),
                      currentValues: _tempFilter.statusIds.map((id) => id.toString()).toList(),
                      getTitle: (item) => cleanStatusName((item as MapEntry<String, int>).key),
                      getValue: (item) => (item as MapEntry<String, int>).value.toString(),
                      getGroupTab: (item) {
                        int statusId = (item as MapEntry<String, int>).value;
                        int? statusCat = GlobalCache.statusCategoryMap[statusId];
                        if (statusCat == null) return 'Otros';
                        return GlobalCache.statusCategoryNameMap[statusCat] ?? 'Otros';
                      },
                      onSelected: (vals) => setState(() => _tempFilter = _tempFilter.copyWith(
                        statusIds: vals.map((v) => int.parse(v)).toList()
                      )),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildMultiSearchableField(
              label: 'Prioridad',
              hintText: 'Todos',
              values: _tempFilter.levels,
              isLoading: false,
              isDisabled: false,
              onTap: () => _openMultiSelectSearchModal(
                title: 'Prioridad',
                items: ['Urgente', 'Alta', 'Media', 'Baja', 'Muy baja'],
                currentValues: _tempFilter.levels,
                getTitle: (item) => item.toString(),
                getValue: (item) => item.toString(),
                onSelected: (vals) => setState(() => _tempFilter = _tempFilter.copyWith(levels: vals)),
              ),
            ),
            const SizedBox(height: 16),
            _buildMultiSearchableField(
              label: 'Ficha de Producto',
              hintText: (!AccessControl.isAdmin) ? 'Todas las Fichas' : (_tempFilter.bpIds.isEmpty ? 'Seleccione primero un Tercero' : 'Todas las Fichas'),
              values: GlobalCache.productChips
                  .where((c) => _tempFilter.productChipIds.contains((c['id'] as num?)?.toInt()))
                  .map((c) => (c['Description'] ?? 'Ficha ${c['id']}').toString())
                  .toList(),
              isLoading: false,
              isDisabled: AccessControl.isAdmin && _tempFilter.bpIds.isEmpty,
              onTap: () {
                if (AccessControl.isAdmin && _tempFilter.bpIds.isEmpty) {
                  ToastMessage.show(
                    context: context,
                    message: 'Debe seleccionar al menos un Tercero primero',
                    type: ToastType.warning,
                  );
                  return;
                }

                // Filtrar fichas según los terceros seleccionados en el filtro o por el usuario
                List<Map<String, dynamic>> filteredChips = GlobalCache.productChips.where((chip) {
                  final isActive = chip['IsActive'];
                  if (isActive == false || isActive == 'N') return false;

                  final rawBp = chip['C_BPartner_ID'];
                  final chipBpId = rawBp is Map ? (rawBp['id'] as num?)?.toInt() : (rawBp as num?)?.toInt();
                  if (AccessControl.isAdmin) {
                    return _tempFilter.bpIds.contains(chipBpId);
                  } else {
                    return chipBpId == User.cBPartnerID;
                  }
                }).toList();

                _openMultiSelectSearchModal(
                  title: 'Ficha de Producto',
                  items: filteredChips,
                  currentValues: _tempFilter.productChipIds.map((id) => id.toString()).toList(),
                  getTitle: (item) => (item['Description'] ?? 'Ficha ${item['id']}').toString(),
                  getSubtitle: (item) {
                    final rawBp = item['C_BPartner_ID'];
                    final chipBpId = rawBp is Map ? (rawBp['id'] as num?)?.toInt() : (rawBp as num?)?.toInt();
                    
                    final bpInfo = GlobalCache.allBPartners.firstWhere(
                      (bp) => bp['id'] == chipBpId,
                      orElse: () => <String, dynamic>{},
                    );
                    final bpName = bpInfo.isNotEmpty ? (bpInfo['Name'] ?? 'ID $chipBpId') : 'ID $chipBpId';
                    
                    return "Tercero: $bpName";
                  },
                  getValue: (item) => (item['id'] as num).toInt().toString(),
                  onSelected: (vals) {
                    final newIds = vals.map((v) => int.parse(v)).toList();
                    setState(() => _tempFilter = _tempFilter.copyWith(
                      productChipIds: newIds
                    ));
                  },
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, null), child: Text(AppLocale.cancel.getString(context))),
        CustomButton(text: 'Aplicar Filtros', onPressed: () {
          Navigator.pop(context, _tempFilter);
        }),
      ],
    );
  }
}

/// A helper dialog for multi-selection with a search bar.
class MultiSelectSearchDialog extends StatefulWidget {
  final String title;
  final List<dynamic> items;
  final List<String> initialSelectedValues;
  final String Function(dynamic) getTitle;
  final String? Function(dynamic)? getSubtitle;
  final String Function(dynamic) getValue;
  final String? Function(dynamic)? getGroupTab;

  const MultiSelectSearchDialog({
    super.key, 
    required this.title, 
    required this.items, 
    required this.initialSelectedValues, 
    required this.getTitle, 
    this.getSubtitle, 
    required this.getValue,
    this.getGroupTab,
  });

  @override
  State<MultiSelectSearchDialog> createState() => _MultiSelectSearchDialogState();
}

class _MultiSelectSearchDialogState extends State<MultiSelectSearchDialog> {
  late Set<String> _tempSelectedValues;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Normalize initial selected values for robust comparison
    _tempSelectedValues = Set.from(widget.initialSelectedValues.map((s) => s.toLowerCase().trim()));
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = widget.items.where((item) {
      return widget.getTitle(item).toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    Map<String, List<dynamic>>? groupedItems;
    List<String> tabs = [];
    if (widget.getGroupTab != null) {
      groupedItems = {};
      for (var item in filteredItems) {
        final group = widget.getGroupTab!(item) ?? 'Otros';
        groupedItems.putIfAbsent(group, () => []).add(item);
      }
      tabs = groupedItems.keys.toList()..sort();
    }

    Widget buildList(List<dynamic> itemsToDisplay) {
      return ListView.separated(
        itemCount: itemsToDisplay.length,
        separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.grey, thickness: 0.3),
        itemBuilder: (context, index) {
          final item = itemsToDisplay[index];
          final itemValue = widget.getValue(item).toLowerCase().trim();
          final isSelected = _tempSelectedValues.contains(itemValue);

          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.getTitle(item), style: const TextStyle(fontSize: 14)),
            subtitle: widget.getSubtitle != null && widget.getSubtitle!(item) != null 
                ? Text(widget.getSubtitle!(item)!, style: const TextStyle(fontSize: 12, color: Colors.grey)) 
                : null,
            value: isSelected,
            onChanged: (bool? selected) => setState(() => selected == true ? _tempSelectedValues.add(itemValue) : _tempSelectedValues.remove(itemValue)),
          );
        },
      );
    }

    Widget listWidget;
    if (groupedItems != null && tabs.length > 1) {
      listWidget = DefaultTabController(
        length: tabs.length,
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Colors.grey,
              tabAlignment: TabAlignment.start,
              tabs: tabs.map((t) => Tab(text: t)).toList(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: tabs.map((t) => buildList(groupedItems![t]!)).toList(),
              ),
            ),
          ],
        ),
      );
    } else {
      listWidget = buildList(filteredItems);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 500, // Widened slightly to accommodate tabs
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Seleccionar ${widget.title}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.filter_list, color: Colors.grey),
                hintText: 'Filtrar...',
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
            const SizedBox(height: 16),
            Expanded(child: listWidget),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(null), child: Text(AppLocale.cancel.getString(context))),
                const SizedBox(width: 8),
                CustomButton(text: 'Aplicar', onPressed: () => Navigator.of(context).pop(_tempSelectedValues.toList())),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

