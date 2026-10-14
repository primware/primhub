import 'dart:io';

void main() {
  final file = File('lib/ui/pages/Admin/user_management_page.dart');
  var content = file.readAsStringSync();

  // Add import
  if (!content.contains('searchable_dropdown.dart')) {
    content = content.replaceFirst(
      "import 'package:primhub/ui/pages/Admin/user_management_logic.dart';",
      "import 'package:primhub/ui/pages/Admin/user_management_logic.dart';\nimport 'package:primhub/ui/Shared_Custom/searchable_dropdown.dart';"
    );
  }

  // Rewrite _showUserModal
  final modalStart = content.indexOf('void _showUserModal');
  final modalEnd = content.indexOf('Future<void> _toggleUserActive');
  
  if (modalStart != -1 && modalEnd != -1) {
    const newModal = '''
  void _showUserModal(Map<String, dynamic>? user) {
    final bool isEditing = user != null;
    final nameController = TextEditingController(text: user?['Name']?.toString() ?? '');
    final emailController = TextEditingController(text: user?['EMail']?.toString() ?? '');
    final passwordController = TextEditingController();
    
    // Roles state
    List<Map<String, dynamic>> originalRoles = user != null ? List<Map<String, dynamic>>.from(user['RolesDetails'] ?? []) : [];
    List<Map<String, dynamic>> currentRoles = List.from(originalRoles);
    
    int? selectedBPartnerId = user?['C_BPartner_ID'];
    bool isActive = user?['IsActive'] == true;

    showDialog(
      context: context,
      builder: (modalContext) => StatefulBuilder(
        builder: (context, setModalState) {
          return CustomModal(
            title: isEditing ? 'Editar Usuario' : 'Nuevo Usuario',
            width: 600,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text('Activo'),
                  value: isActive,
                  onChanged: (val) => setModalState(() => isActive = val),
                ),
                CustomTextField(
                  controller: nameController,
                  label: 'Nombre Completo',
                  prefixIcon: const Icon(Icons.person),
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: emailController,
                  label: 'Correo Electrónico',
                  prefixIcon: const Icon(Icons.email),
                ),
                const SizedBox(height: 16),
                SearchableDropdown<int>(
                  label: 'Tercero / Empresa',
                  value: selectedBPartnerId,
                  displayText: selectedBPartnerId != null 
                      ? _bPartners.firstWhere((bp) => (bp['id'] ?? bp['C_BPartner_ID']) == selectedBPartnerId, orElse: () => {})['Name'] ?? ''
                      : '',
                  onTap: () async {
                    final res = await SearchableDropdown.openSearchModal<int>(
                      context: context,
                      title: 'Empresa',
                      items: _bPartners,
                      currentValue: selectedBPartnerId,
                      getTitle: (item) => item['Name'] ?? '',
                      getValue: (item) => (item['id'] ?? item['C_BPartner_ID'] as num).toInt(),
                    );
                    if (res != null) setModalState(() => selectedBPartnerId = res);
                  },
                ),
                const SizedBox(height: 16),
                if (!isEditing) ...[
                  CustomTextField(
                    controller: passwordController,
                    label: 'Contraseña Inicial (Obligatoria)',
                    prefixIcon: const Icon(Icons.lock),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  CustomTextField(
                    controller: passwordController,
                    label: 'Nueva Contraseña (Opcional)',
                    prefixIcon: const Icon(Icons.lock),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                ],
                
                // --- Roles Section ---
                const Text('Roles Asignados', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: currentRoles.length,
                    itemBuilder: (ctx, i) {
                      final rId = currentRoles[i]['roleId'];
                      return ListTile(
                        dense: true,
                        title: Text(_roles[rId] ?? 'Rol \$rId'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                          onPressed: () => setModalState(() => currentRoles.removeAt(i)),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                CustomButton(
                  text: 'Añadir Rol',
                  icon: Icons.add,
                  backgroundColor: Colors.blueGrey,
                  onPressed: () async {
                    final res = await SearchableDropdown.openSearchModal<int>(
                      context: context,
                      title: 'Rol',
                      items: _roles.entries.toList(),
                      currentValue: null,
                      getTitle: (item) => item.value,
                      getValue: (item) => item.key,
                    );
                    if (res != null) {
                      if (!currentRoles.any((r) => r['roleId'] == res)) {
                        setModalState(() => currentRoles.add({'roleId': res, 'uuid': null}));
                      }
                    }
                  },
                ),
              ],
            ),
            actions: [
              CustomButton(
                text: 'Cancelar',
                backgroundColor: Colors.grey,
                onPressed: () => Navigator.of(context).pop(),
              ),
              CustomButton(
                text: 'Guardar',
                onPressed: () async {
                  if (nameController.text.isEmpty || emailController.text.isEmpty || selectedBPartnerId == null) {
                    ToastMessage.show(context: context, message: 'Por favor completa los campos obligatorios', type: ToastType.failure);
                    return;
                  }
                  if (!isEditing && passwordController.text.isEmpty) {
                    ToastMessage.show(context: context, message: 'La contraseña inicial es obligatoria', type: ToastType.failure);
                    return;
                  }
                  
                  // Calcular diff de roles
                  List<int> rolesToAdd = [];
                  List<String> rolesToRemove = [];
                  
                  for (var r in currentRoles) {
                    if (r['uuid'] == null) rolesToAdd.add(r['roleId']);
                  }
                  for (var r in originalRoles) {
                    if (!currentRoles.any((cr) => cr['uuid'] == r['uuid'])) {
                      rolesToRemove.add(r['uuid']);
                    }
                  }
                  
                  final success = await UserManagementLogic.saveUser(
                    uuid: user?['uuid']?.toString(),
                    name: nameController.text.trim(),
                    email: emailController.text.trim(),
                    rolesToAdd: rolesToAdd,
                    rolesToRemove: rolesToRemove,
                    bPartnerId: selectedBPartnerId!,
                    password: passwordController.text.isNotEmpty ? passwordController.text : null,
                    isActive: isActive,
                  );

                  if (success && mounted) {
                    Navigator.of(context).pop();
                    ToastMessage.show(context: context, message: 'Usuario guardado correctamente', type: ToastType.success);
                    _loadData();
                  } else if (mounted) {
                    ToastMessage.show(context: context, message: 'No se pudo guardar el usuario', type: ToastType.failure);
                  }
                },
              ),
            ],
          );
        }
      ),
    );
  }
  ''';
    content = content.replaceRange(modalStart, modalEnd, newModal);
  }

  // Replace _buildUserFilters dropdowns
  final filtersStart = content.indexOf('Widget _buildUserFilters()');
  final filtersEnd = content.indexOf('Widget _buildTeamsTab()');
  
  if (filtersStart != -1 && filtersEnd != -1) {
    var filtersStr = content.substring(filtersStart, filtersEnd);
    
    filtersStr = filtersStr.replaceAll(
      '''                Expanded(
                  child: CustomDropdown<int?>(
                    label: 'Filtrar por Rol',
                    value: _filterRoleId,
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Todos los roles')),
                      ..._roles.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    ],
                    onChanged: (val) => setState(() => _filterRoleId = val),
                  ),
                ),''',
      '''                Expanded(
                  child: SearchableDropdown<int?>(
                    label: 'Filtrar por Rol',
                    value: _filterRoleId,
                    displayText: _filterRoleId != null ? _roles[_filterRoleId] ?? '' : 'Todos los roles',
                    onTap: () async {
                      final res = await SearchableDropdown.openSearchModal<int?>(
                        context: context,
                        title: 'Rol',
                        items: [{'key': null, 'value': 'Todos los roles'}, ..._roles.entries.map((e) => {'key': e.key, 'value': e.value})],
                        currentValue: _filterRoleId,
                        getTitle: (item) => item['value'],
                        getValue: (item) => item['key'],
                      );
                      if (res != null || res == null) setState(() => _filterRoleId = res);
                    },
                  ),
                ),'''
    );
    
    filtersStr = filtersStr.replaceAll(
      '''                Expanded(
                  child: CustomDropdown<int?>(
                    label: 'Filtrar por Tercero',
                    value: _filterBPartnerId,
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Todos los terceros')),
                      ..._bPartners.map((bp) => DropdownMenuItem(
                            value: (bp['id'] ?? bp['C_BPartner_ID'] as num?)?.toInt(),
                            child: Text(bp['Name'] ?? ''),
                          ))
                    ],
                    onChanged: (val) => setState(() => _filterBPartnerId = val),
                  ),
                ),''',
      '''                Expanded(
                  child: SearchableDropdown<int?>(
                    label: 'Filtrar por Tercero',
                    value: _filterBPartnerId,
                    displayText: _filterBPartnerId != null 
                        ? _bPartners.firstWhere((bp) => (bp['id'] ?? bp['C_BPartner_ID']) == _filterBPartnerId, orElse: () => {})['Name'] ?? ''
                        : 'Todos los terceros',
                    onTap: () async {
                      final items = [{'id': null, 'Name': 'Todos los terceros'}, ..._bPartners];
                      final res = await SearchableDropdown.openSearchModal<int?>(
                        context: context,
                        title: 'Tercero',
                        items: items,
                        currentValue: _filterBPartnerId,
                        getTitle: (item) => item['Name'] ?? '',
                        getValue: (item) => item['id'] ?? item['C_BPartner_ID'],
                      );
                      if (res != null || res == null) setState(() => _filterBPartnerId = res);
                    },
                  ),
                ),'''
    );
    
    content = content.replaceRange(filtersStart, filtersEnd, filtersStr);
  }

  file.writeAsStringSync(content);
}
