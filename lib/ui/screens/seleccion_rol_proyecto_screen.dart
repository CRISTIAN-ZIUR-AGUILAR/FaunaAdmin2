// lib/ui/screens/seleccion_rol_proyecto_screen.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/models/rol.dart';
import 'package:faunadmin2/models/usuario_rol_proyecto.dart';
import 'package:faunadmin2/models/proyecto.dart';
import 'package:faunadmin2/services/firestore_service.dart';
import 'package:faunadmin2/ui/widgets/app_drawer.dart';

class SeleccionRolProyectoScreen extends StatefulWidget {
  const SeleccionRolProyectoScreen({Key? key}) : super(key: key);

  @override
  State<SeleccionRolProyectoScreen> createState() =>
      _SeleccionRolProyectoScreenState();
}

class _SeleccionRolProyectoScreenState
    extends State<SeleccionRolProyectoScreen> {
  final _fs = FirestoreService();

  // Ruta del dashboard de usuario (ajústala si usas otra)
  static const String _userDashboardRoute = '/dashboard';

  // --- Estado para stream combinado ---
  final _payloadCtrl = StreamController<_Payload>.broadcast();
  StreamSubscription<List<Proyecto>>? _subProy;
  StreamSubscription<List<UsuarioRolProyecto>>? _subUrps;

  // caches para combinar
  List<Proyecto> _cacheOwnerProy = const [];
  List<UsuarioRolProyecto> _cacheUrps = const [];

  @override
  void initState() {
    super.initState();
    // El wiring de streams se hace en didChangeDependencies, cuando ya hay AuthProvider
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final auth = context.read<AuthProvider>();
    final uid = auth.usuario?.uid;
    if (uid == null) return;

    // Cancela subs previas si cambia de usuario
    _subProy?.cancel();
    _subUrps?.cancel();

    // Suscribirse a proyectos donde soy dueño
    _subProy = _fs.streamProyectosByOwner(uid).listen((proys) {
      _cacheOwnerProy = proys;
      _emitCombined();
    }, onError: (e) {
      if (!_payloadCtrl.isClosed) {
        _payloadCtrl.addError(e);
      }
    });

    // Suscribirse a todas mis URPs (activas según tu service)
    _subUrps = _fs.streamUsuarioRolProyectosForUser(uid).listen((urps) {
      _cacheUrps = urps;
      _emitCombined();
    }, onError: (e) {
      if (!_payloadCtrl.isClosed) {
        _payloadCtrl.addError(e);
      }
    });
  }

  @override
  void dispose() {
    _subProy?.cancel();
    _subUrps?.cancel();
    _payloadCtrl.close();
    super.dispose();
  }

  void _emitCombined() {
    try {
      // URPs por proyecto (idProyecto no vacío y activo)
      List<UsuarioRolProyecto> _byRoleWithProject(int roleId) => _cacheUrps
          .where((x) =>
      x.idRol == roleId &&
          (x.idProyecto?.isNotEmpty ?? false) &&
          (x.activo != false))
          .toList();

      // Flags globales (idProyecto null/empty y activo)
      bool _hasGlobal(int roleId) => _cacheUrps.any((x) =>
      x.idRol == roleId &&
          ((x.idProyecto == null) || (x.idProyecto?.isEmpty ?? true)) &&
          (x.activo != false));

      final payload = _Payload(
        ownerProjects: _cacheOwnerProy,
        supervisorUrps: _byRoleWithProject(Rol.supervisor),
        colaboradorUrps: _byRoleWithProject(Rol.colaborador),
        recoUrps: _byRoleWithProject(Rol.recolector),
        hasOwnerGlobal: _hasGlobal(Rol.duenoProyecto),
        hasRecoGlobal: _hasGlobal(Rol.recolector),
      );

      if (!_payloadCtrl.isClosed) {
        _payloadCtrl.add(payload);
      }

      if (kDebugMode) {
        final up = _cacheUrps
            .map((u) => '(${u.idRol}, p:${u.idProyecto}, a:${u.activo})')
            .join(', ');
        debugPrint(
          '[seleccion] proyOwner=${_cacheOwnerProy.length} urps=[ $up ] '
              'ownerGlobal=${payload.hasOwnerGlobal} recoGlobal=${payload.hasRecoGlobal}',
        );
      }
    } catch (e, st) {
      if (!_payloadCtrl.isClosed) {
        _payloadCtrl.addError(e, st);
      }
    }
  }

  // -------- Helpers de vista --------
  String _rolName(int idRol) {
    const labels = {
      Rol.admin: 'Administrador',
      Rol.supervisor: 'Supervisor',
      Rol.recolector: 'Recolector',
      Rol.duenoProyecto: 'Dueño de Proyecto',
      Rol.colaborador: 'Colaborador',
    };
    return labels[idRol] ?? 'Rol $idRol';
  }

  IconData _rolIcon(int idRol) {
    switch (idRol) {
      case Rol.admin:
        return Icons.admin_panel_settings_rounded;
      case Rol.supervisor:
        return Icons.verified_user_rounded;
      case Rol.recolector:
        return Icons.nature_people_rounded;
      case Rol.duenoProyecto:
        return Icons.workspaces_rounded;
      case Rol.colaborador:
        return Icons.group_rounded;
      default:
        return Icons.badge_rounded;
    }
  }

  Color _rolColor(BuildContext context, int idRol) {
    switch (idRol) {
      case Rol.admin:
        return Colors.deepPurple;
      case Rol.supervisor:
        return Colors.indigo;
      case Rol.recolector:
        return Colors.teal;
      case Rol.duenoProyecto:
        return Colors.orange;
      case Rol.colaborador:
        return Colors.blueGrey;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  bool _isRoleSelected(AuthProvider auth, int idRol) {
    final sel = auth.selectedRolProyecto;
    return sel != null && sel.idRol == idRol;
  }

  // ---------- Helper: crear proyecto (solo Dueño global) ----------
  Future<void> _crearProyecto(AuthProvider auth) async {
    final res = await Navigator.of(context).pushNamed(
      '/proyectos/crear',
      arguments: {'allowFromSeleccion': true},
    );
    if (!mounted) return;
    if (res is String && res.isNotEmpty) {
      auth.selectRolProyecto(UsuarioRolProyecto(
        id: 'local-owner-$res',
        idRol: Rol.duenoProyecto,
        uidUsuario: auth.usuario!.uid,
        idProyecto: res,
        activo: true,
        estatus: 'aprobado',
      ));
      Navigator.of(context)
          .pushNamed('/proyectos/detalle_dueno', arguments: res);
    }
  }

  // ============================ Acciones ============================

  // Dueño: elegir proyecto (si hay varios) y entrar a la vista del dueño
  Future<void> _onTapOwner(
      AuthProvider auth, List<Proyecto> ownerProjects) async {
    if (ownerProjects.length == 1) {
      final p = ownerProjects.first;
      _selectOwnerAndEnter(auth, p);
      return;
    }
    // Varios: picker
    await _showProjectPicker(
      title: 'Tus proyectos (Dueño)',
      projects: ownerProjects,
      onChoose: (p) => _selectOwnerAndEnter(auth, p),
    );
  }

  void _selectOwnerAndEnter(AuthProvider auth, Proyecto p) {
    final urp = UsuarioRolProyecto(
      id: 'local-owner-${p.id}',
      idRol: Rol.duenoProyecto,
      uidUsuario: auth.usuario!.uid,
      idProyecto: p.id,
      activo: true,
      estatus: 'aprobado',
    );
    auth.selectRolProyecto(urp);
    Navigator.of(context)
        .pushNamed('/proyectos/detalle_dueno', arguments: p.id);
  }

  // Supervisor/Colaborador/Recolector: usar URPs existentes por proyecto
  Future<void> _onTapUrpRole(
      AuthProvider auth,
      int roleId,
      List<UsuarioRolProyecto> urps,
      ) async {
    if (urps.length == 1) {
      final u = urps.first;
      auth.selectRolProyecto(u);
      Navigator.of(context)
          .pushNamed(_routeForRole(roleId), arguments: u.idProyecto);
      return;
    }

    // Varios: cargar proyectos para mostrar nombres
    final ids = urps.map((u) => u.idProyecto!).toSet().toList();
    final proyectos = await _fs.getProyectosPorIds(ids);

    await _showProjectPicker(
      title: '${_rolName(roleId)} · Proyectos',
      projects: proyectos,
      onChoose: (p) {
        final chosen = urps.firstWhere((u) => u.idProyecto == p.id);
        auth.selectRolProyecto(chosen);
        Navigator.of(context)
            .pushNamed(_routeForRole(roleId), arguments: p.id);
      },
    );
  }

  String _routeForRole(int roleId) {
    if (roleId == Rol.duenoProyecto) return '/proyectos/detalle_dueno';
    return '/proyectos/detalle';
  }

  // Recolector GLOBAL: sin proyecto, entra directo a Observaciones
  Future<void> _onTapRecolectorGlobal(AuthProvider auth) async {
    UsuarioRolProyecto? urpGlobal;

    try {
      urpGlobal = _cacheUrps.firstWhere(
            (u) =>
        u.idRol == Rol.recolector &&
            ((u.idProyecto == null) || (u.idProyecto?.isEmpty ?? true)) &&
            (u.activo != false),
      );
    } catch (_) {
      // Fallback defensivo: URP virtual si no lo encuentra en cache
      final user = auth.usuario;
      if (user != null) {
        urpGlobal = UsuarioRolProyecto(
          id: 'local-recolector-global',
          idRol: Rol.recolector,
          uidUsuario: user.uid,
          idProyecto: null,
          activo: true,
          estatus: 'aprobado',
        );
      }
    }

    if (urpGlobal != null) {
      auth.selectRolProyecto(urpGlobal);
    }

    if (!mounted) return;
    Navigator.of(context).pushNamed('/observaciones/list');
  }

  Future<void> _showProjectPicker({
    required String title,
    required List<Proyecto> projects,
    required void Function(Proyecto) onChoose,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: const [
                    Icon(Icons.folder_open_rounded),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Selecciona un proyecto',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: projects.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = projects[i];
                    final nombre = p.nombre.trim().isNotEmpty
                        ? p.nombre.trim()
                        : 'Proyecto ${p.id}';
                    final cat = (p.categoriaNombre ?? '').trim();
                    return ListTile(
                      leading: const Icon(Icons.folder_rounded),
                      title: Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: cat.isNotEmpty ? Text(cat) : null,
                      onTap: () {
                        Navigator.of(context).pop();
                        onChoose(p);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // --------- UI ---------
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.usuario == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Si es admin, lo redirige al dashboard admin
    if (auth.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context)
            .pushReplacementNamed('/admin/dashboard');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Seleccionar Rol/Proyecto')),
      drawer: const AppDrawer(),
      body: StreamBuilder<_Payload>(
        stream: _payloadCtrl.stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return _StateMsg(
              icon: Icons.error_outline,
              title: 'No se pudo cargar',
              subtitle: '${snap.error}',
              action: TextButton(
                onPressed: () => _emitCombined(),
                child: const Text('Reintentar'),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!;
          final tiles = <Widget>[];

          tiles.add(_sectionHeader(context, 'Elige cómo quieres entrar'));

          // Acceso directo al panel principal (dashboard de usuario)
          tiles.add(_tileEntradaDashboard(context));

          // ===== Dueño =====
          if (data.ownerProjects.isNotEmpty) {
            final ownerCounter =
                'Tus proyectos: ${data.ownerProjects.length}';
            tiles.add(
              _tileRol(
                context: context,
                auth: auth,
                idRol: Rol.duenoProyecto,
                titulo: _rolName(Rol.duenoProyecto),
                subtitulo: 'Gestiona y abre tus proyectos',
                contadorLabel: ownerCounter,
                icon: _rolIcon(Rol.duenoProyecto),
                color: _rolColor(context, Rol.duenoProyecto),
                onTap: () => _onTapOwner(auth, data.ownerProjects),
              ),
            );
          } else if (data.hasOwnerGlobal) {
            // Dueño global sin proyectos → CTA crear
            tiles.add(
              _tileRol(
                context: context,
                auth: auth,
                idRol: Rol.duenoProyecto,
                titulo: _rolName(Rol.duenoProyecto),
                subtitulo: 'Aún no tienes proyectos. Crea el primero.',
                contadorLabel: '0 proyectos',
                icon: _rolIcon(Rol.duenoProyecto),
                color: _rolColor(context, Rol.duenoProyecto),
                onTap: () async {
                  final projId = await Navigator.of(context).pushNamed(
                    '/proyectos/crear',
                    arguments: {'allowFromSeleccion': true},
                  );

                  if (!mounted) return;
                  if (projId is String && projId.isNotEmpty) {
                    auth.selectRolProyecto(UsuarioRolProyecto(
                      id: 'local-owner-$projId',
                      idRol: Rol.duenoProyecto,
                      uidUsuario: auth.usuario!.uid,
                      idProyecto: projId,
                      activo: true,
                      estatus: 'aprobado',
                    ));
                    Navigator.of(context).pushNamed(
                      '/proyectos/detalle_dueno',
                      arguments: projId,
                    );
                  }
                },
              ),
            );
          }

          // ===== Supervisor (por proyecto) =====
          if (data.supervisorUrps.isNotEmpty) {
            tiles.add(
              _tileRol(
                context: context,
                auth: auth,
                idRol: Rol.supervisor,
                titulo: _rolName(Rol.supervisor),
                subtitulo: 'Revisa proyectos asignados',
                contadorLabel:
                'Asignados: ${data.supervisorUrps.length}',
                icon: _rolIcon(Rol.supervisor),
                color: _rolColor(context, Rol.supervisor),
                onTap: () =>
                    _onTapUrpRole(auth, Rol.supervisor, data.supervisorUrps),
              ),
            );
          }

          // ===== Colaborador (por proyecto) =====
          if (data.colaboradorUrps.isNotEmpty) {
            tiles.add(
              _tileRol(
                context: context,
                auth: auth,
                idRol: Rol.colaborador,
                titulo: _rolName(Rol.colaborador),
                subtitulo: 'Trabaja en tus proyectos asignados',
                contadorLabel:
                'Asignados: ${data.colaboradorUrps.length}',
                icon: _rolIcon(Rol.colaborador),
                color: _rolColor(context, Rol.colaborador),
                onTap: () =>
                    _onTapUrpRole(auth, Rol.colaborador, data.colaboradorUrps),
              ),
            );
          }

          // ===== Recolector (por proyecto) =====
          if (data.recoUrps.isNotEmpty) {
            tiles.add(
              _tileRol(
                context: context,
                auth: auth,
                idRol: Rol.recolector,
                titulo: _rolName(Rol.recolector),
                subtitulo: 'Captura dentro de tus proyectos',
                contadorLabel: 'Asignados: ${data.recoUrps.length}',
                icon: _rolIcon(Rol.recolector),
                color: _rolColor(context, Rol.recolector),
                onTap: () =>
                    _onTapUrpRole(auth, Rol.recolector, data.recoUrps),
              ),
            );
          } else if (data.hasRecoGlobal) {
            // Recolector global → Observaciones (sin proyecto)
            tiles.add(
              _tileRol(
                context: context,
                auth: auth,
                idRol: Rol.recolector,
                titulo: _rolName(Rol.recolector),
                subtitulo: 'Accede a Observaciones (sin proyecto).',
                contadorLabel: 'Sin proyecto',
                icon: _rolIcon(Rol.recolector),
                color: _rolColor(context, Rol.recolector),
                onTap: () => _onTapRecolectorGlobal(auth),
              ),
            );
          }

          if (tiles.isEmpty) return const _EmptyState();

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => tiles[i],
          );
        },
      ),

      // FAB --> Solo aparece si el usuario tiene Dueño global
      floatingActionButton: StreamBuilder<_Payload>(
        stream: _payloadCtrl.stream,
        builder: (context, snapFab) {
          final canCreate =
              snapFab.hasData && (snapFab.data!.hasOwnerGlobal == true);
          if (!canCreate) return const SizedBox.shrink();
          final auth = context.read<AuthProvider>();
          return FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Crear proyecto'),
            onPressed: () => _crearProyecto(auth),
          );
        },
      ),
    );
  }

  // ---------- Encabezado de sección ----------
  Widget _sectionHeader(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          letterSpacing: .3,
          fontWeight: FontWeight.w700,
          color: cs.onSurface.withOpacity(.7),
        ),
      ),
    );
  }

  // ---------- Card de acceso directo al dashboard ----------
  Widget _tileEntradaDashboard(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).pushNamed(_userDashboardRoute),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: _boxDecoration(context, color, false),
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withOpacity(.12),
              child: Icon(
                Icons.dashboard_customize_rounded,
                color: color,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Panel principal',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text('Ir al dashboard de usuario'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Card de rol ----------
  Widget _tileRol({
    required BuildContext context,
    required AuthProvider auth,
    required int idRol,
    required String titulo,
    required String? subtitulo,
    required String? contadorLabel,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isSelected = _isRoleSelected(auth, idRol);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: _boxDecoration(context, color, isSelected),
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withOpacity(.12),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (subtitulo != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(.7),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        label: Text(_rolName(idRol)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: color.withOpacity(.1),
                        shape: StadiumBorder(
                          side: BorderSide(color: color.withOpacity(.25)),
                        ),
                        labelStyle: TextStyle(
                            color: color, fontWeight: FontWeight.w600),
                      ),
                      if (contadorLabel != null)
                        const SizedBox.shrink(),
                      if (contadorLabel != null)
                        Chip(
                          label: Text(contadorLabel),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (isSelected)
                        const Chip(
                          label: Text('Seleccionado'),
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(Icons.check, size: 18),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _boxDecoration(
      BuildContext context, Color color, bool isSelected) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: Theme.of(context).colorScheme.surface,
      boxShadow: [
        BoxShadow(
          blurRadius: 10,
          spreadRadius: 0,
          offset: const Offset(0, 2),
          color: Colors.black.withOpacity(0.06),
        ),
      ],
      border: Border.all(
        color: isSelected
            ? color.withOpacity(.5)
            : Theme.of(context).colorScheme.outline.withOpacity(.18),
        width: isSelected ? 1.5 : 1,
      ),
    );
  }
}

class _Payload {
  final List<Proyecto> ownerProjects;
  final List<UsuarioRolProyecto> supervisorUrps;
  final List<UsuarioRolProyecto> colaboradorUrps;
  final List<UsuarioRolProyecto> recoUrps;

  // Flags globales
  final bool hasOwnerGlobal;
  final bool hasRecoGlobal;

  _Payload({
    required this.ownerProjects,
    required this.supervisorUrps,
    required this.colaboradorUrps,
    required this.recoUrps,
    required this.hasOwnerGlobal,
    required this.hasRecoGlobal,
  });
}

class _StateMsg extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const _StateMsg({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final onSurf =
    Theme.of(context).colorScheme.onSurface.withOpacity(.75);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: onSurf),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center),
            ],
            if (action != null) ...[
              const SizedBox(height: 10),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline_rounded,
                size: 48, color: cs.primary),
            const SizedBox(height: 12),
            const Text(
              'No tienes roles o proyectos asignados.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pide a un administrador que te asigne un rol o un proyecto.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
