import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:primhub/ui/Shared_Custom/searchable_dropdown.dart';
import 'package:primhub/ui/pages/Admin/user_management_logic.dart';

class UserModal extends StatefulWidget {
  final Map<String, dynamic>? user;
  final String? initialSearch;
  final List<Map<String, dynamic>> bPartners;
  final Map<int, String> roles; // (primhubRoles)
  final Map<int, String> allRoles; // (todas las roles del sistema)
  final VoidCallback onSuccess;

  const UserModal({
    super.key,
    required this.user,
    this.initialSearch,
    required this.bPartners,
    required this.roles,
    required this.allRoles,
    required this.onSuccess,
  });

  @override
  State<UserModal> createState() => _UserModalState();
}

class _UserModalState extends State<UserModal> {
  late bool isEditing;
  late TextEditingController nameController;
  late TextEditingController emailController;
  late TextEditingController passwordController;
  
  late List<Map<String, dynamic>> originalRoles;
  late List<Map<String, dynamic>> currentRoles;
  int? selectedBPartnerId;
  late bool isActive;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    isEditing = widget.user != null;
    
    String initialName = widget.user?['Name']?.toString() ?? '';
    String initialEmail = widget.user?['EMail']?.toString() ?? '';
    
    // Si estamos creando un nuevo usuario y vino de la verificación
    if (!isEditing && widget.initialSearch != null && widget.initialSearch!.isNotEmpty) {
      if (widget.initialSearch!.contains('@')) {
        initialEmail = widget.initialSearch!;
      } else {
        initialName = widget.initialSearch!;
      }
    }

    nameController = TextEditingController(text: initialName);
    emailController = TextEditingController(text: initialEmail);
    passwordController = TextEditingController();
    
    if (!isEditing) {
      passwordController.text = _generateSecurePassword();
    }
    
    originalRoles = widget.user != null ? List<Map<String, dynamic>>.from(widget.user!['RolesDetails'] ?? []) : [];
    currentRoles = List.from(originalRoles);
    
