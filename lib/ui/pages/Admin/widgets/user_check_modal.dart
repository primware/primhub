import 'package:flutter/material.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:primhub/ui/pages/Admin/user_management_logic.dart';

class UserCheckModal extends StatefulWidget {
  final Function(String query) onProceedToCreate;

  const UserCheckModal({super.key, required this.onProceedToCreate});

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

  @override
  Widget build(BuildContext context) {
    return CustomModal(
      title: 'Verificar Existencia de Usuario',
      width: 500,
      content: Column(
        children: [
          const Text('Antes de crear un nuevo Usuario, busque por Correo o Nombre para verificar que no exista ya en el sistema.'),
          const SizedBox(height: 16),
          CustomTextField(
            label: 'Buscar (ej. correo@empresa.com o Nombre)',
            controller: searchController,
            prefixIcon: const Icon(Icons.search),
            onSubmitted: (_) => _checkExists(),
          ),
          if (matchingUsers.isNotEmpty) ...[
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
                itemCount: matchingUsers.length,
                itemBuilder: (context, index) {
                  final u = matchingUsers[index];
                  return ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(u['Name'] ?? 'Sin nombre'),
                    subtitle: Text(u['EMail'] ?? 'Sin correo'),
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
          backgroundColor: Theme.of(context).colorScheme.primary,
          isLoading: isChecking,
          onPressed: isChecking ? null : _checkExists,
        ),
      ],
    );
  }
}
