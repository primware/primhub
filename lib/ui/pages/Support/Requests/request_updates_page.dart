import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter_quill/flutter_quill.dart' hide Style;
import 'package:primhub/ui/pages/Support/Requests/html_editor_utils.dart';
import 'package:primhub/api/api_http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/pages/Support/Requests/request_functions.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ImagesManagment/fetch_attachments.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:primhub/ui/Shared_Custom/help_icon.dart';
import 'package:flutter_localization/flutter_localization.dart';

class RequestUpdatesPage extends StatefulWidget {
  final int requestId;
  final String docNo;

  const RequestUpdatesPage({super.key, required this.requestId, required this.docNo});

  @override
  State<RequestUpdatesPage> createState() => _RequestUpdatesPageState();
}

class _RequestUpdatesPageState extends State<RequestUpdatesPage> {
  late Future<List<Map<String, dynamic>>> _updatesFuture;
  Map<String, dynamic>? _requestDetails;
  String? _memoizedDescription;


  @override
  void initState() {
    super.initState();
    _fetchDetails();
    _refreshUpdates();
  }

  Future<void> _fetchDetails({bool forceNetwork = false}) async {
    try {

      // 1. INTENTO EN CACHÉ (Instantáneo si no se fuerza red)
      if (!forceNetwork) {
        var cached = GlobalCache.requests.where((r) => r['id']?.toString() == widget.requestId.toString()).toList();

        // Buscar también en la caché de proyectos
        if (cached.isEmpty) {
          for (var projList in GlobalCache.projectRequestsCache.values) {
            final foundInProj = projList.where((r) => r['id']?.toString() == widget.requestId.toString()).toList();
            if (foundInProj.isNotEmpty) {
              cached = foundInProj;
              break;
            }
          }
        }

        if (cached.isNotEmpty) {
          _handleFoundRequest(cached.first);
          return;
        }
      }

      // 2. INTENTO API POR ID (Búsqueda principal y más precisa)
      final reqsId = await fetchRequest(
        filter: "id eq ${widget.requestId}",
      );

      if (reqsId.isNotEmpty) {
        _handleFoundRequest(reqsId.first);
        return;
      }

      // 3. INTENTO API POR DOCUMENT NO (Respaldo si el ID no funcionó)
      if (widget.docNo.isNotEmpty && widget.docNo != widget.requestId.toString()) {
        final reqsDoc = await fetchRequest(
          filter: "DocumentNo eq '${widget.docNo}'",
        );
        if (reqsDoc.isNotEmpty) {
          _handleFoundRequest(reqsDoc.first);
          return;
        }
      }

      

    } catch (_) {
      // Ignored: Fail silently
    }
  }

  void _handleFoundRequest(Map<String, dynamic> details) {
    if (!mounted) return;
    
    final realId = details['id'] is int ? details['id'] : int.tryParse(details['id']?.toString() ?? '');

    if (realId != null && realId != widget.requestId) {
      _refreshUpdates(realId);
    }

    setState(() {
      _requestDetails = details;
      
      // Pre-calcular descripción para evitar lag en renderizado
      final fields = ['Description', 'description', 'Help', 'help', 'Result', 'result'];
      _memoizedDescription = 'Sin descripción adicional.';
      for (var f in fields) {
        final val = details[f]?.toString();
        if (val != null && val.trim().isNotEmpty && val != 'null') {
          _memoizedDescription = val;
          break;
        }
      }
    });
  }

  void _refreshUpdates([int? id]) {
    final targetId = id ?? widget.requestId;
    setState(() {
      _updatesFuture = fetchRequestUpdates(targetId).then((list) {
        // Filtrar actualizaciones de transferencia automática del backend
        list = list.where((update) {
          final result = update['Result']?.toString() ?? '';
          if (result.contains('fue transferida')) {
            return false;
          }
          if (result.toLowerCase().contains('from:')) {
            if (!AccessControl.isAdmin) {
              return false;
            }
          }
          return true;
        }).toList();

        // Ordenar por fecha de creación descendente (más recientes arriba)
        list.sort((a, b) {
          final dateA = DateTime.tryParse(a['Created'] ?? '') ?? DateTime(1900);
          final dateB = DateTime.tryParse(b['Created'] ?? '') ?? DateTime(1900);
          return dateB.compareTo(dateA);
        });
        return list;
      });
    });
  }

