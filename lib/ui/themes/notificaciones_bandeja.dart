import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:faunadmin2/providers/notificacion_provider.dart';
import 'package:faunadmin2/models/notificacion.dart';
import 'package:faunadmin2/utils/notificaciones_constants.dart';

class NotificacionesBandeja extends StatefulWidget {
  const NotificacionesBandeja({super.key});

  @override
  State<NotificacionesBandeja> createState() => _NotificacionesBandejaState();
}

class _NotificacionesBandejaState extends State<NotificacionesBandeja> {
  @override
  void initState() {
    super.initState();
    // Arranca el stream cuando se monta el widget
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificacionProvider>().start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<NotificacionProvider>();
    final items = prov.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FiltrosBar(
          filtro: prov.filtro,
          onChange: prov.setFiltro,
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? const _EmptyState()
              : ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _NotiTile(n: items[i]),
          ),
        ),
      ],
    );
  }
}

class _FiltrosBar extends StatelessWidget {
  final NotiFiltro filtro;
  final ValueChanged<NotiFiltro> onChange;
  const _FiltrosBar({required this.filtro, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final chips = <MapEntry<String, NotiFiltro>>[
      const MapEntry('Todas', NotiFiltro.todas),
      const MapEntry('No leídas', NotiFiltro.noLeidas),
      const MapEntry('Proyectos', NotiFiltro.proyectos),
      const MapEntry('Observaciones', NotiFiltro.observaciones),
      const MapEntry('Roles', NotiFiltro.sistema),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: chips.map((e) {
          final selected = filtro == e.value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(e.key),
              selected: selected,
              onSelected: (_) => onChange(e.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NotiTile extends StatelessWidget {
  final Notificacion n;
  const _NotiTile({required this.n});

  IconData _iconoPorTipo(String tipo) {
    if (NotiTipo.grupoObservaciones.contains(tipo)) return Icons.pets;
    if (NotiTipo.grupoProyectos.contains(tipo)) return Icons.workspaces;
    if (NotiTipo.grupoRoles.contains(tipo)) return Icons.verified_user;
    return Icons.notifications;
  }

  Color _bgPorNivel(BuildContext ctx, String nivel) {
    final cs = Theme.of(ctx).colorScheme;
    switch (nivel) {
      case NotiNivel.success: return cs.secondaryContainer;
      case NotiNivel.warning: return cs.tertiaryContainer;
      case NotiNivel.error:   return cs.errorContainer;
      default:                return cs.surfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hora = '${n.createdAt.hour.toString().padLeft(2,'0')}:${n.createdAt.minute.toString().padLeft(2,'0')}';
    final bg = _bgPorNivel(context, n.nivel);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: bg,
        child: Icon(_iconoPorTipo(n.tipo)),
      ),
      title: Text(n.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(n.mensaje, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(hora, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          if (!n.leida) const Icon(Icons.brightness_1, size: 8),
        ],
      ),
      onTap: () {
        if (n.obsId != null) {
          Navigator.pushNamed(context, '/observaciones/approve', arguments: n.obsId);
        } else if (n.proyectoId != null) {
          Navigator.pushNamed(context, '/proyectos/detalle', arguments: n.proyectoId);
        }
        context.read<NotificacionProvider>().marcarLeida(n.id);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('Sin notificaciones por ahora',
          style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}
