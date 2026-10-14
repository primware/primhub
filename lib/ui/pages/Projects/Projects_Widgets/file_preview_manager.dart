import 'dart:convert';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:primhub/ImagesManagment/download_attachments.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FilePreviewManager {
  static void showPreview(
    BuildContext context,
    Map<String, dynamic> details,
    String tableName,
    String name,
    VoidCallback onDelete,
    VoidCallback onStatusChanged, {
    bool canDelete = false,
  }) {
    final extension = name.split('.').last.toLowerCase();
    final isImage = [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
    ].contains(extension);
    final isPdf = extension == 'pdf';
    final isCsv = extension == 'csv';
    final isText = ['txt', 'json', 'xml', 'md', 'log'].contains(extension);
    bool isDownloading = false;

    String currentVisualName =
        (details['Description'] != null &&
            details['Description'].toString().trim().isNotEmpty)
        ? details['Description'].toString()
        : name.split('.').first;
    final TextEditingController visualNameController = TextEditingController(
      text: currentVisualName,
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final theme = Theme.of(context);
            return CustomModal(
              title: 'Vista Previa: $currentVisualName',
              width: 600,
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  CustomTextField(
                    controller: visualNameController,
                    label: 'Nombre Visual (Etiqueta)',
                    readOnly: !AccessControl.canManageFiles,
                  ),
                  const SizedBox(height: 12),
                  if (isImage || isPdf || isText || isCsv)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 16, 4),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.light
                              ? Colors.grey[50]
                              : Colors.grey[900],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.5),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: FutureBuilder<Uint8List?>(
                          future: DocumentsLogic.fetchImagePreview(
                            tableName,
                            details['id'],
                            name,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox(
                                height: 200,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            if (snapshot.hasData && snapshot.data != null) {
                              Widget previewWidget;
                              if (isImage) {
                                previewWidget = Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.contain,
                                );
                              } else if (isPdf) {
                                previewWidget = PdfPreview(
                                  build: (format) async => snapshot.data!,
                                  allowPrinting: false,
                                  allowSharing: false,
                                  canChangeOrientation: false,
                                  canChangePageFormat: false,
                                  canDebug: false,
                                  padding: const EdgeInsets.all(8),
                                );
                              } else if (isCsv) {
                                previewWidget = _buildCsvPreview(snapshot.data!);
                              } else if (isText) {
                                previewWidget = _buildTextPreview(snapshot.data!);
                              } else {
                                previewWidget = const Center(child: Text('No disponible'));
                              }

                              return Stack(
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 500,
                                      minHeight: 200,
                                      minWidth: double.infinity,
                                    ),
                                    child: Center(
                                      child: isPdf 
                                        ? SizedBox(
                                            height: 500,
                                            child: ScrollConfiguration(
                                              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: true),
                                              child: previewWidget,
                                            ),
                                          )
                                        : previewWidget,
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.fullscreen, color: Colors.white),
                                        tooltip: 'Ampliar',
                                        onPressed: () => _showFullScreenPreview(context, previewWidget, currentVisualName),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                            return const Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Center(
                                child: Text(
                                  'No se pudo cargar la previsualización',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  else
                    _buildNoPreviewWidget(extension),
                  const SizedBox(height: 20),
                  _buildPropertyRow('Nombre Real', name),
                  _buildPropertyRow(
                    'Estado',
                    DocumentsLogic.extractStatus(details['Status']),
                  ),
                  _buildPropertyRow(
                    'Versión',
                    DocumentsLogic.extractIdentifier(details['VersionNo']),
                  ),
                ],
              ),
              actions: [
                // Fila superior: Eliminar a la izquierda, Cerrar a la derecha
                Row(
                  children: [
                    if (canDelete)
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        tooltip: 'Eliminar',
                        onPressed: () {
                          Navigator.pop(context);
                          onDelete();
                        },
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cerrar',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    if (AccessControl.canManageFiles)
                      CustomButton(
                        text: 'Guardar',
                        icon: Icons.save,
                        onPressed: () async {
                          setStateDialog(() {
                            currentVisualName = visualNameController.text;
                          });
                          details['Description'] = currentVisualName;
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString(
                            'doc_visual_${details['id']}',
                            currentVisualName,
                          );
                          onStatusChanged();
                          if (context.mounted) {
                            ToastMessage.show(
                              context: context,
                              message: 'Nombre visual actualizado',
                              type: ToastType.success,
                            );
                          }
                        },
                      ),
                  ],
                ),
                // Botón de descarga prominente
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: CustomButton(
                    text: 'Descargar Documento',
                    icon: Icons.download,
                    width: double.infinity,
                    isLoading: isDownloading,
                    onPressed: !AccessControl.canDownloadFiles
                        ? null
                        : () async {
                            setStateDialog(() => isDownloading = true);
                            await downloadAttachment(
                              context: context,
                              recordID: details['id'],
                              tableName: tableName,
                              fileName: name,
                              onStatusChanged: () {
                                if (AccessControl.isProject) {
                                  details['Status'] = 'Entregado';
                                }
                                onStatusChanged();
                              },
                            );
                            if (context.mounted) {
                              setStateDialog(() => isDownloading = false);
                            }
                          },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static void _showFullScreenPreview(BuildContext context, Widget previewWidget, String visualName) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: previewWidget,
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildCsvPreview(Uint8List data) {
    try {
      String content = utf8.decode(data, allowMalformed: true);
      List<String> lines = content.split('\n');
      if (lines.isEmpty) return const Text('Archivo vacío');
      List<List<String>> rows = lines
          .where((l) => l.trim().isNotEmpty)
          .map((line) => line.split(','))
          .toList();
      if (rows.isEmpty) return const Text('Archivo vacío');
      return Container(
        height: 400,
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: rows.first
                  .map((e) => DataColumn(label: Text(e.trim())))
                  .toList(),
              rows: rows.skip(1).map((row) {
                final cells = row.take(rows.first.length).toList();
                while (cells.length < rows.first.length) {
                  cells.add('');
                }
                return DataRow(
                  cells: cells
                      .map((cell) => DataCell(Text(cell.trim())))
                      .toList(),
                );
              }).toList(),
            ),
          ),
        ),
      );
    } catch (e) {
      return const Text('Error al visualizar CSV');
    }
  }

  static Widget _buildTextPreview(Uint8List data) {
    String textContent = "Error al decodificar.";
    try {
      textContent = utf8.decode(data, allowMalformed: true);
    } catch (_) {
      // Ignored: Fail silently
    }
    return Container(
      height: 400,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(child: SelectableText(textContent)),
    );
  }

  static Widget _buildNoPreviewWidget(String extension) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(
            DocumentsLogic.getFileIcon(extension),
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Previsualización no disponible para .$extension',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  static Widget _buildPropertyRow(String title, String value) {
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