  Future<void> _addUpdate() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _AddUpdateDialog(
        requestId: _requestDetails?['id'] ?? widget.requestId,
        currentStatusId: _requestDetails?['R_Status_ID'] is Map 
            ? (_requestDetails!['R_Status_ID']['id'] as num?)?.toInt() 
            : (_requestDetails?['R_Status_ID'] as num?)?.toInt(),
        adUserId: _requestDetails?['AD_User_ID'] is Map
            ? (_requestDetails!['AD_User_ID']['id'] as num?)?.toInt()
            : (_requestDetails?['AD_User_ID'] as num?)?.toInt() ?? 0,
        bPartnerId: _requestDetails?['C_BPartner_ID'] is Map
            ? (_requestDetails!['C_BPartner_ID']['id'] as num?)?.toInt()
            : (_requestDetails?['C_BPartner_ID'] as num?)?.toInt() ?? _requestDetails?['bpId'],
        salesRepId: _requestDetails?['SalesRep_ID'] is Map
            ? (_requestDetails!['SalesRep_ID']['id'] as num?)?.toInt()
            : (_requestDetails?['SalesRep_ID'] as num?)?.toInt() ?? 0,
        summary: (_requestDetails?['Summary'] ?? _requestDetails?['summary'] ?? widget.docNo).toString(),
        description: _memoizedDescription ?? 'Cargando...',
        requestTypeId: _requestDetails?['R_RequestType_ID'] is Map
            ? (_requestDetails!['R_RequestType_ID']['id'] as num?)?.toInt()
            : (_requestDetails?['R_RequestType_ID'] as num?)?.toInt(),
      ),
    );

    if (result == true) {
      _fetchDetails(forceNetwork: true); // Recargar detalles forzando red para ver el nuevo estado
      _refreshUpdates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Actualizaciones: ${widget.docNo}'),
        actions: const [HelpIcon()],
      ),
      floatingActionButton: AccessControl.canAddUpdates
          ? FloatingActionButton.extended(
              onPressed: _addUpdate,
              label: Text(AppLocale.reply.getString(context), style: textTheme.labelLarge?.copyWith(color: colorScheme.onPrimary, fontWeight: FontWeight.bold)),
              icon: Icon(Icons.reply, color: colorScheme.onPrimary),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            // Cabecera Desplegable con el resumen de la solicitud
            if (_requestDetails != null)
              _RequestSummaryHeader(
                details: _requestDetails!,
                docNo: widget.docNo,
                description: _memoizedDescription ?? 'Sin descripción.',
              ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _updatesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 48, color: colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(AppLocale.noRepliesYet.getString(context), style: textTheme.bodyLarge?.copyWith(color: colorScheme.outline)),
                        ],
                      ),
                    );
                  }

                  final updates = snapshot.data!;
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: updates.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 16),
                    itemBuilder: (context, index) => _UpdateCard(
                      update: updates[index],
                      onUpdateChanged: () {
                        setState(() {
                          _updatesFuture = fetchRequestUpdates(widget.requestId);
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  final Map<String, dynamic> update;
  final VoidCallback? onUpdateChanged;
  const _UpdateCard({required this.update, this.onUpdateChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final created = DateTime.tryParse(update['Created'] ?? '');
    final formattedDate = created != null ? '${created.day}/${created.month}/${created.year} ${AppLocale.atTime.getString(context)} ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}' : AppLocale.unknownDate.getString(context);
    final result = update['Result'] ?? AppLocale.noResult.getString(context);
    final confidential = update['ConfidentialTypeEntry']?['identifier'] ?? 'N/A';
    final confId = update['ConfidentialTypeEntry']?['id']?.toString() ?? update['ConfidentialTypeEntry']?.toString() ?? '';

    final createdBy = update['CreatedBy'];
    String createdByName = '';
    if (createdBy is Map) {
      createdByName = (createdBy['identifier'] ?? createdBy['Name'] ?? '').toString();
    } else {
      createdByName = createdBy?.toString() ?? AppLocale.unknown.getString(context);
    }

    final List<int> imageIds = [];
    for (String key in ['AD_Image_ID', 'AD_Image1_ID', 'AD_Image2_ID', 'AD_Image3_ID']) {
      if (update[key] != null) {
        if (update[key] is Map && update[key]['id'] != null) {
          imageIds.add(update[key]['id'] is int ? update[key]['id'] : int.tryParse(update[key]['id'].toString()) ?? 0);
        } else if (update[key] is int) {
          imageIds.add(update[key]);
        } else if (update[key] is String && int.tryParse(update[key]) != null) {
          imageIds.add(int.parse(update[key]));
        }
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant, width: 1),
      ),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_circle, size: 20, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '$createdByName - $formattedDate',
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 4.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (confId == 'I')
                      Tooltip(
                        message: AppLocale.thisReplyNotVisibleToUser.getString(context),
                        child: Icon(Icons.visibility_off, size: 16, color: colorScheme.error),
                      ),
                    if (AccessControl.isAdmin)
                      PopupMenuButton<String>(
                        tooltip: 'Cambiar confidencialidad',
                        onSelected: (String newValue) async {
                          if (newValue == confId) return;
                          final updateId = update['id'];
                          if (updateId != null) {
                            final success = await updateRequestUpdateConfidentiality(updateId, newValue);
                            if (success) {
                              ToastMessage.show(context: context, message: 'Confidencialidad actualizada', type: ToastType.success);
                              onUpdateChanged?.call();
                            } else {
                              ToastMessage.show(context: context, message: 'Error al actualizar', type: ToastType.failure);
                            }
                          }
                        },
                        itemBuilder: (BuildContext context) => [
                          DropdownMenuItem<String>(value: 'I', child: Text(AppLocale.internalNote.getString(context))),
                          DropdownMenuItem<String>(value: 'C', child: Text(AppLocale.visibleToClient.getString(context))),
                          DropdownMenuItem<String>(value: 'P', child: Text(AppLocale.publicLabel.getString(context))),
                        ].map((e) => PopupMenuItem<String>(value: e.value, child: e.child)).toList(),
                        child: _buildBadge(context, confidential, colorScheme.tertiaryContainer, colorScheme.onTertiaryContainer),
                      )
                    else
                      _buildBadge(context, confidential, colorScheme.tertiaryContainer, colorScheme.onTertiaryContainer),
                  ],
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Divider(height: 1),
            ),
            Html(
              data: result,
              style: {
                "body": Style(
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                  fontSize: FontSize(14),
                  fontFamily: 'Poppins',
                  color: colorScheme.onSurface,
                )
              },
            ),
            // Mostramos tanto imágenes en campos fijos como archivos adjuntos
            if (imageIds.isNotEmpty || update['id'] != null) ...[
              const SizedBox(height: 16),
              AttachmentPreviewList(
                recordId: update['id'] is int ? update['id'] : int.tryParse(update['id']?.toString() ?? '') ?? 0,
                tableName: '${Endpoint.baseUrl}/api/v1/models/R_RequestUpdate',
                fixedImageIds: imageIds,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context, String label, Color bgColor, Color textColor, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 10, color: textColor), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor)),
        ],
      ),
    );
  }
}

