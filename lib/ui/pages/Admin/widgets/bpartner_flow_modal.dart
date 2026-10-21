import 'package:flutter/material.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:primhub/ui/pages/Admin/user_management_logic.dart';
import 'package:primhub/api/global_cache.dart';

class BPartnerFlowModal extends StatefulWidget {
  final VoidCallback onSuccess;

  const BPartnerFlowModal({super.key, required this.onSuccess});

  @override
  State<BPartnerFlowModal> createState() => _BPartnerFlowModalState();
}

class _BPartnerFlowModalState extends State<BPartnerFlowModal> {
  bool isCreating = false;
  bool isChecking = false;
  bool isSaving = false;
  bool isLoadingDetails = false;
  int? editingBPartnerId;

  final TextEditingController searchController = TextEditingController();
  final TextEditingController valueController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController taxIdController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();

  bool isCustomer = true;
  bool isVendor = false;
  bool isEmployee = false;
  bool isSalesRep = false;

  int? bpGroupId;
  int? taxIdTypeId;
  int? salesRepId;

  List<Map<String, dynamic>> bpGroups = [];
  List<Map<String, dynamic>> taxIdTypes = [];
  List<Map<String, dynamic>> matchingBPartners = [];

  @override
  void initState() {
    super.initState();
    nameController.addListener(() => setState(() {}));
    _loadCatalogs();
  }

  @override
  void dispose() {
    searchController.dispose();
    valueController.dispose();
    nameController.dispose();
    taxIdController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    final g = await UserManagementLogic.fetchBPGroups();
    final t = await UserManagementLogic.fetchTaxIdTypes();
    if (mounted) {
      setState(() {
        bpGroups = g;
        taxIdTypes = t;
        if (bpGroups.isNotEmpty && bpGroupId == null) {
          bpGroupId = (bpGroups.first['id'] as num? ?? bpGroups.first['C_BP_Group_ID'] as num?)?.toInt();
        }
        if (taxIdTypes.isNotEmpty && taxIdTypeId == null) {
          taxIdTypeId = (taxIdTypes.first['id'] as num? ?? taxIdTypes.first['LCO_TaxIdType_ID'] as num?)?.toInt();
        }
      });
    }
  }

  Future<void> _checkExists() async {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      ToastMessage.show(context: context, message: 'Ingrese un término de búsqueda', type: ToastType.warning);
      return;
    }

    setState(() {
      isChecking = true;
      matchingBPartners.clear();
    });
    
    final existing = await UserManagementLogic.checkBPartnerExists(query);
    
    if (!mounted) return;
    setState(() => isChecking = false);

