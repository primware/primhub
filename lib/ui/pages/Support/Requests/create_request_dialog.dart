import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter_quill/flutter_quill.dart' hide Style;
import 'package:primhub/ui/pages/Support/Requests/html_editor_utils.dart';
import 'package:flutter/services.dart'; // Para FilteringTextInputFormatter
import 'package:primhub/api/api_http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import '../../../Shared_Custom/custom_button.dart';
import '../../../../api/contract_api.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import '../../../../ui/pages/Support/Requests/request_functions.dart';
import '../../../../api/validation_manager.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import '../../../../api/token.dart';
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ImagesManagment/post_attachments.dart';
import 'package:primhub/ui/widgets/duration_formatter.dart';
import 'package:flutter_localization/flutter_localization.dart';

class CreateRequestDialog extends StatefulWidget {
  final String? linkedRecordUU;
  final List<Map<String, dynamic>>? bPartners;
  final int? selectedBPartnerId;
  final int? linkedProjectId;
  final int? linkedPhaseId;
  final int? linkedTaskId;

  const CreateRequestDialog({
    super.key,
    this.linkedRecordUU,
    this.bPartners,
    this.selectedBPartnerId,
    this.linkedProjectId,
    this.linkedPhaseId,
    this.linkedTaskId,
  });

  @override
  State<CreateRequestDialog> createState() => _CreateRequestDialogState();
}

