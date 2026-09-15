import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';

class TaskCreateDialog extends StatefulWidget {
  final Function(Map<String, dynamic> data) onSave;

  const TaskCreateDialog({super.key, required this.onSave});

  @override
  State<TaskCreateDialog> createState() => _TaskCreateDialogState();
}

class _TaskCreateDialogState extends State<TaskCreateDialog> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController descController = TextEditingController();
  final TextEditingController seqNoController = TextEditingController(text: '10');
  final TextEditingController plannedAmtController = TextEditingController(text: '0.0');
  final TextEditingController committedAmtController = TextEditingController(text: '0.0');
  String? invoiceRule;
  List<Map<String, String>> _invoiceRules = [];
  bool _isLoadingRules = true;
  final ProjectsLogic _logic = ProjectsLogic();

  @override
  void initState() {
    super.initState();
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
          if (rules.isNotEmpty) invoiceRule = rules.first['Value'];
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
    return CustomModal(
      title: 'Nueva Tarea',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomTextField(controller: nameController, label: 'Nombre *'),
            const SizedBox(height: 16),
            CustomTextField(controller: descController, label: AppLocale.description.getString(context), maxLines: 2),
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
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocale.cancel.getString(context))),
        CustomButton(
          text: 'Crear',
          isLoading: _isLoadingRules,
          onPressed: _isLoadingRules ? null : () {
            if (nameController.text.isNotEmpty) {
              widget.onSave({
                'Name': nameController.text,
                'Description': descController.text,
                'SeqNo': int.tryParse(seqNoController.text) ?? 10,
                'ProjInvoiceRule': invoiceRule,
                'PlannedAmt': double.tryParse(plannedAmtController.text) ?? 0.0,
                'CommittedAmt': double.tryParse(committedAmtController.text) ?? 0.0,
              });
              Navigator.pop(context);
            }
          },
        ),
      ],
    );
  }
}
