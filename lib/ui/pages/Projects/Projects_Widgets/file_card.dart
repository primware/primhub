import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class FileCard extends StatefulWidget {
  final String extension;
  final String name;
  final String size;
  final Color color;
  final int charLimit;
  final bool isFolder;
  final Map<String, dynamic> details;
  final VoidCallback onTap;
  final VoidCallback? onDownload;
  final VoidCallback? onProperties;
  final bool isDownloading;
  final String tableName;
  final Function(Map<String, dynamic> doc, String tableName, int targetFolderId)? onMoveToFolder;
  final Function(int draggedId, int targetId)? onReorder;
  final int columns;

  const FileCard({
    super.key,
    required this.extension,
    required this.name,
    required this.size,
    required this.color,
    required this.charLimit,
    required this.details,
    required this.onTap,
    this.isFolder = false,
    this.onDownload,
    this.onProperties,
    this.isDownloading = false,
    required this.tableName,
    this.onMoveToFolder,
    this.onReorder,
    this.columns = 5,
  });

  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  bool _isHovered = false;
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final String visualName = (widget.details['Description'] != null && widget.details['Description'].toString().trim().isNotEmpty)
        ? widget.details['Description'].toString()
        : widget.name;
    final bool isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(widget.extension.toLowerCase());
    final bool isCompact = widget.columns >= 8 || MediaQuery.of(context).size.width < 500;

    // Colores basados en el tipo de archivo/carpeta
    final baseColor = widget.isFolder ? Colors.amber.shade700 : widget.color;
    final highlightColor = _isDragOver ? Colors.blue.shade600 : baseColor;

    Widget cardContent = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _isDragOver ? Colors.blue.withOpacity(0.05) : theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isDragOver 
                  ? Colors.blue.shade400 
                  : (_isHovered ? baseColor.withOpacity(0.5) : colorScheme.outlineVariant.withOpacity(0.3)),
              width: (_isHovered || _isDragOver) ? 2 : 1,
            ),
            boxShadow: (_isHovered || _isDragOver)
                ? [
                    BoxShadow(
                      color: (_isDragOver ? Colors.blue : baseColor).withOpacity(0.15),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                      spreadRadius: 2,
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ÁREA SUPERIOR (Icono / Preview)
                  Expanded(
                    flex: 55,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            highlightColor.withOpacity((_isHovered || _isDragOver) ? 0.15 : 0.08),
                            highlightColor.withOpacity((_isHovered || _isDragOver) ? 0.08 : 0.03),
                          ],
                        ),
                      ),
                      child: widget.isFolder
                          ? Hero(
                              tag: 'folder_${widget.details['id']}',
                              child: Icon(
                                Icons.folder_rounded,
                                color: highlightColor.withOpacity((_isHovered || _isDragOver) ? 1.0 : 0.8),
                                size: isCompact ? 56 : 80,
                              ),
                            )
                          : (isImage
                              ? FutureBuilder<Uint8List?>(
                                  future: DocumentsLogic.fetchImagePreview(widget.tableName, widget.details['id'], widget.name),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData && snapshot.data != null) {
                                      return AnimatedOpacity(
                                        duration: const Duration(milliseconds: 300),
                                        opacity: (_isHovered || _isDragOver) ? 0.9 : 1.0,
                                        child: Image.memory(
                                          snapshot.data!,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                          gaplessPlayback: true,
                                        ),
                                      );
                                    }
                                    return Center(
                                      child: Icon(
                                        DocumentsLogic.getFileIcon(widget.extension),
                                        color: highlightColor,
                                        size: isCompact ? 48 : 72,
                                      ),
                                    );
                                  },
                                )
                              : Center(
                                  child: Icon(
                                    DocumentsLogic.getFileIcon(widget.extension),
                                    color: highlightColor.withOpacity((_isHovered || _isDragOver) ? 1.0 : 0.7),
                                    size: isCompact ? 48 : 72,
                                  ),
                                )),
                    ),
                  ),
                  // ÁREA INFERIOR (Info)
                  Expanded(
                    flex: 45,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 6.0 : 12.0,
                        vertical: 8.0,
                      ),
                      decoration: BoxDecoration(
                        color: (_isHovered || _isDragOver) ? highlightColor.withOpacity(0.02) : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            visualName,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: (_isHovered || _isDragOver) ? FontWeight.bold : FontWeight.w600,
                              fontSize: isCompact ? 11 : 12.5,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!widget.isFolder && !isCompact) ...[
                            const SizedBox(height: 6),
                            _buildStatusChip(context),
                          ],
                          if (widget.isFolder && widget.size.isNotEmpty && !isCompact) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.size,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                                fontSize: 10,
                              ),
                            ),
                          ],
                          if (widget.isDownloading)
                            const Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          else if (!isCompact)
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Icon(
                                widget.isFolder ? Icons.open_in_new_rounded : Icons.file_download_outlined,
                                color: (_isHovered || _isDragOver) ? highlightColor : colorScheme.primary.withOpacity(0.5),
                                size: 16,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // BOTÓN INFO (Propiedades)
              if (AccessControl.canManageFiles && widget.onProperties != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isHovered ? 1.0 : 0.0,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.onProperties,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: theme.cardColor.withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                          ),
                          child: Icon(Icons.info_outline_rounded, color: baseColor, size: 18),
                        ),
                      ),
                    ),
                  ),
                ),
              // INDICADOR DRAG
              if (AccessControl.canManageFiles)
                Positioned(
                  top: 4,
                  left: 4,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: (_isHovered || _isDragOver) ? 0.8 : 0.2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme.cardColor.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.drag_indicator_rounded, color: colorScheme.onSurfaceVariant, size: 18),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    Widget dropRegion = DropRegion(
      formats: Formats.standardFormats,
      onDropEnter: (event) {
        setState(() => _isDragOver = true);
      },
      onDropLeave: (event) {
        setState(() => _isDragOver = false);
      },
      onDropOver: (event) {
        if (event.session.items.isEmpty) return DropOperation.none;
        final item = event.session.items.first;
        if (item.localData != null && item.localData is Map) {
          final data = item.localData as Map;
          if (data['id'] == widget.details['id']) return DropOperation.none;

          // REGLA: Si soltamos sobre una CARPETA, movemos adentro.
          // Si soltamos sobre un ARCHIVO, reordenamos.
          if (widget.isFolder) {
            return DropOperation.move; // Mostramos cursor de mover para carpetas
          } else {
            return DropOperation.copy;
          }
        }
        return DropOperation.none;
      },
      onPerformDrop: (event) async {
        setState(() => _isDragOver = false);
        final item = event.session.items.first;
        if (item.localData is Map) {
          final data = item.localData as Map;
          if (widget.isFolder) {
            widget.onMoveToFolder?.call(data['doc'], data['tableName'], widget.details['id']);
          } else {
            widget.onReorder?.call(data['id'], widget.details['id']);
          }
        }
      },
      child: cardContent,
    );

    if (AccessControl.canManageFiles) {
      return DragItemWidget(
        dragItemProvider: (request) {
          final item = DragItem(
            localData: {
              'id': widget.details['id'],
              'tableName': widget.tableName,
              'type': widget.isFolder ? 'folder' : 'file',
              'doc': widget.details
            },
          );
          item.add(Formats.plainText(widget.name));
          return item;
        },
        allowedOperations: () => [DropOperation.copy, DropOperation.move],
        child: DraggableWidget(child: dropRegion),
      );
    }

    return dropRegion;
  }

  Widget _buildStatusChip(BuildContext context) {
    final status = DocumentsLogic.extractStatus(widget.details['Status']);
    final statusColor = DocumentsLogic.getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        status,
        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 9.5),
      ),
    );
  }
}