class _AddUpdateDialog extends StatefulWidget {
  final int requestId;
  final int? currentStatusId;
  final int? adUserId;
  final int? bPartnerId;
  final int? salesRepId;
  final String summary;
  final String description;
  final int? requestTypeId;

  const _AddUpdateDialog({
    required this.requestId,
    this.currentStatusId,
    this.adUserId,
    this.bPartnerId,
    this.salesRepId,
    required this.summary,
    required this.description,
    this.requestTypeId,
  });

  @override
  State<_AddUpdateDialog> createState() => _AddUpdateDialogState();
}

class _AddUpdateDialogState extends State<_AddUpdateDialog> {
  final QuillController _resultController = QuillController.basic();
  String _confidentialType = 'C'; // Visible to client
  final List<PlatformFile?> _evidences = [null, null, null, null];
  bool _isSaving = false;
  int? _newStatusId;

  int _currentLength = 0;

  @override
  void initState() {
    super.initState();
    final filtered = _getFilteredStatuses();
    if (widget.currentStatusId != null && filtered.containsValue(widget.currentStatusId)) {
      _newStatusId = widget.currentStatusId;
    } else {
      _newStatusId = null;
    }
    
    _resultController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // Calculamos la longitud del texto plano para que sea razonable para el usuario final
    // ya que el HTML generado incluye muchas etiquetas invisibles.
    final plainText = _resultController.document.toPlainText().trim();
    if (_currentLength != plainText.length) {
      setState(() {
        _currentLength = plainText.length;
      });
    }
  }

