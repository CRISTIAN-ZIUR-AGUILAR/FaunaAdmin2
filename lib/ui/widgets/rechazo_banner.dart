import 'package:flutter/material.dart';
import 'package:faunadmin2/models/observacion.dart';

class RechazoBanner extends StatelessWidget {
  final Observacion obs;
  final VoidCallback onEditarYReenviar;

  const RechazoBanner({
    super.key,
    required this.obs,
    required this.onEditarYReenviar,
  });

  @override
  Widget build(BuildContext context) {
    if (obs.estado != EstadosObs.rechazado) return const SizedBox.shrink();

    return Material(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.error_outline, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Text(
                'Observación rechazada',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            if ((obs.rejectionReason ?? '').trim().isNotEmpty)
              Text(
                obs.rejectionReason!.trim(),
                style: TextStyle(color: Colors.red.shade900),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.outgoing_mail),
              label: const Text('Editar y reenviar'),
              onPressed: onEditarYReenviar,
            ),
          ],
        ),
      ),
    );
  }
}
