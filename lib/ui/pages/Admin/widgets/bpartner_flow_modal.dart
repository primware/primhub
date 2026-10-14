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
        if (bpGroups.isNotEmpty) bpGroupId = (bpGroups.first['id'] as num? ?? bpGroups.first['C_BP_Group_ID'] as num?)?.toInt();
        if (taxIdTypes.isNotEmpty) taxIdTypeId = (taxIdTypes.first['id'] as num? ?? taxIdTypes.first['LCO_TaxIdType_ID'] as num?)?.toInt();
      });
    }
  }

  List<Map<String, dynamic>> matchingBPartners = [];

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
      isCreating = true;
      nameController.text = defaultName;
    });
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
    if (salesRepId != null) payload['SalesRep_ID'] = salesRepId;

    final success = await UserManagementLogic.saveBPartner(payload);

    if (!mounted) return;
    setState(() => isSaving = false);

    if (success) {
      Navigator.pop(context);
      ToastMessage.show(context: context, message: 'Tercero creado correctamente', type: ToastType.success);
      widget.onSuccess();
    } else {
      ToastMessage.show(context: context, message: 'Error al crear Tercero', type: ToastType.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isCreating) {
      return CustomModal(
        title: 'Verificar Existencia de Tercero',
        width: 500,
        content: Column(
          children: [
            const Text('Antes de crear un nuevo Tercero, busque por Código o Nombre para verificar que no exista ya en el sistema.'),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Buscar (ej. RUC, CI o Nombre)',
              controller: searchController,
              prefixIcon: const Icon(Icons.search),
              onSubmitted: (_) => _checkExists(),
            ),
            if (matchingBPartners.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Resultados encontrados:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: matchingBPartners.length,
                  itemBuilder: (context, index) {
                    final bp = matchingBPartners[index];
                    return ListTile(
                      leading: const Icon(Icons.business),
                      title: Text(bp['Name'] ?? 'Sin nombre'),
                      subtitle: Text(bp['Value'] ?? 'Sin código'),
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
            backgroundColor: Theme.of(context).colorScheme.primary,
            isLoading: isChecking,
            onPressed: isChecking ? null : _checkExists,
          ),
        ],
      );
    }

    return CustomModal(
      title: 'Crear Nuevo Tercero / Empresa',
      width: 700,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
          onPressed: () => setState(() => isCreating = false),
        ),
        CustomButton(
          text: isSaving ? 'Guardando...' : 'Crear Tercero',
          backgroundColor: Colors.teal,
          isLoading: isSaving,
          onPressed: (isSaving || nameController.text.trim().isEmpty || bpGroupId == null || taxIdTypeId == null) ? null : _saveBPartner,
        ),
      ],
    );
  }
}
