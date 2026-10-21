import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:universal_html/html.dart' as html;
import 'package:primhub/ui/widgets/duration_formatter.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/api/access_control.dart';

import 'package:primhub/api/token.dart';

class ExportFunctions {
  static String _sanitizeText(String text) {
    return text
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('•', '*')
        .replaceAll('\u2022', '*');
  }

  static List<List<String>> _prepareData(List<Map<String, dynamic>> requests, {bool isMyRequests = false, bool isPdf = false}) {
    final List<List<String>> rows = [];
    if (isMyRequests) {
      List<String> headers = ['Ticket', 'Estado'];
      if (AccessControl.isAdmin || AccessControl.isSupport) headers.add('Tipo de Solicitud');
      headers.addAll(['Categoría', 'Asunto', 'Prioridad']);
      if (AccessControl.isAdmin) {
        headers.addAll(['Tercero', 'Usuario', 'Rep. Comercial']);
      }
      headers.addAll(['Descripción', 'Horas Consumidas', 'Ficha de Producto']);
      if (AccessControl.isAdmin) {
        headers.addAll(['Creado', 'Creado por']);
      } else {
        headers.add('Creado');
      }
      rows.add(headers);
    } else {
      List<String> headers = ['Ticket', 'Descripción', 'Estado', 'Horas Consumidas', 'Ficha de Producto'];
      if (AccessControl.isAdmin) {
        headers.addAll(['Creado', 'Creado por']);
      } else {
        headers.add('Creado');
      }
      rows.add(headers);
    }

    for (var req in requests) {
      final double h = (req['qtySpent'] as num?)?.toDouble() ?? 0.0;
      final hours = DurationFormatter.format(h);
      
      String chipDesc = 'N/A';
      final chipId = req['productChipId'];
      if (chipId != null) {
        final found = GlobalCache.productChips.firstWhere(
          (c) => c['id'] == chipId,
          orElse: () => <String, dynamic>{},
        );
        if (found.isNotEmpty) {
          chipDesc = (found['Description'] ?? found['Name'] ?? '#$chipId').toString();
        } else {
          chipDesc = '#$chipId';
        }
      }

      String description = (req['descriptionClean'] ?? '').toString().replaceAll('\n', ' ').replaceAll('\r', '');
      description = _sanitizeText(description);
      if (isPdf && description.length > 300) {
        description = '${description.substring(0, 297)}...';
      }

      final original = req['original'] as Map<String, dynamic>? ?? {};
      final createdRaw = original['Created']?.toString() ?? req['created']?.toString() ?? '';
      String createdFormatted = createdRaw;
      if (createdRaw.isNotEmpty) {
        try {
          final dt = DateTime.parse(createdRaw);
          final day = dt.day.toString().padLeft(2, '0');
          final month = dt.month.toString().padLeft(2, '0');
          final year = dt.year.toString();
          final hour24 = dt.hour;
          final minute = dt.minute.toString().padLeft(2, '0');
          final ampm = hour24 >= 12 ? 'PM' : 'AM';
          final hour12 = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24);
          final hourStr = hour12.toString().padLeft(2, '0');
          createdFormatted = '$day/$month/$year $hourStr:$minute $ampm';
        } catch (_) {
          createdFormatted = createdRaw.length >= 19 ? createdRaw.substring(0, 19) : createdRaw;
        }
      }

      String createdBy = (req['createdByName']?.toString().isNotEmpty == true)
          ? req['createdByName'].toString()
          : (original['CreatedBy'] is Map 
              ? (original['CreatedBy']['identifier'] ?? original['CreatedBy']['Name'] ?? '') 
              : '');
      if (createdBy.isEmpty && original['CreatedBy'] != null) {
        final cById = (original['CreatedBy'] is num) ? original['CreatedBy'].toInt() : int.tryParse(original['CreatedBy'].toString());
        if (cById != null) {
          final found = GlobalCache.users.firstWhere((u) => ((u['AD_User_ID'] ?? u['id']) as num?)?.toInt() == cById, orElse: () => {});
          if (found.isNotEmpty) createdBy = (found['Name'] ?? '').toString().trim();
        }
      }

      if (isMyRequests) {
        final catData = original['R_Category_ID'];
        String catName = '';
        int? catId;
        if (catData is Map) {
          catId = (catData['id'] as num?)?.toInt();
        } else if (catData is num) {
          catId = catData.toInt();
        }
        
        if (catId != null) {
          final catInCache = GlobalCache.rawCategories.firstWhere(
            (c) => (c['id'] as num?)?.toInt() == catId,
            orElse: () => <String, dynamic>{},
          );
          if (catInCache.isNotEmpty && catInCache['showinprimhub'] == true) {
            catName = catInCache['Name']?.toString() ?? catInCache['identifier']?.toString() ?? '';
          }
        }
        final finalCatName = catName.isNotEmpty ? catName : 'Sin Categoría';
        
        String asunto = req['emailSubject']?.toString() ?? original['Summary']?.toString() ?? '';
        if (isPdf && asunto.length > 150) {
          asunto = '${asunto.substring(0, 147)}...';
        }
        
        final prioData = original['Priority'];
        final priority = prioData is Map ? (prioData['Name'] ?? prioData['identifier'] ?? '') : prioData?.toString() ?? '';
        
        final bpData = original['C_BPartner_ID'];
        final bpName = bpData is Map ? (bpData['Name'] ?? bpData['identifier'] ?? '') : '';
        
        final userData = original['AD_User_ID'];
        final userName = userData is Map ? (userData['Name'] ?? userData['identifier'] ?? '') : '';
        
        final repData = original['SalesRep_ID'];
        final repName = repData is Map ? (repData['Name'] ?? repData['identifier'] ?? '') : '';
        
        List<String> row = [
          req['id']?.toString() ?? '',
          _sanitizeText((req['status'] ?? '').toString()),
        ];
        if (AccessControl.isAdmin || AccessControl.isSupport) {
          row.add(_sanitizeText(req['situation']?.toString() ?? 'Sin tipo'));
        }
        row.addAll([
          _sanitizeText(finalCatName),
          _sanitizeText(asunto),
          _sanitizeText(priority),
        ]);
        if (AccessControl.isAdmin) {
          row.addAll([
            _sanitizeText(bpName.toString()),
            _sanitizeText(userName.toString()),
            _sanitizeText(repName.toString()),
          ]);
        }
        row.addAll([
          description,
          hours,
          _sanitizeText(chipDesc),
        ]);
        if (AccessControl.isAdmin) {
          row.addAll([
            _sanitizeText(createdFormatted),
            _sanitizeText(createdBy),
          ]);
        } else {
          row.add(_sanitizeText(createdFormatted));
        }
        rows.add(row);
      } else {
        List<String> row = [
          req['id']?.toString() ?? '',
          description,
          _sanitizeText((req['status'] ?? '').toString()),
          hours,
          _sanitizeText(chipDesc),
        ];
        if (AccessControl.isAdmin) {
          row.addAll([
            _sanitizeText(createdFormatted),
            _sanitizeText(createdBy),
          ]);
        } else {
          row.add(_sanitizeText(createdFormatted));
        }
        rows.add(row);
      }
    }

