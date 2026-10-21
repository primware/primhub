import 'package:flutter/material.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/searchable_dropdown.dart';

import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:primhub/ui/pages/Admin/user_management_logic.dart';

class TeamModal extends StatefulWidget {
  final Map<String, dynamic>? team;
  final List<Map<String, dynamic>> allUsers;
  final List<Map<String, dynamic>> bPartners;
  final VoidCallback onSuccess;

  const TeamModal({
    super.key,
    required this.team,
    required this.allUsers,
    required this.bPartners,
    required this.onSuccess,
  });

  @override
  State<TeamModal> createState() => _TeamModalState();
}

class _TeamModalState extends State<TeamModal> {
  late bool isEditing;
  int? selectedBPartnerId;
  late List<dynamic> currentUsers;
  late Set<int> selectedUserIds;
  String searchUserQuery = "";
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    isEditing = widget.team != null;
    selectedBPartnerId = isEditing ? widget.team!['C_BPartner_ID'] : null;
    currentUsers = isEditing ? widget.team!['Users'] : [];
    selectedUserIds = currentUsers.map((u) => u['AD_User_ID'] as int).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final displayUsers = widget.allUsers.where((u) {
      if (searchUserQuery.isEmpty) return true;
      final q = searchUserQuery.toLowerCase();
      final validRolesStr = (u['ValidRoleNames'] ?? '').toString().toLowerCase();
      final bool hasValidRole = u['HasValidRole'] == true && validRolesStr.isNotEmpty;
      final statusStr = hasValidRole ? validRolesStr : 'sin acceso al primhub';

      return (u['Name'] ?? '').toString().toLowerCase().contains(q) || 
             (u['EMail'] ?? '').toString().toLowerCase().contains(q) ||
             statusStr.contains(q);
    }).toList();

    int? currentSalesRepId;
    String? currentSalesRepName;
    if (selectedBPartnerId != null) {
      final bp = widget.bPartners.firstWhere(
        (e) => (e['id'] ?? e['C_BPartner_ID']) == selectedBPartnerId, 
        orElse: () => {}
      );
      final sr = bp['SalesRep_ID'];
      if (sr != null) {
        if (sr is Map) {
          currentSalesRepId = sr['id'] is int ? sr['id'] : int.tryParse(sr['id'].toString());
          if (sr['identifier'] != null) {
            currentSalesRepName = sr['identifier'].toString();
          }
        } else {
          currentSalesRepId = int.tryParse(sr.toString());
        }
      }
      if (currentSalesRepId != null && currentSalesRepName == null) {
        final srUser = widget.allUsers.cast<Map<String, dynamic>?>().firstWhere(
          (u) => (u?['AD_User_ID'] ?? u?['id']) == currentSalesRepId,
          orElse: () => null,
        );
        currentSalesRepName = srUser?['Name'] ?? 'ID $currentSalesRepId';
      }
    }

