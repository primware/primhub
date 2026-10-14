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
      return (u['Name'] ?? '').toString().toLowerCase().contains(searchUserQuery.toLowerCase()) || 
             (u['EMail'] ?? '').toString().toLowerCase().contains(searchUserQuery.toLowerCase());
    }).toList();

    int? currentSalesRepId;
    if (selectedBPartnerId != null) {
      final bp = widget.bPartners.firstWhere(
        (e) => (e['id'] ?? e['C_BPartner_ID']) == selectedBPartnerId, 
        orElse: () => {}
      );
      final sr = bp['SalesRep_ID'];
      if (sr != null) {
        if (sr is Map) {
          currentSalesRepId = sr['id'] is int ? sr['id'] : int.tryParse(sr['id'].toString());
        } else {
          currentSalesRepId = int.tryParse(sr.toString());
        }
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
                    // Eliminar al líder anterior si se cambia de tercero
                    if (selectedBPartnerId != null) {
                      final oldBp = widget.bPartners.firstWhere(
                        (e) => (e['id'] ?? e['C_BPartner_ID']) == selectedBPartnerId, 
                        orElse: () => {}
                      );
                      final oldSr = oldBp['SalesRep_ID'];
                      if (oldSr != null) {
                        int? oldSrId;
                        if (oldSr is Map) {
                          oldSrId = oldSr['id'] is int ? oldSr['id'] : int.tryParse(oldSr['id'].toString());
                        } else {
                          oldSrId = int.tryParse(oldSr.toString());
                        }
                        if (oldSrId != null) {
                          selectedUserIds.remove(oldSrId);
                        }
                      }
                    }

                    selectedBPartnerId = res;
                    
                    // Auto-añadir al representante comercial si el BPartner lo tiene
                    final bp = widget.bPartners.firstWhere(
                      (e) => (e['id'] ?? e['C_BPartner_ID']) == res, 
                      orElse: () => {}
                    );
                    
                    final sr = bp['SalesRep_ID'];
                    if (sr != null) {
                      int? srId;
                      if (sr is Map) {
                        srId = sr['id'] is int ? sr['id'] : int.tryParse(sr['id'].toString());
                      } else {
                        srId = int.tryParse(sr.toString());
                      }
                      if (srId != null) {
                        selectedUserIds.add(srId);
                      }
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),
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
                  final isSelected = selectedUserIds.contains(uId) || isLeader;
                  
                  return CheckboxListTile(
                    title: Row(
                      children: [
                        Flexible(child: Text(u['Name'] ?? '')),
                        if (isLeader) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.star, color: Theme.of(context).colorScheme.primary, size: 16),
                        ],
                      ]
                    ),
                    subtitle: Text(u['EMail'] ?? ''),
                    value: isSelected,
                    activeColor: Theme.of(context).colorScheme.primary,
                    onChanged: isLeader ? null : (val) {
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