    if (existing.isNotEmpty) {
      setState(() => matchingBPartners = existing);
    } else {
      _proceedToCreate(query);
    }
  }

  void _proceedToCreate(String defaultName) {
    setState(() {
      editingBPartnerId = null;
      isCreating = true;
      nameController.text = defaultName;
      valueController.text = '';
      taxIdController.text = '';
      descriptionController.text = '';
      isCustomer = true;
      isVendor = false;
      isEmployee = false;
      isSalesRep = false;
      salesRepId = null;
      if (bpGroups.isNotEmpty) {
        bpGroupId = (bpGroups.first['id'] as num? ?? bpGroups.first['C_BP_Group_ID'] as num?)?.toInt();
      }
      if (taxIdTypes.isNotEmpty) {
        taxIdTypeId = (taxIdTypes.first['id'] as num? ?? taxIdTypes.first['LCO_TaxIdType_ID'] as num?)?.toInt();
      }
    });
  }

  Future<void> _selectExistingBPartner(Map<String, dynamic> bp) async {
    final bpId = (bp['id'] ?? bp['C_BPartner_ID'] as num?)?.toInt();
    if (bpId == null) return;

    setState(() {
      editingBPartnerId = bpId;
      isCreating = true;
      isLoadingDetails = true;

      nameController.text = (bp['Name'] ?? '').toString();
      valueController.text = (bp['Value'] ?? '').toString();
      taxIdController.text = (bp['TaxID'] ?? '').toString();
      descriptionController.text = (bp['Description'] ?? '').toString();

      _applyBPartnerData(bp);
    });

    // Cargar detalles completos del tercero por ID para asegurar todos los campos
    final fullBp = await UserManagementLogic.fetchBPartnerById(bpId);
    if (!mounted) return;

    if (fullBp != null) {
      setState(() {
        _applyBPartnerData(fullBp);
        nameController.text = (fullBp['Name'] ?? nameController.text).toString();
        valueController.text = (fullBp['Value'] ?? valueController.text).toString();
        taxIdController.text = (fullBp['TaxID'] ?? taxIdController.text).toString();
        descriptionController.text = (fullBp['Description'] ?? descriptionController.text).toString();
        isLoadingDetails = false;
      });
    } else {
      setState(() => isLoadingDetails = false);
    }
  }

  void _applyBPartnerData(Map<String, dynamic> data) {
    // Grupo de tercero
    if (data['C_BP_Group_ID'] != null) {
      final gVal = data['C_BP_Group_ID'];
      final gId = ((gVal is Map ? gVal['id'] : gVal) as num?)?.toInt();
      if (gId != null && bpGroups.any((g) => ((g['id'] ?? g['C_BP_Group_ID']) as num?)?.toInt() == gId)) {
        bpGroupId = gId;
      }
    }

    // Tipo de identificación
    if (data['LCO_TaxIdType_ID'] != null) {
      final tVal = data['LCO_TaxIdType_ID'];
      final tId = ((tVal is Map ? tVal['id'] : tVal) as num?)?.toInt();
      if (tId != null && taxIdTypes.any((t) => ((t['id'] ?? t['LCO_TaxIdType_ID']) as num?)?.toInt() == tId)) {
        taxIdTypeId = tId;
      }
    }

    // Representante Comercial
    if (data['SalesRep_ID'] != null) {
      final sVal = data['SalesRep_ID'];
      final sId = ((sVal is Map ? sVal['id'] : sVal) as num?)?.toInt();
      salesRepId = sId;
    }

    // Roles
    if (data.containsKey('IsCustomer')) {
      isCustomer = UserManagementLogic.isTruthy(data['IsCustomer']);
    }
    if (data.containsKey('IsVendor')) {
      isVendor = UserManagementLogic.isTruthy(data['IsVendor']);
    }
    if (data.containsKey('IsEmployee')) {
      isEmployee = UserManagementLogic.isTruthy(data['IsEmployee']);
    }
    if (data.containsKey('IsSalesRep')) {
      isSalesRep = UserManagementLogic.isTruthy(data['IsSalesRep']);
    }
  }

  Future<void> _saveBPartner() async {
    if (nameController.text.trim().isEmpty || bpGroupId == null || taxIdTypeId == null || valueController.text.trim().isEmpty) {
      ToastMessage.show(context: context, message: 'Complete los campos obligatorios (*)', type: ToastType.warning);
      return;
    }

    setState(() => isSaving = true);
    
    final payload = {
      'Name': nameController.text.trim(),
      'C_BP_Group_ID': bpGroupId,
      'LCO_TaxIdType_ID': taxIdTypeId,
      'IsCustomer': isCustomer,
      'IsVendor': isVendor,
      'IsEmployee': isEmployee,
      'IsSalesRep': isSalesRep,
      'IsActive': true,
    };
    if (valueController.text.trim().isNotEmpty) payload['Value'] = valueController.text.trim();
    if (taxIdController.text.trim().isNotEmpty) payload['TaxID'] = taxIdController.text.trim();
    if (descriptionController.text.trim().isNotEmpty) payload['Description'] = descriptionController.text.trim();
    if (salesRepId != null) {
      payload['SalesRep_ID'] = salesRepId;
    } else {
      payload['SalesRep_ID'] = null;
    }

    bool success;
    if (editingBPartnerId != null) {
      success = await UserManagementLogic.updateBPartner(editingBPartnerId!, payload);
    } else {
      success = await UserManagementLogic.saveBPartner(payload);
    }

    if (!mounted) return;
    setState(() => isSaving = false);

    if (success) {
      // Si editamos un tercero existente que está en GlobalCache, actualizamos su información en memoria
      if (editingBPartnerId != null && GlobalCache.bPartners.isNotEmpty) {
        for (var i = 0; i < GlobalCache.bPartners.length; i++) {
          final cur = GlobalCache.bPartners[i];
          final curId = (cur['id'] ?? cur['C_BPartner_ID'] as num?)?.toInt();
          if (curId == editingBPartnerId) {
            GlobalCache.bPartners[i] = {
              ...cur,
              'Name': nameController.text.trim(),
              'Value': valueController.text.trim(),
              'TaxID': taxIdController.text.trim(),
              'Description': descriptionController.text.trim(),
              'IsCustomer': isCustomer,
              'IsVendor': isVendor,
              'IsEmployee': isEmployee,
              'IsSalesRep': isSalesRep,
            };
            break;
          }
        }
      }

      Navigator.pop(context);
      ToastMessage.show(
        context: context, 
        message: editingBPartnerId != null ? 'Tercero actualizado correctamente' : 'Tercero creado correctamente', 
        type: ToastType.success
      );
      widget.onSuccess();
    } else {
      ToastMessage.show(
        context: context, 
        message: editingBPartnerId != null ? 'Error al actualizar Tercero' : 'Error al crear Tercero', 
        type: ToastType.failure
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!isCreating) {
      return CustomModal(
        title: 'Verificar Existencia de Tercero',
        width: 540,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Antes de crear un nuevo Tercero, busque por Código o Nombre para verificar si ya existe en el sistema.',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Buscar (ej. RUC, CI o Nombre)',
              controller: searchController,
              prefixIcon: const Icon(Icons.search),
              onSubmitted: (_) => _checkExists(),
            ),
            if (matchingBPartners.isNotEmpty) ...[
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Resultados encontrados:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  Text(
                    'Haz clic en uno para editarlo',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(10),
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.2),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: matchingBPartners.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: colorScheme.outline.withOpacity(0.15)),
                  itemBuilder: (context, index) {
                    final bp = matchingBPartners[index];
                    final bpName = (bp['Name'] ?? 'Sin nombre').toString();
                    final bpCode = (bp['Value'] ?? 'Sin código').toString();
                    final taxId = (bp['TaxID'] ?? '').toString();

                    return Tooltip(
                      message: 'Clic para editar los datos generales de este tercero',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _selectExistingBPartner(bp),
                        hoverColor: colorScheme.primary.withOpacity(0.08),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.business_rounded, size: 20, color: colorScheme.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      bpName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Código: $bpCode${taxId.isNotEmpty ? '  •  Identificación: $taxId' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit_outlined, size: 14, color: colorScheme.onPrimaryContainer),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Editar',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
        actions: [
          CustomButton(text: 'Cancelar', backgroundColor: Colors.grey, onPressed: () => Navigator.pop(context)),
          if (matchingBPartners.isNotEmpty)
            CustomButton(
              text: 'Crear de todos modos',
              backgroundColor: Colors.orange,
              onPressed: () => _proceedToCreate(searchController.text.trim()),
            ),
          CustomButton(
            text: isChecking ? 'Verificando...' : 'Verificar',
            backgroundColor: colorScheme.primary,
            isLoading: isChecking,
            onPressed: isChecking ? null : _checkExists,
          ),
        ],
      );
    }

    final isEditMode = editingBPartnerId != null;

    return CustomModal(
      title: isEditMode
          ? 'Editar Tercero: ${nameController.text.trim().isNotEmpty ? nameController.text.trim() : "Existente"}'
          : 'Crear Nuevo Tercero / Empresa',
      width: 700,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLoadingDetails) ...[
              LinearProgressIndicator(color: colorScheme.primary),
              const SizedBox(height: 12),
            ],
            if (isEditMode) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Editando los datos generales del tercero existente (ID: $editingBPartnerId). Los cambios se actualizarán directamente en el sistema.',
                        style: TextStyle(fontSize: 12.5, color: colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: CustomTextField(
                    label: 'Nombre *',
                    controller: nameController,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomDropdown<int>(
                    label: 'Grupo de Tercero *',
                    value: bpGroupId,
                    items: bpGroups.map((g) {
                      return DropdownMenuItem<int>(
                        value: (g['id'] as num? ?? g['C_BP_Group_ID'] as num?)?.toInt(),
                        child: Text(g['Name'] ?? ''),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => bpGroupId = val),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomDropdown<int>(
                    label: 'Tipo de Identificación *',
                    value: taxIdTypeId,
                    items: taxIdTypes.map((t) {
                      return DropdownMenuItem<int>(
                        value: (t['id'] as num? ?? t['LCO_TaxIdType_ID'] as num?)?.toInt(),
                        child: Text(t['Name'] ?? ''),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => taxIdTypeId = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: CustomTextField(
                    label: 'Código (Value) *',
                    controller: valueController,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: CustomTextField(
                    label: 'Número Identificación',
                    controller: taxIdController,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: CustomDropdown<int>(
                    label: 'Rep. Comercial',
                    value: salesRepId,
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('Ninguno'),
                      ),
                      ...GlobalCache.salesReps.map((sr) {
                        return DropdownMenuItem<int>(
                          value: (sr['id'] as num? ?? sr['AD_User_ID'] as num?)?.toInt(),
                          child: Text(sr['Name'] ?? ''),
                        );
                      }),
                    ],
                    onChanged: (val) => setState(() => salesRepId = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Descripción',
              controller: descriptionController,
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            const Text('Roles del Tercero:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Cliente'),
                  selected: isCustomer,
                  onSelected: (val) => setState(() => isCustomer = val),
                ),
                FilterChip(
                  label: const Text('Proveedor'),
                  selected: isVendor,
                  onSelected: (val) => setState(() => isVendor = val),
                ),
                FilterChip(
                  label: const Text('Empleado'),
                  selected: isEmployee,
                  onSelected: (val) => setState(() => isEmployee = val),
                ),
                FilterChip(
                  label: const Text('Rep. Comercial'),
                  selected: isSalesRep,
                  onSelected: (val) => setState(() => isSalesRep = val),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        CustomButton(
          text: 'Volver',
          backgroundColor: Colors.grey,
          onPressed: isSaving
              ? null
              : () => setState(() {
                    isCreating = false;
                    editingBPartnerId = null;
                  }),
        ),
        CustomButton(
          text: isSaving
              ? 'Guardando...'
              : (isEditMode ? 'Guardar Cambios' : 'Crear Tercero'),
          backgroundColor: colorScheme.primary,
          isLoading: isSaving,
          onPressed: (isSaving ||
                  isLoadingDetails ||
                  nameController.text.trim().isEmpty ||
                  bpGroupId == null ||
                  taxIdTypeId == null ||
                  valueController.text.trim().isEmpty)
              ? null
              : _saveBPartner,
        ),
      ],
    );
  }
}