    return rows;
  }

  static Future<void> _saveFile(List<int> bytes, String fileName, BuildContext context, String mimeType) async {
    try {
      if (kIsWeb) {
        final blob = html.Blob([bytes], mimeType);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", fileName)
          ..click();
        var _ = anchor;
        html.Url.revokeObjectUrl(url);
        if (context.mounted) {
          ToastMessage.show(context: context, message: 'Descarga iniciada en el navegador.', type: ToastType.help);
        }
      } else {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar como...',
          fileName: fileName,
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsBytes(bytes);
          if (context.mounted) {
            ToastMessage.show(context: context, message: 'Archivo guardado exitosamente en: $outputFile', type: ToastType.help);
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ToastMessage.show(context: context, message: 'Error al guardar el archivo: $e', type: ToastType.failure);
      }
    }
  }

  static Future<void> exportToCsv(List<Map<String, dynamic>> requests, BuildContext context, {bool isMyRequests = false}) async {
    try {
      final rows = _prepareData(requests, isMyRequests: isMyRequests, isPdf: false);
      rows.add([]);
      rows.add(['Generado desde Primhub']);
      
      String csv = rows.map((r) => r.map((c) => '"${c.toString().replaceAll('"', '""')}"').join(',')).join('\n');
      // Añadir BOM para que excel detecte el UTF-8 correctamente
      final bytes = [0xEF, 0xBB, 0xBF] + utf8.encode(csv);
      final dateStr = DateTime.now().toString().split(' ')[0];
      await _saveFile(bytes, 'Horas de Soporte - $dateStr.csv', context, 'text/csv;charset=utf-8');
    } catch (e) {
      if (context.mounted) {
        ToastMessage.show(context: context, message: 'Error generando CSV: $e', type: ToastType.failure);
      }
    }
  }

  static Future<void> exportToExcel(List<Map<String, dynamic>> requests, BuildContext context, {bool isMyRequests = false}) async {
    try {
      final rows = _prepareData(requests, isMyRequests: isMyRequests, isPdf: false);
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Horas_Soporte'];
      excel.setDefaultSheet('Horas_Soporte');
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      // Agregando las filas al sheet
      for (var row in rows) {
        sheetObject.appendRow(row.map((e) => TextCellValue(e)).toList());
      }
      
      sheetObject.appendRow([TextCellValue('')]);
      sheetObject.appendRow([TextCellValue('Generado desde Primhub')]);

      if (rows.isNotEmpty) {
        final headerRow = rows.first;
        final headerStyle = CellStyle(
          bold: true,
          fontColorHex: ExcelColor.white,
          backgroundColorHex: ExcelColor.blueGrey800,
          verticalAlign: VerticalAlign.Center,
          horizontalAlign: HorizontalAlign.Left,
        );

        for (int i = 0; i < headerRow.length; i++) {
          final cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
          cell.cellStyle = headerStyle;

          final header = headerRow[i];
          int maxLen = header.length;
          for (int r = 1; r < rows.length; r++) {
            if (i < rows[r].length) {
              final len = rows[r][i].length;
              if (len > maxLen) {
                maxLen = len;
              }
            }
          }

          double colWidth = (maxLen + 4).toDouble();

          switch (header) {
            case 'Ticket':
              colWidth = colWidth.clamp(14.0, 18.0);
              break;
            case 'Estado':
              colWidth = colWidth.clamp(16.0, 22.0);
              break;
            case 'Tipo de Solicitud':
              colWidth = colWidth.clamp(20.0, 28.0);
              break;
            case 'Categoría':
              colWidth = colWidth.clamp(20.0, 28.0);
              break;
            case 'Asunto':
              colWidth = colWidth.clamp(28.0, 48.0);
              break;
            case 'Prioridad':
              colWidth = colWidth.clamp(14.0, 18.0);
              break;
            case 'Tercero':
              colWidth = colWidth.clamp(22.0, 36.0);
              break;
            case 'Usuario':
              colWidth = colWidth.clamp(20.0, 30.0);
              break;
            case 'Rep. Comercial':
              colWidth = colWidth.clamp(20.0, 30.0);
              break;
            case 'Descripción':
              colWidth = colWidth.clamp(45.0, 60.0);
              break;
            case 'Horas Consumidas':
              colWidth = colWidth.clamp(18.0, 22.0);
              break;
            case 'Ficha de Producto':
              colWidth = colWidth.clamp(20.0, 28.0);
              break;
            case 'Creado':
              colWidth = colWidth.clamp(22.0, 26.0);
              break;
            case 'Creado por':
              colWidth = colWidth.clamp(20.0, 30.0);
              break;
            default:
              colWidth = colWidth.clamp(15.0, 35.0);
          }

          sheetObject.setColumnWidth(i, colWidth);
        }

        sheetObject.setDefaultRowHeight(20.0);
        sheetObject.setRowHeight(0, 26.0);
      }

      var bytes = excel.encode();
      if (bytes != null) {
        final dateStr = DateTime.now().toString().split(' ')[0];
        await _saveFile(bytes, 'Horas de Soporte - $dateStr.xlsx', context, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      }
    } catch (e) {
      if (context.mounted) {
        ToastMessage.show(context: context, message: 'Error generando Excel: $e', type: ToastType.failure);
      }
    }
  }

  static Future<void> exportToPdf(List<Map<String, dynamic>> requests, BuildContext context, {bool isMyRequests = false}) async {
    try {
      final rows = _prepareData(requests, isMyRequests: isMyRequests, isPdf: true);
      final pdf = pw.Document(
        title: 'Reporte de Horas de Soporte',
        author: 'Primhub',
        creator: 'Primhub',
        producer: 'Primhub Export',
      );

      String userName = User.name ?? 'Usuario Desconocido';
      String bPartnerName = 'Sin Tercero';
      if (User.cBPartnerID != null) {
        final bp = GlobalCache.allBPartners.firstWhere(
          (b) => b['id'] == User.cBPartnerID,
          orElse: () => <String, dynamic>{},
        );
        if (bp.isNotEmpty) {
          bPartnerName = bp['Name'] ?? 'Tercero Desconocido';
        }
      }

      // Fuente predeterminada para evitar problemas con acentos en web/desktop
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context ctx) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Reporte de Horas de Soporte', textScaleFactor: 2),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Fecha: ${DateTime.now().toString().split(' ')[0]}'),
                        pw.Text('Generado por: $userName'),
                        pw.Text('Tercero: $bPartnerName'),
                      ]
                    )
                  ]
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Builder(
                builder: (context) {
                  Map<int, pw.TableColumnWidth> widths = {};
                  final headerRow = rows.first;
                  for (int i = 0; i < headerRow.length; i++) {
                    final h = headerRow[i];
                    if (h == 'Descripción') {
                      widths[i] = pw.FlexColumnWidth(isMyRequests ? 2.5 : 3.5);
                    } else if (h == 'Asunto') {
                      widths[i] = const pw.FlexColumnWidth(1.8);
                    } else if (h == 'Ticket' || h == 'Estado' || h == 'Horas Consumidas') {
                      widths[i] = const pw.FlexColumnWidth(0.8);
                    } else if (h == 'Creado') {
                      widths[i] = const pw.FlexColumnWidth(1.4);
                    } else if (h == 'Creado por') {
                      widths[i] = const pw.FlexColumnWidth(1.2);
                    } else {
                      widths[i] = const pw.FlexColumnWidth(1.1);
                    }
                  }
                  
                  return pw.TableHelper.fromTextArray(
                    context: ctx,
                    data: rows,
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: isMyRequests ? 6.5 : 9),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                    rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blueGrey100, width: .5))),
                    cellAlignment: pw.Alignment.centerLeft,
                    columnWidths: widths,
                    cellStyle: pw.TextStyle(fontSize: isMyRequests ? 5.5 : 8.5),
                    headerHeight: isMyRequests ? 18 : 24,
                    cellHeight: isMyRequests ? 14 : 18,
                  );
                }
              ),
            ];
          },
          footer: (pw.Context ctx) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Text(
                'Generado desde Primhub - Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(color: PdfColors.grey, fontSize: 10),
              ),
            );
          },
        ),
      );

      final bytes = await pdf.save();
      final dateStr = DateTime.now().toString().split(' ')[0];
      await _saveFile(bytes, 'Horas de Soporte - $dateStr.pdf', context, 'application/pdf');
    } catch (e) {
      if (context.mounted) {
        ToastMessage.show(context: context, message: 'Error generando PDF: $e', type: ToastType.failure);
      }
    }
  }
}
