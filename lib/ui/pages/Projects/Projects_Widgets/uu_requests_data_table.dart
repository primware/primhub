import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:primhub/ui/Shared_Custom/custom_table.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:primhub/ui/pages/Projects/dialogs/request_details_dialog.dart';
import 'package:go_router/go_router.dart';

import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ImagesManagment/fetch_attachments.dart';
import 'package:primhub/ImagesManagment/post_attachments.dart';
import 'package:primhub/ImagesManagment/download_attachments.dart';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/api/api_http.dart' as http;
import 'package:primhub/api/token.dart';
import 'package:primhub/ui/pages/Projects/Projects_Widgets/file_preview_manager.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart';
import 'package:primhub/ui/pages/Support/Requests/bulk_edit_request_dialog.dart';
import 'dart:math';
import 'package:flutter_html/flutter_html.dart';
import 'package:primhub/ui/Shared_Custom/animated_copy_widget.dart';
import 'package:flutter_localization/flutter_localization.dart';

class RequestsDataTable extends StatefulWidget {
  final List<Map<String, dynamic>> requests;
  final Map<String, int> statusIdMap;
  final Map<String, String> priorityMap;
  final Function(Map<String, dynamic>) onEdit;
  final VoidCallback? onRefresh;
  final bool showProjectContext;

  const RequestsDataTable({super.key, required this.requests, required this.statusIdMap, required this.priorityMap, required this.onEdit, this.onRefresh, this.showProjectContext = false});

  @override
  State<RequestsDataTable> createState() => _RequestsDataTableState();
}

class _RequestsDataTableState extends State<RequestsDataTable> {
  final ScrollController _scrollController = ScrollController();
  final Set<int> _selectedIds = {};
  int? _lastSelectedIndex;

  int _getRealId(Map<String, dynamic> req) => req['realId'] ?? req['_rawId'] ?? int.tryParse(req['id'].toString()) ?? 0;

