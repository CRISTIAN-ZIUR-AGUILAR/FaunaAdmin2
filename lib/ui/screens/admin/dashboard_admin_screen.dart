// lib/ui/screens/admin/dashboard_admin_screen.dart
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/models/rol.dart';
import 'package:faunadmin2/services/seed_service.dart';

class DashboardAdminScreen extends StatefulWidget {
  const DashboardAdminScreen({super.key});

  @override
  State<DashboardAdminScreen> createState() => _DashboardAdminScreenState();
}

class _DashboardAdminScreenState extends State<DashboardAdminScreen> {
  int _usuariosPendientes = 0;
  int _proyectosActivos = 0;
  int _supervisoresGlobales = 0;

  bool _loadingCounts = false;
  String? _errorCounts;

  @override
  void initState() {
    super.initState();
    _fetchCounts();
  }

  Future<void> _fetchCounts() async {
    setState(() {
      _loadingCounts = true;
      _errorCounts = null;
    });

    try {
      final usuariosQ = FirebaseFirestore.instance
          .collection('usuarios')
          .where('estatus', isEqualTo: 'pendiente')
          .get();

      final proyectosQ = FirebaseFirestore.instance
          .collection('proyectos')
          .where('activo', isEqualTo: true)
          .get();

      final supervisoresQ = FirebaseFirestore.instance
          .collection('usuario_rol_proyecto')
          .where('id_proyecto', isEqualTo: null)
          .where('id_rol', isEqualTo: Rol.supervisor)
          .where('activo', isEqualTo: true)
          .get();

      final res = await Future.wait([
        usuariosQ,
        proyectosQ,
        supervisoresQ,
      ]);

      if (!mounted) return;
      setState(() {
        _usuariosPendientes   = res[0].docs.length;
        _proyectosActivos     = res[1].docs.length;
        _supervisoresGlobales = res[2].docs.length;
        _loadingCounts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCounts = e.toString();
        _loadingCounts = false;
      });
    }
  }

  Future<void> _cerrarSesion(BuildContext context) async {
    await fb.FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  int _gridColumnsForWidth(double w) {
    if (w >= 1100) return 4;
    if (w >= 800) return 3;
    return 2;
  }


  @override
  Widget build(BuildContext context) {
    final nombre = context.select<AuthProvider, String>(
          (a) => (a.usuario?.nombreCompleto ?? '').trim(),
    );
    final correo = context.select<AuthProvider, String>(
          (a) => (a.usuario?.correo ?? '').trim(),
    );

    final canPop = Navigator.canPop(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        leading: canPop
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        )
            : null,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: _loadingCounts
                ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _loadingCounts ? null : _fetchCounts,
          ),
          IconButton(
            tooltip: 'Sembrar roles',
            icon: const Icon(Icons.cloud_download),
            onPressed: () async {
              final seeded = await SeedService().seedRolesIfEmpty();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(seeded ? 'Roles sembrados' : 'Los roles ya existen')),
              );
            },
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => _cerrarSesion(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchCounts,
        child: LayoutBuilder(
          builder: (context, cons) {
            final cols = _gridColumnsForWidth(cons.maxWidth);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Encabezado
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 1.5,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          child: Text(
                            (nombre.isNotEmpty ? nombre[0] : 'A').toUpperCase(),
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nombre.isNotEmpty ? nombre : 'Administrador',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                correo.isNotEmpty ? correo : '—',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                if (_errorCounts != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MaterialBanner(
                      content: Text(
                        'No se pudieron cargar los KPIs.\n$_errorCounts',
                        style: const TextStyle(fontSize: 13),
                      ),
                      leading: const Icon(Icons.error_outline),
                      actions: [
                        TextButton(
                          onPressed: _fetchCounts,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),

                // KPIs
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _KpiChip(
                      icon: Icons.pending_actions_outlined,
                      label: 'Usuarios pendientes',
                      value: _usuariosPendientes,
                      loading: _loadingCounts,
                      onTap: () => Navigator.pushNamed(context, '/admin/usuarios'),
                    ),
                    _KpiChip(
                      icon: Icons.folder_open_outlined,
                      label: 'Proyectos activos',
                      value: _proyectosActivos,
                      loading: _loadingCounts,
                      onTap: () => Navigator.pushNamed(context, '/admin/proyectos'), // 👈 admin
                    ),
                    _KpiChip(
                      icon: Icons.verified_user_outlined,
                      label: 'Supervisores (global)',
                      value: _supervisoresGlobales,
                      loading: _loadingCounts,
                      onTap: () => Navigator.pushNamed(context, '/admin/roles'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Grid de accesos
                GridView.count(
                  crossAxisCount: cols,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _DashboardCard(
                      icon: Icons.people_alt_outlined,
                      label: 'Usuarios',
                      subtitle: 'Aprobar y gestionar',
                      onTap: () => Navigator.pushNamed(context, '/admin/usuarios'),
                    ),
                    _DashboardCard(
                      icon: Icons.folder_shared_outlined,
                      label: 'Proyectos',
                      subtitle: 'Listado y detalle (admin)',
                      onTap: () => Navigator.pushNamed(context, '/admin/proyectos'), // 👈 admin
                    ),
                    _DashboardCard(
                      icon: Icons.badge_outlined,
                      label: 'Roles',
                      subtitle: 'Catálogo de roles',
                      onTap: () => Navigator.pushNamed(context, '/admin/roles'),
                    ),
                    _DashboardCard(
                      icon: Icons.label_outline,
                      label: 'Categorías',
                      subtitle: 'Catálogo global',
                      onTap: () => Navigator.pushNamed(context, '/admin/categorias'),
                    ),
                    _DashboardCard(
                      icon: Icons.shield_outlined,
                      label: 'Permisos',
                      subtitle: 'Reglas y políticas',
                      onTap: () => Navigator.pushNamed(context, '/admin/permisos'),
                    ),
                    _DashboardCard(
                      icon: Icons.fact_check_outlined,
                      label: 'Observaciones',
                      subtitle: 'Revisar y aprobar',
                      onTap: () => Navigator.pushNamed(context, '/observaciones/list'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------- Widgets internos ----------

class _KpiChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final bool loading;
  final VoidCallback? onTap;

  const _KpiChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.loading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.primary;
    final bg = fg.withOpacity(.08);

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: fg.withOpacity(.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: loading
                ? const SizedBox(
                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
              '$value',
              style: TextStyle(
                color: fg,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    return onTap == null
        ? child
        : InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: child,
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 42, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: scheme.onSurface.withOpacity(.65),
                    fontSize: 12.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
