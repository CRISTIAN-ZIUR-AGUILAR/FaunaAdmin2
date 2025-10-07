// lib/ui/screens/proyectos/detalle_proyecto_dueno_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:faunadmin2/models/proyecto.dart';
import 'package:faunadmin2/models/rol.dart';
import 'package:faunadmin2/models/usuario.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/providers/proyecto_provider.dart';
import 'package:faunadmin2/services/firestore_service.dart';
import 'package:faunadmin2/services/permisos_service.dart';

class DetalleProyectoDuenoScreen extends StatefulWidget {
  final String proyectoId;
  const DetalleProyectoDuenoScreen({super.key, required this.proyectoId});

  @override
  State<DetalleProyectoDuenoScreen> createState() => _DetalleProyectoDuenoScreenState();
}

class _DetalleProyectoDuenoScreenState extends State<DetalleProyectoDuenoScreen> {
  final fs = FirestoreService();

  // -------- Volver a Selección de Rol/Proyecto (sin romper el stack) --------
  void _goToRoleSelection() {
    try {
      context.read<AuthProvider>().clearSelectedRolProyecto();
    } catch (_) {}
    if (!mounted) return;

    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed(
        '/seleccion', // ruta de selección
        arguments: {'skipAutoNav': true, 'source': 'dueno_detalle'},
      );
    }
  }

  // -------- STREAM colaboradores (uids) --------
  Stream<List<String>> _colaboradoresUidsStream(String proyectoId) {
    return FirebaseFirestore.instance
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: proyectoId)
        .where('id_rol', isEqualTo: Rol.colaborador)
        .snapshots()
        .map((q) => q.docs
        .map((d) => (d.data()['uid_usuario'] as String?) ?? '')
        .where((uid) => uid.isNotEmpty)
        .toSet()
        .toList());
  }

  // -------- COLABORADORES: agregar / retirar --------
  Future<void> _agregarColaboradorSheet({
    required String proyectoId,
    required String? uidDueno,
  }) async {
    final links = await fs.linksColabByProyecto(proyectoId);
    final uidsYa = links.map((m) => m['uid_usuario'] as String).toSet();
    if (uidDueno != null && uidDueno.isNotEmpty) uidsYa.add(uidDueno);

    String filtro = '';
    String? seleccionado;

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: StatefulBuilder(
              builder: (context, setLocal) {
                return SizedBox(
                  height: MediaQuery.of(context).size.height * .75,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Agregar colaborador',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Buscar por nombre o correo…',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setLocal(() => filtro = v.trim()),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: StreamBuilder<List<Usuario>>(
                          stream: fs.streamUsuariosPorEstatus('aprobado'),
                          builder: (context, snapU) {
                            if (snapU.hasError) {
                              return const Center(child: Text('Error cargando usuarios'));
                            }
                            if (!snapU.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final todos = snapU.data!;
                            final candidatos = todos
                                .where((u) {
                              if (uidsYa.contains(u.uid)) return false;
                              if (filtro.isEmpty) return true;
                              final f = filtro.toLowerCase();
                              return u.nombreCompleto.toLowerCase().contains(f) ||
                                  u.correo.toLowerCase().contains(f);
                            })
                                .toList()
                              ..sort((a, b) => a.nombreCompleto
                                  .toLowerCase()
                                  .compareTo(b.nombreCompleto.toLowerCase()));

                            if (candidatos.isEmpty) {
                              return const Center(child: Text('No hay candidatos'));
                            }

                            return ListView.separated(
                              itemCount: candidatos.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final u = candidatos[i];
                                final title = u.nombreCompleto.isNotEmpty ? u.nombreCompleto : u.uid;
                                return RadioListTile<String>(
                                  value: u.uid,
                                  groupValue: seleccionado,
                                  onChanged: (v) => setLocal(() => seleccionado = v),
                                  title: Text(title),
                                  subtitle: Text(u.correo.isNotEmpty ? u.correo : '—'),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                              label: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: seleccionado == null
                                  ? null
                                  : () async {
                                try {
                                  await fs.asignarColaborador(
                                    proyectoId,
                                    seleccionado!,
                                    asignadoBy: context.read<AuthProvider>().uid,
                                  );
                                  if (!mounted) return;
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Colaborador agregado')),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                                }
                              },
                              icon: const Icon(Icons.person_add_alt_1),
                              label: const Text('Agregar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _retirarColaborador({
    required String proyectoId,
    required String uidColab,
  }) async {
    try {
      await fs.retirarColaborador(proyectoId, uidColab);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Colaborador retirado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _confirmarRetiro(String uid, String nombre) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirar colaborador'),
        content: Text('¿Quitar a "$nombre" del proyecto?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok == true) {
      await _retirarColaborador(proyectoId: widget.proyectoId, uidColab: uid);
    }
  }

  // -------- UI --------
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permisos = PermisosService(auth);
    final provider = context.watch<ProyectoProvider>();

    // 👇 Gate lo hacemos DESPUÉS de cargar el proyecto (dentro del StreamBuilder)
    return WillPopScope(
      onWillPop: () async => true,
      child: StreamBuilder<Proyecto?>(
        stream: fs.streamProyectoById(widget.proyectoId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: true,
                title: const Text('Proyecto'),
                actions: [
                  IconButton(
                    tooltip: 'Seleccionar rol',
                    onPressed: _goToRoleSelection,
                    icon: const Icon(Icons.switch_account_outlined),
                  ),
                ],
              ),
              body: Center(child: Text('Error: ${snap.error}')),
            );
          }

          if (!snap.hasData || snap.data == null) {
            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: true,
                title: const Text('Proyecto'),
                actions: [
                  IconButton(
                    tooltip: 'Seleccionar rol',
                    onPressed: _goToRoleSelection,
                    icon: const Icon(Icons.switch_account_outlined),
                  ),
                ],
              ),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          final p = snap.data!;

          // ✅ Gate aquí: admin/admin global o dueño real del doc o dueño en contexto del mismo proyecto
          final isOwnerReal = (p.uidDueno ?? '') == (auth.uid ?? '');
          final isOwnerHere =
              permisos.isDuenoEnContexto && auth.selectedRolProyecto?.idProyecto == widget.proyectoId;
          final allowed = permisos.isAdmin || permisos.isAdminGlobal || isOwnerReal || isOwnerHere;

          if (!allowed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _goToRoleSelection();
            });
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          final puedeEditar = permisos.canEditProjectFor(widget.proyectoId);
          final puedeGestionarColabs = permisos.canManageCollaboratorsFor(widget.proyectoId);
          final puedeAsignarSupervisor = permisos.canAssignSupervisor; // sólo admin único
          final puedeIrAEquipo = permisos.canManageCollaboratorsFor(widget.proyectoId);

          return Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: true,
              title: Text(p.nombre.isNotEmpty ? p.nombre : 'Proyecto'),
              actions: [
                if (puedeIrAEquipo)
                  IconButton(
                    tooltip: 'Equipo',
                    icon: const Icon(Icons.group_outlined),
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/proyectos/equipo',
                        arguments: widget.proyectoId, // <-- String, consistente con routes
                      );
                    },
                  ),
                TextButton.icon(
                  onPressed: _goToRoleSelection,
                  icon: const Icon(Icons.switch_account_outlined),
                  label: const Text('Cambiar de rol'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
                if (puedeEditar)
                  IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit),
                    onPressed: () => Navigator.pushNamed(
                      context,
                      '/proyectos/edit',
                      arguments: p.id ?? widget.proyectoId, // robustez
                    ),
                  ),
              ],
            ),
            floatingActionButton: permisos.canAddObservation
                ? FloatingActionButton.extended(
              onPressed: () {
                final uid = auth.uid;
                if (uid == null) return;
                Navigator.pushNamed(
                  context,
                  '/observaciones/add',
                  arguments: {'proyectoId': widget.proyectoId, 'uidUsuario': uid},
                );
              },
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Nueva observación'),
            )
                : null,
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ----- RESUMEN -----
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.nombre.isNotEmpty ? p.nombre : (p.id ?? 'Proyecto'),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            if ((p.categoriaNombre ?? '').isNotEmpty)
                              Chip(label: Text(p.categoriaNombre!), avatar: const Icon(Icons.label_outline)),
                            Chip(
                              label: Text(p.activo == false ? 'Inactivo' : 'Activo'),
                              avatar: Icon(p.activo == false ? Icons.pause_circle_outline : Icons.check_circle_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          (p.descripcion).isNotEmpty ? (p.descripcion) : 'Sin descripción.',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.event, size: 18),
                            const SizedBox(width: 6),
                            Text(p.fechaInicio != null ? 'Inicio: ${p.fechaInicio}' : 'Inicio: —'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ----- ACCESOS RÁPIDOS -----
                Card(
                  child: Column(
                    children: [
                      if (puedeIrAEquipo)
                        ListTile(
                          leading: const Icon(Icons.group_outlined),
                          title: const Text('Equipo'),
                          subtitle: const Text('Invitar, asignar y quitar miembros'),
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              '/proyectos/equipo',
                              arguments: widget.proyectoId, // <-- String
                            );
                          },
                        ),
                      if (puedeIrAEquipo) const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.photo_library_outlined),
                        title: const Text('Observaciones'),
                        subtitle: const Text('Ir al listado de observaciones'),
                        onTap: () => Navigator.pushNamed(
                          context,
                          '/observaciones/list',
                          arguments: {'proyectoId': widget.proyectoId}, // preparado si la lista filtra por proyecto
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ----- DUEÑO -----
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: const Text('Dueño de proyecto'),
                    subtitle: FutureBuilder<Usuario?>(
                      future: (p.uidDueno != null && p.uidDueno!.isNotEmpty)
                          ? fs.getUsuario(p.uidDueno!)
                          : Future.value(null),
                      builder: (context, s) {
                        if (!s.hasData) return const Text('Cargando…');
                        final u = s.data!;
                        final name = u.nombreCompleto.isNotEmpty ? u.nombreCompleto : u.uid;
                        return Text(name);
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ----- SUPERVISORES (solo ver / admin único puede gestionar) -----
                Card(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.manage_accounts_outlined),
                          title: const Text('Supervisores'),
                          subtitle: const Text('Asignados a este proyecto'),
                          trailing: puedeAsignarSupervisor
                              ? IconButton(
                            tooltip: 'Asignar supervisor',
                            icon: const Icon(Icons.person_add_alt_1),
                            onPressed: () => _openAsignarSupervisorSheet(context),
                          )
                              : null,
                        ),
                        const Divider(height: 1),
                        StreamBuilder<List<Usuario>>(
                          stream: provider.streamSupervisoresDeProyecto(widget.proyectoId),
                          builder: (context, snapSup) {
                            if (snapSup.hasError) {
                              return const ListTile(title: Text('Error al cargar supervisores'));
                            }
                            final supervisores = snapSup.data ?? const <Usuario>[];
                            if (supervisores.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Align(alignment: Alignment.centerLeft, child: Text('Sin supervisores')),
                              );
                            }
                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: supervisores.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final u = supervisores[i];
                                final nombre = u.nombreCompleto.isNotEmpty ? u.nombreCompleto : u.uid;
                                final mail = u.correo.isNotEmpty ? u.correo : '—';
                                return ListTile(
                                  leading: const CircleAvatar(child: Icon(Icons.person)),
                                  title: Text(nombre),
                                  subtitle: Text(mail),
                                  trailing: puedeAsignarSupervisor
                                      ? IconButton(
                                    tooltip: 'Retirar',
                                    icon: const Icon(Icons.remove_circle),
                                    onPressed: () => _quitarSupervisorUsuario(context, u.uid),
                                  )
                                      : null,
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ----- COLABORADORES (dueño puede gestionar) -----
                Card(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.group_outlined),
                          title: const Text('Colaboradores'),
                          subtitle: const Text('Usuarios asignados'),
                          trailing: puedeGestionarColabs
                              ? IconButton(
                            tooltip: 'Agregar colaborador',
                            icon: const Icon(Icons.person_add_alt_1),
                            onPressed: () => _agregarColaboradorSheet(
                              proyectoId: widget.proyectoId,
                              uidDueno: p.uidDueno,
                            ),
                          )
                              : null,
                        ),
                        const Divider(height: 1),
                        StreamBuilder<List<String>>(
                          stream: _colaboradoresUidsStream(widget.proyectoId),
                          builder: (context, uidsSnap) {
                            if (uidsSnap.hasError) {
                              return const ListTile(title: Text('Error al cargar colaboradores'));
                            }
                            final uids = uidsSnap.data ?? const [];
                            if (uids.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Align(alignment: Alignment.centerLeft, child: Text('Sin colaboradores')),
                              );
                            }
                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: uids.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final uid = uids[i];
                                return FutureBuilder<Usuario>(
                                  future: fs.getUsuario(uid),
                                  builder: (context, uSnap) {
                                    if (!uSnap.hasData) {
                                      return const ListTile(title: Text('Cargando…'));
                                    }
                                    final u = uSnap.data!;
                                    final nombre = u.nombreCompleto.isNotEmpty ? u.nombreCompleto : u.uid;
                                    final mail = u.correo.isNotEmpty ? u.correo : '—';
                                    return ListTile(
                                      leading: const CircleAvatar(child: Icon(Icons.person)),
                                      title: Text(nombre),
                                      subtitle: Text(mail),
                                      trailing: puedeGestionarColabs
                                          ? IconButton(
                                        tooltip: 'Retirar',
                                        icon: const Icon(Icons.remove_circle),
                                        onPressed: () => _confirmarRetiro(uid, nombre),
                                      )
                                          : null,
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---- helpers supervisor (solo admin único puede) ----
  void _openAsignarSupervisorSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AsignarSupervisorSheetDueno(proyectoId: widget.proyectoId),
    );
  }

  Future<void> _quitarSupervisorUsuario(BuildContext context, String uidSupervisor) async {
    final provider = context.read<ProyectoProvider>();
    try {
      await provider.quitarSupervisor(proyectoId: widget.proyectoId, uidSupervisor: uidSupervisor);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supervisor retirado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}

// ===== Sheet (reutiliza provider) =====
class _AsignarSupervisorSheetDueno extends StatefulWidget {
  final String proyectoId;
  const _AsignarSupervisorSheetDueno({required this.proyectoId});

  @override
  State<_AsignarSupervisorSheetDueno> createState() => _AsignarSupervisorSheetDuenoState();
}

class _AsignarSupervisorSheetDuenoState extends State<_AsignarSupervisorSheetDueno> {
  String? _uidSeleccionado;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<ProyectoProvider>();

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Asignar Supervisor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          StreamBuilder<List<Usuario>>(
            stream: provider.streamUsuariosAprobados(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              final usuarios = snapshot.data ?? const <Usuario>[];
              if (usuarios.isEmpty) return const Text('No hay usuarios aprobados disponibles.');
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Usuario aprobado',
                  border: OutlineInputBorder(),
                ),
                value: _uidSeleccionado,
                items: usuarios.map((u) {
                  final uid = u.uid;
                  final nombre = u.nombreCompleto;
                  final correo = u.correo;
                  return DropdownMenuItem<String>(
                    value: uid,
                    child: Text('${nombre.isNotEmpty ? nombre : uid} · ${correo.isNotEmpty ? correo : '—'}'),
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
              onPressed: provider.actionInProgress || _uidSeleccionado == null
                  ? null
                  : () async {
                try {
                  await provider.asignarSupervisor(
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

