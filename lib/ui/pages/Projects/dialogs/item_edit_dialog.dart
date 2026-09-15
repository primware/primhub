import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';

class ItemEditDialog extends StatefulWidget {
  final String type;
  final String currentName;
  final String currentDesc;
  final Map<String, dynamic>? currentData;
  final Function(Map<String, dynamic> data) onSave;

  const ItemEditDialog({
    super.key,
    required this.type,
    required this.currentName,
    required this.currentDesc,
    this.currentData,
    required this.onSave,
  });

  @override
  State<ItemEditDialog> createState() => _ItemEditDialogState();
}

class _ItemEditDialogState extends State<ItemEditDialog> {
  late TextEditingController nameController;
  late TextEditingController descController;
  late TextEditingController seqNoController;
  late TextEditingController plannedAmtController;
  late TextEditingController committedAmtController;
  String? invoiceRule;
  List<Map<String, String>> _invoiceRules = [];
  bool _isLoadingRules = true;
  final ProjectsLogic _logic = ProjectsLogic();

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.currentName);
    descController = TextEditingController(text: widget.currentDesc);
    
    final seqNo = widget.currentData?['SeqNo']?.toString() ?? '10';
    final planned = widget.currentData?['PlannedAmt']?.toString() ?? '0.0';
    final committed = widget.currentData?['CommittedAmt']?.toString() ?? '0.0';
    
    seqNoController = TextEditingController(text: seqNo);
    plannedAmtController = TextEditingController(text: planned);
    committedAmtController = TextEditingController(text: committed);
    
    _loadRules();
  }

  Future<void> _loadRules() async {
    try {
      final fetched = await _logic.fetchInvoiceRules();
      final List<Map<String, String>> rules = [];
      for (var r in fetched) {
        rules.add({'Name': r['Name'].toString(), 'Value': r['Value'].toString()});
      }
      if (mounted) {
        setState(() {
          _invoiceRules = rules;
          final invRule = widget.currentData?['ProjInvoiceRule']?.toString();
          if (invRule != null && invRule.isNotEmpty && rules.any((r) => r['Value'] == invRule)) {
            invoiceRule = invRule;
          } else if (rules.isNotEmpty) {
            invoiceRule = rules.first['Value'];
          }
          _isLoadingRules = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingRules = false);
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    descController.dispose();
    seqNoController.dispose();
    plannedAmtController.dispose();
    committedAmtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isProject = widget.type == 'project';

    return CustomModal(
      title: 'Editar ${isProject ? 'Proyecto' : widget.type == 'phase' ? 'Fase' : 'Tarea'}',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomTextField(controller: nameController, label: 'Nombre *'),
            const SizedBox(height: 16),
            CustomTextField(controller: descController, label: AppLocale.description.getString(context), maxLines: 2),
            if (!isProject) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CustomTextField(
                      controller: seqNoController,
                      label: 'Secuencia *',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _isLoadingRules
                        ? const Center(child: CircularProgressIndicator())
                        : CustomDropdown<String>(
                            value: invoiceRule,
                            label: 'Reglas de Factura *',
                            items: _invoiceRules.map((r) => DropdownMenuItem(value: r['Value'], child: Text(r['Name']!))).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => invoiceRule = val);
                            },
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CustomTextField(
                      controller: plannedAmtController,
                      label: 'Total Planeado *',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: CustomTextField(
                      controller: committedAmtController,
                      label: '${AppLocale.committedAmount.getString(context)} *',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        CustomButton(
          text: 'Guardar',
          isLoading: _isLoadingRules,
          onPressed: _isLoadingRules ? null : () {
            if (nameController.text.isNotEmpty) {
              final Map<String, dynamic> dataToSave = {
                'Name': nameController.text,
                'Description': descController.text,
              };
              
              if (!isProject) {
                dataToSave['SeqNo'] = int.tryParse(seqNoController.text) ?? 10;
                dataToSave['ProjInvoiceRule'] = invoiceRule;
                dataToSave['PlannedAmt'] = double.tryParse(plannedAmtController.text) ?? 0.0;
                dataToSave['CommittedAmt'] = double.tryParse(committedAmtController.text) ?? 0.0;
              }
              
              widget.onSave(dataToSave);
              Navigator.pop(context);
            }
          },
        ),
      ],
    );
  }
}
