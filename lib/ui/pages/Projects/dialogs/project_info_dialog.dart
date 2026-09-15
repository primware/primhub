import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_container.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localization/flutter_localization.dart';

class ProjectInfoDialog extends StatelessWidget {
  final Map<String, dynamic> project;

  const ProjectInfoDialog({super.key, required this.project});

  String _getIdentifier(dynamic value) {
    if (value == null) return 'N/A';
    if (value is Map) return value['identifier']?.toString() ?? value['Name']?.toString() ?? 'N/A';
    return value.toString();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (_) {
      return dateStr.split('T').first;
    }
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return '\$ 0.00';
    final number = double.tryParse(value.toString()) ?? 0.0;
    return NumberFormat.currency(symbol: '\$ ', decimalDigits: 2).format(number);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final isMobile = MediaQuery.of(context).size.width < 600;

    return CustomModal(
      title: AppLocale.projectTechnicalSheet.getString(context),
      width: 850,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- HEADER SECTION ---
            Container(
              padding: EdgeInsets.all(isMobile ? 12 : 20),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: isMobile ? 24 : 30,
                    backgroundColor: colorScheme.primary,
                    child: Icon(Icons.assignment_rounded, color: Colors.white, size: isMobile ? 24 : 30),
                  ),
                  SizedBox(width: isMobile ? 12 : 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project['Name'] ?? AppLocale.unnamed.getString(context),
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.secondary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                project['Value'] ?? 'S/C',
                                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.secondary, fontSize: 12),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, size: 8, color: (project['IsActive'] == true || project['IsActive'] == 'Y') ? Colors.green : Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  (project['IsActive'] == true || project['IsActive'] == 'Y')
                                      ? AppLocale.active.getString(context)
                                      : AppLocale.inactive.getString(context),
                                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface.withOpacity(0.7)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- MAIN INFO & STAKEHOLDERS ---
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = MediaQuery.of(context).size.width < 600;
                
                final infoWidget = CustomContainer(
                  title: AppLocale.generalInformation.getString(context),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildInfoRow(context, Icons.notes, AppLocale.description.getString(context), project['Description'] ?? AppLocale.noDescriptionAvailable.getString(context), isLongText: true),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(child: _buildInfoRow(context, Icons.calendar_today, AppLocale.contractStart.getString(context), _formatDate(project['DateContract']))),
                          Expanded(child: _buildInfoRow(context, Icons.event_available, AppLocale.estimatedEnd.getString(context), _formatDate(project['DateFinish']))),
                        ],
                      ),
                    ],
                  ),
                );

                final responsiblesWidget = CustomContainer(
                  title: AppLocale.managersTitle.getString(context),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildInfoRow(context, Icons.business, AppLocale.client.getString(context), _getIdentifier(project['C_BPartner_ID'])),
                      const SizedBox(height: 16),
                      _buildInfoRow(context, Icons.person_outline, AppLocale.salesRepresentative.getString(context), _getIdentifier(project['SalesRep_ID'] ?? project['C_BPartnerSR_ID'])),
                      const SizedBox(height: 16),
                      _buildInfoRow(context, Icons.payments_outlined, AppLocale.currencyBilling.getString(context), '${_getIdentifier(project['C_Currency_ID'])} - ${_getIdentifier(project['ProjInvoiceRule'])}'),
                    ],
                  ),
                );

                if (isMobile) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      infoWidget,
                      const SizedBox(height: 16),
                      responsiblesWidget,
                    ],
                  );
                } else {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: infoWidget),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: responsiblesWidget),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 20),

            // --- FINANCIAL DETAILS ---
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = MediaQuery.of(context).size.width < 600;
                
                final metricChildren = [
                  _buildMetricTile(context, AppLocale.plannedAmount.getString(context), project['PlannedAmt'], Icons.account_balance_wallet_outlined, colorScheme.primary),
                  _buildMetricTile(context, AppLocale.committedAmount.getString(context), project['CommittedAmt'], Icons.shopping_bag_outlined, Colors.orange),
                  _buildMetricTile(context, AppLocale.projectBalance.getString(context), project['ProjectBalanceAmt'], Icons.balance, Colors.blue),
                  _buildMetricTile(context, AppLocale.plannedQuantity.getString(context), project['PlannedQty'], Icons.layers_outlined, colorScheme.secondary, isCurrency: false),
                  _buildMetricTile(context, AppLocale.committedQuantity.getString(context), project['CommittedQty'], Icons.inventory_2_outlined, Colors.purple, isCurrency: false),
                  _buildMetricTile(context, AppLocale.plannedMargin.getString(context), project['PlannedMarginAmt'], Icons.trending_up, Colors.green),
                ];

                return CustomContainer(
                  title: AppLocale.financialMetrics.getString(context),
                  child: isMobile 
                      ? Column(
                          children: metricChildren.map((e) => Padding(padding: const EdgeInsets.only(bottom: 16.0), child: e)).toList(),
                        )
                      : GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 3,
                          childAspectRatio: 2.5,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          children: metricChildren,
                        ),
                );
              }
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0, bottom: 8.0),
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(AppLocale.closeWindow.getString(context), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        )
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value, {bool isLongText = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: isLongText ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: colorScheme.primary.withOpacity(0.7)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withOpacity(0.5), fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                  height: 1.3,
                ),
                maxLines: isLongText ? 4 : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile(BuildContext context, String label, dynamic value, IconData icon, Color color, {bool isCurrency = true}) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayValue = isCurrency ? _formatCurrency(value) : (value?.toString() ?? '0.0');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withOpacity(0.5), fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    displayValue,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
