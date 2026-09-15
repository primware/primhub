import 'package:flutter/material.dart';

import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:flutter_localization/flutter_localization.dart';

class PhaseCreateDialog extends StatefulWidget {
  final Function(Map<String, dynamic> data) onSave;

  const PhaseCreateDialog({super.key, required this.onSave});

  @override
  State<PhaseCreateDialog> createState() => _PhaseCreateDialogState();
}

class _PhaseCreateDialogState extends State<PhaseCreateDialog> {
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
      title: AppLocale.newPhase.getString(context),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomTextField(controller: nameController, label: AppLocale.nameRequired.getString(context)),
            const SizedBox(height: 16),
            CustomTextField(controller: descController, label: AppLocale.description.getString(context), maxLines: 2),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: CustomTextField(
                    controller: seqNoController,
                    label: AppLocale.sequenceRequired.getString(context),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _isLoadingRules
                      ? const Center(child: CircularProgressIndicator())
                      : CustomDropdown<String>(
                          value: invoiceRule,
                          label: AppLocale.invoiceRuleRequired.getString(context),
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
                    label: AppLocale.plannedPriceRequired.getString(context),
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
        CustomButton(
          text: AppLocale.cancel.getString(context),
          backgroundColor: Colors.white,
          textColor: Theme.of(context).colorScheme.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        CustomButton(
          text: AppLocale.save.getString(context),
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
