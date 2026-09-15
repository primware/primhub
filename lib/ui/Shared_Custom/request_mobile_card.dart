import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/Shared_Custom/animated_copy_widget.dart';
import 'package:primhub/ui/widgets/duration_formatter.dart';
import 'package:flutter_localization/flutter_localization.dart';

/// Tarjeta individual para la vista móvil de solicitudes.
class RequestMobileCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final Function(Map<String, dynamic>) onEdit;
  final VoidCallback onGoToUpdates;
  final VoidCallback onShowAttachments;
  final bool isReadOnly;
  final bool isSelected;
  final bool showCheckbox;
  final ValueChanged<bool?>? onSelectChanged;

  const RequestMobileCard({
    super.key,
    required this.request,
    required this.onEdit,
    required this.onGoToUpdates,
    required this.onShowAttachments,
    this.isReadOnly = false,
    this.isSelected = false,
    this.showCheckbox = false,
    this.onSelectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final String subject = request['emailSubject']?.toString() ?? 'Sin asunto';
    final String bpName = request['bpName']?.toString() ?? '';
    final String userName = request['userName']?.toString() ?? '';
    final String time = request['time'] ?? '';
    final String status = request['status'] ?? 'N/A';
    final String level = request['level'] ?? 'N/A';
    final Color levelBgColor = request['levelBgColor'] ?? Colors.transparent;
    final Color levelColor = request['levelColor'] ?? colorScheme.onSurface;
    final double qtySpent = (request['qtySpent'] as num?)?.toDouble() ?? 0.0;
    final String productChipName = request['productChipName']?.toString().trim() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected ? theme.colorScheme.primary.withOpacity(0.05) : null,
      shape: isSelected
          ? RoundedRectangleBorder(
              side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            )
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
      child: InkWell(
        onTap: () {
          if (showCheckbox && onSelectChanged != null) {
            onSelectChanged!(!isSelected);
          } else {
            onEdit(request);
          }
        },
        onLongPress: () {
           if (onSelectChanged != null) {
              onSelectChanged!(!isSelected);
           }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showCheckbox)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Checkbox(
                        value: isSelected,
                        onChanged: onSelectChanged,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Ticket #${request['id']}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            AnimatedCopyWidget(
                              textToCopy: request['id'].toString(),
                              snackBarMessage: AppLocale.ticketCopiedToClipboard.getString(context),
                              iconSize: 16,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subject,
                          style: theme.textTheme.bodyLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isReadOnly) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade700),
                      ),
                      child: Text(
                        'Est: ${request['PrimHub_Estimated_development_hours'] ?? 0}h',
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ] else ...[
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'updates') onGoToUpdates();
                        if (value == 'attachments') onShowAttachments();
                        if (value == 'edit') onEdit(request);
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'updates',
                              child: ListTile(
                                leading: Icon(
                                  AccessControl.canAddUpdates
                                      ? Icons.reply
                                      : Icons.forum,
                                ),
                                title: Text(
                                  AccessControl.canAddUpdates
                                      ? 'Responder'
                                      : 'Ver Actualizaciones',
                                ),
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'attachments',
                              child: ListTile(
                                leading: Icon(Icons.attach_file),
                                title: Text('Adjuntos'),
                              ),
                            ),
                            if (AccessControl.canManageRequests)
                              const PopupMenuItem<String>(
                                value: 'edit',
                                child: ListTile(
                                  leading: Icon(Icons.edit),
                                  title: Text('Editar'),
                                ),
                              ),
                          ],
                    ),
                  ],
                ],
              ),
              if (AccessControl.isAdmin &&
                  (bpName.isNotEmpty || userName.isNotEmpty)) ...[
                const SizedBox(height: 4),
                Text(
                  '$bpName • $userName',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (productChipName.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.label_outline, 
                            size: 12, 
                            color: colorScheme.onSurfaceVariant
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              productChipName,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: levelBgColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      level,
                      style: TextStyle(
                        color: levelColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (time.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          time,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DurationFormatter.format(qtySpent),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
