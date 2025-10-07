// lib/ui/screens/proyectos/detalle_proyecto_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:faunadmin2/models/proyecto.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/services/permisos_service.dart';

class DetalleProyectoScreen extends StatelessWidget {
  final String proyectoId;
  const DetalleProyectoScreen({super.key, required this.proyectoId});

  Stream<Proyecto?> _streamProyecto(String id) {
    return FirebaseFirestore.instance
        .collection('proyectos')
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? Proyecto.fromMap(doc.data()!, doc.id) : null);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permisos = PermisosService(auth);

    // Gate fino: permiso para ver ESTE proyecto
    if (!permisos.canViewProject(proyectoId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.of(context).pushReplacementNamed('/dashboard');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<Proyecto?>(
      stream: _streamProyecto(proyectoId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Detalle del proyecto')),
            body: Center(child: Text('Error: ${snap.error}')),
          );
        }

        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Detalle del proyecto')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final p = snap.data;
        if (p == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Detalle del proyecto')),
            body: const Center(child: Text('Proyecto no encontrado')),
          );
        }

        final nombre    = (p.nombre).trim().isNotEmpty ? p.nombre.trim() : 'Proyecto ${p.id ?? proyectoId}';
        final categoria = (p.categoriaNombre ?? '').trim();
        final activo    = p.activo != false;

        final puedeIrAEquipo = permisos.canManageCollaboratorsFor(proyectoId);

        return Scaffold(
          appBar: AppBar(
            title: Text(nombre),
            actions: [
              if (puedeIrAEquipo)
                IconButton(
                  tooltip: 'Equipo',
                  icon: const Icon(Icons.group_outlined),
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/proyectos/equipo',
                      arguments: {'proyectoId': proyectoId},
                    );
                  },
                ),
              if (permisos.canEditProjectFor(proyectoId))
                IconButton(
                  tooltip: 'Editar proyecto',
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Navigator.pushNamed(context, '/proyectos/edit', arguments: proyectoId);
                  },
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Encabezado
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(.18),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.blueGrey.withOpacity(.12),
                      child: const Icon(Icons.folder_open_rounded, color: Colors.blueGrey, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nombre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (categoria.isNotEmpty)
                                Chip(label: Text(categoria), visualDensity: VisualDensity.compact),
                              Chip(label: Text(activo ? 'Activo' : 'Inactivo'), visualDensity: VisualDensity.compact),
                              Chip(label: Text('ID: ${p.id ?? proyectoId}'), visualDensity: VisualDensity.compact),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Descripción
              if ((p.descripcion).trim().isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      p.descripcion.trim(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(.88),
                        height: 1.25,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              // Datos básicos
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(.9),
                      fontSize: 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SecTitle('Datos del proyecto'),
                        const SizedBox(height: 12),
                        _RowInfo('Código', p.id ?? proyectoId),
                        if ((p.nombre).trim().isNotEmpty) _RowInfo('Nombre', p.nombre.trim()),
                        if (categoria.isNotEmpty) _RowInfo('Categoría', categoria),
                        _RowInfo('Estado', activo ? 'Activo' : 'Inactivo'),

                        // Dueño (nombre + correo)
                        if ((p.uidDueno ?? '').trim().isNotEmpty)
                          FutureBuilder<_UserMini?>(
                            future: _UserLookup.get((p.uidDueno!).trim()),
                            builder: (context, s) {
                              if (!s.hasData) return const _RowInfo('Dueño', 'Cargando…');
                              final u = s.data!;
                              final value = u.correo.isNotEmpty ? '${u.nombre} · ${u.correo}' : u.nombre;
                              return _RowInfo('Dueño', value);
                            },
                          ),

                        // Supervisor (si existe)
                        if ((p.uidSupervisor ?? '').trim().isNotEmpty)
                          FutureBuilder<_UserMini?>(
                            future: _UserLookup.get((p.uidSupervisor!).trim()),
                            builder: (context, s) {
                              if (!s.hasData) return const _RowInfo('Supervisor', 'Cargando…');
                              final u = s.data!;
                              final value = u.correo.isNotEmpty ? '${u.nombre} · ${u.correo}' : u.nombre;
                              return _RowInfo('Supervisor', value);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Acciones rápidas
              Card(
                child: Column(
                  children: [
                    if (puedeIrAEquipo)
                      ListTile(
                        leading: const Icon(Icons.group_outlined),
                        title: const Text('Equipo'),
                        subtitle: const Text('Ver/gestionar integrantes y permisos'),
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/proyectos/equipo',
                            arguments: {'proyectoId': proyectoId},
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
                        arguments: {'proyectoId': proyectoId},
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Align(
                alignment: Alignment.center,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Volver a proyectos'),
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).maybePop();
                    } else {
                      Navigator.pushReplacementNamed(context, '/proyectos/list');
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SecTitle extends StatelessWidget {
  final String text;
  const _SecTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16));
  }
}

class _RowInfo extends StatelessWidget {
  final String label;
  final String value;
  const _RowInfo(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: onSurface.withOpacity(.7))),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: TextStyle(color: onSurface.withOpacity(.95)))),
        ],
      ),
    );
  }
}

/// ===== Helpers para mostrar nombre/correo a partir del UID =====

class _UserMini {
  final String uid;
  final String nombre;
  final String correo;
  _UserMini({required this.uid, required this.nombre, required this.correo});
}

class _UserLookup {
  static final _db = FirebaseFirestore.instance;
  static final Map<String, Future<_UserMini?>> _cache = {};

  static Future<_UserMini?> get(String uid) {
    if (uid.isEmpty) return Future.value(null);
    return _cache.putIfAbsent(uid, () async {
      try {
        final doc = await _db.collection('usuarios').doc(uid).get();
        if (!doc.exists) return _UserMini(uid: uid, nombre: uid, correo: '');
        final m = doc.data()!;

        String pickNombre(Map<String, dynamic> m) {
          final raw = (m['nombre_completo'] ??
              m['nombreCompleto'] ??
              m['displayName'] ??
              m['nombre'] ??
              '') as String;
          final v = raw.trim();
          return v.isEmpty ? uid : v;
        }

        String pickCorreo(Map<String, dynamic> m) {
          final raw = (m['correo'] ?? m['email'] ?? m['correo_electronico'] ?? '') as String;
          return raw.trim();
        }

        return _UserMini(uid: uid, nombre: pickNombre(m), correo: pickCorreo(m));
      } catch (_) {
        return _UserMini(uid: uid, nombre: uid, correo: '');
      }
    });
  }
}
