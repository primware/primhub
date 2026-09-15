import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:primhub/api/api_http.dart' as http;
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart'; // Para priorityMap
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/pages/Support/Requests/bulk_summary_view.dart';
import 'package:primhub/api/contract_api.dart'; // Para Product Chips
import 'package:primhub/api/access_control.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';

class BulkEditRequestDialog extends StatefulWidget {
  final Set<int> selectedIds;
  final VoidCallback onSaved;

  const BulkEditRequestDialog({
    super.key,
    required this.selectedIds,
    required this.onSaved,
  });

  @override
  State<BulkEditRequestDialog> createState() => _BulkEditRequestDialogState();
}

class _BulkEditRequestDialogState extends State<BulkEditRequestDialog> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showSummary = false;
  final List<Map<String, dynamic>> _results = [];
  int? _processingId;
  int _successCount = 0;
  int _errorCount = 0;
  int _currentIndex = 0;
  Map<String, String> _currentChangesMap = {};

  String? _selectedType;
  String? _selectedCategory;
  String? _selectedGroup;
  String? _selectedStatus;
  int? _selectedBpId;
  int? _selectedUserId;
  int? _selectedProductChipId;

  bool _isProductChipBlocked = false;
  List<Map<String, dynamic>> _productChips = [];
  bool _isLoadingChips = false;
  final Set<int> _originalBpIds = {};

  Map<String, int> _statusIdMap = {};
  Map<String, int> _requestTypeMap = {};
  Map<String, int> _categoryMap = {};
  Map<String, int> _groupMap = {};
  List<dynamic> _users = [];
  List<dynamic> _bPartnersList = [];

  @override
  void initState() {
    super.initState();
    _checkOriginalBps();
    _loadDictionaries();
  }

  void _checkOriginalBps() {
    for (var id in widget.selectedIds) {
      final req = GlobalCache.requests.firstWhere((r) => r['id'] == id, orElse: () => <String,dynamic>{});
      if (req.isNotEmpty) {
        final bpRaw = req['C_BPartner_ID'];
        if (bpRaw is Map && bpRaw['id'] != null) {
          _originalBpIds.add(bpRaw['id'] as int);
        } else if (bpRaw is int) {
          _originalBpIds.add(bpRaw);
        }
      }
    }
    if (_originalBpIds.length > 1) {
      _isProductChipBlocked = true;
    } else if (_originalBpIds.length == 1) {
      _fetchProductChips(_originalBpIds.first);
    }
  }

  Future<void> _fetchProductChips(int bpId) async {
    setState(() {
      _isLoadingChips = true;
      _selectedProductChipId = null;
    });
    final chips = await ContractApi.getSupportProductChips(bPartnerId: bpId);
    if (mounted) {
      setState(() {
        _productChips = chips.where((c) {
          final active = c['IsActive'] == 'Y' || c['IsActive'] == true;
          return active;
        }).toList();
        _isLoadingChips = false;
      });
    }
  }

  Future<void> _loadDictionaries() async {
    try {
      final bPartnersFuture = GlobalCache.bPartners.isNotEmpty
          ? Future.value(GlobalCache.bPartners)
          : ProjectsLogic().fetchBPartners();

      final futures = await Future.wait([
        fetchStatuses(),
        _fetchMap('${Endpoint.baseUrl}/api/v1/models/R_RequestType'),
        _fetchMap(
          '${Endpoint.baseUrl}/api/v1/models/R_Category?\$filter=showinprimhub eq true',
        ),
        _fetchMap('${Endpoint.baseUrl}/api/v1/models/R_Group'),
        ProjectsLogic().fetchUsers(),
        bPartnersFuture,
      ]);

      if (mounted) {
        setState(() {
          _statusIdMap = futures[0] as Map<String, int>;
          _requestTypeMap = futures[1] as Map<String, int>;
          _categoryMap = futures[2] as Map<String, int>;
          _groupMap = futures[3] as Map<String, int>;
          _users = futures[4] as List<dynamic>;
          // Aplicamos el filtro para excluir terceros inactivos (con '~')
          final bps = futures[5] as List<dynamic>;
          _bPartnersList = bps.where((bp) {
            final name = bp['Name']?.toString() ?? '';
            final rawVendor = bp['IsVendor'] ?? bp['isVendor'];
            final isVendorStr = rawVendor?.toString().trim().toLowerCase();
            bool isVendor = isVendorStr == 'true' || isVendorStr == 'y';

            final rawCustomer = bp['IsCustomer'] ?? bp['isCustomer'];
            final isCustomerStr = rawCustomer?.toString().trim().toLowerCase();
            bool isCustomer = isCustomerStr == 'true' || isCustomerStr == 'y';
            if (rawCustomer == null) isCustomer = true;

            final isSpecificAdmin = name.trim().toUpperCase().contains('LA CASA DEL SOFTWARE') ||
                                    bp['C_BPartner_UU'] == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95' ||
                                    bp['Record_UU'] == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95' ||
                                    bp['UUID'] == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95' ||
                                    bp['uuid'] == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95';

            return !name.startsWith('~') && ((isCustomer && !isVendor) || isSpecificAdmin);
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastMessage.show(context: context, message: 'Error cargando diccionarios', type: ToastType.failure);
      }
    }
  }

  Future<Map<String, int>> _fetchMap(String url) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': Token.token,
      },
    );
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      final records = jsonResponse['records'] as List;
      return {for (var r in records) r['Name']: r['id']};
    }
    return {};
  }

  Future<void> _handleSave() async {
    // 1. Recopilar y mapear los cambios para mostrar en el resumen
    final Map<String, String> changes = {};
    if (_selectedType != null) changes['Tipo de Solicitud'] = _selectedType!;
    if (_selectedCategory != null) changes['Categoría'] = _selectedCategory!;
    if (_selectedGroup != null) changes['Grupo'] = _selectedGroup!;
    if (_selectedProductChipId != null) {
      final chipName = _productChips.firstWhere((c) => c['id'] == _selectedProductChipId, orElse: () => <String,dynamic>{})['Name']?.toString() ?? 'Ficha $_selectedProductChipId';
      changes['Ficha de Producto'] = chipName;
    }
    if (_selectedStatus != null) changes['Estado'] = cleanStatusName(_selectedStatus!);
    if (_selectedBpId != null) {
      final bpName =
          _bPartnersList
              .firstWhere(
                (bp) => bp['id'] == _selectedBpId,
                orElse: () => <String, dynamic>{},
              )['Name']
              ?.toString() ??
          'Tercero $_selectedBpId';
      changes['Tercero'] = bpName;
    }
    if (_selectedUserId != null) {
      final userName =
          _users
              .firstWhere(
                (u) => (u['AD_User_ID'] ?? u['id']) == _selectedUserId,
                orElse: () => <String, dynamic>{},
              )['Name']
              ?.toString() ??
          'Usuario $_selectedUserId';
      changes['Usuario Asignado'] = userName;
    }

    // 2. Validar que haya al menos un cambio seleccionado
    if (changes.isEmpty) {
      ToastMessage.show(context: context, message: 'No has seleccionado ningún campo para modificar.', type: ToastType.warning);
      return;
    }

    // 3. Mostrar el diálogo de confirmación al administrador
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => CustomModal(
        title: 'Confirmar Edición Masiva',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Seguro que vas a hacer este cambio? Vas a afectar a ${widget.selectedIds.length} fila(s) en los siguientes campos:',
            ),
            const SizedBox(height: 16),
            ...changes.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Text(
                  '• ${e.key}: ${e.value}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Esta acción se aplicará inmediatamente y no se puede deshacer de forma masiva.',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          CustomButton(
            text: 'Continuar',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isSaving = true;
      _showSummary = false;
      _results.clear();
      _successCount = 0;
      _errorCount = 0;
      _currentIndex = 0;
      _currentChangesMap = changes;
    });

    for (int i = 0; i < widget.selectedIds.length; i++) {
      final id = widget.selectedIds.elementAt(i);
      if (!mounted) break;
      
      setState(() {
        _processingId = id;
        _currentIndex = i + 1;
      });

      final request = GlobalCache.requests.firstWhere((r) => r['id'] == id, orElse: () => <String, dynamic>{});
      final documentNo = request['DocumentNo']?.toString() ?? request['documentNo']?.toString() ?? id.toString();
      final summary = request['Summary']?.toString() ?? '';

      final result = await updateRemoteRequest(
        id: id,
        productChipId: _selectedProductChipId,
        statusId: _selectedStatus != null
            ? _statusIdMap[_selectedStatus]
            : null,
        requestTypeId: _selectedType != null
            ? _requestTypeMap[_selectedType]
            : null,
        categoryId: _selectedCategory != null
            ? _categoryMap[_selectedCategory]
            : null,
        groupId: _selectedGroup != null ? _groupMap[_selectedGroup] : null,
        bPartnerId: _selectedBpId,
        userId: _selectedUserId,
      );

      final success = result['success'] == true;

      _results.add({
        'id': id,
        'documentNo': documentNo,
        'summary': summary,
        'success': success,
        'error': success ? null : result['message'],
      });

      if (success) {
        await GlobalCache.syncSingleRequest(id);
        if (mounted) setState(() => _successCount++);
      } else {
        if (mounted) setState(() => _errorCount++);
      }
    }

    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 600)); // Pequeña pausa para que el usuario vea que terminó
      if (!mounted) return;
      
      setState(() {
        _isSaving = false;
        _showSummary = true;
        _processingId = null;
      });
      widget.onSaved();
    }
  }

  Widget _buildSingleSearchableField({
    required String label,
    required String hintText,
    required String? valueText,
    required bool isLoading,
    required bool isDisabled,
    required VoidCallback onTap,
  }) {
    String displayText = valueText ?? hintText;

    return InkWell(
      onTap: (isLoading || isDisabled) ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          suffixIcon: isLoading 
            ? Transform.scale(scale: 0.5, child: const CircularProgressIndicator(strokeWidth: 3)) 
            : const Icon(Icons.search),
        ),
        isEmpty: valueText == null,
        child: Text(
          displayText,
          style: TextStyle(
            fontSize: 16, 
            color: (isLoading || isDisabled || valueText == null) 
              ? Colors.grey[600] 
              : Theme.of(context).colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  void _openSingleSelectSearchModal({
    required String title,
    required List<dynamic> items,
    required dynamic currentValue,
    required String Function(dynamic) getTitle,
    String? Function(dynamic)? getSubtitle,
    String? Function(dynamic)? getGroupTab,
    required void Function(dynamic) onSelected,
  }) {
    showDialog<dynamic>(
      context: context,
      builder: (ctx) => _SingleSelectSearchDialog(
        title: title,
        items: items,
        initialSelectedItem: currentValue,
        getTitle: getTitle,
        getSubtitle: getSubtitle,
        getGroupTab: getGroupTab,
      ),
    ).then((selected) {
      if (selected != null) {
        if (selected == 'CLEAR_SELECTION') {
          onSelected(null);
        } else {
          onSelected(selected);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showSummary) {
      return CustomModal(
        title: 'Resumen de Edición Masiva',
        width: 600,
        content: BulkSummaryView(
          results: _results,
        ),
        actions: [
          CustomButton(
            text: 'Cerrar',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
    }

    if (_isLoading) {
      return const CustomModal(
        title: 'Edición Masiva',
        content: SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_isSaving) {
      final request = _processingId != null 
          ? GlobalCache.requests.firstWhere((r) => r['id'] == _processingId, orElse: () => <String, dynamic>{}) 
          : <String, dynamic>{};
      final documentNo = request['DocumentNo']?.toString() ?? 'Cargando...';
      final summary = request['Summary']?.toString() ?? '';

      return CustomModal(
        title: 'Aplicando Cambios...',
        width: 500,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Procesando solicitud $_currentIndex de ${widget.selectedIds.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: widget.selectedIds.isEmpty ? 0 : _currentIndex / widget.selectedIds.length),
            const SizedBox(height: 24),
            if (_processingId != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sync, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ticket #$documentNo', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Aplicando los siguientes cambios:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _currentChangesMap.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                        children: [
                          TextSpan(text: '${e.key}: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                          TextSpan(text: e.value),
                        ],
                      ),
                    ),
                  )).toList(),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(height: 4),
                    Text('$_successCount Exitosos'),
                  ],
                ),
                Column(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(height: 4),
                    Text('$_errorCount Errores'),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: const [], // Sin botones mientras se guarda
      );
    }

    return CustomModal(
      titleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Edición Masiva (${widget.selectedIds.length} Solicitudes)', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.blue, size: 22),
            tooltip: '¿Cómo funciona la edición masiva?',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => CustomModal(
                  title: 'Interacción y Reglas',
                  width: 450,
                  content: const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• Los campos en "-- No modificar --" mantendrán su valor original en todas las solicitudes.'),
                      SizedBox(height: 12),
                      Text('• Solo los campos a los que les asignes un valor serán actualizados. Si seleccionas más de uno, todos los cambios se aplicarán a cada una de las solicitudes seleccionadas.'),
                      SizedBox(height: 12),
                      Text('Dependencias de campos:', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('• Tercero → Fichas de Producto:\n  Al seleccionar un Tercero, las fichas se filtran automáticamente. Si las solicitudes seleccionadas pertenecen a varios terceros distintos, la edición de la ficha se bloquea.'),
                      SizedBox(height: 8),
                      Text('• Tipo de Solicitud → Estado:\n  Al seleccionar un Tipo de Solicitud, la lista de Estados se filtra para mostrar solo los correspondientes a esa categoría.'),
                    ],
                  ),
                  actions: [
                    CustomButton(text: AppLocale.gotIt.getString(context), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      width: 600,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seleccione los campos que desea actualizar. Los campos en "-- No modificar --" mantendrán su valor original.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: CustomDropdown<String?>(
                    label: 'Tipo de Solicitud',
                    value: _selectedType,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('-- No modificar --'),
                      ),
                      ..._requestTypeMap.keys.map(
                        (k) => DropdownMenuItem(value: k, child: Text(k)),
                      ),
                    ],
                    onChanged: AccessControl.isRealSupport
                        ? null
                        : (val) => setState(() => _selectedType = val),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomDropdown<String?>(
                    label: 'Categoría',
                    value: _selectedCategory,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('-- No modificar --'),
                      ),
                      ..._categoryMap.keys.map(
                        (k) => DropdownMenuItem(value: k, child: Text(k)),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedCategory = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: CustomDropdown<String?>(
                    label: 'Grupo',
                    value: _selectedGroup,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('-- No modificar --'),
                      ),
                      ..._groupMap.keys.map(
                        (k) => DropdownMenuItem(value: k, child: Text(k)),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedGroup = val),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: CustomDropdown<int?>(
                          label: 'Ficha de Producto',
                          value: _selectedProductChipId,
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('-- No modificar --'),
                            ),
                            if (!_isProductChipBlocked)
                              ..._productChips.map(
                                (c) {
                                  final name = c['identifier'] ?? c['Name'] ?? 'Ficha ${c['id']}';
                                  final desc = c['Description'] ?? '';
                                  final displayText = desc.isNotEmpty ? '$name - $desc' : name;
                                  return DropdownMenuItem<int?>(
                                    value: c['id'],
                                    child: Text(
                                      displayText,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                },
                              ),
                          ],
                          onChanged: _isProductChipBlocked
                              ? null
                              : (val) => setState(() => _selectedProductChipId = val),
                        ),
                      ),
                      if (_isProductChipBlocked) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Todas las solicitudes deben pertenecer al mismo tercero para editar masivamente una ficha de producto.',
                          child: const Icon(Icons.info_outline, color: Colors.orange),
                        ),
                      ] else if (_isLoadingChips) ...[
                        const SizedBox(width: 8),
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      ]
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSingleSearchableField(
              label: 'Estado',
              hintText: '-- No modificar --',
              valueText: _selectedStatus != null ? cleanStatusName(_selectedStatus!) : null,
              isLoading: _isLoading,
              isDisabled: false,
              onTap: () {
                var entries = _statusIdMap.entries.toList();
                if (_selectedType != null) {
                  final int? reqTypeId = _requestTypeMap[_selectedType];
                  if (reqTypeId != null) {
                    int? catId = GlobalCache.requestTypeCategoryMap[reqTypeId];
                    if (catId != null) {
                      entries = entries.where((e) {
                        int? statusCat = GlobalCache.statusCategoryMap[e.value];
                        return statusCat == null || statusCat == catId;
                      }).toList();
                    }
                  }
                }
                
                MapEntry<String, int>? selectedItem;
                if (_selectedStatus != null) {
                  try {
                    selectedItem = entries.firstWhere((e) => e.key == _selectedStatus);
                  } catch (_) {
                    selectedItem = MapEntry(_selectedStatus!, _statusIdMap[_selectedStatus!] ?? 0);
                    entries.add(selectedItem);
                  }
                }

                _openSingleSelectSearchModal(
                  title: 'Estado',
                  items: entries,
                  currentValue: selectedItem,
                  getTitle: (item) => cleanStatusName((item as MapEntry<String, int>).key),
                  getGroupTab: (item) {
                    int statusId = (item as MapEntry<String, int>).value;
                    int? statusCat = GlobalCache.statusCategoryMap[statusId];
                    if (statusCat == null) return 'Otros';
                    return GlobalCache.statusCategoryNameMap[statusCat] ?? 'Otros';
                  },
                  onSelected: (val) {
                    setState(() {
                      if (val != null) {
                        _selectedStatus = (val as MapEntry<String, int>).key;
                      } else {
                        _selectedStatus = null;
                      }
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: CustomDropdown<int?>(
                    label: 'Tercero',
                    value: _selectedBpId,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('-- No modificar --'),
                      ),
                      ..._bPartnersList.map(
                        (bp) => DropdownMenuItem<int?>(
                          value: bp['id'],
                          child: Text(
                            bp['Name'] ?? 'Tercero ${bp['id']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedBpId = val);
                      if (val != null) {
                        if (!_isProductChipBlocked) _fetchProductChips(val);
                      } else {
                        if (!_isProductChipBlocked && _originalBpIds.length == 1) {
                           _fetchProductChips(_originalBpIds.first);
                        } else {
                          setState(() {
                            _productChips = [];
                            _selectedProductChipId = null;
                          });
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomDropdown<int?>(
                    label: 'Usuario Asignado',
                    value: _selectedUserId,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('-- No modificar --'),
                      ),
                      ..._users.map(
                        (u) => DropdownMenuItem<int?>(
                          value: u['AD_User_ID'] ?? u['id'],
                          child: Text(
                            u['Name'] ?? 'Sin Nombre',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedUserId = val),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        CustomButton(
          text: 'Aplicar a ${widget.selectedIds.length} solicitudes',
          onPressed: _handleSave,
          isLoading: _isSaving,
        ),
      ],
    );
  }
}

class _SingleSelectSearchDialog extends StatefulWidget {
  final String title;
  final List<dynamic> items;
  final dynamic initialSelectedItem;
  final String Function(dynamic) getTitle;
  final String? Function(dynamic)? getSubtitle;
  final String? Function(dynamic)? getGroupTab;

  const _SingleSelectSearchDialog({
    required this.title, 
    required this.items, 
    this.initialSelectedItem, 
    required this.getTitle, 
    this.getSubtitle, 
    this.getGroupTab,
  });

  @override
  State<_SingleSelectSearchDialog> createState() => _SingleSelectSearchDialogState();
}

class _SingleSelectSearchDialogState extends State<_SingleSelectSearchDialog> {
  dynamic _tempSelectedItem;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tempSelectedItem = widget.initialSelectedItem;
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

    Widget buildList(List<dynamic> itemsToDisplay, {bool isFirstTab = false}) {
      return ListView.separated(
        itemCount: itemsToDisplay.length + (isFirstTab ? 1 : 0),
        separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.grey, thickness: 0.3),
        itemBuilder: (context, index) {
          if (isFirstTab && index == 0) {
            return RadioListTile<dynamic>(
              contentPadding: EdgeInsets.zero,
              title: const Text('-- No modificar --', style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
              value: 'CLEAR_SELECTION',
              groupValue: _tempSelectedItem ?? 'CLEAR_SELECTION',
              onChanged: (val) {
                setState(() => _tempSelectedItem = null);
              },
            );
          }
          final actualIndex = isFirstTab ? index - 1 : index;
          final item = itemsToDisplay[actualIndex];

          return RadioListTile<dynamic>(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.getTitle(item), style: const TextStyle(fontSize: 14)),
            subtitle: widget.getSubtitle != null && widget.getSubtitle!(item) != null 
                ? Text(widget.getSubtitle!(item)!, style: const TextStyle(fontSize: 12, color: Colors.grey)) 
                : null,
            value: item,
            groupValue: _tempSelectedItem,
            onChanged: (val) {
              setState(() => _tempSelectedItem = val);
            },
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
                children: tabs.asMap().entries.map((e) => buildList(groupedItems![e.value]!, isFirstTab: e.key == 0)).toList(),
              ),
            ),
          ],
        ),
      );
    } else {
      listWidget = buildList(filteredItems, isFirstTab: true);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 500,
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
                TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancelar')),
                const SizedBox(width: 8),
                CustomButton(text: 'Aplicar', onPressed: () => Navigator.of(context).pop(_tempSelectedItem ?? 'CLEAR_SELECTION')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
