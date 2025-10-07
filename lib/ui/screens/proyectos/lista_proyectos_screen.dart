// lib/ui/screens/proyectos/lista_proyectos_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:faunadmin2/models/proyecto.dart';
import 'package:faunadmin2/models/usuario.dart';
import 'package:faunadmin2/models/rol.dart';
import 'package:faunadmin2/providers/auth_provider.dart';

// 👇 Usamos solo FirestoreService con alias para claridad
import 'package:faunadmin2/services/firestore_service.dart' as db;
import 'package:faunadmin2/services/permisos_service.dart';

class ListaProyectosScreen extends StatefulWidget {
  const ListaProyectosScreen({super.key});

  @override
  State<ListaProyectosScreen> createState() => _ListaProyectosScreenState();
}

class _ListaProyectosScreenState extends State<ListaProyectosScreen> {
  final db.FirestoreService _fs = db.FirestoreService();

  // --- Streams locales (Dueño por campo directo) ---
  Stream<List<Proyecto>> _streamByOwner(String uid) {
    return FirebaseFirestore.instance
        .collection('proyectos')
        .where('uid_dueno', isEqualTo: uid)
        .orderBy('nombre')
        .snapshots()
        .map((q) => q.docs.map((d) => Proyecto.fromMap(d.data(), d.id)).toList());
  }

