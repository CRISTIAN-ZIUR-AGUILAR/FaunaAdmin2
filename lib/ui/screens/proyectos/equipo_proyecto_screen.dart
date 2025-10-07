// lib/ui/screens/proyectos/equipo_proyecto_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import 'package:faunadmin2/models/rol.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/providers/proyecto_provider.dart';
import 'package:faunadmin2/services/firestore_service.dart';
import 'package:faunadmin2/services/permisos_service.dart';

class EquipoProyectoScreen extends StatefulWidget {
  final String proyectoId;
  const EquipoProyectoScreen({super.key, required this.proyectoId});

  @override
  State<EquipoProyectoScreen> createState() => _EquipoProyectoScreenState();
}

class _Miembro {
  final String idDoc;
  final String uid;
  final bool activo;
  final String? nombre;
  final String? correo;

  _Miembro({
    required this.idDoc,
    required this.uid,
    required this.activo,
    this.nombre,
    this.correo,
  });
}

class _UsuarioMini {
  final String uid;
  final String nombre;
  final String correo;
  _UsuarioMini({required this.uid, required this.nombre, required this.correo});
}

class _EquipoProyectoScreenState extends State<EquipoProyectoScreen> {
  final _db = FirebaseFirestore.instance;
  final _fs = FirestoreService();
  final Map<String, Future<_UsuarioMini?>> _userCache = {};