  void _handleRowSelection(bool? selected, int index, int realId) {
    final isShiftPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) || HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);

    setState(() {
      if (isShiftPressed && _lastSelectedIndex != null) {
        int start = min(_lastSelectedIndex!, index);
        int end = max(_lastSelectedIndex!, index);
        for (int i = start; i <= end; i++) {
          final id = _getRealId(widget.requests[i]);
          if (selected == true) {
            _selectedIds.add(id);
          } else {
            _selectedIds.remove(id);
          }
        }
      } else {
        if (selected == true) {
          _selectedIds.add(realId);
        } else {
          _selectedIds.remove(realId);
        }
        _lastSelectedIndex = index;
      }
    });
  }

  void _handleSelectAll(bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedIds.addAll(widget.requests.map((r) => _getRealId(r)));
      } else {
        _selectedIds.clear();
      }
      _lastSelectedIndex = null;
    });
  }

  void _handleRowClick(Map<String, dynamic> req) {
    if (AccessControl.canManageRequests) {
      widget.onEdit(req);
    } else if (AccessControl.canViewRequestDetails) {
      showDialog(
        context: context,
        builder: (context) => RequestDetailsDialog(req: req),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CustomTable(
              showCheckboxColumn: false,
              columns: [
                if (AccessControl.canManageRequests)
                  DataColumn(
                    label: Checkbox(value: (widget.requests.isNotEmpty && _selectedIds.length == widget.requests.length) ? true : (_selectedIds.isNotEmpty ? null : false), tristate: true, onChanged: (val) => _handleSelectAll(val == true)),
                  ),
                const DataColumn(label: Text('#')),
                DataColumn(label: Text(AppLocale.actions.getString(context))),
                DataColumn(label: Text(AppLocale.request.getString(context))),
                DataColumn(label: Text(AppLocale.summary.getString(context))),
                if (widget.showProjectContext) DataColumn(label: Text(AppLocale.phase.getString(context))),
                if (widget.showProjectContext) DataColumn(label: Text(AppLocale.task.getString(context))),
                DataColumn(label: Text(AppLocale.requestType.getString(context))),
                DataColumn(label: Text(AppLocale.subject.getString(context))),
                DataColumn(label: Text(AppLocale.category.getString(context))),
                if (AccessControl.isAdmin) DataColumn(label: Text(AppLocale.clientPartner.getString(context).replaceAll(' *', ''))),
                if (AccessControl.isAdmin) DataColumn(label: Text(AppLocale.user.getString(context))),
                if (AccessControl.isAdmin) DataColumn(label: Text(AppLocale.salesRepresentative.getString(context))),
                DataColumn(label: Text(AppLocale.group.getString(context))),
                DataColumn(label: Text(AppLocale.status.getString(context))),
                DataColumn(label: Text(AppLocale.priority.getString(context))),
                DataColumn(label: Text(AppLocale.plannedEndDate.getString(context))),
                if (AccessControl.isRealAdmin) DataColumn(label: Text(AppLocale.confidentiality.getString(context))),
              ],
              rows: widget.requests.asMap().entries.map((entry) {
                final int index = entry.key;
                final Map<String, dynamic> req = entry.value;
                final int realId = _getRealId(req);
                return DataRow(
                  selected: _selectedIds.contains(realId),
                  onSelectChanged: (_) => _handleRowClick(req),
                  cells: [
                    if (AccessControl.canManageRequests) DataCell(Checkbox(value: _selectedIds.contains(realId), onChanged: (selected) => _handleRowSelection(selected, index, realId))),
                    DataCell(Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(AccessControl.canAddUpdates ? Icons.reply : Icons.forum),
                            tooltip: AccessControl.canAddUpdates ? 'Responder Solicitud' : 'Ver Actualizaciones',
                            onPressed: () {
                              final realId = _getRealId(req);
                              final encodedId = Uri.encodeComponent(realId.toString());
                              GoRouter.of(context).push('/request-updates/$encodedId', extra: {'docNo': req['id'].toString()});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.attach_file),
                            tooltip: AppLocale.attachments.getString(context),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => _RequestAttachmentsDialog(requestId: req['_rawId'] ?? req['realId'] ?? int.tryParse(req['id'].toString()) ?? 0, documentNo: req['DocumentNo']?.toString() ?? req['id'].toString()),
                              );
                            },
                          ),
                          if (AccessControl.canManageRequests)
                            IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: () => widget.onEdit(req))
                          else if (AccessControl.canViewRequestDetails)
                            IconButton(
                              icon: const Icon(Icons.visibility),
                              tooltip: AppLocale.viewDetails.getString(context),
                              onPressed: () => showDialog(
                                context: context,
                                builder: (context) => RequestDetailsDialog(req: req),
                              ),
                            ),
                        ],
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedCopyWidget(
                            textToCopy: req['id'].toString(),
                            snackBarMessage: AppLocale.codeCopied.getString(context),
                            leadingText: Text(req['id'].toString()),
                            iconSize: 16,
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Tooltip(
                        message: stripHtmlTags(DocumentsLogic.extractValue(req['Summary'])),
                        waitDuration: const Duration(milliseconds: 500),
                        child: SizedBox(
                          width: 250,
                          child: Html(
                            data: DocumentsLogic.extractValue(req['Summary']).toString(),
                            style: {
                              "body": Style(
                                margin: Margins.zero,
                                padding: HtmlPaddings.zero,
                                fontSize: FontSize(12),
                                maxLines: 2,
                                textOverflow: TextOverflow.ellipsis,
                              ),
                            },
                          ),
                        ),
                      ),
                    ),
                    if (widget.showProjectContext) DataCell(Text(req['phaseName'] ?? '-')),
                    if (widget.showProjectContext) DataCell(Text(req['taskName'] ?? 'General')),
                    DataCell(Text(DocumentsLogic.extractValue(req['R_RequestType_ID']))),
                    DataCell(
                      Tooltip(
                        message: () {
                          final text = req['CDS_EmailSubject']?.toString() ?? '';
                          return text.length > 2000 ? '${text.substring(0, 2000)}...' : text;
                        }(),
                        waitDuration: const Duration(milliseconds: 500),
                        child: Text(() {
                          final text = req['CDS_EmailSubject']?.toString() ?? '';
                          return text.length > 25 ? '${text.substring(0, 25)}...' : text;
                        }()),
                      ),
                    ),
                    DataCell(Text(DocumentsLogic.extractValue(req['R_Category_ID']))),
                    if (AccessControl.isAdmin) DataCell(Text(DocumentsLogic.extractValue(req['C_BPartner_ID']))),
                    if (AccessControl.isAdmin) DataCell(Text(DocumentsLogic.extractValue(req['AD_User_ID']))),
                    if (AccessControl.isAdmin) DataCell(Text(DocumentsLogic.extractValue(req['SalesRep_ID']))),
                    DataCell(Text(DocumentsLogic.extractValue(req['R_Group_ID']))),
                    DataCell(Text(cleanStatusName(DocumentsLogic.extractValue(req['R_Status_ID'])))),
                    DataCell(Text(DocumentsLogic.extractValue(req['Priority']))),
                    DataCell(Text(req['DateCompletePlan']?.toString().split('T')[0] ?? '')),
                    if (AccessControl.isRealAdmin) DataCell(Text(
                      (() {
                        final rawConf = req['original']?['ConfidentialType'] ?? req['ConfidentialType'];
                        final confVal = rawConf is Map ? rawConf['id']?.toString() ?? 'C' : rawConf?.toString() ?? 'C';
                        return confVal == 'I' ? AppLocale.internalNote.getString(context) : (confVal == 'C' ? AppLocale.visibleToClient.getString(context) : AppLocale.publicLabel.getString(context));
                      })()
                    )),
                  ],
                );
              }).toList(),
            ),
            // Espaciador animado para permitir scroll debajo del Toast flotante
            AnimatedContainer(duration: const Duration(milliseconds: 250), height: _selectedIds.isNotEmpty && AccessControl.canManageRequests ? 80.0 : 0.0),
          ],
        ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
            child: _selectedIds.isNotEmpty && AccessControl.canManageRequests
                ? Container(
                    key: const ValueKey('action_bar'),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_box, color: Theme.of(context).colorScheme.onSecondaryContainer),
                        const SizedBox(width: 8),
                        Text(
                          '${_selectedIds.length} solicitudes seleccionadas',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSecondaryContainer),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() {
                            _selectedIds.clear();
                            _lastSelectedIndex = null;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.edit),
                          label: Text(AppLocale.bulkEdit.getString(context)),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (context) => BulkEditRequestDialog(
                              selectedIds: _selectedIds,
                              onSaved: () {
                                setState(() {
                                  _selectedIds.clear();
                                  _lastSelectedIndex = null;
                                });
                                widget.onRefresh?.call();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('empty_bar')),
          ),
        ),
      ],
    );
  }
}

