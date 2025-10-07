import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:faunadmin2/services/firestore_service.dart';
import 'package:faunadmin2/models/usuario.dart';
import 'package:faunadmin2/utils/constants.dart';

/// Header reusable.
/// - Sólo se muestra si el usuario ES ADMIN (global).
/// - No interfiere con el AppBar/back.
/// - Opcional: chips con contadores (usuarios pendientes, proyectos activos, supervisores globales).
class AdminHeader extends StatefulWidget {
  const AdminHeader({
    super.key,
    this.contextText,
    this.showCounters = true, // pon false si no quieres chips en alguna pantalla
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 8),
  });

  final String? contextText;
  final bool showCounters;
  final EdgeInsetsGeometry padding;

  @override
  State<AdminHeader> createState() => _AdminHeaderState();
}

class _AdminHeaderState extends State<AdminHeader>
    with AutomaticKeepAliveClientMixin {
  final _fs = FirestoreService();

  fb.User? _authUser;
  Future<Usuario?>? _futureUser;     // cache de perfil
  Future<bool>? _futureEsAdmin;      // cache de verificación admin

  @override
  void initState() {
    super.initState();
    final auth = fb.FirebaseAuth.instance;
    _authUser = auth.currentUser;

    if (_authUser != null) {
      _futureUser   = _fs.getUsuario(_authUser!.uid);
      _futureEsAdmin = _fs.userTieneRolGlobal(_authUser!.uid, RoleIds.admin);
    }

    // Reacciona a cambios de sesión
    auth.userChanges().listen((user) {
      if (!mounted) return;
      setState(() {
        _authUser = user;
        if (user != null) {
          _futureUser    = _fs.getUsuario(user.uid);
          _futureEsAdmin = _fs.userTieneRolGlobal(user.uid, RoleIds.admin);
        } else {
          _futureUser = null;
          _futureEsAdmin = null;
        }
      });
    });
  }

  // ---- Streams de contadores (opcionales) ----
  Stream<int> _usuariosPendientesCount() => FirebaseFirestore.instance
      .collection(Collections.usuarios)
      .where('estatus', isEqualTo: 'pendiente')
      .snapshots()
      .map((s) => s.size);

  Stream<int> _proyectosActivosCount() => FirebaseFirestore.instance
      .collection(Collections.proyectos)
      .where('activo', isEqualTo: true)
      .snapshots()
      .map((s) => s.size);

  Stream<int> _supervisoresGlobalCount() => FirebaseFirestore.instance
      .collection(Collections.usuarioRolProyecto)
      .where('id_rol', isEqualTo: RoleIds.supervisor)
      .where('id_proyecto', isNull: true)
      .where('activo', isEqualTo: true)
      .snapshots()
      .map((s) => s.size);

  String _initials(String? nombre, String? email) {
    final src = (nombre?.trim().isNotEmpty == true)
        ? nombre!.trim()
        : (email?.trim().isNotEmpty == true ? email!.trim() : '');
    if (src.isEmpty) return '?';
    final parts = src.split(RegExp(r'\s+'));
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Si no hay sesión, no pintamos nada.
    if (_authUser == null) return const SizedBox.shrink();

    return FutureBuilder<bool>(
      future: _futureEsAdmin,
      builder: (context, adminSnap) {
        // Si aún no sabemos si es admin, no rompas el layout
        if (adminSnap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        // Si NO es admin, no mostrar header
        if (adminSnap.data != true) return const SizedBox.shrink();

        // Es admin → construimos el header normal
        final emailAuth = fb.FirebaseAuth.instance.currentUser?.email;
        return Padding(
          padding: widget.padding,
          child: Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.25),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FutureBuilder<Usuario?>(
                future: _futureUser,
                builder: (context, snap) {
                  final hasData = snap.hasData && snap.data != null;
                  final nombre = hasData
                      ? (snap.data!.nombreCompleto.trim().isNotEmpty == true
                      ? snap.data!.nombreCompleto.trim()
                      : 'Administrador Principal')
                      : 'Administrador Principal';
                  final email = hasData
                      ? (snap.data!.correo.trim().isNotEmpty == true
                      ? snap.data!.correo
                      : emailAuth)
                      : emailAuth;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            child: Text(_initials(nombre, email)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nombre,
                                  style: Theme.of(context).textTheme.titleMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (email != null && email.isNotEmpty)
                                  Text(
                                    email,
                                    style: Theme.of(context).textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (widget.contextText != null &&
                                    widget.contextText!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.contextText!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: Theme.of(context).hintColor),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),

                      if (widget.showCounters) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatChip(
                              icon: Icons.group_outlined,
                              label: 'Usuarios pendientes',
                              streamCount: _usuariosPendientesCount(),
                            ),
                            _StatChip(
                              icon: Icons.folder_copy_outlined,
                              label: 'Proyectos activos',
                              streamCount: _proyectosActivosCount(),
                            ),
                            _StatChip(
                              icon: Icons.verified_user_outlined,
                              label: 'Supervisores (global)',
                              streamCount: _supervisoresGlobalCount(),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Stream<int> streamCount;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.streamCount,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return StreamBuilder<int>(
      stream: streamCount,
      builder: (context, snap) {
        final n = snap.data ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: color.withOpacity(0.12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$n',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