class _CreateRequestDialogState extends State<CreateRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  final QuillController _summaryQuillController = QuillController.basic();
  final TextEditingController _dateStartController = TextEditingController();
  final TextEditingController _dateCompleteController = TextEditingController();
  final TextEditingController _qtyUsedController = TextEditingController();
  final TextEditingController _estimatedDevHoursController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _errorUserController = TextEditingController();
  final TextEditingController _errorRoleController = TextEditingController();
  final TextEditingController _errorTimeController = TextEditingController();
  final TextEditingController _errorWindowController = TextEditingController();
  final TextEditingController _errorServerUrlController =
      TextEditingController();

  String? _selectedEnvironment;
  String _selectedPriority = 'Media';
  String? _selectedType;
  String _selectedStatus = 'Recibida';
  String? _selectedCategory;
  String? _selectedGroup;
  int? _selectedProjectId;
  int? _selectedBpId;
  int? _selectedSalesRepId;
  int? _selectedUserId;
  int? _selectedProductChipId;

  Map<String, int> _statusIdMap = {};
  Map<String, int> _requestTypeMap = {};
  Map<String, int> _categoryMap = {};
  Map<String, String> _categoryPriorityMap = {};
  List<Map<String, dynamic>> _categoryRecords = [];
  Map<String, int> _groupMap = {};
  List<dynamic> _users = [];
  List<Map<String, dynamic>> _salesReps = [];
  List<dynamic> _bPartnersList = [];

  bool _isLoadingStatuses = true;
  bool _isLoadingTypes = true;
  bool _isLoadingCategories = true;
  bool _loadingGroupsState = true;
  bool _isLoadingUsers = true;
  bool _isLoadingSalesReps = true;
  bool _isLoadingBPartners = true;
  bool _isLoadingProducts = true;
  List<dynamic> _productChips = [];

  final List<PlatformFile?> _evidences = [null, null, null, null];

  bool get _isProjectRequest =>
      widget.linkedProjectId != null ||
      widget.linkedTaskId != null ||
      _selectedProjectId != null;

  bool get _requiresAdditionalFields {
    if (_selectedCategory == null || _categoryRecords.isEmpty) return false;
    final cat = _categoryRecords.firstWhere(
      (c) => c['Name'] == _selectedCategory,
      orElse: () => <String, dynamic>{},
    );
    if (cat.isEmpty) return false;

    // Ignorar mayúsculas y minúsculas
    final rawVal = cat.entries
        .firstWhere(
            (e) =>
                e.key.toLowerCase() ==
                'primhub_additional_category_textfields',
            orElse: () => const MapEntry('', null))
        .value;
    return rawVal == true || rawVal?.toString().toLowerCase() == 'true';
  }

  @override
  void initState() {
    super.initState();
    _salesReps = GlobalCache.salesReps;
    _isLoadingSalesReps = false;
    _fetchInitialData();
    final now = DateTime.now();
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    _dateStartController.text = todayStr;
    _dateCompleteController.text = todayStr;

    final payload = Token.decodePayload(Token.token);
    final currentUserId = payload['AD_User_ID'];

    // Si viene vinculado a una tarea, pre-llenar el asunto
    if (widget.linkedRecordUU != null) {
      _subjectController.text = 'Solicitud de Tarea';
    }
    if (currentUserId != null) {
      _selectedUserId = payload['AD_User_ID'];
      // Solo pre-seleccionar si el usuario actual es un representante de ventas válido
      final currentUserIsRep = _salesReps.any(
        (rep) => (rep['AD_User_ID'] ?? rep['id']) == currentUserId,
      );
      if (currentUserIsRep && !AccessControl.isRealSupport) {
        _selectedSalesRepId = currentUserId;
      }
    }

    _selectedBpId = widget.selectedBPartnerId ?? (AccessControl.isAdmin ? null : User.cBPartnerID);
    _fetchBPartners();
  }

  @override
  void dispose() {
    _summaryQuillController.dispose();
    _dateStartController.dispose();
    _dateCompleteController.dispose();
    _qtyUsedController.dispose();
    _estimatedDevHoursController.dispose();
    _subjectController.dispose();
    _errorUserController.dispose();
    _errorRoleController.dispose();
    _errorTimeController.dispose();
    _errorWindowController.dispose();
    _errorServerUrlController.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    if (widget.linkedRecordUU == null &&
        AccessControl.isAdmin &&
        _selectedBpId == null) {
      return false;
    }
    if (_subjectController.text.trim().isEmpty) return false;
    
    if (AccessControl.isSupport && _selectedCategory == null) return false;

    if (!_isProjectRequest) {
      if (_summaryQuillController.document.toPlainText().trim().isEmpty) {
        return false;
      }
      // [Temporal] Campos no obligatorios
      // if (_selectedEnvironment == null) return false;
      // if (_errorServerUrlController.text.trim().isEmpty) return false;
      // if (_errorUserController.text.trim().isEmpty) return false;
      // if (_errorRoleController.text.trim().isEmpty) return false;
      // if (_errorTimeController.text.trim().isEmpty) return false;
      // if (_errorWindowController.text.trim().isEmpty) return false;
      // if (_evidences[0] == null) return false;
    }
    return true;
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
            return active;
          }).toList();
          // Si solo hay 1 ficha, se coloca automáticamente (independiente del rol)
          if (_productChips.length == 1) {
            _selectedProductChipId =
                ((_productChips.first['id'] ??
                            _productChips.first['C_BPartner_Product_Chip_ID'])
                        as num?)
                    ?.toInt();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _fetchInitialData() async {
    await Future.wait([
      _fetchStatuses(),
      _fetchRequestTypes(),
      _fetchCategories(),
      _fetchGroups(),
      _fetchBPartners(),
      _fetchUsers(),
      _fetchProductChips(),
    ]);
  }

  Future<void> _fetchBPartners() async {
    try {
      int? resolvedBpId = widget.selectedBPartnerId;

      // Si la solicitud nace desde un proyecto, heredamos obligatoriamente su tercero
      if (resolvedBpId == null && widget.linkedProjectId != null) {
        var projRes = await http.get(
          Uri.parse(
            '${Endpoint.project}/${widget.linkedProjectId}?\$select=C_BPartner_ID',
          ),
          headers: {'Authorization': Token.token},
        );
        if (projRes.statusCode == 401) {
          if (await handleTokenRefresh()) {
            projRes = await http.get(
              Uri.parse(
                '${Endpoint.project}/${widget.linkedProjectId}?\$select=C_BPartner_ID',
              ),
              headers: {'Authorization': Token.token},
            );
          }
        }
        if (projRes.statusCode == 200) {
          final data = jsonDecode(utf8.decode(projRes.bodyBytes));
          final bpField = data['C_BPartner_ID'];
          resolvedBpId = (bpField is Map)
              ? bpField['id']
              : (bpField is int ? bpField : null);
        }
      }

      List<dynamic> bps = [];
      if (GlobalCache.bPartners.isNotEmpty) {
        bps = GlobalCache.bPartners;
      } else {
        final logic = ProjectsLogic();
        bps = await logic.fetchBPartners();
      }

      int? newSelectedBpId =
          _selectedBpId ??
          resolvedBpId ??
          (AccessControl.isAdmin ? null : User.cBPartnerID);

      // Si el tercero seleccionado no está en la lista bps, intentamos buscarlo de forma individual para obtener su nombre real
      String? fetchedSingleBpName;
      if (newSelectedBpId != null &&
          !bps.any((bp) => bp['id'] == newSelectedBpId)) {
        try {
          var singleBpRes = await http.get(
            Uri.parse('${Endpoint.cBPartner}/$newSelectedBpId?\$select=Name'),
            headers: {'Authorization': Token.token},
          );
          if (singleBpRes.statusCode == 401) {
            if (await handleTokenRefresh()) {
              singleBpRes = await http.get(
                Uri.parse(
                  '${Endpoint.cBPartner}/$newSelectedBpId?\$select=Name',
                ),
                headers: {'Authorization': Token.token},
              );
            }
          }
          if (singleBpRes.statusCode == 200) {
            final data = jsonDecode(utf8.decode(singleBpRes.bodyBytes));
            fetchedSingleBpName = data['Name'];
          }
        } catch (_) {
      // Ignored: Fail silently
    }
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

          _isLoadingBPartners = false;

          if (newSelectedBpId == null && _bPartnersList.isNotEmpty) {
            newSelectedBpId =
                resolvedBpId != null &&
                    _bPartnersList.any((bp) => bp['id'] == resolvedBpId)
                ? resolvedBpId
                : (widget.linkedProjectId != null ? resolvedBpId : null);
          }
          _selectedBpId = newSelectedBpId;

          // Añadir el rescatado a la lista con su nombre real si se obtuvo
          if (_selectedBpId != null &&
              !_bPartnersList.any((bp) => bp['id'] == _selectedBpId)) {
            _bPartnersList.add({
              'id': _selectedBpId,
              'Name': fetchedSingleBpName ?? 'Tercero $_selectedBpId',
            });
          }
        });
        // Llamar a las funciones de carga después de que el estado se haya actualizado
        if (_selectedBpId != null) {
          _fetchUsers();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingBPartners = false);
    }
  }

  Map<String, int> _getFilteredStatuses() {
    if (_requestTypeMap.isEmpty || _statusIdMap.isEmpty) return _statusIdMap;
    
    int? currentRequestTypeId = _requestTypeMap[_selectedType];
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
    
    // Fallback por si la categoría no tiene ningún estado
    return filtered.isNotEmpty ? filtered : _statusIdMap;
  }

  void _validateSelectedStatus() {
    final filtered = _getFilteredStatuses();
    if (filtered.isEmpty) return;
    
    if (!filtered.containsKey(_selectedStatus)) {
      if (AccessControl.isRealSupport) {
        _selectedStatus = filtered.keys.firstWhere(
          (k) => k.toLowerCase().contains('recibida'),
          orElse: () => filtered.keys.firstWhere(
            (k) => k.toLowerCase().contains('open'),
            orElse: () => filtered.keys.first,
          ),
        );
      } else {
        _selectedStatus = filtered.keys.firstWhere(
          (k) => k.toLowerCase().contains('open'),
          orElse: () => filtered.keys.first,
        );
      }
    }
  }

  Future<void> _fetchStatuses() async {
    try {
      final mapData = await fetchStatusesWithMetadata();
      if (mounted) {
        setState(() {
          _statusIdMap = mapData['nameToId'] as Map<String, int>;
          _isLoadingStatuses = false;
          _validateSelectedStatus();
        });
      }
    } catch (e) {
      // Ignore error
    } finally {
      if (mounted && _isLoadingStatuses) {
        setState(() => _isLoadingStatuses = false);
      }
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
            widget.linkedRecordUU != null && widget.linkedRecordUU!.isNotEmpty;

        if (mounted) {
          setState(() {
            _requestTypeMap = {for (var r in records) r['Name']: r['id']};

            // Establecer tipo por defecto según el contexto
            if (_requestTypeMap.isNotEmpty) {
              if (AccessControl.isRealSupport) {
                _selectedType = _requestTypeMap.keys.firstWhere(
                  (k) => k.toLowerCase().contains('soporte lirion'),
                  orElse: () => _requestTypeMap.keys.first,
                );
              } else if (isProject) {
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

            _isLoadingTypes = false;
            _validateSelectedStatus();
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingTypes = false);
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

  Future<void> _fetchCategories() async {
    try {
      final bool isProject =
          widget.linkedRecordUU != null && widget.linkedRecordUU!.isNotEmpty;

      final allRecords = await fetchCategories();

      // Filtrar categorías según el contexto:
      // Si es Proyecto: mostrar las que tienen showinprimhub = false
      // Si es Soporte: mostrar las que tienen showinprimhub = true
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
          if (_selectedCategory == null &&
              _categoryMap.isNotEmpty &&
              AccessControl.isAdmin) {
            _selectedCategory = _categoryMap.keys.first;
          }
          _isLoadingCategories = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
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
            if (_selectedGroup == null && _groupMap.isNotEmpty) {
              _selectedGroup = _groupMap.keys.first;
            }
            _loadingGroupsState = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadingGroupsState = false);
    }
  }

  Future<void> _fetchUsers() async {
    try {
      if (_selectedBpId == null) {
        if (mounted) setState(() => _isLoadingUsers = false);
        return;
      }
      final logic = ProjectsLogic();
      final users = await logic.fetchUsers(bPartnerId: _selectedBpId);
      if (mounted) {
        final previouslySelectedUserId = _selectedUserId;
        bool userWasCleared = false;

        // Si el usuario actual ya no está en la lista filtrada, lo deseleccionamos.
        if (previouslySelectedUserId != null &&
            !users.any(
              (u) => (u['AD_User_ID'] ?? u['id']) == previouslySelectedUserId,
            )) {
          _selectedUserId = null;
          userWasCleared = true;
        }

        setState(() {
          _users = users;
          _isLoadingUsers = false;
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
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  final Map<String, String> _priorityMap = {
    'Urgente': '1',
    'Alta': '3',
    'Media': '5',
    'Baja': '7',
    'Muy baja': '9',
  };

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



  Future<void> _pickFile(int index) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      if (result.files.first.size > 5 * 1024 * 1024) {
        ToastMessage.show(context: context, message: 'El archivo excede el tamaño máximo permitido de 5 MB.', type: ToastType.failure);
        return;
      }

      if (result.files.first.bytes == null) {
        ToastMessage.show(context: context, message: 'Error al leer el archivo. Intente con otro formato.', type: ToastType.warning);
        return;
      }
      setState(() {
        _evidences[index] = result.files.first;
      });
    }
  }

  void _removeFile(int index) {
    setState(() {
      _evidences[index] = null;
    });
  }

  Widget _buildEvidenceField(int index) {
    final file = _evidences[index];
    final theme = Theme.of(context);

    bool isImage = false;
    if (file != null && file.extension != null) {
      final ext = file.extension!.toLowerCase();
      isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: (isImage && file?.bytes != null)
                  ? () {
                      showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          backgroundColor: Colors.transparent,
                          child: Stack(
                            alignment: Alignment.topRight,
                            children: [
                              InteractiveViewer(
                                child: Image.memory(file!.bytes!),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ],
                                ),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.5),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        file != null
                            ? file.name
                            : 'Adjunto ${index + 1} (Sin archivo)',
                        style: TextStyle(
                          color: file != null
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isImage)
                      const Icon(
                        Icons.visibility,
                        size: 18,
                        color: Colors.grey,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (file == null)
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: () => _pickFile(index),
              tooltip: 'Adjuntar Archivo',
              color: theme.colorScheme.primary,
            )
          else
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _removeFile(index),
              tooltip: 'Eliminar Adjunto',
              color: theme.colorScheme.error,
            ),
        ],
      ),
    );
  }

  Future<void> _openSearchModal<T>({
    required String title,
    required List<dynamic> items,
    required T? currentValue,
    required String Function(dynamic) getTitle,
    String Function(dynamic)? getSubtitle,
    required T Function(dynamic) getValue,
    required void Function(T) onSelected,
  }) async {
    final double dialogHeight = MediaQuery.of(context).size.height * 0.6;
    final T? result = await showDialog<T>(
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
                      'Seleccionar $title *',
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
                            subtitle: getSubtitle != null
                                ? Text(
                                    getSubtitle(item),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(itemValue),
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

    if (result != null) onSelected(result);
  }

  Widget _buildSearchableField<T>({
    required String label,
    required String? hintText,
    required T? value,
    required bool isLoading,
    required bool isDisabled,
    required String displayText,
    required VoidCallback onTap,
    String? errorMessage,
  }) {
    return InkWell(
      onTap: (isLoading || isDisabled) ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorMessage,
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
        isEmpty: value == null,
        child: Text(
          value == null ? (hintText ?? '') : displayText,
          style: TextStyle(
            fontSize: 16,
            color: (isLoading || isDisabled || value == null)
                ? Colors.grey[600]
                : Theme.of(context).colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<void> _submitForm() async {
    final bool isFullAccess = AccessControl.isAdmin || AccessControl.isExtSupport;

    if (!_formKey.currentState!.validate()) return;

    final summaryText = _summaryQuillController.document.toPlainText().trim();
    if (!_isProjectRequest && summaryText.isEmpty) {
      ToastMessage.show(context: context, message: 'Por favor ingrese una descripción', type: ToastType.failure);
      return;
    }

    if (_requiresAdditionalFields) {
      if (_selectedEnvironment == null ||
          _errorServerUrlController.text.trim().isEmpty ||
          _errorUserController.text.trim().isEmpty ||
          _errorRoleController.text.trim().isEmpty ||
          _errorTimeController.text.trim().isEmpty ||
          _errorWindowController.text.trim().isEmpty) {
        ToastMessage.show(
          context: context,
          message: 'Por favor llene todos los datos adicionales (obligatorios)',
          type: ToastType.failure,
        );
        return;
      }
    }

    if (!AccessControl.canCreateRequests) return;
    if (_isLoadingStatuses ||
        _isLoadingTypes ||
        _isLoadingCategories ||
        _loadingGroupsState ||
        _isLoadingUsers ||
        _isLoadingBPartners) {
      return;
    }

    double qty = double.tryParse(_qtyUsedController.text) ?? 0.0;

    // Notificación de Ficha de Producto preferible (ya no es obligatorio)
    if (widget.linkedRecordUU == null &&
        _selectedProductChipId == null &&
        !AccessControl.isRealSupport) {
      final bool? continueWithoutChip = await showDialog<bool>(
        context: context,
        builder: (context) => CustomModal(
          title: 'Ficha de Producto no seleccionada',
          content: const Text(
            'Es preferible seleccionar una Ficha de Producto para solicitudes de soporte para asegurar una correcta vinculación y seguimiento de horas.\n\n¿Desea continuar sin seleccionar una ficha?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Volver y seleccionar'),
            ),
            CustomButton(
              text: 'Continuar de todos modos',
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );

      if (continueWithoutChip != true) return;
    }

    int? bpId = _selectedBpId ?? User.cBPartnerID;

    // Validación de Horas Disponibles (Solo para Soporte)
    if (widget.linkedRecordUU == null &&
        qty > 0 &&
        !ValidationManager.isExempt(bpId)) {
      setState(() => _isSubmitting = true); // Mostrar carga mientras validamos
      try {
        if (bpId != null) {
          if (_selectedProductChipId != null) {
            final selectedChip = _productChips.firstWhere(
              (c) => c['id'] == _selectedProductChipId,
              orElse: () => {},
            );
            if (selectedChip.isNotEmpty) {
              final double chipTotalQty =
                  (selectedChip['Qty'] as num?)?.toDouble() ?? 0.0;

              // Fetch all requests linked to THIS SPECIFIC CHIP
              final chipRequests = await fetchRequest(
                filter: "C_BPartner_Product_Chip_ID eq $_selectedProductChipId",
              );
              double totalEstimatedAndConsumedForChip = 0.0;

              for (var req in chipRequests) {
                if (req['Record_UU'] != null &&
                    req['Record_UU'].toString().isNotEmpty) {
                  continue;
                }

                // Sumamos QtySpent (consumidas) o QtyPlan (en progreso)
                totalEstimatedAndConsumedForChip +=
                    (req['QtySpent'] as num?)?.toDouble() ??
                    (req['QtyPlan'] as num?)?.toDouble() ??
                    0.0;
              }

              if (totalEstimatedAndConsumedForChip + qty > chipTotalQty) {
                if (mounted) {
                  ToastMessage.show(
                    context: context,
                    message: 'La solicitud consumirá más horas de las que tiene disponible dicha ficha de producto. Disponibles: ${DurationFormatter.format(chipTotalQty - totalEstimatedAndConsumedForChip)} h, Intentando registrar: ${DurationFormatter.format(qty)} h',
                    type: ToastType.failure,
                  );
                  setState(() => _isSubmitting = false);
                }
                return;
              }
            }
          }
        }
      } catch (e) {
        // Si la validación falla por un error de red, se permite continuar para no bloquear al usuario.
      }
      // No se detiene el spinner aquí, continúa al bloque de submit.
    }

    if (widget.linkedRecordUU == null &&
        AccessControl.isAdmin &&
        _selectedBpId == null) {
      if (mounted) {
        ToastMessage.show(context: context, message: 'Como administrador, debe seleccionar un tercero.', type: ToastType.failure);
      }
      // Detener el spinner si la validación falla aquí
      if (_isSubmitting) setState(() => _isSubmitting = false);
      return;
    }

    final bool hasEvidence = _evidences.any((e) => e != null);
    final String confirmMessage = hasEvidence
        ? '¿Seguro quiere continuar? Al enviar la solicitud esta no puede ser editada por usted, compruebe que toda la información y/o adjuntos sean correctos antes de continuar.'
        : 'El equipo de soporte o desarrollo puede atender su solicitud más rápido si adjunta algún tipo de evidencia o información adicional que pueda ser de utilidad.\n\n¿Seguro quiere continuar sin adjuntos? Al enviar la solicitud esta no puede ser editada por usted.';

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => CustomModal(
        title: 'Confirmar Solicitud',
        content: Text(confirmMessage),
        actions: [
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop(false);
                    }
                  },
            child: const Text('Revisar'),
          ),
          CustomButton(
            text: 'Sí, continuar',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;

    if (!_isSubmitting) setState(() => _isSubmitting = true);

    try {

      final payloadToken = Token.decodePayload(Token.token);
      int? clientId = Token.client ?? payloadToken['AD_Client_ID'];
      int? orgId = Token.organitation ?? payloadToken['AD_Org_ID'];
      int? userId = payloadToken['AD_User_ID'];

      int defaultStatusId = _statusIdMap.isNotEmpty
          ? _statusIdMap.values.first
          : 100;
      int openStatusId = _statusIdMap.entries
          .firstWhere(
            (e) => e.key.toLowerCase().contains('recibida'),
            orElse: () => _statusIdMap.entries.firstWhere(
              (e) => e.key.toLowerCase().contains('open'),
              orElse: () => MapEntry('', defaultStatusId),
            ),
          )
          .value;

      // Inyectamos directamente la relación a la tabla y el UUID en el modelo R_Request
      // asegurando que herede el proyecto y se vincule a la tarea.
      await _createManualRequest(
        clientId,
        orgId,
        userId,
        openStatusId,
        isFullAccess,
      );
    } catch (e) {
      if (mounted) {
        ToastMessage.show(context: context, message: 'Error: $e', type: ToastType.failure);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _createManualRequest(
    int? clientId,
    int? orgId,
    int? userId,
    int openStatusId,
    bool isFullAccess,
  ) async {
    final url = Uri.parse(Endpoint.request);
    double qty = double.tryParse(_qtyUsedController.text) ?? 0.0;

    String summaryHtml = HtmlEditorUtils.deltaToHtml(
      _summaryQuillController.document,
    );

    // Agregar campos adicionales estructurados al resumen HTML si la categoría lo requiere
    if (_requiresAdditionalFields) {
      final String structuredInfo =
          '''
<p><strong>Entorno de la solicitud:</strong> ${_selectedEnvironment ?? ''}</p>
<p><strong>URL del servidor (Link):</strong> ${_errorServerUrlController.text.trim()}</p>
<p><strong>Usuario implicado:</strong> ${_errorUserController.text.trim()}</p>
<p><strong>Rol implicado:</strong> ${_errorRoleController.text.trim()}</p>
<p><strong>Hora aprox. del evento:</strong> ${_errorTimeController.text.trim()}</p>
<p><strong>Ventana/Reporte asociado:</strong> ${_errorWindowController.text.trim()}</p>
<br/>
''';
      summaryHtml = structuredInfo + summaryHtml;
    }
    final subjectText = _subjectController.text.trim();

    final Map<String, dynamic> data = {
      'Summary': summaryHtml,
      'Priority': _priorityMap[_selectedPriority] ?? '5',
      'R_RequestType_ID': {'id': _requestTypeMap[_selectedType!]},
      'R_Status_ID': {
        'id': isFullAccess
            ? (_statusIdMap[_selectedStatus] ?? openStatusId)
            : openStatusId,
      },
    };

    if (subjectText.isNotEmpty) {
      data['CDS_EmailSubject'] = subjectText;
    }

    if (_selectedCategory != null &&
        _categoryMap.containsKey(_selectedCategory)) {
      data['R_Category_ID'] = {'id': _categoryMap[_selectedCategory]};
    }

    if (clientId != null) data['AD_Client_ID'] = {'id': clientId};
    if (orgId != null) data['AD_Org_ID'] = {'id': orgId};

    if (isFullAccess && _selectedUserId != null) {
      data['AD_User_ID'] = {'id': _selectedUserId};
    } else if (userId != null) {
      data['AD_User_ID'] = {'id': userId};
    }

    // --- Lógica segura para asignar SalesRep_ID ---
    int? repIdToAssign;

    // 1. Si es admin, el valor seleccionado tiene prioridad.
    if (isFullAccess) {
      repIdToAssign = _selectedSalesRepId;
    }
    // 2. Si no hay rep, usar el usuario actual si es un rep válido (o forzar si es Extsp).
    if (repIdToAssign == null && userId != null) {
      if (AccessControl.isExtSupport) {
        repIdToAssign = userId;
      } else {
        final currentUserIsRep = _salesReps.any(
          (rep) => (rep['AD_User_ID'] ?? rep['id']) == userId,
        );
        if (currentUserIsRep) repIdToAssign = userId;
      }
    }
    // 3. Como fallback (y necesario para soporte/proyecto), usar el rep del tercero si existe.
    if (repIdToAssign == null && _selectedBpId != null) {
      final bpData = _bPartnersList.firstWhere(
        (bp) => bp['id'] == _selectedBpId,
        orElse: () => {},
      );
      final bpRep = bpData['SalesRep_ID'];
      repIdToAssign = (bpRep is Map)
          ? bpRep['id']
          : (bpRep is int ? bpRep : null);
    }

    // 4. Asignar al payload si se encontró un rep válido.
    if (repIdToAssign != null) data['SalesRep_ID'] = {'id': repIdToAssign};

    if (isFullAccess) {
      if (_selectedGroup != null && _groupMap.containsKey(_selectedGroup)) {
        data['R_Group_ID'] = {'id': _groupMap[_selectedGroup]};
      }
    }

    if (_selectedBpId != null) data['C_BPartner_ID'] = {'id': _selectedBpId};
    if (_selectedProductChipId != null) {
      data['C_BPartner_Product_Chip_ID'] = {'id': _selectedProductChipId};
    }

    // Vinculación directa de IDs del Proyecto en el payload nativo
    if (widget.linkedProjectId != null) {
      data['C_Project_ID'] = {'id': widget.linkedProjectId};
    } else if (_selectedProjectId != null) {
      data['C_Project_ID'] = {'id': _selectedProjectId};
    }

    if (widget.linkedRecordUU != null) {
      data['Record_UU'] = widget.linkedRecordUU;
      data['Record_ID'] = widget.linkedTaskId;

      // Obtenemos dinámicamente el ID de la tabla C_ProjectTask para evitar errores de Foreign Key
      try {
        final tableRes = await http.get(
          Uri.parse(
            '${Endpoint.baseUrl}/api/v1/models/AD_Table?\$filter=TableName eq \'C_ProjectTask\'',
          ),
          headers: {'Authorization': Token.token},
        );
        if (tableRes.statusCode == 200) {
          final tData = jsonDecode(utf8.decode(tableRes.bodyBytes));
          if (tData['records'] != null && tData['records'].isNotEmpty) {
            data['AD_Table_ID'] = {'id': tData['records'][0]['id']};
          }
        }
      } catch (_) {
      // Ignored: Fail silently
    }
    }

    if (isFullAccess &&
        (_selectedType == 'Service Request' ||
            _dateStartController.text.isNotEmpty)) {
      // Corregimos el envío de fechas y horas combinándolas
      String startDate = _dateStartController.text;
      String endDate = _dateCompleteController.text;

      data['DateStartPlan'] = "${startDate}T00:00:00Z";
      data['DateCompletePlan'] = "${endDate}T00:00:00Z";

      // Fecha de Inicio y Cierre reales (solicitado)
      data['StartDate'] = "${startDate}T00:00:00Z";
      data['CloseDate'] = "${endDate}T00:00:00Z";

      // Cantidad usada (solicitado) en lugar de horas/minutos separados
      if (qty > 0) {
        data['QtySpent'] = qty;
      }
      
      double estDevHours = double.tryParse(_estimatedDevHoursController.text) ?? 0.0;
      if (estDevHours > 0) {
        data['PrimHub_Estimated_development_hours'] = estDevHours;
      }
    }

    final body = jsonEncode(data);

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': Token.token,
      },
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final newId = data['id'];
        if (newId != null) {
          // Subir archivos adjuntos
          final tableName = '${Endpoint.baseUrl}/api/v1/models/R_Request';
          for (var file in _evidences) {
            if (file != null && file.bytes != null) {
              final convertedFile = {
                'title': file.name,
                'base64': base64Encode(file.bytes!),
              };
              await postAttachments(
                recordID: newId,
                tableName: tableName,
                convertedFile: convertedFile,
              );
            }
          }

          await GlobalCache.syncSingleRequest(newId);

          // Disparar correo de "Nueva Solicitud" (Plantilla 1000015)
          try {
            int adUserId = 0;
            if (data['AD_User_ID'] != null) {
              adUserId = data['AD_User_ID'] is Map ? data['AD_User_ID']['id'] : data['AD_User_ID'];
            }
            int customerBpId = _selectedBpId ?? 0;

            if (adUserId > 0 || customerBpId > 0) {
              sendRequestStatusEmail(
                requestId: newId,
                adUserId: adUserId,
                bPartnerId: customerBpId,
                templateType: MailTemplateType.newRequest,
              );
            }
          } catch (_) {
      // Ignored: Fail silently
    }
        }
      } catch (_) {
      // Ignored: Fail silently
    }

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
        ToastMessage.show(context: context, message: 'Solicitud creada correctamente', type: ToastType.success);
      }
    } else {
      if (mounted) {
        ToastMessage.show(context: context, message: 'Error ${response.statusCode}: ${response.body}', type: ToastType.failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isFullAccess = AccessControl.isAdmin || AccessControl.isExtSupport;
    return CustomModal(
      title: widget.linkedRecordUU != null
          ? AppLocale.newTaskRequest.getString(context)
          : AppLocale.newSupportRequest.getString(context),
      width: 700,
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),

              // SECCIÓN: Datos de Tercero y Usuario
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildSearchableField<int>(
                      label: AppLocale.partnerLabel.getString(context),
                      hintText: AppLocale.selectBPartner.getString(context),
                      value: _selectedBpId,
                      isLoading: _isLoadingBPartners,
                      isDisabled: !AccessControl.isAdmin,
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
                      errorMessage: _selectedBpId == null
                          ? AppLocale.mustSelectBPartner.getString(context)
                          : null,
                      onTap: () => _openSearchModal<int>(
                        title: AppLocale.partnerLabel.getString(context),
                        items: _bPartnersList
                            .where((bp) => bp['id'] != null)
                            .toList(),
                        currentValue: _selectedBpId,
                        getTitle: (item) => item['Name'] ?? 'Sin Nombre',
                        getValue: (item) => item['id'] as int,
                        onSelected: (val) {
                          setState(() {
                            _selectedBpId = val;
                            _selectedUserId =
                                null; // Reseteamos usuario al cambiar tercero
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
                          ? AppLocale.selectBPartnerFirst.getString(context)
                          : AppLocale.selectUser.getString(context),
                      value: _selectedUserId,
                      isLoading: _isLoadingUsers,
                      isDisabled:
                          !isFullAccess ||
                          _selectedBpId == null ||
                          _isLoadingUsers,
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
                          : (User.name ?? ''),
                      onTap: () => _openSearchModal<int>(
                        title: AppLocale.user.getString(context),
                        items: _users
                            .where((u) => (u['AD_User_ID'] ?? u['id']) != null)
                            .toList(),
                        currentValue: _selectedUserId,
                        getTitle: (item) => item['Name'] ?? 'Sin Nombre',
                        getValue: (item) =>
                            (item['AD_User_ID'] ?? item['id']) as int,
                        onSelected: (val) =>
                            setState(() => _selectedUserId = val),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildSearchableField<String>(
                      label: AppLocale.requestType.getString(context),
                      hintText: 'Seleccione Tipo',
                      value: _selectedType,
                      isLoading: _isLoadingTypes,
                      isDisabled: AccessControl.isRealSupport,
                      displayText: _selectedType ?? '',
                      onTap: () => _openSearchModal<String>(
                        title: AppLocale.requestType.getString(context),
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
                label: AppLocale.requestSubject.getString(context),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 10,
                    child: _buildSearchableField<String>(
                      label: '${AppLocale.category.getString(context)}${AccessControl.isSupport ? ' *' : ''}',
                      hintText: AppLocale.selectCategory.getString(context),
                      value: _selectedCategory,
                      isLoading: _isLoadingCategories,
                      isDisabled: false,
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
                                widget.linkedRecordUU != null &&
                                widget.linkedRecordUU!.isNotEmpty;

                            // La automatización de prioridad solo aplica a SOPORTE (no proyectos)
                            if (!isProject &&
                                _categoryPriorityMap.containsKey(val)) {
                              final pValue = _categoryPriorityMap[val]!;
                              final label = _priorityMap.entries
                                  .firstWhere(
                                    (e) => e.value == pValue,
                                    orElse: () => _priorityMap.entries
                                        .firstWhere((e) => e.key == 'Media'),
                                  )
                                  .key;
                              _selectedPriority = label;
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: IconButton(
                      icon: const Icon(Icons.info_outline, color: Colors.blue),
                      tooltip: AppLocale.viewCategoryGuide.getString(context),
                      onPressed: _showCategoryHelpModal,
                    ),
                  ),
                  Expanded(
                    flex: 10,
                    child: _buildSearchableField<String>(
                      label: AppLocale.priority.getString(context),
                      hintText: 'Seleccione Prioridad',
                      value: _selectedPriority,
                      isLoading: false,
                      isDisabled:
                          !(widget.linkedRecordUU != null &&
                              widget.linkedRecordUU!.isNotEmpty),
                      displayText: _selectedPriority,
                      onTap: () => _openSearchModal<String>(
                        title: AppLocale.priority.getString(context),
                        items: _priorityMap.keys.toList(),
                        currentValue: _selectedPriority,
                        getTitle: (item) => item.toString(),
                        getValue: (item) => item.toString(),
                        onSelected: (val) =>
                            setState(() => _selectedPriority = val),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // SECCIÓN: Ficha de Producto (Solo para Soporte)
              if (!(widget.linkedRecordUU != null &&
                      widget.linkedRecordUU!.isNotEmpty) &&
                  (AccessControl.isAdmin || AccessControl.isExtSupport)) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildSearchableField<int>(
                        label: AppLocale.productChip.getString(context),
                        hintText: _selectedBpId == null
                            ? AppLocale.selectBPartnerFirst.getString(context)
                            : 'Seleccione Ficha',
                        value: _selectedProductChipId,
                        isLoading: _isLoadingProducts,
                        isDisabled: _selectedBpId == null || _isLoadingProducts,
                        displayText:
                            _selectedProductChipId != null &&
                                _productChips.any(
                                  (c) => c['id'] == _selectedProductChipId,
                                )
                            ? _productChips.firstWhere(
                                    (c) => c['id'] == _selectedProductChipId,
                                  )['Description'] ??
                                  'Ficha $_selectedProductChipId'
                            : '',
                        onTap: () => _openSearchModal<int>(
                          title: AppLocale.productChip.getString(context),
                          items: _productChips,
                          currentValue: _selectedProductChipId,
                          getTitle: (item) =>
                              item['Description'] ?? 'Ficha #${item['id']}',
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

              // SECCIÓN: Gestión Interna (Solo Admin)
              if (isFullAccess) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildSearchableField<String>(
                        label: AppLocale.group.getString(context),
                        hintText: 'Seleccione Grupo',
                        value: _selectedGroup,
                        isLoading: _loadingGroupsState,
                        isDisabled: false,
                        displayText: _selectedGroup ?? '',
                        onTap: () => _openSearchModal<String>(
                          title: AppLocale.group.getString(context),
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
                        hintText: 'Seleccione Representante',
                        value: _selectedSalesRepId,
                        isLoading: _isLoadingSalesReps,
                        isDisabled: !AccessControl.isAdmin,
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
                          title: AppLocale.salesRepresentative.getString(context),
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
                        hintText: 'Seleccione Estado',
                        value: _selectedStatus,
                        isLoading: _isLoadingStatuses,
                        isDisabled: false,
                        displayText: cleanStatusName(_selectedStatus),
                        onTap: () {
                          final filteredStatuses = _getFilteredStatuses();
                          _openSearchModal<String>(
                            title: AppLocale.status.getString(context),
                            items: filteredStatuses.keys.toList(),
                            currentValue: _selectedStatus,
                          getTitle: (item) => cleanStatusName(item.toString()),
                          getValue: (item) => item.toString(),
                          onSelected: (val) =>
                              setState(() => _selectedStatus = val),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // SECCIÓN: Planificación y Horas (Solo Admin)
                if (_selectedType != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              _selectDate(context, _dateStartController),
                          child: AbsorbPointer(
                            child: CustomTextField(
                              controller: _dateStartController,
                              label: AppLocale.plannedStartDate.getString(context),
                              hintText: 'YYYY-MM-DD',
                              prefixIcon: const Icon(Icons.calendar_today),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              _selectDate(context, _dateCompleteController),
                          child: AbsorbPointer(
                            child: CustomTextField(
                              controller: _dateCompleteController,
                              label: AppLocale.closeDate.getString(context),
                              hintText: 'YYYY-MM-DD',
                              prefixIcon: const Icon(Icons.calendar_today),
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
                        child: CustomTextField(
                          controller: _qtyUsedController,
                          label: AppLocale.investedHours.getString(context),
                          hintText: '0.0',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                        ),
                      ),
                      if (isFullAccess) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: CustomTextField(
                            controller: _estimatedDevHoursController,
                            label: AppLocale.estimatedHoursDev.getString(context),
                            hintText: '0.0',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ],

              if (_requiresAdditionalFields) ...[
                // DATOS ADICIONALES
                Row(
                  children: [
                    const Text(
                      'Datos Adicionales (Obligatorios)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: CustomDropdown<String>(
                        value: _selectedEnvironment,
                        items: [
                          const DropdownMenuItem(
                            value: 'test',
                            child: Text('Test (Pruebas)'),
                          ),
                          DropdownMenuItem(
                            value: 'producción',
                            child: Text(AppLocale.production.getString(context)),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedEnvironment = val),
                        label: 'Entorno de la solicitud',
                        hintText: 'Seleccione el entorno',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CustomTextField(
                        controller: _errorServerUrlController,
                        label: 'URL del servidor (Link)',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _errorUserController,
                        label: 'Usuario implicado',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CustomTextField(
                        controller: _errorRoleController,
                        label: 'Rol implicado',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _errorTimeController,
                        label: 'Hora aprox. del evento',
                        hintText: 'Ej: 14:30 o 2:30 PM',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CustomTextField(
                        controller: _errorWindowController,
                        label: 'Ventana/Reporte asociado',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],

              // RESUMEN Y ADJUNTOS (Campos comunes)
              Text(
                !_isProjectRequest
                    ? AppLocale.descriptionWhatTried.getString(context)
                    : 'Descripción (Opcional)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              QuillExpandableField(
                controller: _summaryQuillController,
                label: !_isProjectRequest
                    ? 'Descripción / Resumen'
                    : 'Descripción / Resumen',
                isRequired: !_isProjectRequest,
                height: 150,
              ),
              const SizedBox(height: 24),
              const Text(
                'Adjuntos (Opcional, hasta 4 archivos, max 5MB c/u):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              _buildEvidenceField(0),
              _buildEvidenceField(1),
              _buildEvidenceField(2),
              _buildEvidenceField(3),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(AppLocale.cancel.getString(context)),
        ),
        AnimatedBuilder(
          animation: Listenable.merge([
            _subjectController,
            _summaryQuillController,
            _errorServerUrlController,
            _errorUserController,
            _errorRoleController,
            _errorTimeController,
            _errorWindowController,
          ]),
          builder: (context, child) {
            return CustomButton(
              text: AppLocale.sendRequest.getString(context),
              onPressed: (_isFormValid && !_isSubmitting) ? _submitForm : null,
              isLoading: _isSubmitting,
            );
          },
        ),
      ],
    );
  }
}
