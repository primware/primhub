import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:primhub/ui/pages/Projects/Projects_Widgets/uu_requests_data_table.dart';
import 'package:primhub/ui/pages/Projects/dialogs/item_edit_dialog.dart';
import 'package:primhub/ui/pages/Support/Requests/edit_request_dialog.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart';
import 'package:primhub/ui/pages/Support/Requests/create_request_dialog.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:flutter_localization/flutter_localization.dart';

class TaskItem extends StatefulWidget {
  final Map<String, dynamic> task;
  final Map<String, dynamic>? phase;
  final bool initiallyExpanded;
  final Map<String, int> statusIdMap;
  final Map<String, String> priorityMap;
  final VoidCallback onRefresh;
  final Function(String type, int id, Map<String, dynamic> data) onEdit;
  final bool isArchived;
  final int projectId;

  const TaskItem({super.key, required this.task, this.phase, required this.initiallyExpanded, required this.statusIdMap, required this.priorityMap, required this.onRefresh, required this.onEdit, this.isArchived = false, required this.projectId});

  @override
  State<TaskItem> createState() => _TaskItemState();
}

class _TaskItemState extends State<TaskItem> {
  final ProjectsLogic _logic = ProjectsLogic();

  Future<List<Map<String, dynamic>>> _getTaskRequests(String? taskUU) async {
    if (taskUU == null || taskUU.isEmpty) return [];

    // 1. Intentar buscar en memoria primero
    final cached = GlobalCache.requests.where((r) => r['Record_UU'] == taskUU).toList();

    // 2. Si encontramos algo, lo devolvemos de inmediato
    if (cached.isNotEmpty) return cached;

    // 3. Si NO hay nada en memoria:
    //    - Si la carga completa (Fase 2) YA terminó, significa que realmente no hay solicitudes.
    //    - Si la carga completa NO ha terminado, pedimos a la API por si acaso.
    if (!GlobalCache.isFullyLoaded) {
      return await _logic.fetchRequestsForTask(taskUU);
    }

    return [];
  }

  String? _getDropdownValue(dynamic rawValue) {
    final extracted = DocumentsLogic.extractValue(rawValue);
    return extracted == 'N/A' ? null : extracted;
  }

