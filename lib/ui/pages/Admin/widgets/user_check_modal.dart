import 'package:flutter/material.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:primhub/ui/pages/Admin/user_management_logic.dart';

class UserCheckModal extends StatefulWidget {
  final Function(String query) onProceedToCreate;
  final Function(Map<String, dynamic> user) onSelectExistingUser;

  const UserCheckModal({
    super.key,
    required this.onProceedToCreate,
    required this.onSelectExistingUser,
  });

  @override
  State<UserCheckModal> createState() => _UserCheckModalState();
}

class _UserCheckModalState extends State<UserCheckModal> {
  final TextEditingController searchController = TextEditingController();
  bool isChecking = false;
  List<Map<String, dynamic>> matchingUsers = [];

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _checkExists() async {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      ToastMessage.show(context: context, message: 'Ingrese un correo o nombre', type: ToastType.warning);
      return;
    }

    setState(() {
      isChecking = true;
      matchingUsers.clear();
    });
    
    final existing = await UserManagementLogic.checkUserExists(query);
    
    if (!mounted) return;
    setState(() => isChecking = false);

    if (existing.isNotEmpty) {
      setState(() => matchingUsers = existing);
    } else {
      _proceedToCreate();
    }
  }

  void _proceedToCreate() {
    Navigator.pop(context); // Cerrar el modal de check
    widget.onProceedToCreate(searchController.text.trim());
  }

  void _selectExistingUser(Map<String, dynamic> user) {
    Navigator.pop(context); // Cerrar el modal de check
    widget.onSelectExistingUser(user);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return CustomModal(
      title: 'Verificar Existencia de Usuario',
      width: 540,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Antes de crear un nuevo Usuario, busque por Correo o Nombre para verificar si ya existe en el sistema.',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          CustomTextField(
            label: 'Buscar (ej. correo@empresa.com o Nombre)',
            controller: searchController,
            prefixIcon: const Icon(Icons.search),
            onSubmitted: (_) => _checkExists(),
          ),
          if (matchingUsers.isNotEmpty) ...[
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
                itemCount: matchingUsers.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: colorScheme.outline.withOpacity(0.15)),
                itemBuilder: (context, index) {
                  final u = matchingUsers[index];
                  final userName = (u['Name'] ?? 'Sin nombre').toString();
                  final userEmail = (u['EMail'] ?? 'Sin correo').toString();

                  return Tooltip(
                    message: 'Clic para editar usuario',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _selectExistingUser(u),
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
                              child: Icon(Icons.person_rounded, size: 20, color: colorScheme.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    userEmail,
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
        if (matchingUsers.isNotEmpty)
          CustomButton(
            text: 'Crear de todos modos',
            backgroundColor: Colors.orange,
            onPressed: _proceedToCreate,
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
}
