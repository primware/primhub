import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter/services.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:flutter_localization/flutter_localization.dart';

class RequestDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> req;

  const RequestDetailsDialog({super.key, required this.req});

  @override
  Widget build(BuildContext context) {
    final summary = req['Summary'] ?? '';
    final status = DocumentsLogic.extractValue(req['Status'] ?? req['R_Status_ID']);
    final priority = DocumentsLogic.extractValue(req['Priority']);
    final dateStart = req['DateStartPlan']?.toString().split('T')[0] ?? '';
    final dateComplete = req['DateCompletePlan']?.toString().split('T')[0] ?? '';
    final qtyPlan = req['QtyPlan']?.toString() ?? '0';

    return CustomModal(
      title: 'Detalle Solicitud ${req['DocumentNo'] ?? req['id']}',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ticket N°: ${req['DocumentNo'] ?? req['id']}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copiar Ticket',
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: (req['DocumentNo'] ?? req['id']).toString()));
                      ToastMessage.show(context: context, message: AppLocale.ticketCopied.getString(context), type: ToastType.help);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: TextEditingController(text: summary),
              label: 'Resumen',
              readOnly: true,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: CustomTextField(
                    controller: TextEditingController(text: status),
                    label: 'Estado',
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomTextField(
                    controller: TextEditingController(text: priority),
                    label: 'Prioridad',
                    readOnly: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: CustomTextField(
                    controller: TextEditingController(text: dateStart),
                    label: 'Fecha Inicio',
                    readOnly: true,
                    prefixIcon: const Icon(Icons.calendar_today),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomTextField(
                    controller: TextEditingController(text: dateComplete),
                    label: 'Fecha Fin',
                    readOnly: true,
                    prefixIcon: const Icon(Icons.calendar_today),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: TextEditingController(text: qtyPlan),
              label: 'Horas Planificadas',
              readOnly: true,
              prefixIcon: const Icon(Icons.timer),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}
