// lib/ui/screens/admin/usuarios_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:faunadmin2/models/usuario.dart';
import 'package:faunadmin2/services/firestore_service.dart';
import 'package:faunadmin2/utils/constants.dart';

class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});
  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen>
    with SingleTickerProviderStateMixin {
  final _fs = FirestoreService();
  late final TabController _tab;

  static const _estPend  = 'pendiente';
  static const _estAprob = 'aprobado';
  static const _estRech  = 'rechazado';

  String get _uidActual =>
      fb.FirebaseAuth.instance.currentUser?.uid ?? 'desconocido';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      body: Column(
        children: [
          // Encabezado con info del admin actual y chips de roles
          _MiPerfilHeader(fs: _fs),

          // Tabs
          TabBar(
            controller: _tab,
            tabs: const [
              Tab(text: 'Pendientes'),
              Tab(text: 'Aprobados'),
              Tab(text: 'Rechazados'),
            ],
          ),

          // Listas por estatus
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _ListaUsuarios(
                  estatus: _estPend,
                  fs: _fs,
                  uidAdmin: _uidActual,
                  excluirUid: _uidActual,
                ),
                _ListaUsuarios(
                  estatus: _estAprob,
                  fs: _fs,
                  uidAdmin: _uidActual,
                  excluirUid: _uidActual,
                ),
                _ListaUsuarios(
                  estatus: _estRech,
                  fs: _fs,
                  uidAdmin: _uidActual,
                  excluirUid: _uidActual,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------- Encabezado de “mi perfil” con chips de roles ----------
class _MiPerfilHeader extends StatelessWidget {
  final FirestoreService fs;
  const _MiPerfilHeader({required this.fs});

  String _initials(String? nombre, String? email) {
    final base = (nombre?.trim().isNotEmpty == true)
        ? nombre!.trim()
        : (email?.trim().isNotEmpty == true ? email!.trim() : '');
    if (base.isEmpty) return '?';
    final parts = base.split(RegExp(r'\s+'));
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final auth = fb.FirebaseAuth.instance.currentUser;
    if (auth == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 1.5,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<Usuario?>(
            future: fs.getUsuario(auth.uid),
            builder: (context, snapUser) {
              final u = snapUser.data;
              final nombre = (u?.nombreCompleto.trim().isNotEmpty == true)
                  ? u!.nombreCompleto.trim()
                  : 'Administrador Principal';
              final correo = (u?.correo.trim().isNotEmpty == true)
                  ? u!.correo.trim()
                  : (auth.email ?? '—');

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(radius: 24, child: Text(_initials(nombre, correo))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nombre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              correo,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(.75),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Roles globales',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<int>>(
                    future: fs.getRolesGlobalesIds(auth.uid),
                    builder: (context, snap) {
                      final ids = snap.data ?? const <int>[];
                      if (ids.isEmpty) {
                        return const Text('Sin roles globales', style: TextStyle(fontSize: 12, color: Colors.grey));
                      }
                      return Wrap(
                        spacing: 8,
                        runSpacing: -8,
                        children: ids
                            .map((id) => Chip(
                          label: Text(
                            kRoleLabels[id] ?? 'Rol $id',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ))
                            .toList(),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// ---------- Lista de usuarios por estatus ----------
class _ListaUsuarios extends StatelessWidget {
  final String estatus;
  final FirestoreService fs;
  final String uidAdmin;
  final String? excluirUid; // para no mostrar al usuario actual si se desea
  const _ListaUsuarios({
    required this.estatus,
    required this.fs,
    required this.uidAdmin,
    this.excluirUid,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Usuario>>(
      stream: fs.streamUsuariosPorEstatus(estatus),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        var data = snap.data ?? const <Usuario>[];

        if (excluirUid != null) {
          data = data.where((u) => u.uid != excluirUid).toList();
        }

        if (data.isEmpty) {
          return Center(child: Text('Sin usuarios "$estatus".'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: data.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _UsuarioTile(
            u: data[i],
            fs: fs,
            uidAdmin: uidAdmin,
            estatus: estatus,
          ),
        );
      },
    );
  }
}

/// ---------- Tile de usuario ----------
class _UsuarioTile extends StatelessWidget {
  final Usuario u;
  final FirestoreService fs;
  final String uidAdmin;
  final String estatus;
  const _UsuarioTile({
    required this.u,
    required this.fs,
    required this.uidAdmin,
    required this.estatus,
  });

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  bool _hasText(String? s) => s != null && s.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final nombre = _hasText(u.nombreCompleto) ? u.nombreCompleto.trim() : u.correo;
    final correo = u.correo;
    final ocupacion = u.ocupacion;
    final nivel = u.nivelAcademico;
    final area = u.area;

    return Card(
      elevation: 1.5,
      child: ListTile(
        leading: CircleAvatar(child: Text(_initials(nombre))),
        title: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_hasText(correo)) Text(correo),
            if (_hasText(ocupacion)) _InfoRow(icon: Icons.work_outline, label: ocupacion),
            if (_hasText(nivel)) _InfoRow(icon: Icons.school_outlined, label: nivel),
            if (_hasText(area)) _InfoRow(icon: Icons.category_outlined, label: area),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: -8,
              children: [
                _estadoChip(context, estatus),
                FutureBuilder<List<int>>(
                  future: fs.getRolesGlobalesIds(u.uid),
                  builder: (context, snap) {
                    final ids = snap.data ?? const <int>[];
                    if (ids.isEmpty) {
                      return const Text('Sin roles globales',
                          style: TextStyle(fontSize: 12, color: Colors.grey));
                    }
                    return Wrap(
                      spacing: 6,
                      runSpacing: -8,
                      children: ids
                          .map((id) => Chip(
                        label: Text(
                          kRoleLabels[id] ?? 'Rol $id',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        // Trailing: resolvemos si el usuario objetivo es admin global
        trailing: FutureBuilder<bool>(
          future: fs.userTieneRolGlobal(u.uid, RoleIds.admin),
          builder: (context, snap) {
            final esAdminObjetivo = snap.data == true;
            return _ActionsMenu(
              u: u,
              estatus: estatus,
              fs: fs,
              uidAdmin: uidAdmin,
              isTargetAdminGlobal: esAdminObjetivo,
            );
          },
        ),
      ),
    );
  }
}

/// ---------- UI helpers ----------
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoRow({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _estadoChip(BuildContext context, String estatus) {
  final label = {
    'pendiente': 'Pendiente',
    'aprobado': 'Aprobado',
    'rechazado': 'Rechazado',
  }[estatus] ?? estatus;

  Color fg;
  switch (estatus) {
    case 'aprobado':
      fg = Colors.green.shade600;
      break;
    case 'rechazado':
      fg = Colors.red.shade600;
      break;
    default:
      fg = Colors.amber.shade700;
      break;
  }
  final bg = fg.withOpacity(.12);

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: const ShapeDecoration(
      color: Colors.transparent,
      shape: StadiumBorder(),
    ),
    child: DecoratedBox(
      decoration: ShapeDecoration(
        color: bg,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

/// ---------- Acciones ----------
class _ActionsMenu extends StatelessWidget {
  final Usuario u;
  final String estatus;
  final FirestoreService fs;
  final String uidAdmin;

  /// Si el usuario objetivo (u) es admin global. Se usa para ocultar “Eliminar”.
  final bool isTargetAdminGlobal;

  const _ActionsMenu({
    required this.u,
    required this.estatus,
    required this.fs,
    required this.uidAdmin,
    this.isTargetAdminGlobal = false,
  });

  // ---------- acciones existentes ----------
  Future<void> _aprobar(BuildContext context) async {
    await fs.aprobarUsuario(uidUsuario: u.uid, uidAdmin: uidAdmin);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Usuario aprobado')),
    );
  }

  Future<void> _rechazar(BuildContext context) async {
    final ok = await _confirm(
      context,
      title: 'Rechazar usuario',
      message: '¿Seguro que deseas rechazar a este usuario?',
    );
    if (ok != true) return;
    await fs.rechazarUsuario(u.uid);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Usuario rechazado')),
    );
  }

  Future<void> _asignarRol(BuildContext context, int idRol) async {
    try {
      await fs.asignarRol(
        uidUsuario: u.uid,
        idRol: idRol,
        idProyecto: null, // GLOBAL: acceso general
        uidAdmin: uidAdmin,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rol asignado: ${kRoleLabels[idRol] ?? idRol}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  /// Quitar rol GLOBAL: borra los docs URP uid=idUsuario, rol=idRol, id_proyecto=null
  Future<void> _quitarRolGlobal(BuildContext context, int idRol) async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('usuario_rol_proyecto')
          .where('uid_usuario', isEqualTo: u.uid)
          .where('id_rol', isEqualTo: idRol)
          .where('id_proyecto', isNull: true)
          .get();

      if (qs.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El usuario no tiene ese rol con acceso general.')),
        );
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (final d in qs.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rol quitado: ${kRoleLabels[idRol] ?? idRol}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al quitar rol: $e')),
      );
    }
  }

  Future<void> _abrirQuitarRolesDialog(BuildContext context) async {
    final rolesIds = await fs.getRolesGlobalesIds(u.uid);
    if (rolesIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este usuario no tiene roles con acceso general.')),
      );
      return;
    }

    final filtered = rolesIds;

    // ignore: use_build_context_synchronously
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Quitar rol (acceso general)'),
              subtitle: Text('Selecciona un rol para desasignarlo'),
            ),
            for (final id in filtered)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: Text(kRoleLabels[id] ?? 'Rol $id'),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await _confirm(
                    context,
                    title: 'Quitar rol',
                    message: 'Se quitará el rol "${kRoleLabels[id] ?? 'Rol $id'}" con acceso general. ¿Deseas continuar?',
                    confirmText: 'Quitar',
                  );
                  if (ok == true) {
                    await _quitarRolGlobal(context, id);
                  }
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// ---------- NUEVO: eliminar usuario en cascada (FirestoreService) ----------
  /// Usa deleteUsuarioFirestoreCascadeNoAdmin:
  /// - No borra admin global
  /// - No borra dueños de proyecto
  /// - Elimina vínculos usuario_rol_proyecto y limpia supervisiones
  Future<void> _eliminarCascada(BuildContext context) async {
    final yo = fb.FirebaseAuth.instance.currentUser?.uid;

    // 🔒 no te borres a ti mismo
    if (yo == u.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No puedes eliminar tu propio usuario.')),
      );
      return;
    }

    // 🔒 defensa extra: no intentar si es admin (el service igual bloquea)
    final esAdminGlobal = isTargetAdminGlobal ||
        await fs.userTieneRolGlobal(u.uid, RoleIds.admin);
    if (esAdminGlobal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se puede eliminar al usuario ADMIN.')),
      );
      return;
    }

    final ok = await _confirm(
      context,
      title: 'Eliminar usuario',
      message:
      'Esta acción eliminará al usuario en la base de datos y sus vínculos (roles y equipo).\n'
          'No se eliminará la cuenta de Authentication.\n\n'
          '¿Deseas continuar?',
      confirmText: 'Eliminar',
    );
    if (ok != true) return;

    try {
      await fs.deleteUsuarioFirestoreCascadeNoAdmin(u.uid);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario eliminado correctamente')),
        );
      }
      // El StreamBuilder actualizará la lista automáticamente.
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // === Menú actualizado: SOLO roles globales (acceso general) desde Usuarios ===
    final items = <PopupMenuEntry<String>>[];

    if (estatus == 'pendiente') {
      items.addAll(const [
        PopupMenuItem(value: 'aprobar', child: Text('Aprobar')),
        PopupMenuItem(value: 'rechazar', child: Text('Rechazar')),
      ]);
    } else if (estatus == 'aprobado') {
      items.addAll(const [
        PopupMenuDivider(),
        PopupMenuItem(value: 'rol_dueno',      child: Text('Asignar DUEÑO (acceso general)')),
        PopupMenuItem(value: 'rol_recolector', child: Text('Asignar RECOLECTOR (acceso general)')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'quitar_rol',     child: Text('Quitar/desasignar rol (acceso general)')),
      ]);

      // Mostrar “Eliminar usuario en base de datos (cascada)” SOLO si:
      // - el objetivo NO es admin global
      // - el objetivo NO soy yo
      final soyYo = fb.FirebaseAuth.instance.currentUser?.uid == u.uid;
      if (!isTargetAdminGlobal && !soyYo) {
        items.addAll(const [
          PopupMenuDivider(),
          PopupMenuItem(
            value: 'eliminar_cascada',
            child: Text('Eliminar usuario en base de datos (cascada)'),
          ),
        ]);
      }
    } else {
      items.add(const PopupMenuItem(value: 'aprobar', child: Text('Aprobar')));
    }

    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'aprobar':
            await _aprobar(context);
            break;
          case 'rechazar':
            await _rechazar(context);
            break;

        // 👇 Asignaciones GLOBALes (acceso general) desde Usuarios
          case 'rol_dueno':
            await _asignarRol(context, RoleIds.duenoProyecto);     // id_proyecto=null
            break;
          case 'rol_recolector':
            await _asignarRol(context, RoleIds.recolector);        // id_proyecto=null
            break;

          case 'quitar_rol':
            await _abrirQuitarRolesDialog(context);                // usa _quitarRolGlobal
            break;

          case 'eliminar_cascada':
            await _eliminarCascada(context);
            break;
        }
      },
      itemBuilder: (context) => items,
    );
  }
}

Future<bool?> _confirm(
    BuildContext context, {
      required String title,
      required String message,
      String confirmText = 'Confirmar',
      String cancelText = 'Cancelar',
    }) async {
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(_, false), child: Text(cancelText)),
        FilledButton(onPressed: () => Navigator.pop(_, true), child: Text(confirmText)),
      ],
    ),
  );
}