    selectedBPartnerId = widget.user?['C_BPartner_ID'];
    isActive = widget.user != null ? widget.user!['IsActive'] == true : true;
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String _generateSecurePassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()';
    final random = Random();
    return List.generate(12, (index) => chars[random.nextInt(chars.length)]).join();
  }

  @override
  Widget build(BuildContext context) {
    return CustomModal(
      title: isEditing ? 'Editar Usuario' : 'Nuevo Usuario',
      width: 600,
      content: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  label: 'Nombre *',
                  controller: nameController,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: CustomTextField(
                  label: 'Email *',
                  controller: emailController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SearchableDropdown<int>(
                  label: 'Tercero (Empresa) *',
                  value: selectedBPartnerId,
                  displayText: selectedBPartnerId != null 
                    ? widget.bPartners.firstWhere(
                        (e) => (e['id'] ?? e['C_BPartner_ID']) == selectedBPartnerId,
                        orElse: () => {'Name': 'Desconocido'})['Name']
                    : 'Seleccionar...',
                  onTap: () async {
                    final res = await SearchableDropdown.openSearchModal<int>(
                      context: context,
                      title: 'Buscar Tercero',
                      items: widget.bPartners,
                      currentValue: selectedBPartnerId,
                      getTitle: (i) => i['Name'] ?? '',
                      getValue: (i) => i['id'] ?? i['C_BPartner_ID'],
                    );
                    if (res != null) {
                      setState(() => selectedBPartnerId = res);
                    }
                  },
                ),
              ),
              if (!isEditing) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: CustomTextField(
                          label: 'Contraseña Inicial *',
                          controller: passwordController,
                          obscureText: false,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Generar nueva',
                        onPressed: () {
                          setState(() {
                            passwordController.text = _generateSecurePassword();
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copiar',
                        onPressed: () {
                          if (passwordController.text.isNotEmpty) {
                            Clipboard.setData(ClipboardData(text: passwordController.text));
                            ToastMessage.show(context: context, message: 'Contraseña copiada al portapapeles', type: ToastType.success);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Roles del Usuario:', style: TextStyle(fontWeight: FontWeight.bold)),
              CustomButton(
                text: 'Añadir Rol',
                icon: Icons.add,
                backgroundColor: Colors.blueGrey,
                onPressed: () async {
                  final entries = widget.roles.entries.map((e) => {'id': e.key, 'Name': e.value}).toList();
                  final res = await SearchableDropdown.openSearchModal<int>(
                    context: context,
                    title: 'Buscar Rol',
                    items: entries,
                    currentValue: null,
                    getTitle: (item) => item['Name'] ?? '',
                    getValue: (item) => item['id'],
                  );
                  if (res != null) {
                    if (!currentRoles.any((r) => r['roleId'] == res)) {
                      setState(() => currentRoles.add({'roleId': res, 'uuid': null}));
                    }
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              itemCount: currentRoles.length,
              itemBuilder: (context, i) {
                final rId = currentRoles[i]['roleId'];
                final roleName = widget.allRoles[rId] ?? 'Rol $rId';
                final isPrimhubRole = widget.roles.containsKey(rId);
                
                Color tagColor = Colors.grey.shade600;
                if (isPrimhubRole) {
                  if (roleName.toUpperCase().contains('ADMIN')) {
                    tagColor = Colors.blue.shade600; // Modo mixto
                  } else if (roleName.toUpperCase().contains('SUPPORT')) {
                    tagColor = Colors.orange.shade600; // Modo soporte
                  } else if (roleName.toUpperCase().contains('PROJECT')) {
                    tagColor = Colors.teal.shade600; // Modo proyecto
                  }
                }

                return ListTile(
                  title: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: tagColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: tagColor.withOpacity(0.5)),
                      ),
                      child: Text(
                        roleName,
                        style: TextStyle(color: tagColor, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                  trailing: isPrimhubRole
                      ? IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => CustomModal(
                          title: 'Quitar Rol',
                          content: Text('¿Está seguro de que desea quitar el rol ${widget.roles[rId] ?? 'Rol $rId'}?'),
                          actions: [
                            CustomButton(text: 'Cancelar', backgroundColor: Colors.grey, onPressed: () => Navigator.of(ctx).pop()),
                            CustomButton(
                              text: 'Confirmar',
                              backgroundColor: Colors.red,
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                setState(() => currentRoles.removeAt(i));
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : const SizedBox.shrink(),
                );
              },
            ),
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
          text: isSaving ? 'Guardando...' : 'Guardar',
          isLoading: isSaving,
          onPressed: isSaving ? null : () async {
            if (nameController.text.isEmpty || emailController.text.isEmpty || selectedBPartnerId == null) {
              ToastMessage.show(context: context, message: 'Por favor completa los campos obligatorios', type: ToastType.failure);
              return;
            }
            if (!isEditing && passwordController.text.isEmpty) {
              ToastMessage.show(context: context, message: 'La contraseña inicial es obligatoria', type: ToastType.failure);
              return;
            }
            if (currentRoles.isEmpty) {
              ToastMessage.show(context: context, message: 'El usuario debe tener al menos un rol asignado', type: ToastType.failure);
              return;
            }
            
            setState(() => isSaving = true);
            
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
            
            final String? userUuid = widget.user != null ? widget.user!['uuid']?.toString().trim() : null;

            final success = await UserManagementLogic.saveUser(
              uuid: (userUuid != null && userUuid.isNotEmpty) ? userUuid : null,
              userId: widget.user != null ? (widget.user!['AD_User_ID'] as num?)?.toInt() : null,
              name: nameController.text.trim(),
              email: emailController.text.trim(),
              rolesToAdd: rolesToAdd,
              rolesToRemove: rolesToRemove,
              bPartnerId: selectedBPartnerId!,
              password: !isEditing && passwordController.text.isNotEmpty ? passwordController.text : null,
              isActive: isActive,
            );

            if (success && mounted) {
              Navigator.of(context).pop();
              ToastMessage.show(context: context, message: 'Usuario guardado correctamente', type: ToastType.success);
              widget.onSuccess();
            } else if (mounted) {
              setState(() => isSaving = false);
              ToastMessage.show(context: context, message: 'No se pudo guardar el usuario', type: ToastType.failure);
            }
          },
        ),
      ],
    );
  }
}
