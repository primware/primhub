import "package:flutter_quill/quill_delta.dart";
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' hide Style;
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:universal_html/html.dart' as html;
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:material_symbols_icons/symbols.dart';

class HtmlEditorUtils {
  /// Convierte un documento de Quill (Delta) a HTML
  static String deltaToHtml(Document document) {
    try {
      final deltaJson = document.toDelta().toJson();
      final converter = QuillDeltaToHtmlConverter(
        List.castFrom(deltaJson),
        ConverterOptions(
          converterOptions: OpConverterOptions(
            inlineStylesFlag: true, // Usa estilos inline en lugar de clases CSS
          ),
        ),
      );
      
      String html = converter.convert();
      if (html == '<p><br/></p>') return '';
      return html;
    } catch (e) {
      debugPrint('Error al convertir Delta a HTML: $e');
      return document.toPlainText();
    }
  }

  /// Convierte HTML simple a un Documento de Quill (Delta)
  /// Implementación básica para soportar negrita, cursiva, subrayado,
  /// saltos de línea y colores básicos.
  static Document htmlToDelta(String htmlContent) {
    if (htmlContent.isEmpty) return Document();

    try {
      // Use DomParser to parse HTML without sanitization, preserving style attributes
      final parsedDoc = html.DomParser().parseFromString('<div>$htmlContent</div>', 'text/html');
      final container = parsedDoc.querySelector('div') ?? parsedDoc.querySelector('body') ?? parsedDoc.documentElement!;
      final delta = Delta();

      void traverse(html.Node node, Map<String, dynamic> activeAttributes) {
        if (node.nodeType == html.Node.TEXT_NODE) {
          final text = node.text ?? '';
          if (text.isNotEmpty) {
            delta.insert(text, activeAttributes.isEmpty ? null : Map<String, dynamic>.from(activeAttributes));
          }
        } else if (node.nodeType == html.Node.ELEMENT_NODE) {
          final element = node as html.Element;
          final tagName = element.tagName.toLowerCase();
          final localAttributes = Map<String, dynamic>.from(activeAttributes);

          bool isBlock = false;

          switch (tagName) {
            case 'b':
            case 'strong':
              localAttributes['bold'] = true;
              break;
            case 'i':
            case 'em':
              localAttributes['italic'] = true;
              break;
            case 'u':
              localAttributes['underline'] = true;
              break;
            case 's':
            case 'strike':
            case 'del':
              localAttributes['strike'] = true;
              break;
            case 'br':
              delta.insert('\n', activeAttributes.isEmpty ? null : Map<String, dynamic>.from(activeAttributes));
              return;
            case 'p':
            case 'div':
              isBlock = true;
              break;
            case 'ul':
            case 'ol':
              for (final child in element.nodes) {
                traverse(child, localAttributes);
              }
              return;
            case 'li':
              final liAttributes = Map<String, dynamic>.from(activeAttributes);
              html.Element? parent = element.parent;
              String type = 'bullet';
              if (parent != null && parent.tagName.toLowerCase() == 'ol') {
                type = 'ordered';
              }
              for (final child in element.nodes) {
                traverse(child, liAttributes);
              }
              delta.insert('\n', {'list': type});
              return;
          }

          final styleAttr = element.getAttribute('style');
          if (styleAttr != null) {
            final colorMatch = RegExp(r'color\s*:\s*(#[0-9a-fA-F]{6}|[a-zA-Z]+)').firstMatch(styleAttr);
            if (colorMatch != null) {
              localAttributes['color'] = colorMatch.group(1);
            }
            final bgMatch = RegExp(r'background-color\s*:\s*(#[0-9a-fA-F]{6}|[a-zA-Z]+)').firstMatch(styleAttr);
            if (bgMatch != null) {
              localAttributes['background'] = bgMatch.group(1);
            }
            if (styleAttr.contains('text-decoration')) {
              if (styleAttr.contains('line-through')) {
                localAttributes['strike'] = true;
              }
              if (styleAttr.contains('underline')) {
                localAttributes['underline'] = true;
              }
            }
          }

          if (tagName == 'font') {
            final colorAttr = element.getAttribute('color');
            if (colorAttr != null) {
              localAttributes['color'] = colorAttr.startsWith('#') ? colorAttr : '#$colorAttr';
            }
          }

          for (final child in element.nodes) {
            traverse(child, localAttributes);
          }

          if (isBlock) {
            final lastOp = delta.isNotEmpty ? delta.last : null;
            bool endsWithNewline = false;
            if (lastOp != null && lastOp.value is String) {
              endsWithNewline = (lastOp.value as String).endsWith('\n');
            }
            if (!endsWithNewline) {
              delta.insert('\n');
            }
          }
        }
      }

      for (final node in container.nodes) {
        traverse(node, {});
      }

      final doc = Document.fromDelta(delta);
      final text = doc.toPlainText();
      if (!text.endsWith('\n')) {
        doc.insert(doc.length, '\n');
      }
      return doc;
    } catch (e) {
      debugPrint('Error al convertir HTML a Delta: $e');
      return Document()..insert(0, htmlContent);
    }
  }

  static bool isDeltaEmpty(Delta delta) {
    final buffer = StringBuffer();
    for (final op in delta.toList()) {
      if (op.isInsert && op.data is String) {
        buffer.write(op.data as String);
      }
    }
    return buffer.toString().trim().isEmpty;
  }