    return CustomModal(
      title: isEditing ? 'Editar Equipo: ${widget.team!['Name']}' : 'Crear Nuevo Equipo',
      width: 700,
      height: 600,
      scrollable: false,
      content: Column(
        children: [
          if (!isEditing) ...[
            SearchableDropdown<int>(
              label: 'Seleccionar Tercero',
              value: selectedBPartnerId,
              displayText: selectedBPartnerId != null
                  ? widget.bPartners.firstWhere(
                      (e) => (e['id'] ?? e['C_BPartner_ID']) == selectedBPartnerId,
                      orElse: () => {'Name': 'Desconocido'})['Name']
                  : 'Seleccionar empresa...',
              onTap: () async {
                final res = await SearchableDropdown.openSearchModal<int>(
                  context: context,
                  title: 'Buscar Empresa',
                  items: widget.bPartners,
                  currentValue: selectedBPartnerId,
                  getTitle: (i) => i['Name'] ?? '',
                  getValue: (i) => i['id'] ?? i['C_BPartner_ID'],
                );
                if (res != null) {
                  setState(() {
                    selectedBPartnerId = res;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
          ],
          if (selectedBPartnerId != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.star_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Rep. Comercial (Supuesto Líder): ',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        children: [
                          TextSpan(
                            text: currentSalesRepName ?? 'Sin asignar en este tercero',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (currentSalesRepId != null)
                            TextSpan(
                              text: selectedUserIds.contains(currentSalesRepId)
                                  ? '  •  (Agregado al equipo)'
                                  : '  •  (No incluido - márquelo en la lista abajo si desea agregarlo)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selectedUserIds.contains(currentSalesRepId)
                                    ? Colors.green.shade700
                                    : Colors.orange.shade800,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          CustomTextField(
            label: 'Buscar Usuario a añadir/quitar',
            prefixIcon: const Icon(Icons.search),
            onChanged: (val) => setState(() => searchUserQuery = val),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: displayUsers.length,
                itemBuilder: (context, index) {
                  final u = displayUsers[index];
                  final uId = u['AD_User_ID'] as int;
                  final isLeader = currentSalesRepId != null && uId == currentSalesRepId;
                  final isSelected = selectedUserIds.contains(uId);
                  
                  return CheckboxListTile(
                    title: Row(
                      children: [
                        Flexible(child: Text(u['Name'] ?? '')),
                        if (isLeader) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, color: Theme.of(context).colorScheme.primary, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'Rep. Comercial / Supuesto Líder',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ]
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if ((u['EMail'] ?? '').toString().isNotEmpty)
                            Text(
                              u['EMail'].toString(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (u['HasValidRole'] == true && (u['ValidRoleNames'] ?? '').toString().trim().isNotEmpty)
                                Tooltip(
                                  message: u['ValidRoleNames'].toString(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.shield_outlined,
                                          size: 13,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            u['ValidRoleNames'].toString(),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: Colors.red.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        size: 13,
                                        color: Colors.red.shade700,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Sin acceso al Primhub',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.red.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if ((u['Company'] ?? '').toString().trim().isNotEmpty && u['Company'] != 'Ninguna')
                                Text(
                                  '• ${u['Company']}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    value: isSelected,
                    activeColor: Theme.of(context).colorScheme.primary,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          selectedUserIds.add(uId);
                        } else {
                          selectedUserIds.remove(uId);
                        }
                      });
                    },
                  );
                }
              ),
            ),
          )
        ]
      ),
      actions: [
        CustomButton(text: 'Cancelar', backgroundColor: Colors.grey, onPressed: () => Navigator.pop(context)),
        CustomButton(
          text: isSaving ? 'Guardando...' : 'Guardar Equipo', 
          backgroundColor: Colors.teal, 
          isLoading: isSaving,
          onPressed: (selectedBPartnerId == null || selectedUserIds.isEmpty || isSaving) 
            ? null 
            : () async {
            setState(() => isSaving = true);
            
            List<int> usersToAdd = [];
            List<int> idsToRemove = [];
            final oldUserIds = currentUsers.map((u) => u['AD_User_ID'] as int).toSet();
            
            for (var id in selectedUserIds) {
              if (!oldUserIds.contains(id)) usersToAdd.add(id);
            }
            
            for (var u in currentUsers) {
              if (!selectedUserIds.contains(u['AD_User_ID'])) {
                if (u['DevTeamID'] != null) idsToRemove.add(u['DevTeamID']);
              }
            }
            
            bool success = await UserManagementLogic.saveTeam(selectedBPartnerId!, usersToAdd, idsToRemove);
            
            if (success) {
              if (mounted) {
                Navigator.pop(context);
                ToastMessage.show(context: context, message: 'Equipo guardado correctamente', type: ToastType.success);
                widget.onSuccess();
              }
            } else {
              setState(() => isSaving = false);
              if (mounted) ToastMessage.show(context: context, message: 'Error al guardar equipo', type: ToastType.failure);
            }
          }
        ),
      ],
    );
  }
}
