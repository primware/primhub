import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter_quill/flutter_quill.dart' hide Style;
import 'package:primhub/ui/pages/Support/Requests/html_editor_utils.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart'; // Para FilteringTextInputFormatter
import 'package:primhub/api/api_http.dart' as http;
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart';
import 'package:primhub/api/validation_manager.dart';
import 'package:primhub/api/contract_api.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/ui/widgets/duration_formatter.dart';
import 'package:flutter_localization/flutter_localization.dart';

class EditRequestDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final Map<String, int> statusIdMap;
  final Map<String, String> priorityMap;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  const EditRequestDialog({
    super.key,
    required this.request,
    required this.statusIdMap,
    required this.priorityMap,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<EditRequestDialog> createState() => _EditRequestDialogState();
}

class _EditRequestDialogState extends State<EditRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _currentPriority;
  late String _currentStatus;
  late int? _statusId;
  late bool _isReadOnly;

  Map<String, int> _statusIdMap = {};
  String? _selectedType;
  String? _selectedCategory;
  String? _selectedGroup;
  int? _selectedSalesRepId;
  int? _selectedBpId;
  int? _selectedUserId;
  int? _selectedProductChipId;

  Map<String, int> _requestTypeMap = {};
  Map<String, int> _categoryMap = {};
  Map<String, String> _categoryPriorityMap = {};
  List<Map<String, dynamic>> _categoryRecords = [];
  Map<String, int> _groupMap = {};
  List<dynamic> _users = [];
  List<Map<String, dynamic>> _salesReps = [];
  List<dynamic> _bPartnersList = [];
  List<Map<String, dynamic>> _productChips = [];

  bool _isLoadingTypes = true;
  bool _isLoadingCategories = true;
  bool _isLoadingGroups = true;
  bool _isLoadingUsers = true;
  bool _isLoadingSalesReps = true;
  bool _isLoadingBPartners = true;
  bool _isLoadingProducts = true;

  bool _isSaving = false;

  final _modalScrollController = ScrollController();
  final _descriptionScrollController = ScrollController();

  late TextEditingController _resultController;
  late TextEditingController _newUpdateController;
  late TextEditingController _dateStartController;
  late TextEditingController _dateCompleteController;
  late TextEditingController _qtyUsedController;
  late TextEditingController _estimatedDevHoursController;
  late TextEditingController _subjectController;

  final QuillController _summaryQuillController = QuillController.basic();

  @override
  void initState() {
    super.initState();
    _statusIdMap = widget.statusIdMap;
    _currentPriority = widget.request['level'] ?? 'Media';
    _currentStatus = widget.request['status'] ?? '';
    _statusId = widget.request['statusId'];

    if (_statusId != null && _statusIdMap.isNotEmpty) {
      for (var entry in _statusIdMap.entries) {
        if (entry.value == _statusId) {
          _currentStatus = entry.key;
          break;
        }
      }
    }

    final String statusNameLower = _currentStatus.toLowerCase();
    _isReadOnly =
        statusNameLower.contains('archivada') ||
        statusNameLower.contains('anulada') ||
        _statusId == 1000019 ||
        _statusId == 1000018 ||
        _statusId == 1000015;

    _resultController = TextEditingController(text: widget.request['result']);
    _newUpdateController = TextEditingController();
    _dateStartController = TextEditingController(
      text: widget.request['dateStartPlan'],
    );
    _dateCompleteController = TextEditingController(
      text: widget.request['dateCompletePlan'],
    );

    final String initialSubject = stripHtmlTags(
      (widget.request['emailSubject'] ?? widget.request['summary'] ?? '')
          .toString(),
    );
    _subjectController = TextEditingController(text: initialSubject);
    final String initialSummary = (widget.request['description'] ?? '')
        .toString();
    _summaryQuillController.document = HtmlEditorUtils.htmlToDelta(
      initialSummary,
    );
    _qtyUsedController = TextEditingController(
      text: ((widget.request['qtySpent'] as num?)?.toDouble() ?? 0.0)
          .toString(),
    );
    _estimatedDevHoursController = TextEditingController(
      text: ((widget.request['PrimHub_Estimated_development_hours'] as num?)?.toDouble() ?? 0.0)
          .toString(),
    );

    _selectedType = widget.request['type'];
    _selectedCategory = widget.request['category'];
    _selectedGroup = widget.request['group'];
    _selectedSalesRepId = widget.request['salesRepId'];
    _selectedBpId = widget.request['bpId'];
    _selectedUserId = widget.request['userId'];
    _selectedProductChipId = widget.request['productChipId'];

    _salesReps = GlobalCache.salesReps;
    _isLoadingSalesReps = false;
    _fetchBPartners();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    await Future.wait([
      _fetchStatuses(),
      _fetchRequestTypes(),
      _fetchCategories(),
      _fetchGroups(),
      _fetchUsers(),
    ]);
    _fetchProductChips();
  }

  Future<void> _fetchBPartners() async {
    try {
      List<dynamic> bps = [];
      if (GlobalCache.bPartners.isNotEmpty) {
        bps = GlobalCache.bPartners;
      } else {
        final logic = ProjectsLogic();
        bps = await logic.fetchBPartners();
      }

      if (mounted) {
        setState(() {
          _bPartnersList = bps.where((bp) {
            final name = bp['Name']?.toString() ?? '';
            final rawVendor = bp['IsVendor'] ?? bp['isVendor'];
            final isVendorStr = rawVendor?.toString().trim().toLowerCase();
            bool isVendor = isVendorStr == 'true' || isVendorStr == 'y';

            final rawCustomer = bp['IsCustomer'] ?? bp['isCustomer'];
            final isCustomerStr = rawCustomer?.toString().trim().toLowerCase();
            bool isCustomer = isCustomerStr == 'true' || isCustomerStr == 'y';
            if (rawCustomer == null) isCustomer = true;

            final isSpecificAdmin =
                name.trim().toUpperCase().contains('LA CASA DEL SOFTWARE') ||
                bp['C_BPartner_UU'] == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95' ||
                bp['Record_UU'] == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95' ||
                bp['UUID'] == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95' ||
                bp['uuid'] == 'e4e48cad-f8f8-4f61-954c-60f431bd5d95';

            return !name.startsWith('~') &&
                ((isCustomer && !isVendor) || isSpecificAdmin);
          }).toList();

          if (_selectedBpId != null &&
              !_bPartnersList.any((bp) => bp['id'] == _selectedBpId)) {
            _bPartnersList.add({
              'id': _selectedBpId,
              'Name': widget.request['bpName'] ?? 'Tercero $_selectedBpId',
            });
          }
          _isLoadingBPartners = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingBPartners = false);
    }
  }

  Future<void> _fetchProductChips() async {
    if (_selectedBpId == null) {
      if (mounted) setState(() => _isLoadingProducts = false);
      return;
    }
    if (mounted) setState(() => _isLoadingProducts = true);
    try {
      final fetchedChips = await ContractApi.getSupportProductChips(
        bPartnerId: _selectedBpId,
      );
      if (mounted) {
        setState(() {
          _productChips = fetchedChips.where((c) {
            final active = c['IsActive'] == 'Y' || c['IsActive'] == true;
            final isCurrent = c['id'] == _selectedProductChipId;
            return active || isCurrent;
          }).toList();
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  @override
  void dispose() {
    _modalScrollController.dispose();
    _descriptionScrollController.dispose();
    _resultController.dispose();
    _newUpdateController.dispose();
    _dateStartController.dispose();
    _dateCompleteController.dispose();
    _qtyUsedController.dispose();
    _estimatedDevHoursController.dispose();
    _subjectController.dispose();
    _summaryQuillController.dispose();
    super.dispose();
  }

  Map<String, int> _getFilteredStatuses() {
    if (_requestTypeMap.isEmpty || _statusIdMap.isEmpty) return _statusIdMap;
    
    int? currentRequestTypeId = _selectedType != null ? _requestTypeMap[_selectedType] : null;
    if (currentRequestTypeId == null) return _statusIdMap;
    
    int? targetCategoryId = GlobalCache.requestTypeCategoryMap[currentRequestTypeId];
    
    if (targetCategoryId == null) return _statusIdMap;
    
    final filtered = <String, int>{};
    for (var entry in _statusIdMap.entries) {
      int statusId = entry.value;
      int? statusCategory = GlobalCache.statusCategoryMap[statusId];
      if (statusCategory == targetCategoryId) {
        filtered[entry.key] = statusId;
      }
    }
    
    if (_currentStatus.isNotEmpty && _statusIdMap.containsKey(_currentStatus)) {
      filtered[_currentStatus] = _statusIdMap[_currentStatus]!;
    }
    
    return filtered.isNotEmpty ? filtered : _statusIdMap;
  }

  void _validateSelectedStatus() {
    final filtered = _getFilteredStatuses();
    if (filtered.isEmpty) return;
    
    if (!filtered.containsKey(_currentStatus)) {
      if (AccessControl.isRealSupport) {
        _currentStatus = filtered.keys.firstWhere(
          (k) => k.toLowerCase().contains('recibida'),
          orElse: () => filtered.keys.firstWhere(
            (k) => k.toLowerCase().contains('open'),
            orElse: () => filtered.keys.first,
          ),
        );
      } else {
        _currentStatus = filtered.keys.firstWhere(
          (k) => k.toLowerCase().contains('open'),
          orElse: () => filtered.keys.first,
        );
      }
    }
  }

  Future<void> _fetchStatuses() async {
    try {
      final mapData = await fetchStatuses();
      if (mounted) {
        setState(() {
          if (mapData.isNotEmpty) {
            _statusIdMap = mapData;
            
            // Si el statusId no es nulo, actualizamos _currentStatus con la llave formateada
            if (_statusId != null) {
              for (var entry in _statusIdMap.entries) {
                if (entry.value == _statusId) {
                  _currentStatus = entry.key;
                  break;
                }
              }
            }
            _validateSelectedStatus();
          }
        });
      }
    } catch (e) {
      // Ignore error
    }
  }

  Future<void> _fetchRequestTypes() async {
    try {
      final response = await http.get(
        Uri.parse('${Endpoint.baseUrl}/api/v1/models/R_RequestType'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': Token.token,
        },
      );
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        final records = jsonResponse['records'] as List;
        final bool isProject =
            (widget.request['recordUU'] != null &&
                widget.request['recordUU'].toString().trim().isNotEmpty) ||
            (widget.request['Record_UU'] != null &&
                widget.request['Record_UU'].toString().trim().isNotEmpty);

        if (mounted) {
          setState(() {
            _requestTypeMap = {for (var r in records) r['Name']: r['id']};

            if ((_selectedType == null ||
                    _selectedType == 'Solicitud' ||
                    _selectedType!.isEmpty) &&
                _requestTypeMap.isNotEmpty) {
              if (isProject) {
                _selectedType = _requestTypeMap.keys.firstWhere(
                  (k) => k.toLowerCase().contains('implantacion lirion'),
                  orElse: () => _requestTypeMap.keys.first,
                );
              } else {
                _selectedType = _requestTypeMap.keys.firstWhere(
                  (k) => k.toLowerCase().contains('soporte lirion'),
                  orElse: () => _requestTypeMap.keys.first,
                );
              }
            }
            _validateSelectedStatus();
          });
        }
      }
    } catch (e) {
      // Ignorar
    } finally {
      if (mounted) setState(() => _isLoadingTypes = false);
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final bool isProject =
          (widget.request['recordUU'] != null &&
              widget.request['recordUU'].toString().trim().isNotEmpty) ||
          (widget.request['Record_UU'] != null &&
              widget.request['Record_UU'].toString().trim().isNotEmpty);

      final allRecords = await fetchCategories();

      final records = allRecords.where((c) {
        final bool isPrimhub = c['showinprimhub'] == true;
        return isProject ? !isPrimhub : isPrimhub;
      }).toList();

      if (mounted) {
        setState(() {
          _categoryRecords = records;
          _categoryMap = {for (var r in records) r['Name']: r['id']};
          _categoryPriorityMap = {
            for (var r in records) r['Name']: r['Priority']?.toString() ?? '5',
          };
        });
      }
    } catch (e) {
      // Ignorar
    } finally {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  void _showCategoryHelpModal() {
    showDialog(
      context: context,
      builder: (context) => CustomModal(
        title: AppLocale.categoryGuide.getString(context),
        width: 800,
        content: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: SingleChildScrollView(
            child: Table(
              border: TableBorder.all(color: Colors.grey.withOpacity(0.3)),
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(2),
              },
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: Colors.deepPurple),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'Categoría / Síntoma',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'Justificación Técnica',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                ..._categoryRecords.map(
                  (cat) => TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          cat['Name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          cat['Description'] ??
                              'Sin descripción técnica disponible.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          CustomButton(text: 'Cerrar', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }

  Future<void> _fetchGroups() async {
    try {
      final response = await http.get(
        Uri.parse('${Endpoint.baseUrl}/api/v1/models/R_Group'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': Token.token,
        },
      );
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        final records = jsonResponse['records'] as List;
        if (mounted) {
          setState(() {
            _groupMap = {for (var r in records) r['Name']: r['id']};
          });
        }
      }
    } catch (e) {
      // Ignorar
    } finally {
      if (mounted) setState(() => _isLoadingGroups = false);
    }
  }

  Future<void> _fetchUsers() async {
    try {
      final logic = ProjectsLogic();
      final users = await logic.fetchUsers(bPartnerId: _selectedBpId);
      if (mounted) {
        final previouslySelectedUserId = _selectedUserId;
        bool userWasCleared = false;

        if (previouslySelectedUserId != null &&
            !users.any(
              (u) => (u['AD_User_ID'] ?? u['id']) == previouslySelectedUserId,
            )) {
          _selectedUserId = null;
          userWasCleared = true;
        }

        setState(() {
          _users = users;
          if (previouslySelectedUserId != null &&
              !userWasCleared &&
              !_users.any(
                (u) => (u['AD_User_ID'] ?? u['id']) == previouslySelectedUserId,
              )) {
            _users.add({
              'id': _selectedUserId,
              'AD_User_ID': _selectedUserId,
              'Name': widget.request['userName'] ?? 'Usuario $_selectedUserId',
            });
          }
        });
        if (userWasCleared && AccessControl.isAdmin) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => ToastMessage.show(
              context: context,
              message:
                  AppLocale.userFilterUpdated.getString(context),
              type: ToastType.help,
            ),
          );
        }
      }
    } catch (e) {
      // Ignorar
    } finally {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _selectDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        controller.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _openSearchModal<T>({
    required String title,
    required List<dynamic> items,
    required T? currentValue,
    required String Function(dynamic) getTitle,
    String Function(dynamic)? getSubtitle,
    required T? Function(dynamic) getValue,
    required void Function(T?) onSelected,
  }) async {
    final double dialogHeight = MediaQuery.of(context).size.height * 0.6;
    final dynamic result = await showDialog(
      context: context,
      builder: (context) {
        String searchQuery = '';
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          insetAnimationDuration: Duration.zero,
          child: Container(
            width: 400,
            height: dialogHeight,
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                final filteredItems = items.where((item) {
                  return getTitle(
                    item,
                  ).toLowerCase().contains(searchQuery.toLowerCase());
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seleccionar $title',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.filter_list, color: Colors.grey),
                        hintText: 'Filtrar...',
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                      onChanged: (val) =>
                          setStateDialog(() => searchQuery = val),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filteredItems.length,
                        separatorBuilder: (context, index) => const Divider(
                          height: 1,
                          color: Colors.grey,
                          thickness: 0.3,
                        ),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          final itemValue = getValue(item);
                          final isSelected = itemValue == currentValue;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            tileColor: isSelected
                                ? Colors.grey.withOpacity(0.1)
                                : null,
                            title: Text(
                              getTitle(item),
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: getSubtitle != null && itemValue != null
                                ? Text(
                                    getSubtitle(item),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  )
                                : null,
                            onTap: () => Navigator.of(
                              context,
                            ).pop({'selected': true, 'value': itemValue}),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (result != null && result is Map && result['selected'] == true) {
      onSelected(result['value'] as T?);
    }
  }

  Widget _buildSearchableField<T>({
    required String label,
    required String? hintText,
    required T? value,
    required bool isLoading,
    required bool isDisabled,
    required String displayText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: (isLoading || isDisabled) ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          suffixIcon: isLoading
              ? Transform.scale(
                  scale: 0.5,
                  child: const CircularProgressIndicator(strokeWidth: 3),
                )
              : const Icon(Icons.search),
        ),
        isEmpty: value == null && displayText.isEmpty,
        child: Text(
          (value == null || displayText.isEmpty)
              ? (hintText ?? '')
              : displayText,
          style: TextStyle(
            fontSize: 16,
            color:
                (isLoading ||
                    isDisabled ||
                    (value == null && displayText.isEmpty))
                ? Colors.grey[600]
                : Theme.of(context).colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<void> _handleSave({bool navigateToReply = false}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      int? statusIdToSend;
      String? statusIdentifierToSend;

      int? targetStatusId = _statusIdMap[_currentStatus];

      if (targetStatusId != null && widget.request['statusId'] != null) {
        if (targetStatusId != widget.request['statusId']) {
          statusIdToSend = targetStatusId;
        }
      } else if (_currentStatus != widget.request['status']) {
        if (targetStatusId != null) {
          statusIdToSend = targetStatusId;
        } else {
          statusIdentifierToSend = _currentStatus;
        }
      }

      String? dateStartPlanToSend =
          _dateStartController.text != widget.request['dateStartPlan']
          ? _dateStartController.text
          : null;
      String? dateCompletePlanToSend =
          _dateCompleteController.text != widget.request['dateCompletePlan']
          ? _dateCompleteController.text
          : null;

      double currentQty =
          (widget.request['qtySpent'] as num?)?.toDouble() ?? 0.0;
      double inputQty = double.tryParse(_qtyUsedController.text) ?? 0.0;

      if (inputQty > 0) {
        setState(() => _isSaving = true);
        final freshData = await fetchRequest(
          filter: "R_Request_ID eq ${widget.request['realId']}",
        );
        if (freshData.isNotEmpty) {
          final req = freshData.first;
          final bpId = req['C_BPartner_ID']?['id'];
          final recordUU = req['Record_UU'];

          if (bpId != null &&
              !ValidationManager.isExempt(bpId) &&
              (recordUU == null || recordUU.toString().isEmpty)) {
            try {
              if (_selectedProductChipId != null) {
                final selectedChip = _productChips.firstWhere(
                  (c) => c['id'] == _selectedProductChipId,
                  orElse: () => {},
                );
                if (selectedChip.isNotEmpty) {
                  final double chipTotalQty =
                      (selectedChip['Qty'] as num?)?.toDouble() ?? 0.0;

                  final chipRequests = await fetchRequest(
                    filter:
                        "C_BPartner_Product_Chip_ID eq $_selectedProductChipId",
                  );
                  double totalEstimatedAndConsumedForChip = 0.0;

                  for (var r in chipRequests) {
                    if (r['Record_UU'] != null &&
                        r['Record_UU'].toString().isNotEmpty) {
                      continue;
                    }
                    if (r['id'] == widget.request['realId']) continue;

                    totalEstimatedAndConsumedForChip +=
                        (r['QtySpent'] as num?)?.toDouble() ??
                        (r['QtyPlan'] as num?)?.toDouble() ??
                        0.0;
                  }

                  if (totalEstimatedAndConsumedForChip + inputQty >
                      chipTotalQty) {
                    if (mounted) {
                      ToastMessage.show(
                        context: context,
                        message: 'La solicitud consumirá más horas de las que tiene disponible dicha ficha de producto. Disponibles: ${DurationFormatter.format(chipTotalQty - totalEstimatedAndConsumedForChip)} h, Intentando registrar: ${DurationFormatter.format(inputQty)} h',
                        type: ToastType.failure,
                      );
                      setState(() => _isSaving = false);
                    }
                    return;
                  }
                }
              }
            } catch (e) {
              // Ignore exception
            }
          }
        }
      }

      double? qtySpentToSend;

      if ((inputQty - currentQty).abs() > 0.001) {
        qtySpentToSend = inputQty;
      }

      String? startDateToSend;
      String? closeDateToSend;

      final bool isClosing =
          _currentStatus == '9_Final Close' ||
          _currentStatus == 'Final Close' ||
          (statusIdToSend != null &&
              (statusIdToSend == 103 ||
                  statusIdToSend == 1000019 ||
                  statusIdToSend == 1000001)) ||
          _currentStatus.toLowerCase().contains('por entregar');

      if (isClosing) {
        if (_dateStartController.text.isNotEmpty) {
          startDateToSend = "${_dateStartController.text}T00:00:00Z";
        }
        if (_dateCompleteController.text.isNotEmpty) {
          closeDateToSend = "${_dateCompleteController.text}T00:00:00Z";
        }
        statusIdToSend ??=
            _statusIdMap['9_Final Close'] ??
            _statusIdMap.entries
                .firstWhere(
                  (e) => e.key.toLowerCase().contains('close'),
                  orElse: () => const MapEntry('', 103),
                )
                .value;
        statusIdentifierToSend = null;
      }

      if (_selectedBpId != widget.request['bpId']) {
        if (_selectedUserId == null) {
          if (mounted) {
            setState(() => _isSaving = false);
            ToastMessage.show(
              context: context,
              message: 'Debe seleccionar un usuario para el nuevo tercero antes de guardar.',
              type: ToastType.warning,
            );
          }
          return;
        }

        final Map<String, dynamic> phase1Data = {
          "C_BPartner_ID": {"id": _selectedBpId},
          "AD_User_ID": {"id": _selectedUserId},
        };
        if (_selectedProductChipId != null) {
          phase1Data["C_BPartner_Product_Chip_ID"] = {"id": _selectedProductChipId};
        }

        final url = Uri.parse(
          '${Endpoint.request}/${widget.request['realId']}',
        );
        http.Response? response;
        try {
          response = await http.put(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': Token.token,
            },
            body: jsonEncode(phase1Data),
          );

          if (response.statusCode == 401) {
            final refreshed = await handleTokenRefresh();
            if (refreshed) {
              response = await http.put(
                url,
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': Token.token,
                },
                body: jsonEncode(phase1Data),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isSaving = false);
            ToastMessage.show(context: context, message: 'Error de red al actualizar el tercero: $e', type: ToastType.failure);
          }
          return;
        }

        if (response.statusCode != 200 &&
            response.statusCode != 201 &&
            response.statusCode != 204) {
          if (mounted) {
            setState(() => _isSaving = false);
            ToastMessage.show(
              context: context,
              message: 'Error al actualizar el tercero: ${response.body}',
              type: ToastType.failure,
            );
          }
          return;
        }
        widget.request['bpId'] = _selectedBpId;
      }

      if (!_categoryMap.containsKey(_selectedCategory)) {
        if (mounted) {
          setState(() => _isSaving = false);
          ToastMessage.show(
            context: context,
            message: 'La categoría actual no es válida o no está disponible. Por favor, seleccione una nueva categoría antes de guardar.',
            type: ToastType.warning,
          );
        }
        return;
      }

      final summaryHtml = HtmlEditorUtils.deltaToHtml(
        _summaryQuillController.document,
      );
      final subjectText = _subjectController.text.trim();

      final String originalResult = widget.request['result']?.toString() ?? '';
      final String originalSummary = (widget.request['description'] ?? '')
          .toString();
      final String originalSubject = stripHtmlTags(
        (widget.request['emailSubject'] ?? widget.request['summary'] ?? '')
            .toString(),
      );

      double? originalEstimated = (widget.request['PrimHub_Estimated_development_hours'] as num?)?.toDouble() ?? 0.0;
      double? inputEstimated = double.tryParse(_estimatedDevHoursController.text);
      double? estimatedDevHoursToSend;
      if (inputEstimated != null && inputEstimated != originalEstimated) {
        estimatedDevHoursToSend = inputEstimated;
      }

      final result = await updateRemoteRequest(
        id: widget.request['realId'],
        priority: _currentPriority,
        statusId: statusIdToSend,
        statusIdentifier: statusIdentifierToSend,
        result: _resultController.text != originalResult
            ? _resultController.text
            : null,
        summary: summaryHtml != originalSummary ? summaryHtml : null,
        dateStartPlan: dateStartPlanToSend,
        dateCompletePlan: dateCompletePlanToSend,
        qtySpent: qtySpentToSend,
        estimatedDevHours: estimatedDevHoursToSend,
        startDate: startDateToSend,
        closeDate: closeDateToSend,
        emailSubject: subjectText != originalSubject ? subjectText : null,
        requestTypeId: _requestTypeMap[_selectedType],
        categoryId: _categoryMap[_selectedCategory],
        groupId: _groupMap[_selectedGroup],
        salesRepId: _selectedSalesRepId,
        bPartnerId: _selectedBpId,
        userId: _selectedUserId,
        productChipId: _selectedProductChipId,
      );

      final newUpdateText = _newUpdateController.text.trim();
      int? newUpdateId;
      if (newUpdateText.isNotEmpty) {
        final updateResult = await createRequestUpdate(
          requestId: widget.request['realId'],
          resultText: newUpdateText,
          confidentialType: 'I',
          evidences: [null, null, null, null],
        );
        if (updateResult['success'] == true) {
          newUpdateId = updateResult['id'];
        }
      }

      if (result['success'] == true) {
        await GlobalCache.syncSingleRequest(widget.request['realId']);

        // --- INICIO: Lógica de Correos Automáticos Lirion ---
        int adUserId = _selectedUserId ?? 
            (widget.request['AD_User_ID'] is Map ? widget.request['AD_User_ID']['id'] : widget.request['AD_User_ID']) ?? 
            (widget.request['userId']) ?? 0;
        
        int customerBpId = _selectedBpId ?? widget.request['bpId'] ?? 0;
        int currentStatusId = widget.request['R_Status_ID'] is Map ? widget.request['R_Status_ID']['id'] : (widget.request['R_Status_ID'] ?? 0);
        
        bool statusChanged = (statusIdToSend != null || statusIdentifierToSend != null);
        bool hasNewComment = newUpdateText.isNotEmpty;

        if ((adUserId > 0 || customerBpId > 0) && (statusChanged || hasNewComment)) {
          _sendEmailsInBackground(
            requestId: widget.request['realId'],
            adUserId: adUserId,
            salesRepId: _selectedSalesRepId,
            bPartnerId: customerBpId,
            currentStatusId: currentStatusId,
            statusChanged: statusChanged,
            resultHtml: newUpdateText,
            updateId: newUpdateId ?? 0,
            context: context,
          );
        }
        // --- FIN: Lógica de Correos Automáticos Lirion ---
      }

      if (mounted) {
        if (result['success'] == true) {
          final router = GoRouter.of(context);
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
          
          ToastMessage.show(
            context: context,
            message: 'Solicitud actualizada correctamente',
            type: ToastType.success,
          );
          widget.onSave();

          if (navigateToReply) {
            router.push(
              '/request-updates/${widget.request['realId']}',
              extra: {'docNo': widget.request['id']?.toString() ?? '...'},
            );
          }
        } else {
          ToastMessage.show(
            context: context,
            message: 'Error: ${result['error']}',
            type: ToastType.failure,
          );
        }
      }
    } catch (e, stackTrace) {
      CurrentLogMessage.add(
        'Error en _handleSave: $e\n$stackTrace',
        level: 'ERROR',
        tag: 'EditRequest',
      );
      if (mounted) {
        ToastMessage.show(context: context, message: 'Error inesperado al guardar: $e', type: ToastType.failure);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _sendEmailsInBackground({
    required int requestId,
    required int? adUserId,
    required int? salesRepId,
    required int? bPartnerId,
    required int? currentStatusId,
    required bool statusChanged,
    required String resultHtml,
    required int updateId,
    required BuildContext context,
  }) async {
    try {
      String oldStatusName = '';
      for (var entry in GlobalCache.statuses.entries) {
        if (entry.value == currentStatusId) {
          oldStatusName = entry.key;
          break;
        }
      }

      bool hasAdUser = adUserId != null && adUserId > 0;
      bool hasSalesRep = salesRepId != null && salesRepId > 0;
      bool success1 = true;
      bool success2 = true;
      bool emailsAttempted = false;

      bool isAdUserCurrentUser = adUserId != null && User.userID != null && adUserId == User.userID;
      bool isSalesRepCurrentUser = salesRepId != null && User.userID != null && salesRepId == User.userID;

      if (hasAdUser) {
        emailsAttempted = true;
        if (statusChanged) {
          if (!isAdUserCurrentUser) {
            success1 = await sendRequestStatusEmail(
              requestId: requestId,
              adUserId: adUserId,
              bPartnerId: bPartnerId ?? 0,
              templateType: MailTemplateType.statusUpdate,
              updateText: resultHtml,
              oldStatusName: oldStatusName,
              updateId: updateId,
            );
          }
        } else if (resultHtml.isNotEmpty) {
          // If status didn't change but there's a comment, send update template 1000017
          success1 = await sendRequestStatusEmail(
            requestId: requestId,
            adUserId: adUserId,
            bPartnerId: bPartnerId ?? 0,
            templateType: MailTemplateType.updateRequest,
            updateText: resultHtml,
            oldStatusName: oldStatusName,
            updateId: updateId,
          );
        }
      }

      if (hasSalesRep && salesRepId != adUserId) {
        emailsAttempted = true;
        
        if (statusChanged && !isSalesRepCurrentUser) {
          bool s2a = await sendRequestStatusEmail(
            requestId: requestId,
            adUserId: salesRepId,
            bPartnerId: bPartnerId ?? 0,
            templateType: MailTemplateType.statusUpdate,
            updateText: resultHtml,
            oldStatusName: oldStatusName,
            updateId: updateId,
          );
          success2 = success2 && s2a;
        }

        if (resultHtml.isNotEmpty) {
          bool s2b = await sendRequestStatusEmail(
            requestId: requestId,
            adUserId: salesRepId,
            bPartnerId: bPartnerId ?? 0,
            templateType: MailTemplateType.updateRequest,
            updateText: resultHtml,
            oldStatusName: oldStatusName,
            updateId: updateId,
          );
          success2 = success2 && s2b;
        }
      }

      if (!emailsAttempted) return;

      if (mounted) {
        if (success1 && success2) {
          bool isInternal = AccessControl.isAdmin;
          String msg = isInternal ? 'Correo enviado al cliente' : 'Correo enviado al equipo';
          ToastMessage.show(context: context, message: msg, type: ToastType.success);
        } else {
          ToastMessage.show(context: context, message: 'No se pudo enviar el correo de notificación', type: ToastType.failure);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final filteredStatuses = _getFilteredStatuses();
    final List<String> statusItems = filteredStatuses.isNotEmpty
        ? filteredStatuses.keys.toList()
        : ['1_Open', '2_Waiting on customer', '3_Closed', '9_Final Close'];
    if (_currentStatus.isNotEmpty && !statusItems.contains(_currentStatus)) {
      statusItems.add(_currentStatus);
    }
    final bool isFullAccess = AccessControl.isAdmin || AccessControl.isExtSupport;
    final bool isProject =
        (widget.request['recordUU'] != null &&
            widget.request['recordUU'].toString().trim().isNotEmpty) ||
        (widget.request['Record_UU'] != null &&
            widget.request['Record_UU'].toString().trim().isNotEmpty) ||
        (widget.request['C_Project_ID'] != null &&
            widget.request['C_Project_ID'].toString().isNotEmpty);

    return CustomModal(
      title: AppLocale.editRequest.getStringWithVariables(context, {'id': '${widget.request['id']}'}),
      width: 700,
      content: Scrollbar(
        controller: _modalScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _modalScrollController,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ticket N°: ${widget.request['id']}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copiar Ticket',
                        color: Theme.of(context).colorScheme.primary,
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(
                              text: widget.request['id'].toString(),
                            ),
                          );
                          ToastMessage.show(
                            context: context,
                            message: AppLocale.ticketCopied.getString(context),
                            type: ToastType.help,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (isFullAccess) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildSearchableField<int>(
                          label: AppLocale.businessPartner.getString(context),
                          hintText: 'Seleccione Tercero',
                          value: _selectedBpId,
                          isLoading: _isLoadingBPartners,
                          isDisabled: _isReadOnly || !AccessControl.isAdmin,
                          displayText:
                              _selectedBpId != null &&
                                  _bPartnersList.any(
                                    (bp) => bp['id'] == _selectedBpId,
                                  )
                              ? _bPartnersList.firstWhere(
                                      (bp) => bp['id'] == _selectedBpId,
                                    )['Name'] ??
                                    ''
                              : '',
                          onTap: () => _openSearchModal<int>(
                            title: 'Tercero',
                            items: _bPartnersList
                                .where((bp) => bp['id'] != null)
                                .toList(),
                            currentValue: _selectedBpId,
                            getTitle: (item) => item['Name'] ?? 'Sin Nombre',

                            getValue: (item) {
                              var id = item['id'];
                              return id is int
                                  ? id
                                  : int.tryParse(id.toString());
                            },
                            onSelected: (val) {
                              setState(() {
                                _selectedBpId = val;
                                _selectedUserId = null;
                                _selectedProductChipId = null;
                                _users = [];
                                _isLoadingUsers = true;
                              });
                              _fetchUsers();
                              _fetchProductChips();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSearchableField<int>(
                          label: AppLocale.user.getString(context),
                          hintText: _selectedBpId == null
                              ? 'Seleccione un tercero'
                              : AppLocale.selectUser.getString(context),
                          value: _selectedUserId,
                          isLoading: _isLoadingUsers,
                          isDisabled:
                              _isReadOnly ||
                              _isLoadingUsers ||
                              _selectedBpId == null,
                          displayText:
                              _selectedUserId != null &&
                                  _users.any(
                                    (u) =>
                                        (u['AD_User_ID'] ?? u['id']) ==
                                        _selectedUserId,
                                  )
                              ? _users.firstWhere(
                                      (u) =>
                                          (u['AD_User_ID'] ?? u['id']) ==
                                          _selectedUserId,
                                    )['Name'] ??
                                    ''
                              : '',
                          onTap: () => _openSearchModal<int>(
                            title: 'Usuario',
                            items: _users
                                .where(
                                  (u) => (u['AD_User_ID'] ?? u['id']) != null,
                                )
                                .toList(),
                            currentValue: _selectedUserId,
                            getTitle: (item) => item['Name'] ?? 'Sin Nombre',

                            getValue: (item) {
                              var id = item['AD_User_ID'] ?? item['id'];
                              return id is int
                                  ? id
                                  : int.tryParse(id.toString());
                            },
                            onSelected: (val) =>
                                setState(() => _selectedUserId = val),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (!isProject && (AccessControl.isAdmin || AccessControl.isExtSupport)) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildSearchableField<int>(
                          label: AppLocale.productSheet.getString(context),
                          hintText: _selectedBpId == null
                              ? 'Seleccione un tercero'
                              : 'Seleccione Ficha',
                          value: _selectedProductChipId,
                          isLoading: _isLoadingProducts,
                          isDisabled:
                              _isLoadingProducts || _selectedBpId == null,
                          displayText:
                              _selectedProductChipId != null &&
                                  _productChips.any(
                                    (c) => c['id'] == _selectedProductChipId,
                                  )
                              ? _productChips.firstWhere(
                                      (c) =>
                                          c['id'] == _selectedProductChipId,
                                    )['Description'] ??
                                    'Ficha $_selectedProductChipId'
                              : '',
                          onTap: () => _openSearchModal<int>(
                            title: 'Ficha de Producto',
                            items: _productChips,
                            currentValue: _selectedProductChipId,
                            getTitle: (item) =>
                                item['Description'] ?? 'Sin Descripción',

                            getValue: (item) => item['id'] as int,
                            onSelected: (val) =>
                                setState(() => _selectedProductChipId = val),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildSearchableField<String>(
                        label: AppLocale.requestType.getString(context),
                        hintText: 'Seleccione Tipo',
                        value: _selectedType,
                        isLoading: _isLoadingTypes,
                        isDisabled:
                            _isReadOnly ||
                            _isLoadingTypes ||
                            AccessControl.isRealSupport,
                        displayText: _selectedType ?? '',
                        onTap: () => _openSearchModal<String>(
                          title: 'Tipo de Solicitud',
                          items: _requestTypeMap.keys.toList(),
                          currentValue: _selectedType,
                          getTitle: (item) => item.toString(),
                          getValue: (item) => item.toString(),
                          onSelected: (val) {
                            setState(() {
                              _selectedType = val;
                              _validateSelectedStatus();
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _subjectController,
                  label: AppLocale.subject.getString(context),
                  readOnly: _isReadOnly,
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 10,
                      child: _buildSearchableField<String>(
                        label: AppLocale.category.getString(context),
                        hintText: AppLocale.selectCategory.getString(context),
                        value: _selectedCategory,
                        isLoading: _isLoadingCategories,
                        isDisabled: _isReadOnly || _isLoadingCategories,
                        displayText: _selectedCategory ?? '',
                        onTap: () => _openSearchModal<String>(
                          title: AppLocale.category.getString(context),
                          items: _categoryMap.keys.toList(),
                          currentValue: _selectedCategory,
                          getTitle: (item) => item.toString(),
                          getValue: (item) => item.toString(),
                          onSelected: (val) {
                            setState(() {
                              _selectedCategory = val;
                              final bool isProject =
                                  (widget.request['recordUU'] != null &&
                                      widget.request['recordUU']
                                          .toString()
                                          .trim()
                                          .isNotEmpty) ||
                                  (widget.request['Record_UU'] != null &&
                                      widget.request['Record_UU']
                                          .toString()
                                          .trim()
                                          .isNotEmpty);

                              if (!isProject &&
                                  val != null &&
                                  _categoryPriorityMap.containsKey(val)) {
                                final pValue = _categoryPriorityMap[val]!;
                                final label = widget.priorityMap.entries
                                    .firstWhere(
                                      (e) => e.value == pValue,
                                      orElse: () => widget.priorityMap.entries
                                          .firstWhere((e) => e.key == 'Media'),
                                    )
                                    .key;
                                _currentPriority = label;
                              }
                            });
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: IconButton(
                        icon: const Icon(
                          Icons.info_outline,
                          color: Colors.blue,
                        ),
                        tooltip: AppLocale.viewCategoryGuide.getString(context),
                        onPressed: _showCategoryHelpModal,
                      ),
                    ),
                    Expanded(
                      flex: 10,
                      child: _buildSearchableField<String>(
                        label: AppLocale.priority.getString(context),
                        hintText: 'Seleccione Prioridad',
                        value: _currentPriority,
                        isLoading: false,
                        isDisabled:
                            !((widget.request['recordUU'] != null &&
                                    widget.request['recordUU']
                                        .toString()
                                        .trim()
                                        .isNotEmpty) ||
                                (widget.request['Record_UU'] != null &&
                                    widget.request['Record_UU']
                                        .toString()
                                        .trim()
                                        .isNotEmpty)),
                        displayText: _currentPriority,
                        onTap: () => _openSearchModal<String>(
                          title: 'Prioridad',
                          items: widget.priorityMap.keys.toList(),
                          currentValue: _currentPriority,
                          getTitle: (item) => item.toString(),
                          getValue: (item) => item.toString(),
                          onSelected: (val) => setState(
                            () => _currentPriority = val ?? _currentPriority,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (isFullAccess) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildSearchableField<String>(
                          label: AppLocale.group.getString(context),
                          hintText: AppLocale.selectGroup.getString(context),
                          value: _selectedGroup,
                          isLoading: _isLoadingGroups,
                          isDisabled: _isReadOnly || _isLoadingGroups,
                          displayText: _selectedGroup ?? '',
                          onTap: () => _openSearchModal<String>(
                            title: 'Grupo',
                            items: _groupMap.keys.toList(),
                            currentValue: _selectedGroup,
                            getTitle: (item) => item.toString(),
                            getValue: (item) => item.toString(),
                            onSelected: (val) =>
                                setState(() => _selectedGroup = val),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSearchableField<int>(
                          label: AppLocale.salesRepresentative.getString(context),
                          hintText: AppLocale.selectRepresentative.getString(context),
                          value: _selectedSalesRepId,
                          isLoading: _isLoadingSalesReps,
                          isDisabled: _isReadOnly || _isLoadingSalesReps || !AccessControl.isAdmin,
                          displayText:
                              _selectedSalesRepId != null &&
                                  _salesReps.any(
                                    (u) =>
                                        (u['AD_User_ID'] ?? u['id']) ==
                                        _selectedSalesRepId,
                                  )
                              ? _salesReps.firstWhere(
                                      (u) =>
                                          (u['AD_User_ID'] ?? u['id']) ==
                                          _selectedSalesRepId,
                                    )['Name'] ??
                                    ''
                              : '',
                          onTap: () => _openSearchModal<int>(
                            title: 'Representante Comercial',
                            items: _salesReps,
                            currentValue: _selectedSalesRepId,
                            getTitle: (item) => item['Name'] ?? 'Sin Nombre',
                            getValue: (item) =>
                                (item['AD_User_ID'] ?? item['id']) as int,
                            onSelected: (val) =>
                                setState(() => _selectedSalesRepId = val),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSearchableField<String>(
                          label: AppLocale.status.getString(context),
                          hintText: AppLocale.selectStatus.getString(context),
                          value: _currentStatus,
                          isLoading: false,
                          isDisabled: false,
                          displayText: cleanStatusName(_currentStatus),
                          onTap: () => _openSearchModal<String>(
                            title: 'Estado',
                            items: statusItems,
                            currentValue: _currentStatus,
                            getTitle: (item) =>
                                cleanStatusName(item.toString()),
                            getValue: (item) => item.toString(),
                            onSelected: (val) => setState(
                              () => _currentStatus = val ?? _currentStatus,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _isReadOnly
                              ? null
                              : () =>
                                    _selectDate(context, _dateStartController),
                          child: AbsorbPointer(
                            child: CustomTextField(
                              controller: _dateStartController,
                              label: AppLocale.plannedStartDate.getString(context),
                              readOnly: true,
                              hintText: 'YYYY-MM-DD',
                              prefixIcon: const Icon(Icons.calendar_today),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: _isReadOnly
                              ? null
                              : () => _selectDate(
                                  context,
                                  _dateCompleteController,
                                ),
                          child: AbsorbPointer(
                            child: CustomTextField(
                              controller: _dateCompleteController,
                              label: AppLocale.closingDate.getString(context),
                              readOnly: true,
                              hintText: 'YYYY-MM-DD',
                              prefixIcon: const Icon(Icons.calendar_today),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _qtyUsedController,
                    label: AppLocale.investedHours.getString(context),
                    readOnly: _isReadOnly,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isFullAccess) ...[
                    CustomTextField(
                      controller: _estimatedDevHoursController,
                      label: AppLocale.estimatedDevelopmentHours.getString(context),
                      readOnly: _isReadOnly,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    _isReadOnly
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outline.withOpacity(0.5),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Descripción / Resumen',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Html(
                                  data: HtmlEditorUtils.deltaToHtml(
                                    _summaryQuillController.document,
                                  ),
                                  style: {
                                    "body": Style(
                                      margin: Margins.zero,
                                      padding: HtmlPaddings.zero,
                                      fontSize: FontSize(14),
                                    ),
                                  },
                                ),
                              ],
                            ),
                          )
                        : QuillExpandableField(
                            controller: _summaryQuillController,
                            label: AppLocale.descriptionSummary.getString(context),
                            readOnly: _isReadOnly,
                            height: 150,
                          ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onDelete();
          },
          child: Text(AppLocale.delete.getString(context), style: const TextStyle(color: Colors.red)),
        ),
        // BOTÓN DE RESPONDER (Estilo limpio)
        TextButton.icon(
          onPressed: _isSaving
              ? null
              : () => _handleSave(navigateToReply: true),
          icon: const Icon(Icons.reply, size: 20),
          label: Text(
            AppLocale.reply.getString(context),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
        ),
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: Text(AppLocale.cancel.getString(context)),
        ),
        CustomButton(
          text: 'Guardar',
          isLoading: _isSaving,
          onPressed: () => _handleSave(),
        ),
      ],
    );
  }
}