  static Future<void> showColorPicker(BuildContext context, QuillController controller, bool isBackground) async {
    Color? selectedColor;
    final colors = [
      Colors.transparent,
      Colors.black, Colors.white, Colors.grey, Colors.red,
      Colors.orange, Colors.yellow, Colors.green, Colors.blue,
      Colors.indigo, Colors.purple, Colors.pink, Colors.brown,
    ];
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Seleccionar color', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((c) => GestureDetector(
            onTap: () {
              selectedColor = c;
              Navigator.pop(ctx);
            },
            child: c == Colors.transparent
                ? Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey),
                    ),
                    child: const Icon(Icons.format_color_reset, size: 24, color: Colors.grey),
                  )
                : Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey),
                    ),
                  ),
          )).toList(),
        ),
      ),
    );

    if (selectedColor != null) {
      if (selectedColor == Colors.transparent) {
        controller.formatSelection(
          isBackground ? const BackgroundAttribute(null) : const ColorAttribute(null)
        );
      } else {
        var hex = selectedColor!.value.toRadixString(16).padLeft(8, '0');
        hex = '#${hex.substring(2)}';
        controller.formatSelection(
          isBackground ? BackgroundAttribute(hex) : ColorAttribute(hex)
        );
      }
    }
  }
}

class QuillExpandableField extends StatefulWidget {
  final QuillController controller;
  final String label;
  final double height;
  final bool isRequired;
  final bool readOnly;

  const QuillExpandableField({
    super.key,
    required this.controller,
    required this.label,
    this.height = 100,
    this.isRequired = false,
    this.readOnly = false,
  });

  @override
  State<QuillExpandableField> createState() => _QuillExpandableFieldState();
}

class _QuillExpandableFieldState extends State<QuillExpandableField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onEditorChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onEditorChanged);
    super.dispose();
  }

  void _onEditorChanged() {
    setState(() {});
  }

  void _openFullEditor(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return CustomModal(
          title: widget.label,
          width: 800,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QuillSimpleToolbar(
                controller: widget.controller,
                config: QuillSimpleToolbarConfig(
                  showSearchButton: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showAlignmentButtons: false,
                  showClearFormat: false,
                  showCodeBlock: false,
                  showHeaderStyle: false,
                  showIndent: false,
                  showInlineCode: false,
                  showLink: false,
                  showListCheck: false,
                  showListNumbers: false,
                  showQuote: false,
                  showUndo: true,
                  showRedo: true,
                  showBoldButton: true,
                  showItalicButton: true,
                  showUnderLineButton: true,
                  showStrikeThrough: true,
                  showColorButton: true,
                  showBackgroundColorButton: true,
                  showListBullets: true,
                  showFontFamily: false,
                  showFontSize: false,
                  buttonOptions: QuillSimpleToolbarButtonOptions(
                    bold: const QuillToolbarToggleStyleButtonOptions(iconData: Symbols.format_bold),
                    italic: const QuillToolbarToggleStyleButtonOptions(iconData: Symbols.format_italic),
                    underLine: const QuillToolbarToggleStyleButtonOptions(iconData: Symbols.format_underlined),
                    strikeThrough: const QuillToolbarToggleStyleButtonOptions(iconData: Symbols.strikethrough_s),
                    listBullets: const QuillToolbarToggleStyleButtonOptions(iconData: Symbols.format_list_bulleted),
                    undoHistory: const QuillToolbarHistoryButtonOptions(iconData: Symbols.undo),
                    redoHistory: const QuillToolbarHistoryButtonOptions(iconData: Symbols.redo),
                    color: QuillToolbarColorButtonOptions(
                      iconData: Symbols.palette,
                      customOnPressedCallback: (controller, isBackground) => HtmlEditorUtils.showColorPicker(context, controller, isBackground),
                    ),
                    backgroundColor: QuillToolbarColorButtonOptions(
                      iconData: Symbols.format_color_fill,
                      customOnPressedCallback: (controller, isBackground) => HtmlEditorUtils.showColorPicker(context, controller, isBackground),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Container(
                height: 400,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: QuillEditor.basic(
                  controller: widget.controller,
                ),
              ),
              AnimatedBuilder(
                animation: widget.controller,
                builder: (context, child) {
                  final length = widget.controller.document.toPlainText().trim().length;
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0, right: 4.0),
                      child: Text(
                        '$length / 6000',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: length > 6000 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            CustomButton(text: 'Listo', onPressed: () => Navigator.pop(context)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Hidden widget to force the Flutter Web tree-shaker to keep these icons in --release builds
        Offstage(
          child: Row(
            children: const [
              Icon(Icons.format_bold), Icon(Icons.format_italic), Icon(Icons.format_underline),
              Icon(Icons.format_strikethrough), Icon(Icons.format_list_bulleted),
              Icon(Icons.undo), Icon(Icons.redo), Icon(Icons.color_lens), Icon(Icons.format_color_fill), Icon(Icons.format_color_reset),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${widget.label}${widget.isRequired ? ' *' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    if (!widget.readOnly)
                      IconButton(
                        icon: const Icon(Icons.zoom_out_map),
                        tooltip: 'Expandir editor',
                        onPressed: () => _openFullEditor(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              InkWell(
                onTap: widget.readOnly ? null : () => _openFullEditor(context),
                child: Container(
                  height: widget.height,
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  child: SingleChildScrollView(
                    child: Html(
                      data: HtmlEditorUtils.deltaToHtml(widget.controller.document),
                      style: {
                        "body": Style(
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                          fontSize: FontSize(14),
                        ),
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