  @override
  void dispose() {
    _resultController.removeListener(_onTextChanged);
    _resultController.dispose();
    super.dispose();
  }

  Map<String, int> _getFilteredStatuses() {
    if (GlobalCache.statuses.isEmpty) return GlobalCache.statuses;
    
    int? currentRequestTypeId = widget.requestTypeId;
    if (currentRequestTypeId == null) return GlobalCache.statuses;
    
    int? targetCategoryId = GlobalCache.requestTypeCategoryMap[currentRequestTypeId];
    
    if (targetCategoryId == null) return GlobalCache.statuses;
    
    final filtered = <String, int>{};
    for (var entry in GlobalCache.statuses.entries) {
      int statusId = entry.value;
      int? statusCategory = GlobalCache.statusCategoryMap[statusId];
      if (statusCategory == targetCategoryId) {
        filtered[entry.key] = statusId;
      }
    }
    
    if (widget.currentStatusId != null && GlobalCache.statuses.containsValue(widget.currentStatusId)) {
       final currentKey = GlobalCache.statuses.keys.firstWhere((k) => GlobalCache.statuses[k] == widget.currentStatusId);
       filtered[currentKey] = widget.currentStatusId!;
    }
    
    return filtered.isNotEmpty ? filtered : GlobalCache.statuses;
  }