  // --- Nuevo: proyectos asignados por URP (supervisor/colaborador/recolector) ---
  Stream<List<Proyecto>> _streamAsignadosViaUrp(String uid, List<int> roles) {
    // Nota: reaccionará cuando cambien los URP; si quisieras LIVE cuando cambia el
    // proyecto (nombre, activo, etc.), necesitarías combinar streams por doc.
    return FirebaseFirestore.instance
        .collection('usuario_rol_proyecto')
        .where('uid_usuario', isEqualTo: uid)
        .where('id_rol', whereIn: roles)
        .where('activo', isEqualTo: true)
        .snapshots()
        .asyncMap((snap) async {
      final ids = snap.docs
          .map((d) => (d.data()['id_proyecto'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      return _fs.getProyectosPorIds(ids);
    });
  }

  void _openAsignarSupervisor(Proyecto p) {
    if (p.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proyecto sin ID. No se puede asignar supervisor.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AsignarSupervisorSheet(proyectoId: p.id!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permisos = PermisosService(auth);
    final uid = auth.uid!;

    final showCreate = permisos.canCreateProject;

    // Flag opcional para mostrar solo asignados
    final args = ModalRoute.of(context)?.settings.arguments;
    final onlyAssigned = (args is Map && args['onlyAssigned'] == true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proyectos'),
        leading: Navigator.of(context).canPop()
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        )
            : (permisos.isAdmin
            ? IconButton(
          tooltip: 'Panel de administración',
          icon: const Icon(Icons.dashboard_outlined),
          onPressed: () =>
              Navigator.pushReplacementNamed(context, '/admin/dashboard'),
        )
            : null),
        actions: [
          if (permisos.isAdmin)
            IconButton(
              tooltip: 'Panel',
              icon: const Icon(Icons.dashboard_customize_outlined),
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/admin/dashboard'),
            ),
        ],
      ),
      floatingActionButton: showCreate
          ? FloatingActionButton.extended(
        tooltip: 'Nuevo proyecto',
        onPressed: () => Navigator.pushNamed(context, '/proyectos/crear'),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo proyecto'),
      )
          : null,
      body: _buildBody(permisos, uid, onlyAssigned: onlyAssigned),
    );
  }

  Widget _buildBody(PermisosService permisos, String uid, {bool onlyAssigned = false}) {
    // 1) Admin: todos (salvo que pidan solo asignados)
    if (permisos.isAdmin && !onlyAssigned) {
      return StreamBuilder<List<Proyecto>>(
        stream: _fs.streamProyectos(),
        builder: (context, snap) {
          if (snap.hasError) return _ErrorMsg(error: snap.error.toString());
          if (!snap.hasData) return const _Loading();
          return _Lista(
            proyectos: snap.data!,
            isAdmin: true,
            onAsignarSupervisor: _openAsignarSupervisor,
          );
        },
      );
    }

    // 2) Solo asignados (cuando se navega con onlyAssigned: true)
    if (onlyAssigned) {
      return StreamBuilder<List<Proyecto>>(
        stream: _streamAsignadosViaUrp(uid, const [Rol.supervisor, Rol.colaborador, Rol.recolector]),
        builder: (context, snap) {
          if (snap.hasError) return _ErrorMsg(error: snap.error.toString());
          if (!snap.hasData) return const _Loading();
          return _Lista(proyectos: snap.data!);
        },
      );
    }

    // 3) Dueño: proyectos donde uid_dueno == uid (reactivo por doc)
    if (permisos.isDuenoEnContexto) {
      return StreamBuilder<List<Proyecto>>(
        stream: _streamByOwner(uid),
        builder: (context, snap) {
          if (snap.hasError) return _ErrorMsg(error: snap.error.toString());
          if (!snap.hasData) return const _Loading();
          return _Lista(proyectos: snap.data!);
        },
      );
    }

    // 4) Supervisor/Colaborador/Recolector (sin onlyAssigned): mostrar asignados
    return StreamBuilder<List<Proyecto>>(
      stream: _streamAsignadosViaUrp(uid, const [Rol.supervisor, Rol.colaborador, Rol.recolector]),
      builder: (context, snap) {
        if (snap.hasError) return _ErrorMsg(error: snap.error.toString());
        if (!snap.hasData) return const _Loading();
        return _Lista(proyectos: snap.data!);
      },
    );
  }
}

class _Lista extends StatelessWidget {
  final List<Proyecto> proyectos;
  final bool isAdmin;
  final void Function(Proyecto p)? onAsignarSupervisor;

  const _Lista({
    required this.proyectos,
    this.isAdmin = false,
    this.onAsignarSupervisor,
  });

  @override
  Widget build(BuildContext context) {
    if (proyectos.isEmpty) return const _Empty();

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: proyectos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final p = proyectos[i];
        final nombre = (p.nombre).trim().isNotEmpty ? p.nombre.trim() : 'Proyecto ${p.id}';
        final categoria = (p.categoriaNombre ?? '').trim();
        final activo = p.activo != false;

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            final pid = p.id;
            if (pid == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Proyecto sin ID válido')),
              );
              return;
            }
            Navigator.pushNamed(context, '/proyectos/detalle', arguments: pid);
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  blurRadius: 10,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                  color: Colors.black.withAlpha((0.06 * 255).round()),
                ),
              ],
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withAlpha((0.18 * 255).round()),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.orange.withAlpha((0.12 * 255).round()),
                  child: const Icon(Icons.workspaces_rounded, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (categoria.isNotEmpty)
                            Chip(
                              label: Text(categoria),
                              visualDensity: VisualDensity.compact,
                            ),
                          Chip(
                            label: Text(activo ? 'Activo' : 'Inactivo'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Menú solo para Admin
                if (isAdmin)
                  PopupMenuButton<String>(
                    tooltip: 'Acciones',
                    onSelected: (value) async {
                      if (value == 'asignar') {
                        onAsignarSupervisor?.call(p);
                      } else if (value == 'equipo') {
                        final pid = p.id;
                        if (pid == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Proyecto sin ID válido')),
                          );
                          return;
                        }
                        Navigator.pushNamed(
                          context,
                          '/proyectos/equipo', // 👈 corregido
                          arguments: {'proyectoId': pid},
                        );
                      } else if (value == 'eliminar') {
                        final pid = p.id;
                        if (pid == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Proyecto sin ID válido')),
                          );
                          return;
                        }
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Eliminar proyecto'),
                            content: const Text(
                              'Se eliminarán vínculos, categorías y observaciones asociadas.\n'
                                  'Esta acción no se puede deshacer. ¿Continuar?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          try {
                            await db.FirestoreService().deleteProyectoCascade(pid);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Proyecto eliminado')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error al eliminar: $e')),
                              );
                            }
                          }
                        }
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'asignar',
                        child: Text('Asignar supervisor'),
                      ),
                      PopupMenuItem(
                        value: 'equipo',
                        child: Text('Ver equipo'),
                      ),
                      PopupMenuItem(
                        value: 'eliminar',
                        child: Text('Eliminar proyecto'),
                      ),
                    ],
                    icon: Icon(
                      Icons.more_vert,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.outline,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AsignarSupervisorSheet extends StatefulWidget {
  final String proyectoId;
  const _AsignarSupervisorSheet({required this.proyectoId});

  @override
  State<_AsignarSupervisorSheet> createState() => _AsignarSupervisorSheetState();
}

class _AsignarSupervisorSheetState extends State<_AsignarSupervisorSheet> {
  final db.FirestoreService _fs = db.FirestoreService();

  String? _uidSeleccionado;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Asignar Supervisor',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),

          // 👇 Leemos los usuarios aprobados directamente del servicio
          StreamBuilder<List<Usuario>>(
            stream: _fs.streamUsuariosAprobados(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              final usuarios = snapshot.data ?? const <Usuario>[];
              if (usuarios.isEmpty) {
                return const Text('No hay usuarios aprobados disponibles.');
              }
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Usuario aprobado',
                  border: OutlineInputBorder(),
                ),
                value: _uidSeleccionado,
                items: usuarios.map((u) {
                  final uid = u.uid;
                  final nombre = u.nombreCompleto.isNotEmpty ? u.nombreCompleto : uid;
                  final correo = u.correo.isNotEmpty ? u.correo : '—';
                  return DropdownMenuItem<String>(
                    value: uid,
                    child: Text('$nombre · $correo'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _uidSeleccionado = val),
              );
            },
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving || _uidSeleccionado == null
                  ? null
                  : () async {
                setState(() => _saving = true);
                try {
                  await _fs.asignarSupervisorAProyecto(
                    proyectoId: widget.proyectoId,
                    uidSupervisor: _uidSeleccionado!,
                    uidAdmin: auth.uid!,
                  );
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Supervisor asignado')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _saving = false);
                }
              },
              icon: const Icon(Icons.check),
              label: const Text('Confirmar'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'No hay proyectos para mostrar',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Revisa tu rol o solicita acceso.',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withAlpha((0.7 * 255).round()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorMsg extends StatelessWidget {
  final String error;
  const _ErrorMsg({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Error: $error'),
      ),
    );
  }
}

