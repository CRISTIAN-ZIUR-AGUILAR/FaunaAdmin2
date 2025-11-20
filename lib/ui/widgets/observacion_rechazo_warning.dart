import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

class ObservacionRechazoWarning extends StatelessWidget {
  final String motivo;
  final int? reviewRound;
  final DateTime? validatedAt;
  final String? validatedBy;

  const ObservacionRechazoWarning({
    super.key,
    required this.motivo,
    this.reviewRound,
    this.validatedAt,
    this.validatedBy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = theme.colorScheme.onErrorContainer;
    final textTheme = theme.textTheme;

    String? _formatFecha(DateTime? dt) {
      if (dt == null) return null;
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    }

    return Card(
      color: theme.colorScheme.errorContainer.withOpacity(0.95),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 28,
              color: onColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Observación rechazada',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: onColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    motivo,
                    style: textTheme.bodyMedium?.copyWith(
                      color: onColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (reviewRound != null)
                        Text(
                          'Ronda: $reviewRound',
                          style: textTheme.bodySmall?.copyWith(
                            color: onColor,
                          ),
                        ),
                      if (_formatFecha(validatedAt) != null)
                        Text(
                          'Revisado: ${_formatFecha(validatedAt)}',
                          style: textTheme.bodySmall?.copyWith(
                            color: onColor,
                          ),
                        ),
                      if (validatedBy != null && validatedBy!.trim().isNotEmpty)
                        Text(
                          'Revisor: $validatedBy',
                          style: textTheme.bodySmall?.copyWith(
                            color: onColor,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Por favor corrige los puntos indicados arriba y vuelve a enviar la observación.',
                    style: textTheme.bodySmall?.copyWith(
                      color: onColor.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