class _RequestAttachmentsDialog extends StatefulWidget {
  final int requestId;
  final String documentNo;

  const _RequestAttachmentsDialog({required this.requestId, required this.documentNo});

  @override
  State<_RequestAttachmentsDialog> createState() => _RequestAttachmentsDialogState();
}

class _RequestAttachmentsDialogState extends State<_RequestAttachmentsDialog> {
  List<Map<String, dynamic>> _attachments = [];
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  Future<void> _loadAttachments() async {
    setState(() => _isLoading = true);
    final tableName = '${Endpoint.baseUrl}/api/v1/models/R_Request';
    final attachments = await fetchAttachments(recordID: widget.requestId, tableName: tableName);
    if (mounted) {
      setState(() {
        _attachments = attachments;
        _isLoading = false;
      });
    }
  }

  Future<void> _uploadAttachment() async {
    if (!AccessControl.canManageFiles) {
      ToastMessage.show(context: context, message: 'No tienes permisos para subir archivos.', type: ToastType.help);
      return;
    }

    if (_attachments.length >= 4) {
      ToastMessage.show(context: context, message: 'Solo se pueden subir 4 Adjuntos', type: ToastType.warning);
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;

    setState(() => _isUploading = true);

    final tableName = '${Endpoint.baseUrl}/api/v1/models/R_Request';
    final file = result.files.first;

    final convertedFile = {'title': file.name, 'base64': base64Encode(file.bytes!)};
    final success = await postAttachments(recordID: widget.requestId, tableName: tableName, convertedFile: convertedFile);

    if (mounted) {
      setState(() => _isUploading = false);
      if (success) {
        ToastMessage.show(context: context, message: 'Archivo subido correctamente', type: ToastType.help);
        _loadAttachments();
      } else {
        ToastMessage.show(context: context, message: 'Error al subir archivo', type: ToastType.failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tableName = '${Endpoint.baseUrl}/api/v1/models/R_Request';

    return CustomModal(
      title: 'Adjuntos: ${widget.documentNo}',
      width: 500,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_attachments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Center(child: Text('No hay archivos adjuntos en esta solicitud.')),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              itemCount: _attachments.length,
              itemBuilder: (context, index) {
                final att = _attachments[index];
                return ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: Text(att['name'] ?? 'Sin nombre'),
                  onTap: () {
                    FilePreviewManager.showPreview(context, {'id': widget.requestId, 'Status': 'N/A', 'VersionNo': 'N/A'}, tableName, att['name'] ?? '', () async {
                      try {
                        setState(() => _isLoading = true);
                        final url = Uri.parse('$tableName/${widget.requestId}/attachments/${Uri.encodeComponent(att['name'] ?? '')}');
                        final response = await http.delete(url, headers: {'Authorization': Token.token});
                        if (response.statusCode == 200 || response.statusCode == 204) {
                          if (mounted) {
                            setState(() {
                              _attachments.removeWhere((item) => item['name'] == att['name']);
                              _isLoading = false;
                            });
                            ToastMessage.show(context: context, message: 'Adjunto eliminado', type: ToastType.help);
                          }
                        } else {
                          if (mounted) {
                            setState(() => _isLoading = false);
                            ToastMessage.show(context: context, message: 'Error al eliminar adjunto', type: ToastType.failure);
                          }
                        }
                      } catch (e) {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    }, () {}, canDelete: AccessControl.isAdmin || AccessControl.isSupport);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.download, color: Color(0xFF4F47E5)),
                    tooltip: 'Descargar',
                    onPressed: () => downloadAttachment(context: context, recordID: widget.requestId, tableName: tableName, fileName: att['name']),
                  ),
                );
              },
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        if (AccessControl.canManageFiles) CustomButton(text: 'Subir Archivo', icon: Icons.upload_file, isLoading: _isUploading, onPressed: _uploadAttachment),
      ],
    );
  }
}