  // ========= COLABORADORES =========
  Stream<List<_Miembro>> _streamColaboradores() {
    return _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: widget.proyectoId)
        .where('id_rol', isEqualTo: Rol.colaborador)
        .snapshots()
        .map((q) => q.docs.map((d) {
      final m = d.data();
      return _Miembro(
        idDoc: d.id,
        uid: (m['uid_usuario'] ?? '') as String,
        activo: (m['activo'] != false),
        nombre: (m['usuario_nombre'] as String?)?.trim(),
        correo: (m['usuario_correo'] as String?)?.trim(),
      );
    }).toList());
  }

  // ========= SUPERVISORES =========
  Stream<List<_Miembro>> _streamSupervisores() {
    return _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: widget.proyectoId)
        .where('id_rol', isEqualTo: Rol.supervisor)
        .snapshots()
        .map((q) => q.docs.map((d) {
      final m = d.data();
      return _Miembro(
        idDoc: d.id,
        uid: (m['uid_usuario'] ?? '') as String,
        activo: (m['activo'] != false),
        nombre: (m['usuario_nombre'] as String?)?.trim(),
        correo: (m['usuario_correo'] as String?)?.trim(),
      );
    }).toList());
  }

  // ========= Usuarios aprobados (selector) =========
  Stream<List<_UsuarioMini>> _streamUsuariosAprobados() {
    return _db
        .collection('usuarios')
        .where('estatus', isEqualTo: 'aprobado')
        .snapshots()
        .map((q) => q.docs.map((d) {
      final m = d.data();
      final nombre = ((m['nombre_completo'] ??
          m['nombreCompleto'] ??
          m['nombre'] ??
          '') as String)
          .trim();
      final correo = (m['correo'] ?? '') as String;
      return _UsuarioMini(
        uid: d.id,
        nombre: nombre.isEmpty ? d.id : nombre,
        correo: correo,
      );
    }).toList());
  }

  // ========= Cache de usuario =========
  Future<_UsuarioMini?> _fetchUser(String uid) {
    return _userCache.putIfAbsent(uid, () async {
      final doc = await _db.collection('usuarios').doc(uid).get();
      if (!doc.exists) return _UsuarioMini(uid: uid, nombre: uid, correo: '');
      final m = doc.data()!;
      final nombre = ((m['nombre_completo'] ??
          m['nombreCompleto'] ??
          m['nombre'] ??
          '') as String)
          .trim();
      final correo = (m['correo'] ?? '') as String;
      return _UsuarioMini(
        uid: uid,
        nombre: nombre.isEmpty ? uid : nombre,
        correo: correo,
      );
    });
  }

  // ========= Helpers de UX =========
  void _showProviderFeedback(BuildContext context, ProyectoProvider provider) {
    final ok = provider.lastMessage;
    final err = provider.lastError;
    if (ok != null && ok.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      provider.resetStatus();
    } else if (err != null && err.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Atención'),
          content: Text(err),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                provider.resetStatus();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<bool> _confirmDialog({
    required String title,
    required String content,
    String confirmLabel = 'Confirmar',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
        ],
      ),
    );
    return ok == true;
  }

  /// Cambiar SUPERVISOR -> COLABORADOR
  Future<void> _switchSupervisorToColaborador(String uidUsuario) async {
    final ok = await _confirmDialog(
      title: 'Cambiar a colaborador',
      content:
      'Este usuario ya es SUPERVISOR en el proyecto.\n\nSi continúas, se quitará su rol de supervisor y se asignará como COLABORADOR.',
      confirmLabel: 'Cambiar a colaborador',
    );
    if (!ok) return;

    final provider = context.read<ProyectoProvider>();

    try {
      await provider.quitarSupervisor(
        proyectoId: widget.proyectoId,
        uidSupervisor: uidUsuario,
      );
      _showProviderFeedback(context, provider);

      await _fs.asignarColaborador(widget.proyectoId, uidUsuario);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rol actualizado: ahora es COLABORADOR.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar el rol: $e')),
      );
    }
  }

  /// Cambiar COLABORADOR -> SUPERVISOR (con confirmación y fallback)
  Future<void> _switchColaboradorToSupervisor(String uidUsuario) async {
    final ok = await _confirmDialog(
      title: 'Cambiar a supervisor',
      content:
      'Este usuario ya es COLABORADOR en el proyecto.\n\nSi continúas, se reemplazará su rol por SUPERVISOR.',
      confirmLabel: 'Cambiar a supervisor',
    );
    if (!ok) return;

    final auth = context.read<AuthProvider>();
    final provider = context.read<ProyectoProvider>();

    // 1) Intento normal vía provider (en muchos casos ya funcionará).
    final code = await provider.asignarSupervisor(
      proyectoId: widget.proyectoId,
      uidSupervisor: uidUsuario,
      uidAdmin: auth.uid!,
    );
    if (!mounted) return;
    _showProviderFeedback(context, provider);

    // 2) Si persiste conflicto, hacemos el "force" manual: quitar colab y asignar sup
    if (code != ProyResultCode.ok) {
      try {
        await _fs.retirarColaborador(widget.proyectoId, uidUsuario);
        await _fs.asignarSupervisorAProyecto(
          proyectoId: widget.proyectoId,
          uidSupervisor: uidUsuario,
          uidAdmin: auth.uid!,
          force: true,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rol actualizado: ahora es SUPERVISOR.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cambiar el rol: $e')),
        );
      }
    }
  }

  // ========= Colaboradores: activar/desactivar/eliminar/asignar =========
  Future<void> _setActivo(_Miembro m, bool value) async {
    await _db.collection('usuario_rol_proyecto').doc(m.idDoc).set(
      {'activo': value, 'actualizadoAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value ? 'Colaborador activado' : 'Colaborador desactivado')),
    );
  }

  Future<void> _eliminarColaborador(_Miembro m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar colaborador'),
        content:
        const Text('Esta acción eliminará la asignación del proyecto. ¿Deseas continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _fs.retirarColaborador(widget.proyectoId, m.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Colaborador eliminado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Asignar colaborador usando provider y manejar conflictos visualmente
  Future<void> _asignarColaboradorViaProvider(_UsuarioMini u) async {
    final provider = context.read<ProyectoProvider>();
    final code = await provider.asignarColaborador(
      proyectoId: widget.proyectoId,
      uidColaborador: u.uid,
      asignadoBy: context.read<AuthProvider>().uid,
    );

    if (!mounted) return;

    // Si ya era supervisor, ofrecemos el cambio aquí
    if (code == ProyResultCode.supConflict) {
      await _switchSupervisorToColaborador(u.uid);
      return;
    }

    // Mostrar feedback estándar (ok / error)
    _showProviderFeedback(context, provider);
  }

  Future<void> _openAgregarColaboradorSheet() async {
    // UIDs ya colaboradores
    final yaColabSnap = await _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: widget.proyectoId)
        .where('id_rol', isEqualTo: Rol.colaborador)
        .get();
    final uidsColab = yaColabSnap.docs
        .map((d) => (d.data()['uid_usuario'] as String?) ?? '')
        .where((x) => x.isNotEmpty)
        .toSet();

    // UIDs ya supervisores (para ocultar candidatos en conflicto)
    final yaSupSnap = await _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: widget.proyectoId)
        .where('id_rol', isEqualTo: Rol.supervisor)
        .get();
    final uidsSup = yaSupSnap.docs
        .map((d) => (d.data()['uid_usuario'] as String?) ?? '')
        .where((x) => x.isNotEmpty)
        .toSet();

    String filtro = '';
    String? uidSeleccionado;
    _UsuarioMini? usuarioSeleccionado;

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: StatefulBuilder(
              builder: (context, setLocal) {
                return SizedBox(
                  height: MediaQuery.of(context).size.height * .8,
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
                        onChanged: (v) => setLocal(() => filtro = v.trim().toLowerCase()),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: StreamBuilder<List<_UsuarioMini>>(
                          stream: _streamUsuariosAprobados(),
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return const Center(child: Text('Error al cargar usuarios'));
                            }
                            if (!snap.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            final lista = snap.data!
                            // ocultar los ya colaboradores
                                .where((u) => !uidsColab.contains(u.uid))
                            // ocultar los que ya son supervisores (conflicto)
                                .where((u) => !uidsSup.contains(u.uid))
                                .where((u) {
                              if (filtro.isEmpty) return true;
                              final n = u.nombre.toLowerCase();
                              final c = u.correo.toLowerCase();
                              return n.contains(filtro) || c.contains(filtro);
                            }).toList()
                              ..sort((a, b) =>
                                  a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

                            if (lista.isEmpty) {
                              return const Center(child: Text('No hay usuarios que coincidan'));
                            }

                            return ListView.separated(
                              itemCount: lista.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final u = lista[i];
                                return RadioListTile<String>(
                                  value: u.uid,
                                  groupValue: uidSeleccionado,
                                  onChanged: (v) {
                                    setLocal(() {
                                      uidSeleccionado = v;
                                      usuarioSeleccionado = u;
                                    });
                                  },
                                  title: Text(u.nombre),
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
                              onPressed: (uidSeleccionado == null || usuarioSeleccionado == null)
                                  ? null
                                  : () async {
                                final uid = usuarioSeleccionado!.uid;

                                // Si YA es SUPERVISOR => ofrecer cambiar a colaborador
                                if (uidsSup.contains(uid)) {
                                  await _switchSupervisorToColaborador(uid);
                                  if (!mounted) return;
                                  Navigator.pop(context);
                                  return;
                                }

                                // Asignación normal usando provider (para mensajes coherentes)
                                await _asignarColaboradorViaProvider(usuarioSeleccionado!);
                                if (!mounted) return;
                                Navigator.pop(context);
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

  // ========= SUPERVISORES: admin único =========
  Future<void> _openAsignarSupervisorSheet() async {
    final provider = context.read<ProyectoProvider>();
    final auth = context.read<AuthProvider>();

    // UIDs ya supervisores
    final yaSupSnap = await _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: widget.proyectoId)
        .where('id_rol', isEqualTo: Rol.supervisor)
        .get();
    final uidsSup = yaSupSnap.docs
        .map((d) => (d.data()['uid_usuario'] as String?) ?? '')
        .where((x) => x.isNotEmpty)
        .toSet();

    // UIDs ya colaboradores (para ocultar candidatos en conflicto)
    final yaColabSnap = await _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: widget.proyectoId)
        .where('id_rol', isEqualTo: Rol.colaborador)
        .get();
    final uidsColab = yaColabSnap.docs
        .map((d) => (d.data()['uid_usuario'] as String?) ?? '')
        .where((x) => x.isNotEmpty)
        .toSet();

    String? uidSeleccionado;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: StatefulBuilder(
              builder: (context, setLocal) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Asignar Supervisor',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    StreamBuilder<List<_UsuarioMini>>(
                      stream: _streamUsuariosAprobados(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const LinearProgressIndicator();
                        }
                        var usuarios = snapshot.data ?? const <_UsuarioMini>[];
                        // Ocultar ya supervisores y los que son colaboradores (conflicto)
                        usuarios = usuarios
                            .where((u) => !uidsSup.contains(u.uid))
                            .where((u) => !uidsColab.contains(u.uid))
                            .toList();
                        if (usuarios.isEmpty) {
                          return const Text('No hay usuarios aprobados disponibles.');
                        }
                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Usuario aprobado',
                            border: OutlineInputBorder(),
                          ),
                          value: uidSeleccionado,
                          items: usuarios.map((u) {
                            return DropdownMenuItem<String>(
                              value: u.uid,
                              child: Text(
                                  '${u.nombre} · ${u.correo.isNotEmpty ? u.correo : "—"}'),
                            );
                          }).toList(),
                          onChanged: (val) => setLocal(() => uidSeleccionado = val),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: provider.actionInProgress || uidSeleccionado == null
                            ? null
                            : () async {
                          final uid = uidSeleccionado!;

                          // Si YA es COLABORADOR => ofrecer cambiar a supervisor
                          if (uidsColab.contains(uid)) {
                            await _switchColaboradorToSupervisor(uid);
                            if (mounted) Navigator.pop(context);
                            return;
                          }

                          // Asignación normal (sin conflicto)
                          final code = await provider.asignarSupervisor(
                            proyectoId: widget.proyectoId,
                            uidSupervisor: uid,
                            uidAdmin: auth.uid!,
                          );
                          if (!mounted) return;
                          _showProviderFeedback(context, provider);
                          if (code == ProyResultCode.ok) {
                            Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Confirmar'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _quitarSupervisor(String uidSupervisor) async {
    final provider = context.read<ProyectoProvider>();
    try {
      final code = await provider.quitarSupervisor(
          proyectoId: widget.proyectoId, uidSupervisor: uidSupervisor);
      if (!mounted) return;
      _showProviderFeedback(context, provider);
      if (code == ProyResultCode.ok) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Supervisor retirado')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ========= UI =========
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permisos = PermisosService(auth);

    final isAdminGlobal = permisos.isAdminGlobal;
    final canManageColabs =
        isAdminGlobal || permisos.canManageCollaboratorsFor(widget.proyectoId);
    final canSeeColabs = canManageColabs; // dueños/supervisores/admin único
    final canManageSup = isAdminGlobal; // solo admin único
    final canSeeSup = isAdminGlobal; // solo admin único

    if (!canSeeColabs && !canSeeSup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/seleccion');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Listener para mostrar cualquier mensaje pendiente del provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ProyectoProvider>();
      if ((provider.lastMessage?.isNotEmpty ?? false) ||
          (provider.lastError?.isNotEmpty ?? false)) {
        _showProviderFeedback(context, provider);
      }
    });

    final tabs = <_TabSpec>[
      if (canSeeColabs) _TabSpec('Colaboradores', Icons.group_outlined),
      if (canSeeSup) _TabSpec('Supervisores', Icons.verified_user_outlined),
    ];

    // Si solo hay una pestaña (Colaboradores), UI simple
    if (tabs.length == 1 && tabs.first.label == 'Colaboradores') {
      return Scaffold(
        appBar: AppBar(title: const Text('Equipo del proyecto · Colaboradores')),
        floatingActionButton: canManageColabs
            ? FloatingActionButton.extended(
          onPressed: _openAgregarColaboradorSheet,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Agregar'),
        )
            : null,
        body: _ColaboradoresView(
          proyectoId: widget.proyectoId,
          canManage: canManageColabs,
          streamColabs: _streamColaboradores,
          fetchUser: _fetchUser,
          onToggleActivo: _setActivo,
          onDelete: _eliminarColaborador,
        ),
      );
    }

    // Con pestañas (Admin único)
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Equipo del proyecto'),
          bottom: TabBar(
            tabs: tabs.map((t) => Tab(text: t.label, icon: Icon(t.icon))).toList(),
          ),
        ),
        // FAB reactivo a la pestaña activa
        floatingActionButton: Builder(
          builder: (ctx) {
            final ctrl = DefaultTabController.of(ctx);
            return AnimatedBuilder(
              animation: ctrl.animation ?? ctrl,
              builder: (_, __) {
                final idx = ctrl.index;
                final isColabTab = tabs[idx].label == 'Colaboradores';
                if (isColabTab && canManageColabs) {
                  return FloatingActionButton.extended(
                    onPressed: _openAgregarColaboradorSheet,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Agregar colaborador'),
                  );
                } else if (!isColabTab && canManageSup) {
                  return FloatingActionButton.extended(
                    onPressed: _openAsignarSupervisorSheet,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Asignar supervisor'),
                  );
                }
                return const SizedBox.shrink();
              },
            );
          },
        ),
        body: TabBarView(
          children: tabs.map((t) {
            if (t.label == 'Colaboradores') {
              return _ColaboradoresView(
                proyectoId: widget.proyectoId,
                canManage: canManageColabs,
                streamColabs: _streamColaboradores,
                fetchUser: _fetchUser,
                onToggleActivo: _setActivo,
                onDelete: _eliminarColaborador,
              );
            } else {
              return _SupervisoresView(
                proyectoId: widget.proyectoId,
                streamSupervisores: _streamSupervisores,
                fetchUser: _fetchUser,
                canManage: canManageSup,
                onRemove: _quitarSupervisor,
                onAssignTap: _openAsignarSupervisorSheet,
              );
            }
          }).toList(),
        ),
      ),
    );
  }
}

class _ColaboradoresView extends StatelessWidget {
  final String proyectoId;
  final bool canManage;
  final Stream<List<_Miembro>> Function() streamColabs;
  final Future<_UsuarioMini?> Function(String uid) fetchUser;
  final Future<void> Function(_Miembro m, bool value) onToggleActivo;
  final Future<void> Function(_Miembro m) onDelete;

  const _ColaboradoresView({
    required this.proyectoId,
    required this.canManage,
    required this.streamColabs,
    required this.fetchUser,
    required this.onToggleActivo,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<_Miembro>>(
      stream: streamColabs(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final miembros = snap.data!;
        if (miembros.isEmpty) {
          return const Center(child: Text('Aún no hay colaboradores en este proyecto.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: miembros.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final m = miembros[i];

            return FutureBuilder<_UsuarioMini?>(
              future: (m.nombre != null && m.correo != null)
                  ? Future.value(
                  _UsuarioMini(uid: m.uid, nombre: m.nombre!, correo: m.correo!))
                  : fetchUser(m.uid),
              builder: (context, usnap) {
                final u = usnap.data;
                final title = (u?.nombre ?? m.nombre ?? m.uid);
                final subtitle = (u?.correo ?? m.correo ?? '');

                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outline.withOpacity(.2),
                    ),
                  ),
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(title),
                  subtitle: Text(subtitle.isNotEmpty ? subtitle : '—'),
                  trailing: canManage
                      ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: m.activo,
                        onChanged: (val) => onToggleActivo(m, val),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Eliminar',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => onDelete(m),
                      ),
                    ],
                  )
                      : null,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SupervisoresView extends StatelessWidget {
  final String proyectoId;
  final Stream<List<_Miembro>> Function() streamSupervisores;
  final Future<_UsuarioMini?> Function(String uid) fetchUser;
  final bool canManage;
  final Future<void> Function(String uidSupervisor) onRemove;
  final Future<void> Function() onAssignTap;

  const _SupervisoresView({
    required this.proyectoId,
    required this.streamSupervisores,
    required this.fetchUser,
    required this.canManage,
    required this.onRemove,
    required this.onAssignTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (canManage)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Asignar supervisor'),
                onPressed: onAssignTap,
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<List<_Miembro>>(
            stream: streamSupervisores(),
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(child: Text('Error al cargar supervisores'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final lista = snap.data!;
              if (lista.isEmpty) {
                return const Center(child: Text('Sin supervisores'));
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: lista.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final m = lista[i];
                  return FutureBuilder<_UsuarioMini?>(
                    future: (m.nombre != null && m.correo != null)
                        ? Future.value(
                        _UsuarioMini(uid: m.uid, nombre: m.nombre!, correo: m.correo!))
                        : fetchUser(m.uid),
                    builder: (context, usnap) {
                      final u = usnap.data;
                      final title = (u?.nombre ?? m.nombre ?? m.uid);
                      final subtitle = (u?.correo ?? m.correo ?? '');

                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outline.withOpacity(.2),
                          ),
                        ),
                        leading:
                        const CircleAvatar(child: Icon(Icons.verified_user_outlined)),
                        title: Text(title),
                        subtitle: Text(subtitle.isNotEmpty ? subtitle : '—'),
                        trailing: canManage
                            ? IconButton(
                          tooltip: 'Retirar',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => onRemove(m.uid),
                        )
                            : null,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TabSpec {
  final String label;
  final IconData icon;
  _TabSpec(this.label, this.icon);
}