  Future<void> _pickFile(int index) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);

    if (result != null && result.files.isNotEmpty) {
      if (result.files.first.bytes == null) {
        ToastMessage.show(context: context, message: AppLocale.errorReadingFile.getString(context), type: ToastType.warning);
        return;
      }
      setState(() {
        _evidences[index] = result.files.first;
      });
    }
  }

  void _removeFile(int index) {
    setState(() {
      _evidences[index] = null;
    });
  }

  Future<void> _handleSave() async {
    final resultText = _resultController.document.toPlainText().trim();
    if (resultText.isEmpty) {
      ToastMessage.show(context: context, message: AppLocale.resultRequired.getString(context), type: ToastType.warning);
      return;
    }

    setState(() => _isSaving = true);

    final resultHtml = HtmlEditorUtils.deltaToHtml(_resultController.document);

    final result = await createRequestUpdate(requestId: widget.requestId, resultText: resultHtml, confidentialType: _confidentialType, evidences: _evidences);

    if (mounted) {
      setState(() => _isSaving = false);
      
      if (result['success'] == true) {
        ToastMessage.show(context: context, message: result['message'] ?? AppLocale.updateCreated.getString(context), type: ToastType.success);
        bool statusChanged = false;
        if (_newStatusId != null && _newStatusId != widget.currentStatusId) {
          final statusResult = await updateRemoteRequest(id: widget.requestId, statusId: _newStatusId!);
          if (statusResult['success'] == true) {
            statusChanged = true;
          }
        }

        // --- INICIO Lógica Correos ---
        _sendEmailsInBackground(
          requestId: widget.requestId,
          adUserId: widget.adUserId,
          salesRepId: widget.salesRepId,
          bPartnerId: widget.bPartnerId,
          currentStatusId: widget.currentStatusId,
          statusChanged: statusChanged,
          resultHtml: resultHtml,
          updateId: result['id'],
          context: context,
        );
        // --- FIN Lógica Correos ---

        Navigator.of(context).pop(true);
      } else {
        ToastMessage.show(context: context, message: result['message'] ?? AppLocale.unknownError.getString(context), type: ToastType.failure);
      }
    }
  }

  Widget _buildEvidenceField(int index) {
    final file = _evidences[index];
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                file != null ? file.name : 'Evidencia ${index + 1} (Sin archivo)',
                style: TextStyle(color: file != null ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (file == null) IconButton(icon: const Icon(Icons.attach_file), onPressed: () => _pickFile(index), tooltip: AppLocale.attachFile.getString(context), color: theme.colorScheme.primary) else IconButton(icon: const Icon(Icons.delete), onPressed: () => _removeFile(index), tooltip: AppLocale.deleteFile.getString(context), color: theme.colorScheme.error),
        ],
      ),
    );
  }

  Future<void> _sendEmailsInBackground({
    required int requestId,
    required int? adUserId,
    required int? salesRepId,
    required int? bPartnerId,
    required int? currentStatusId,
    required bool statusChanged,
    required String resultHtml,
    required int updateId,
    required BuildContext context,
  }) async {
    try {
      String oldStatusName = '';
      for (var entry in GlobalCache.statuses.entries) {
        if (entry.value == currentStatusId) {
          oldStatusName = entry.key;
          break;
        }
      }

      bool hasAdUser = adUserId != null && adUserId > 0;
      bool hasSalesRep = salesRepId != null && salesRepId > 0;
      bool success1 = true;
      bool success2 = true;
      bool emailsAttempted = false;

      bool isAdUserCurrentUser = adUserId != null && User.userID != null && adUserId == User.userID;

      if (hasAdUser) {
        emailsAttempted = true;
        if (statusChanged && !isAdUserCurrentUser) {
          success1 = await sendRequestStatusEmail(
            requestId: requestId,
            adUserId: adUserId,
            bPartnerId: bPartnerId ?? 0,
            templateType: MailTemplateType.statusUpdate,
            updateText: resultHtml,
            oldStatusName: oldStatusName,
            updateId: updateId,
          );
        }
        bool s1b = true;
        if (_confidentialType != 'I') {
          s1b = await sendRequestStatusEmail(
            requestId: requestId,
            adUserId: adUserId,
            bPartnerId: bPartnerId ?? 0,
            templateType: MailTemplateType.updateRequest,
            updateText: resultHtml,
            oldStatusName: oldStatusName,
            updateId: updateId,
          );
        }
        success1 = success1 && s1b;
      }

      bool isSalesRepCurrentUser = salesRepId != null && User.userID != null && salesRepId == User.userID;

      if (hasSalesRep && salesRepId != adUserId) {
        emailsAttempted = true;
        
        if (statusChanged && !isSalesRepCurrentUser) {
          bool s2a = await sendRequestStatusEmail(
            requestId: requestId,
            adUserId: salesRepId,
            bPartnerId: bPartnerId ?? 0,
            templateType: MailTemplateType.statusUpdate,
            updateText: resultHtml,
            oldStatusName: oldStatusName,
            updateId: updateId,
          );
          success2 = success2 && s2a;
        }

        bool s2b = true;
        if (_confidentialType != 'I') {
          s2b = await sendRequestStatusEmail(
            requestId: requestId,
            adUserId: salesRepId,
            bPartnerId: bPartnerId ?? 0,
            templateType: MailTemplateType.updateRequest,
            updateText: resultHtml,
            oldStatusName: oldStatusName,
            updateId: updateId,
          );
        }
        success2 = success2 && s2b;
      }

      if (!emailsAttempted) return;

      if (mounted) {
        if (success1 && success2) {
          bool isInternal = AccessControl.isAdmin;
          String msg = isInternal ? AppLocale.emailSentToClient.getString(context) : AppLocale.emailSentToTeam.getString(context);
          ToastMessage.show(context: context, message: msg, type: ToastType.success);
        } else {
          ToastMessage.show(context: context, message: AppLocale.notificationEmailFailed.getString(context), type: ToastType.failure);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return CustomModal(
      title: AppLocale.addUpdate.getString(context),
      width: 600,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: SingleChildScrollView(
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Html(
                        data: widget.summary.replaceAll('&lt;', '<').replaceAll('&gt;', '>'),
                        style: {
                          "body": Style(
                            margin: Margins.zero,
                            padding: HtmlPaddings.zero,
                            fontSize: FontSize(14),
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        },
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4.0),
                        child: Divider(height: 12),
                      ),
                      Html(
                        data: widget.description,
                        style: {
                          "body": Style(
                            margin: Margins.zero,
                            padding: HtmlPaddings.zero,
                            fontSize: FontSize(12),
                            color: Theme.of(context).colorScheme.onSurface,
                            height: Height(1.4),
                          )
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
            QuillExpandableField(
              controller: _resultController,
              label: AppLocale.resultOrComment.getString(context),
              isRequired: true,
              height: 120,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4.0, right: 4.0),
                child: Text(
                  '$_currentLength / 5000',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _currentLength > 5000 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (AccessControl.isAdmin) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CustomDropdown<String>(
                      label: AppLocale.confidentiality.getString(context),
                      value: _confidentialType,
                      items: [
                        DropdownMenuItem(value: 'I', child: Text(AppLocale.internalNote.getString(context))),
                        DropdownMenuItem(value: 'C', child: Text(AppLocale.visibleToClient.getString(context))),
                        DropdownMenuItem(value: 'P', child: Text(AppLocale.publicLabel.getString(context))),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _confidentialType = val);
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0, left: 12.0, right: 12.0),
                    child: Tooltip(
                      message: 'Visibilidad de la actualización:\n• Interna: Solo visible para Administradores. NO dispara correos.\n• Cliente/Público: Visible para todos (Admin, Soporte, Cliente). Sí dispara correos.\n\nReglas automáticas adicionales:\n• Mensajes automáticos de "System" son invisibles para clientes y soporte.\n• Respuestas vacías o con texto "Sin resultado" se ocultan por limpieza.',
                      child: Icon(Icons.info_outline, size: 24, color: Colors.grey),
                    ),
                  ),
                  Expanded(
                    child: CustomDropdown<int>(
                      label: AppLocale.status.getString(context),
                      value: _newStatusId,
                      items: _getFilteredStatuses().entries.map((e) => DropdownMenuItem<int>(
                        value: e.value,
                        child: Text(cleanStatusName(e.key)),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _newStatusId = val);
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text('Evidencias (Opcional, hasta 4 archivos):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            _buildEvidenceField(0),
            _buildEvidenceField(1),
            _buildEvidenceField(2),
            _buildEvidenceField(3),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isSaving ? null : () => Navigator.pop(context, false), child: Text(AppLocale.cancel.getString(context))),
        CustomButton(text: AppLocale.save.getString(context), onPressed: _handleSave, isLoading: _isSaving),
      ],
    );
  }
}

class AttachmentPreviewList extends StatelessWidget {
  final int recordId;
  final String tableName;
  final List<int> fixedImageIds;

  const AttachmentPreviewList({
    super.key,
    required this.recordId,
    required this.tableName,
    required this.fixedImageIds,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: fetchAttachments(recordID: recordId, tableName: tableName),
      builder: (context, snapshot) {
        final List<Widget> previews = [];

        // 1. Imágenes de campos fijos (Legacy/Compatibilidad)
        for (var id in fixedImageIds) {
          previews.add(_ImagePreview(imageId: id));
        }

        // 2. Archivos adjuntos reales
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          for (var attr in snapshot.data!) {
            final fileName = attr['name']?.toString() ?? 'archivo';
            previews.add(_AttachmentItem(
              tableName: tableName,
              recordId: recordId,
              fileName: fileName,
            ));
          }
        }

        if (previews.isEmpty && (snapshot.connectionState == ConnectionState.done)) {
          return const SizedBox.shrink();
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: previews,
        );
      },
    );
  }
}

class _AttachmentItem extends StatelessWidget {
  final String tableName;
  final int recordId;
  final String fileName;

  const _AttachmentItem({
    required this.tableName,
    required this.recordId,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    final extension = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension);

    if (isImage) {
      return FutureBuilder<Uint8List?>(
        future: DocumentsLogic.fetchImagePreview(tableName, recordId, fileName),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildBox(const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
          }
          if (snapshot.hasData && snapshot.data != null) {
            return InkWell(
              onTap: () => _showFullScreen(context, snapshot.data!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(snapshot.data!, width: 80, height: 80, fit: BoxFit.cover),
              ),
            );
          }
          return _buildBox(const Icon(Icons.broken_image_outlined, color: Colors.grey));
        },
      );
    }

    return InkWell(
      onTap: () {
        ToastMessage.show(context: context, message: AppLocale.openingFile.getStringWithVariables(context, {'fileName': fileName}), type: ToastType.help);
      },
      child: _buildBox(
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(DocumentsLogic.getFileIcon(extension), size: 32, color: Colors.indigo),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                fileName,
                style: const TextStyle(fontSize: 8),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBox(Widget child) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Center(child: child),
    );
  }

  void _showFullScreen(BuildContext context, Uint8List data) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(child: Image.memory(data)),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, shadows: [Shadow(blurRadius: 4)]),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final int imageId;
  const _ImagePreview({required this.imageId});

  Future<Uint8List?> _fetchImage() async {
    try {
      final url = '${Endpoint.baseUrl}/api/v1/models/AD_Image/$imageId?\$select=BinaryData';
      var response = await http.get(Uri.parse(url), headers: {'Authorization': Token.token});
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final binaryData = data['BinaryData'];
        if (binaryData is String && binaryData.isNotEmpty) {
          return base64Decode(binaryData);
        }
      }
    } catch (_) {
      // Ignored: Fail silently
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _fetchImage(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(width: 80, height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        if (snapshot.hasData && snapshot.data != null) {
          return InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      InteractiveViewer(child: Image.memory(snapshot.data!)),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(snapshot.data!, width: 80, height: 80, fit: BoxFit.cover),
            ),
          );
        }
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
        );
      },
    );
  }
}

class _RequestSummaryHeader extends StatelessWidget {
  final Map<String, dynamic> details;
  final String docNo;
  final String description;

  const _RequestSummaryHeader({
    required this.details,
    required this.docNo,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;


    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(
                  AppLocale.requestSummary.getString(context),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: 8),
                Html(
                  data: (details['Summary'] ?? details['summary'] ?? 'Sin resumen').toString().replaceAll('&lt;', '<').replaceAll('&gt;', '>'),
                  style: {
                    "body": Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                      fontSize: FontSize(16),
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      maxLines: 2,
                      textOverflow: TextOverflow.ellipsis,
                    ),
                  },
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.25,
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Html(
                      data: description.replaceAll('&lt;', '<').replaceAll('&gt;', '>'),
                      style: {
                        "body": Style(
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                          fontSize: FontSize(14),
                          color: colorScheme.onSurfaceVariant,
                          height: Height(1.5),
                        )
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
            padding: const EdgeInsets.only(top: 4.0, right: 4.0),
            child: IconButton(
              icon: const Icon(Icons.zoom_out_map),
              tooltip: AppLocale.viewFullDescription.getString(context),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext dialogContext) => CustomModal(
                    title: AppLocale.fullDescription.getString(context),
                    width: 600,
                    content: SizedBox(
                      height: 400,
                      child: SingleChildScrollView(
                        child: SelectionArea(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Html(
                                data: (details['Summary'] ?? details['summary'] ?? '').toString().replaceAll('&lt;', '<').replaceAll('&gt;', '>'),
                                style: {
                                  "body": Style(
                                    margin: Margins.zero,
                                    padding: HtmlPaddings.zero,
                                  ),
                                },
                              ),
                              if (description != 'Sin descripción adicional.') ...[
                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 16),
                                Html(
                                  data: description.replaceAll('&lt;', '<').replaceAll('&gt;', '>'),
                                  style: {
                                    "body": Style(
                                      margin: Margins.zero,
                                      padding: HtmlPaddings.zero,
                                    ),
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(AppLocale.close.getString(context)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
