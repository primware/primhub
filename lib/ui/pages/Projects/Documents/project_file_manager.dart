import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/ImagesManagment/download_attachments.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:primhub/ui/pages/Projects/Projects_Widgets/breadcrumb_navigator.dart';
import 'package:primhub/ui/pages/Projects/Projects_Widgets/file_card.dart';
import 'package:primhub/ui/pages/Projects/Projects_Widgets/file_preview_manager.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:flutter_localization/flutter_localization.dart';

class ProjectFileManager extends StatefulWidget {
  final Map<String, dynamic>? project;
  final int? bPartnerId;
  final String? bPartnerName;
  final String viewType; // 'Entregables', 'Seguimiento', 'General'
  final VoidCallback onExit;
  final ValueChanged<bool>? onRootChanged;
  final Widget? headerWidget;

  const ProjectFileManager({super.key, this.project, this.bPartnerId, this.bPartnerName, required this.viewType, required this.onExit, this.onRootChanged, this.headerWidget});

  @override
  State<ProjectFileManager> createState() => ProjectFileManagerState();
}

class ProjectFileManagerState extends State<ProjectFileManager> {
  List<String> _currentPath = [];
  List<int> _currentPathIds = []; // IDs de las carpetas en el path (empezando desde el nivel 3)
  List<dynamic> _documents = [];
  bool _isLoadingDocuments = false;
  bool _isDragging = false;
  final TextEditingController _searchController = TextEditingController();

  int? _downloadingId;
  final Set<int> _movingFiles = {}; // Bloqueo de concurrencia para evitar duplicados

  bool get _canManageFiles {
    return AccessControl.canManageFiles;
  }