  Future<void> _deleteRequest(dynamic id) async {
    if (!AccessControl.canManageRequests) {
      ToastMessage.show(context: context, message: 'No tienes permisos para eliminar solicitudes.', type: ToastType.help);
      return;
    }
    // Diálogo de confirmación simple
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: const Text('¿Está seguro de que desea eliminar esta solicitud?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await deleteRequestApi(id);
      if (mounted) {
        if (success) {
          ToastMessage.show(context: context, message: 'Solicitud eliminada correctamente', type: ToastType.help);
          setState(() {}); // Recargar la lista de solicitudes de la tarea
        } else {
          ToastMessage.show(context: context, message: 'Error al eliminar', type: ToastType.failure);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskId = widget.task['id'] is int ? widget.task['id'] as int : int.tryParse(widget.task['id'].toString()) ?? 0;
    final taskName = widget.task['Name'] ?? 'Tarea sin nombre';
    final rawUU = widget.task['C_ProjectTask_UU'] ?? widget.task['UUID'] ?? widget.task['uuid'] ?? widget.task['Record_UU'] ?? widget.task['uid'];
    String? taskUU;
    if (rawUU is String) taskUU = rawUU;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getTaskRequests(taskUU),
      builder: (context, snapshot) {
        final rawRequests = snapshot.data ?? [];
        final requests = rawRequests.map((r) {
          final newR = Map<String, dynamic>.from(r);
          newR['_rawId'] = r['id'];
          newR['id'] = r['DocumentNo'] ?? r['id'].toString();
          return newR;
        }).toList();
        final countText = snapshot.connectionState == ConnectionState.waiting ? '...' : '${requests.length}';

        return Container(
          margin: const EdgeInsets.only(left: 24, right: 12, bottom: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[100]!),
          ),
          child: ExpansionTile(
            key: Key('task-$taskId'),
            initiallyExpanded: widget.initiallyExpanded,
            backgroundColor: Colors.blue[50]?.withOpacity(0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            leading: CircleAvatar(
              backgroundColor: Colors.blue[50],
              radius: 14,
              child: Icon(Icons.task_alt_outlined, size: 16, color: Colors.blue[700]),
            ),
            title: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = MediaQuery.of(context).size.width < 500;
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        taskName,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: Colors.blue[900],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (requests.isNotEmpty && !isNarrow) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.description_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(countText, style: const TextStyle(fontSize: 12, color: Colors.grey))
                    ],
                  ],
                );
              }
            ),
            subtitle: widget.task['Description'] != null
                ? Text(
                    widget.task['Description'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  )
                : null,
            trailing: ((AccessControl.canCreateRequests || AccessControl.canEditProject) && !widget.isArchived)
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (AccessControl.canCreateRequests)
                        IconButton(
                          icon: const Icon(Icons.add_comment_outlined, size: 18, color: Colors.blue),
                          tooltip: AppLocale.createRequest.getString(context),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          onPressed: () async {
                            final result = await showDialog(
                              context: context,
                              builder: (context) => CreateRequestDialog(
                                linkedRecordUU: taskUU,
                                linkedProjectId: widget.projectId,
                                linkedPhaseId: widget.phase?['id'],
                                linkedTaskId: taskId,
                              ),
                            );
                            if (result == true) {
                              setState(() {}); // Refresca solo esta tarea
                            }
                          },
                        ),
                      if (AccessControl.canCreateRequests && AccessControl.canEditProject)
                        const SizedBox(width: 8),
                      if (AccessControl.canEditProject)
                        IconButton(
                          icon: const Icon(Icons.edit, size: 16, color: Colors.grey),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => ItemEditDialog(
                                type: 'task',
                                currentName: taskName,
                                currentDesc: widget.task['Description'] ?? '',
                                currentData: widget.task,
                                onSave: (data) => widget.onEdit('task', taskId, data),
                              ),
                            );
                          },
                        ),
                    ],
                  )
                : null,
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (requests.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: RequestsDataTable(
                    requests: requests,
                    statusIdMap: widget.statusIdMap,
                    priorityMap: widget.priorityMap,
                    onRefresh: () => setState(() {}),
                    onEdit: (req) {
                      if (!AccessControl.canManageRequests) return;

                      final int? currentStatusId = req['R_Status_ID'] is Map
                          ? req['R_Status_ID']['id']
                          : (req['R_Status_ID'] is int ? req['R_Status_ID'] : null);
                      
                      // Intentar obtener el nombre del estado directamente del registro para mayor precisión
                      String currentStatusName = req['R_Status_ID'] is Map 
                          ? (req['R_Status_ID']['identifier'] ?? req['R_Status_ID']['Name'] ?? '1_Open') 
                          : '1_Open';

                      // Si no está en el mapa de IDs, pero tenemos el nombre del registro, lo usamos.
                      // Solo buscamos en el mapa si el nombre del registro es genérico.
                      if (currentStatusId != null && (currentStatusName == '1_Open' || currentStatusName == 'Solicitud')) {
                        for (var entry in widget.statusIdMap.entries) {
                          if (entry.value == currentStatusId) {
                            currentStatusName = entry.key;
                            break;
                          }
                        }
                      }

                      final Map<String, dynamic> processedReq = {
                        'realId': req['_rawId'] ?? req['id'],
                        'id': req['id'].toString(),
                        'description': req['Summary'] ?? '',
                        'summary': req['Summary'] ?? '',
                        'emailSubject': req['CDS_EmailSubject'] ?? '',
                        'level': DocumentsLogic.extractValue(req['Priority']) == 'N/A'
                            ? 'Media'
                            : DocumentsLogic.extractValue(req['Priority']),
                        'status': currentStatusName,
                        'statusId': currentStatusId,
                        'dateStartPlan': req['DateStartPlan'] ?? '',
                        'dateCompletePlan': req['DateCompletePlan'] ?? '',
                        'startTime': extractTime(req['StartTime']),
                        'endTime': extractTime(req['EndTime']),
                        'qtyPlan': req['QtyPlan']?.toString() ?? '',
                        'type': _getDropdownValue(req['R_RequestType_ID']),
                        'category': _getDropdownValue(req['R_Category_ID']),
                        'group': _getDropdownValue(req['R_Group_ID']),
                        'salesRepId': req['SalesRep_ID'] is Map
                            ? req['SalesRep_ID']['id']
                            : (req['SalesRep_ID'] is int ? req['SalesRep_ID'] : null),
                        'bpId': req['C_BPartner_ID'] is Map
                            ? req['C_BPartner_ID']['id']
                            : (req['C_BPartner_ID'] is int ? req['C_BPartner_ID'] : null),
                        'userId': req['AD_User_ID'] is Map
                            ? req['AD_User_ID']['id']
                            : (req['AD_User_ID'] is int ? req['AD_User_ID'] : null),
                        'recordUU': req['Record_UU'], // Crucial para el diálogo de edición
                      };

                      showDialog(
                        context: context,
                        builder: (context) => EditRequestDialog(
                          request: processedReq,
                          statusIdMap: widget.statusIdMap,
                          priorityMap: widget.priorityMap,
                          onSave: () => setState(() {}),
                          onDelete: () => _deleteRequest(req['_rawId'] ?? req['id']),
                        ),
                      );
                    },
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    AppLocale.noRelatedRequests.getString(context),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
