import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';

import 'package:primhub/ui/Shared_Custom/cardcustom.dart';

import 'package:primhub/ui/widgets/duration_formatter.dart';
import 'package:flutter_localization/flutter_localization.dart';

class UnifiedSupportCard extends StatelessWidget {
  final String bpName;
  final String? productLabel; // Descripción de la ficha de producto
  final String? frequency;
  final String? serviceStartDate;
  final String? serviceFinishDate;
  final double acquiredHours;
  final double inProgressHours;
  final double consumedHours;
  final int inProgressRequestsCount;
  final int closedRequestsCount;
  final VoidCallback onShowAllContracts;
  final VoidCallback? onAvailableHoursTap;
  final VoidCallback? onInProgressTap;
  final VoidCallback? onClosedTap;
  final bool isLoading;

  const UnifiedSupportCard({
    super.key,
    required this.bpName,
    this.productLabel,
    this.frequency,
    this.serviceStartDate,
    this.serviceFinishDate,
    required this.acquiredHours,
    required this.inProgressHours,
    required this.consumedHours,
    required this.inProgressRequestsCount,
    required this.closedRequestsCount,
    required this.onShowAllContracts,
    this.onAvailableHoursTap,
    this.onInProgressTap,
    this.onClosedTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final double availableHours =
        acquiredHours -
        consumedHours -
        inProgressHours; // Actualizado: restar estimadas para reflejar el saldo real disponible
    final bool isInsufficient = availableHours < 0;

    const Color headerIconColor = Color(0xFF4F46E5);
    const Color headerIconBgColor = Color(0xFFEEF2FF);

    return CardCustom(
      hover: false,
      height: null,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: headerIconBgColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: headerIconColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productLabel ?? bpName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (productLabel != null)
                        Text(
                          bpName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            const Divider(height: 24),
            // Hours Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MiniStatItem(
                  label: AppLocale.acquired.getString(context),
                  value: acquiredHours,
                  color: Colors.blueGrey,
                  isHour: true,
                ),
                _MiniStatItem(
                  label: 'Estimadas',
                  value: inProgressHours,
                  color: Colors.blue,
                  isHour: true,
                ),
                _MiniStatItem(
                  label: 'Consumidas',
                  value: consumedHours,
                  color: Colors.green,
                  isHour: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Availability Main Stat
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: isInsufficient
                    ? Colors.red.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isInsufficient
                      ? Colors.red.withOpacity(0.3)
                      : Colors.orange.withOpacity(0.3),
                ),
              ),
              child: InkWell(
                onTap: onAvailableHoursTap,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DISPONIBLES',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isInsufficient
                                ? Colors.red.shade900
                                : Colors.orange.shade900,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DurationFormatter.format(availableHours),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: isInsufficient
                                ? Colors.red.shade900
                                : Colors.orange.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Requests counters
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onInProgressTap,
                    borderRadius: BorderRadius.circular(12),
                    child: _CompactRequestStat(
                      label: 'En Curso',
                      count: inProgressRequestsCount,
                      icon: Icons.sync,
                      color: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: onClosedTap,
                    borderRadius: BorderRadius.circular(12),
                    child: _CompactRequestStat(
                      label: 'Finalizadas',
                      count: closedRequestsCount,
                      icon: Icons.check_circle_outline,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStatItem extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool isHour;

  const _MiniStatItem({
    required this.label,
    required this.value,
    required this.color,
    required this.isHour,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          isHour ? DurationFormatter.format(value) : value.toInt().toString(),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}

class _CompactRequestStat extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  const _CompactRequestStat({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