  @override
  void initState() {
    super.initState();
    final rootName = widget.bPartnerId != null ? 'Mis Documentos' : 'Mis Proyectos';
    final entityName = widget.bPartnerId != null ? (widget.bPartnerName ?? 'Tercero') : (widget.project?['Name'] ?? 'Proyecto');
    _currentPath = [rootName, entityName, widget.viewType];
    _searchController.addListener(() => setState(() {}));
    _fetchDocuments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _notifyRootChanged() => widget.onRootChanged?.call(isRoot());
  void refresh() => _fetchDocuments();
  bool isRoot() => _currentPath.length <= 3;

  bool navigateBack() {
    if (_currentPath.length > 3) {
      setState(() {
        _currentPath.removeLast();
        if (_currentPathIds.isNotEmpty) _currentPathIds.removeLast();
        _notifyRootChanged();
      });
      return true;
    }
    return false;
  }

  Future<void> _fetchDocuments({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoadingDocuments = true);
    final docs = await DocumentsLogic.fetchDocuments(projectId: widget.project?['id'], bPartnerId: widget.bPartnerId, viewType: widget.viewType, currentPath: _currentPath);

    // Recuperar el orden guardado
    final prefs = await SharedPreferences.getInstance();
    final String orderKey = 'order_${widget.project?['id'] ?? widget.bPartnerId}_${widget.viewType}_${_currentPath.join('_')}';
    final List<String>? savedOrder = prefs.getStringList(orderKey);

    // Función recursiva para inyectar la secuencia guardada a los documentos y sus hijos
    void applyOrder(List<dynamic> items) {
      if (savedOrder != null) {
        for (var item in items) {
          int idx = savedOrder.indexOf(item['id'].toString());
          item['_localSeqNo'] = idx != -1 ? idx : 9999; // Items nuevos van al final
        }
      } else {
        for (int i = 0; i < items.length; i++) {
          items[i]['_localSeqNo'] = i;
        }
      }
      for (var item in items) {
        if (item['IsSummary'] == true || item['IsSummary'] == 'Y') {
          final children = item['PRIM_Documents_Related'] as List? ?? [];
          applyOrder(children);
        }
      }
    }

    applyOrder(docs);

    if (mounted) {
      setState(() {
        _documents = docs;
        if (showLoading) _isLoadingDocuments = false;
      });
      if (docs.isEmpty && _currentPath.length > 3) context.go('/login'); // Simple auth check fallback
    }
  }

  Future<void> _reorderFile(int draggedId, int targetId) async {
    if (draggedId == targetId) return;

    List<dynamic> currentList;
    if (_currentPath.length > 3) {
      final folderName = _currentPath.last;
      final folder = _documents.firstWhere((doc) => doc['Name'] == folderName && (doc['IsSummary'] == true || doc['IsSummary'] == 'Y'), orElse: () => null);
      currentList = folder != null ? (folder['PRIM_Documents_Related'] as List? ?? []) : _documents;
    } else {
      currentList = _documents;
    }

    String typeCode = widget.viewType == 'Entregables' ? 'ET' : (widget.viewType == 'Seguimiento' ? 'SG' : 'GN');
    var viewItems = currentList.where((item) => (item['Type'] is Map ? item['Type']['id']?.toString() : item['Type']?.toString()) == typeCode).toList();

    // Mantener el mismo orden lógico actual
    viewItems.sort((a, b) => _compareItems(a, b));

    int draggedIndex = viewItems.indexWhere((item) => item['id'] == draggedId);
    int targetIndex = viewItems.indexWhere((item) => item['id'] == targetId);

    if (draggedIndex != -1 && targetIndex != -1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          final item = viewItems.removeAt(draggedIndex);
          viewItems.insert(targetIndex, item); // Insertamos en la nueva posición
          for (int i = 0; i < viewItems.length; i++) {
            viewItems[i]['_localSeqNo'] = i;
          }
        });

        // Lanzar el guardado asíncrono en background sin bloquear la interfaz (Fire and Forget)
        SharedPreferences.getInstance().then((prefs) {
          final String orderKey = 'order_${widget.project?['id'] ?? widget.bPartnerId}_${widget.viewType}_${_currentPath.join('_')}';
          prefs.setStringList(orderKey, viewItems.map((e) => e['id'].toString()).toList());
        });
      });
    }
  }

  /// Mueve archivos mediante Drag and Drop
  Future<void> _moveFile(Map<String, dynamic> doc, String currentTableName, int? targetFolderId) async {
    final int docId = doc['id'];

    if (_movingFiles.contains(docId)) return; // Ignorar si ya se está moviendo

    // Validar si ya está en la carpeta de destino para no hacer peticiones fantasma
    bool alreadyInTarget = false;
    if (targetFolderId == null) {
      alreadyInTarget = currentTableName == Endpoint.primDocuments;
    } else {
      final parent = doc['PRIM_Documents_ID'];
      final parentId = parent is Map ? parent['id'] : parent;
      alreadyInTarget = (currentTableName == Endpoint.primDocumentsRelated) && (parentId == targetFolderId);
    }
    if (alreadyInTarget) return;

    _movingFiles.add(docId);

    // --- 1. OPTIMISTIC UI: Actualización visual instantánea ---
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        Map<String, dynamic>? removedDoc;

        // Remover de la vista actual
        if (_currentPath.length > 3) {
          final folderName = _currentPath.last;
          final folder = _documents.firstWhere((d) => d['Name'] == folderName && (d['IsSummary'] == true || d['IsSummary'] == 'Y'), orElse: () => null);
          if (folder != null && folder['PRIM_Documents_Related'] != null) {
            final List related = folder['PRIM_Documents_Related'];
            final index = related.indexWhere((d) => d['id'] == docId);
            if (index != -1) removedDoc = related.removeAt(index);
          }
        } else {
          final index = _documents.indexWhere((d) => d['id'] == docId);
          if (index != -1) removedDoc = _documents.removeAt(index);
        }

        // Agregar visualmente a la carpeta destino (si es visible en la raíz)
        if (removedDoc != null && targetFolderId != null && _currentPath.length <= 3) {
          final targetFolder = _documents.firstWhere((d) => d['id'] == targetFolderId, orElse: () => null);
          if (targetFolder != null) {
            targetFolder['PRIM_Documents_Related'] ??= [];
            targetFolder['PRIM_Documents_Related'].add(removedDoc);
          }
        }
      });
      ToastMessage.show(context: context, message: 'Moviendo archivo...', type: ToastType.help);
    });

    // --- 2. LLAMADA A LA API EN SEGUNDO PLANO ---
    final result = await DocumentsLogic.moveDocument(doc: doc, currentTableName: currentTableName, targetFolderId: targetFolderId, projectId: widget.project?['id'], bPartnerId: widget.bPartnerId, viewType: widget.viewType);

    _movingFiles.remove(docId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (result['success'] == true) {
        ToastMessage.show(context: context, message: 'Archivo movido correctamente', type: ToastType.help);
        _fetchDocuments(showLoading: false); // Sincronizar IDs silenciosamente
      } else {
        ToastMessage.show(context: context, message: 'Error: ${result['error']}', type: ToastType.failure);
        _fetchDocuments(showLoading: false); // Revertir visualmente el fallo
      }
    });
  }

  Future<void> pickAndUploadFile() async {
    if (!_canManageFiles) {
      ToastMessage.show(context: context, message: 'No tienes permisos para subir archivos.', type: ToastType.help);
      return;
    }
    FilePickerResult? result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;

    final fileName = result.files.first.name;
    final TextEditingController nameController = TextEditingController(text: fileName.split('.').first);

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => CustomModal(
        title: 'Subir Archivo',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomTextField(
              controller: TextEditingController(text: fileName),
              label: 'Nombre Real (Archivo)',
              readOnly: true,
            ),
            const SizedBox(height: 16),
            CustomTextField(controller: nameController, label: 'Nombre Visual (Etiqueta)'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          CustomButton(text: 'Subir', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );

    if (confirm != true) return;
    final displayName = nameController.text.trim().isEmpty ? fileName : nameController.text.trim();

    setState(() => _isLoadingDocuments = true);
    final resultUpload = await DocumentsLogic.uploadFile(fileName: fileName, displayName: displayName, fileBytes: result.files.first.bytes!, projectId: widget.project?['id'], bPartnerId: widget.bPartnerId, viewType: widget.viewType, currentPath: _currentPath, documents: _documents);

    if (resultUpload == true) {
      ToastMessage.show(context: context, message: 'Archivo subido correctamente', type: ToastType.help);
    } else if (resultUpload is String) {
      ToastMessage.show(context: context, message: resultUpload, type: ToastType.failure);
    } else {
      ToastMessage.show(context: context, message: 'Error al subir archivo', type: ToastType.failure);
    }
    _fetchDocuments();
  }

  Future<void> createFolderDialog() async {
    if (!_canManageFiles) {
      ToastMessage.show(context: context, message: 'No tienes permisos para crear carpetas.', type: ToastType.help);
      return;
    }
    if (!isRoot()) {
      ToastMessage.show(context: context, message: 'No se permiten subcarpetas.', type: ToastType.help);
      return;
    }
    final TextEditingController controller = TextEditingController();
    final bool? create = await showDialog<bool>(
      context: context,
      builder: (context) => CustomModal(
        title: 'Nueva Carpeta',
        content: CustomTextField(controller: controller, label: 'Nombre de la carpeta'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          CustomButton(text: 'Crear', onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (create == true && controller.text.isNotEmpty) {
      setState(() => _isLoadingDocuments = true);
      final success = await DocumentsLogic.createFolder(name: controller.text, projectId: widget.project?['id'], bPartnerId: widget.bPartnerId, viewType: widget.viewType, currentPath: _currentPath, documents: _documents);
      if (success) {
        ToastMessage.show(context: context, message: 'Carpeta creada correctamente', type: ToastType.help);
      } else {
        ToastMessage.show(context: context, message: 'Error al crear carpeta', type: ToastType.help);
      }
      _fetchDocuments();
    }
  }

  Future<void> _deleteFile(int id, String tableName, String name) async {
    final item = _documents.firstWhere((e) => e['id'] == id, orElse: () => null);
    if (item != null) {
      final isFolder = item['IsSummary'] == true || item['IsSummary'] == 'Y';
      final children = isFolder ? (item['PRIM_Documents_Related'] as List? ?? []) : [];
      if (isFolder && children.isNotEmpty) {
        ToastMessage.show(context: context, message: 'No puede eliminar esta carpeta con contenido. Elimine los documentos primero.', type: ToastType.failure);
        return;
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => CustomModal(
        title: 'Eliminar Archivo',
        content: Text('¿Estás seguro de que deseas eliminar "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          CustomButton(text: 'Eliminar', backgroundColor: Colors.red, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _isLoadingDocuments = true);
      final result = await DocumentsLogic.deleteFile(id, tableName);
      if (result['success'] == true) {
        ToastMessage.show(context: context, message: 'Archivo eliminado', type: ToastType.help);
        _fetchDocuments();
      } else {
        ToastMessage.show(context: context, message: result['message'] ?? 'Error al eliminar', type: ToastType.failure);
        setState(() => _isLoadingDocuments = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropRegion(
      formats: Formats.standardFormats,
      onDropEnter: (event) {
        if (!_canManageFiles) return;
        if (event.session.items.any((item) => item.localData is Map && (item.localData as Map)['type'] != null)) return;
        if (!_isDragging) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isDragging = true);
          });
        }
      },
      onDropOver: (event) {
        if (!_canManageFiles) return DropOperation.none;
        // Ignorar drags internos para no bloquear el movimiento entre carpetas
        if (event.session.items.any((item) => item.localData is Map && (item.localData as Map)['type'] != null)) {
          return DropOperation.none;
        }
        return DropOperation.copy;
      },
      onDropLeave: (event) {
        if (_isDragging) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isDragging = false);
          });
        }
      },
      onPerformDrop: (event) async {
        if (_isDragging) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isDragging = false);
          });
        }
        if (!_canManageFiles) return;

        // No procesar drags internos de Flutter aquí
        if (event.session.items.any((item) => item.localData is Map && (item.localData as Map)['type'] == 'file')) {
          return;
        }

        setState(() => _isLoadingDocuments = true);
        for (final item in event.session.items) {
          final reader = item.dataReader;
          if (reader != null) {
            reader.getFile(null, (file) async {
              final bytes = await file.readAll();
              final resultUpload = await DocumentsLogic.uploadFile(fileName: file.fileName ?? 'Archivo_Subido', displayName: file.fileName ?? 'Archivo_Subido', fileBytes: bytes, projectId: widget.project?['id'], bPartnerId: widget.bPartnerId, viewType: widget.viewType, currentPath: _currentPath, documents: _documents);
              if (resultUpload is String) {
                if (mounted) ToastMessage.show(context: context, message: resultUpload, type: ToastType.failure);
              } else if (resultUpload != true) {
                if (mounted) ToastMessage.show(context: context, message: 'Error al subir archivo', type: ToastType.failure);
              }
              _fetchDocuments();
            }, onError: (e) {});
          }
        }
      },
      child: Container(
        color: _isDragging ? theme.colorScheme.primary.withOpacity(0.1) : null,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: CustomTextField(controller: _searchController, hintText: AppLocale.searchDocument.getString(context), prefixIcon: const Icon(Icons.search)),
            ),
            if (widget.headerWidget != null)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: widget.headerWidget!,
              ),
            Expanded(
              child: Builder(
                builder: (context) {
                  double availableWidth = MediaQuery.of(context).size.width;
                  if (availableWidth > 800) availableWidth -= 250; 

                  int dynamicColumns = (availableWidth / 160).floor().clamp(2, 6);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1600),
                        child: _searchController.text.isNotEmpty
                            ? _buildSearchResults()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_currentPath.length > 1)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 16.0),
                                      child: BreadcrumbNavigator(
                                        currentPath: _currentPath,
                                        onNavigate: (i) => i <= 1
                                            ? widget.onExit()
                                            : setState(() {
                                                _currentPath = _currentPath.sublist(0, i + 1);
                                                if (i >= 3) {
                                                  _currentPathIds = _currentPathIds.sublist(0, i - 2);
                                                } else {
                                                  _currentPathIds.clear();
                                                }
                                                _notifyRootChanged();
                                              }),
                                        onDropToRoot: (index, data) {
                                          // Si el index es 2, el target es null (la raíz). Si es mayor, necesitamos el ID de ese nivel.
                                          int? targetFolderId;
                                          if (index > 2) {
                                            // Necesitamos el ID de la carpeta en el nivel 'index'
                                            // El index 3 corresponde al primer ID en _currentPathIds
                                            int idIdx = index - 3;
                                            if (idIdx >= 0 && idIdx < _currentPathIds.length) {
                                              targetFolderId = _currentPathIds[idIdx];
                                            }
                                          }

                                          if (data['doc'] != null) {
                                            _moveFile(data['doc'], data['tableName'], targetFolderId);
                                          }
                                        },
                                      ),
                                    ),
                                  _buildContentGrid(dynamicColumns),
                                ],
                              ),
                      ),
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

  Widget _buildSearchResults() {
    if (_isLoadingDocuments) return const Center(child: CircularProgressIndicator());
    final results = DocumentsLogic.performSearch(_searchController.text, _documents, _currentPath.sublist(0, 3));
    if (results.isEmpty) return const Center(child: Text('No se encontraron documentos.'));

    return ListView.builder(
      shrinkWrap: true,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        final doc = result['doc'] as Map<String, dynamic>;
        final path = result['path'] as List<String>;
        final docName = doc['Name'] as String? ?? 'Sin Nombre';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(DocumentsLogic.getFileIcon(DocumentsLogic.extractIdentifier(doc['Extension'], defaultValue: ''))),
            title: Text(docName),
            subtitle: Text('Ubicación: ${path.length > 3 ? path.sublist(3).join(' / ') : 'Principal'}'),
            trailing: AccessControl.canDownloadFiles
                ? (_downloadingId == doc['id']
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () async {
                            final tableName = path.length > 3 ? Endpoint.primDocumentsRelated : Endpoint.primDocuments;
                            setState(() => _downloadingId = doc['id']);
                            await downloadAttachment(
                              context: context,
                              recordID: doc['id'],
                              tableName: tableName,
                              fileName: docName,
                              onStatusChanged: () async {
                                await _fetchDocuments();
                                setState(() {}); // Trigger rebuild for search
                              },
                            );
                            if (mounted) setState(() => _downloadingId = null);
                          },
                        ))
                : null,
            onTap: () {
              setState(() {
                _currentPath = path;
                _currentPathIds.clear(); // Reset IDs and potentially rebuild path if we had them
                // Note: Search results don't easily provide all parent IDs currently.
                // But typically search results are used for navigation, and IDs are filled as we browse.
                _searchController.clear();
                _notifyRootChanged();
              });
            },
          ),
        );
      },
    );
  }

  Widget _buildContentGrid(int crossAxisCount) {
    if (_isLoadingDocuments) return const Center(child: CircularProgressIndicator());
    List<dynamic> currentItems = List.from(_documents);
    String tableName = Endpoint.primDocuments;

    if (_currentPath.length > 3) {
      final folderName = _currentPath.last;
      final folder = _documents.firstWhere((doc) => doc['Name'] == folderName && (doc['IsSummary'] == true || doc['IsSummary'] == 'Y'), orElse: () => null);
      if (folder != null) {
        String typeCode = widget.viewType == 'Entregables' ? 'ET' : (widget.viewType == 'Seguimiento' ? 'SG' : 'GN');
        final allChildren = folder['PRIM_Documents_Related'] as List? ?? [];
        currentItems = allChildren.where((child) => (child['Type'] is Map ? child['Type']['id']?.toString() : child['Type']?.toString()) == typeCode).toList();
        tableName = Endpoint.primDocumentsRelated;
      }
    }

    currentItems.sort((a, b) => _compareItems(a, b));

    if (currentItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(AppLocale.noDocuments.getString(context), style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    // Relación de aspecto dinámica ajustada para dar más altura a las tarjetas
    double aspect = crossAxisCount >= 6 ? 0.8 : (crossAxisCount >= 4 ? 0.85 : 0.78);
    double spacing = crossAxisCount >= 6 ? 8.0 : 16.0;

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: spacing, mainAxisSpacing: spacing, childAspectRatio: aspect),
      itemCount: currentItems.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final item = currentItems[index];
        final name = item['Name'] ?? 'Sin Nombre';
        final isFolder = item['IsSummary'] == true || item['IsSummary'] == 'Y';
        final children = isFolder ? (item['PRIM_Documents_Related'] as List? ?? []) : [];
        String size = isFolder ? '${children.length} archivo${children.length != 1 ? 's' : ''}' : '';
        String extension = DocumentsLogic.extractIdentifier(item['Extension'], defaultValue: '');
        if (extension.isEmpty && !isFolder && name.contains('.')) extension = name.split('.').last;

        return FileCard(
          extension: extension,
          name: name,
          size: size,
          color: isFolder ? Colors.amber : Colors.blue,
          charLimit: crossAxisCount >= 10 ? 12 : 25,
          isFolder: isFolder,
          details: item,
          tableName: tableName,
          columns: crossAxisCount,
          onMoveToFolder: (doc, tName, targetFolderId) => _moveFile(doc, tName, targetFolderId),
          onReorder: (draggedId, targetId) => _reorderFile(draggedId, targetId),
          onTap: () => isFolder
              ? setState(() {
                  _currentPath.add(name);
                  _currentPathIds.add(item['id']);
                  _notifyRootChanged();
                })
              : FilePreviewManager.showPreview(context, item, tableName, name, () => _deleteFile(item['id'], tableName, name), () {
                  setState(() {}); // Únicamente actualiza la grilla visualmente
                }, canDelete: _canManageFiles),
          onProperties: () => _showPropertiesDialog(context, name, item, tableName),
        );
      },
    );
  }

  int _compareItems(dynamic a, dynamic b) {
    final isFolderA = a['IsSummary'] == true || a['IsSummary'] == 'Y';
    final isFolderB = b['IsSummary'] == true || b['IsSummary'] == 'Y';

    if (isFolderA && !isFolderB) return -1;
    if (!isFolderA && isFolderB) return 1;

    int seqA = a['_localSeqNo'] ?? 9999;
    int seqB = b['_localSeqNo'] ?? 9999;
    int seqCompare = seqA.compareTo(seqB);

    // Si ambos tienen igual secuencia (ej. nuevos), ordenamos por fecha
    if (seqCompare != 0) return seqCompare;

    final dateA = DateTime.tryParse(a['Created'] ?? '') ?? DateTime(0);
    final dateB = DateTime.tryParse(b['Created'] ?? '') ?? DateTime(0);
    return dateA.compareTo(dateB);
  }

  void _showPropertiesDialog(BuildContext context, String name, Map<String, dynamic> details, String tableName) {
    final status = DocumentsLogic.extractStatus(details['Status']);
    final bool isFolder = details['IsSummary'] == true || details['IsSummary'] == 'Y';

    final TextEditingController nameController = TextEditingController(text: details['Name']);
    final TextEditingController versionController = TextEditingController(text: details['VersionNo']?.toString() ?? '');
    String currentStatus = status;
    bool isSaving = false;
    String typeCode = (details['Type'] is Map ? details['Type']['id']?.toString() : details['Type']?.toString()) ?? '';

    final List<String> statuses = ['Pendiente', 'En revisión', 'Entregado'];
    if (!statuses.contains(currentStatus)) statuses.add(currentStatus);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return CustomModal(
              title: 'Editar Propiedades',
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomTextField(controller: nameController, label: 'Nombre Real (Archivo)', readOnly: true),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: CustomTextField(controller: versionController, label: 'Versión'),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: isFolder
                              ? CustomTextField(
                                  controller: TextEditingController(text: currentStatus),
                                  label: 'Estado',
                                  readOnly: true,
                                )
                              : CustomDropdown<String>(
                                  value: currentStatus,
                                  label: 'Estado',
                                  items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                  onChanged: (val) {
                                    if (val != null) setStateDialog(() => currentStatus = val);
                                  },
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildPropertyRow('Tipo', typeCode == 'ET' ? 'Entregable' : (typeCode == 'SG' ? 'Seguimiento' : 'General')),
                    _buildPropertyRow('Extensión', DocumentsLogic.extractIdentifier(details['Extension'])),
                    _buildPropertyRow('Creado', DocumentsLogic.formatDate(details['Created'])),
                    _buildPropertyRow('Creado Por', DocumentsLogic.extractIdentifier(details['CreatedBy'], defaultValue: 'Sistema')),
                  ],
                ),
              ),
              actions: [
                if (_canManageFiles)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteFile(details['id'], tableName, name);
                    },
                  ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                CustomButton(
                  text: 'Guardar',
                  isLoading: isSaving,
                  onPressed: !_canManageFiles
                      ? null
                      : () async {
                          setStateDialog(() => isSaving = true);
                          final body = <String, dynamic>{'VersionNo': versionController.text};
                          if (!isFolder) {
                            const statusCodes = {'Pendiente': 'PD', 'En revisión': 'IR', 'Entregado': 'DL'};
                            body['Status'] = statusCodes[currentStatus] ?? currentStatus;
                          }

                          // Usamos la tabla correcta (si estamos dentro de carpeta es Related)
                          final success = await DocumentsLogic.updateDocumentRemote(details['id'], body, tableName: tableName);

                          setStateDialog(() => isSaving = false);
                          if (success) {
                            // Actualizar la memoria local para que se refleje inmediatamente
                            details['VersionNo'] = body['VersionNo'];
                            if (body.containsKey('Status')) {
                              details['Status'] = body['Status'];
                            }

                            if (context.mounted) {
                              Navigator.pop(context);
                              setState(() {}); // Refleja el cambio visualmente en la grilla

                              // Si estamos dentro de una carpeta y cambiamos el estado, verificar la carpeta padre
                              if (_currentPath.length > 3 && !isFolder) {

                                // Buscamos el ID de la carpeta padre en la lista actual (que son los hijos) no es posible directamente.
                                // Pero _documents en este contexto (dentro de carpeta) son los hijos.
                                // Necesitamos el ID de la carpeta padre. Lo podemos obtener de 'PRIM_Documents_ID' del hijo si existe.
                                final parentId = details['PRIM_Documents_ID'] is Map ? details['PRIM_Documents_ID']['id'] : details['PRIM_Documents_ID'];
                                if (parentId != null) {
                                  await DocumentsLogic.checkAndUpdateFolderStatus(parentId);
                                }
                              }
                            }
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPropertyRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          const Divider(),
        ],
      ),
    );
  }
}
