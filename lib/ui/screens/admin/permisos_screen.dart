// lib/ui/screens/admin/permisos_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/services/permisos_service.dart';

class PermisosScreen extends StatelessWidget {
  const PermisosScreen({super.key});

  void _goBack(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.maybePop();
    } else {
      nav.pushReplacementNamed('/admin/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permisos = PermisosService(auth);

    final sel = auth.selectedRolProyecto;
    final proyectoIdCtx = sel?.idProyecto; // puede ser null si es rol global

    // Header inline (igual estilo que en Roles)
    final authUser = fb.FirebaseAuth.instance.currentUser;
    final headerTitle = 'Administrador Principal';
    final headerSubtitle = authUser?.email ?? '—';

    return WillPopScope(
      onWillPop: () async {
        final nav = Navigator.of(context);
        if (nav.canPop()) return true;
        nav.pushReplacementNamed('/admin/dashboard');
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Permisos'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _goBack(context),
          ),
        ),
        body: Column(
          children: [
            _InlineHeader(
              title: headerTitle,
              subtitle: headerSubtitle,
              contextText: 'Permisos y políticas',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ---- Permisos efectivos en este contexto ----
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.verified_user_outlined),
                            title: Text('Tus permisos en este contexto',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('Evaluados con tu rol/proyecto seleccionado'),
                          ),
                          const Divider(height: 1),

                          _PermisoTile(
                            label: 'Administrador',
                            value: permisos.isAdmin,
                          ),
                          _PermisoTile(
                            label: 'Ver proyectos',
                            value: permisos.canViewProjects,
                          ),
                          _PermisoTile(
                            label: 'Crear proyecto',
                            value: permisos.canCreateProject,
                          ),
                          _PermisoTile(
                            label: 'Editar proyecto actual',
                            value: proyectoIdCtx == null
                                ? null
                                : permisos.canEditProjectFor(proyectoIdCtx),
                          ),
                          _PermisoTile(
                            label: 'Asignar supervisor (cualquier proyecto permitido por política)',
                            value: permisos.canAssignSupervisor,
                          ),
                          _PermisoTile(
                            label: 'Gestionar colaboradores del proyecto actual',
                            value: proyectoIdCtx == null
                                ? null
                                : permisos.canManageCollaboratorsFor(proyectoIdCtx),
                          ),
                          _PermisoTile(
                            label: 'Ver observaciones',
                            value: permisos.canViewObservations,
                          ),

                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ---- Matriz de referencia de permisos ----
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.rule_folder_outlined),
                            title: Text('Política por rol (referencia)'),
                            subtitle: Text(
                              'Guía sugerida. Ajusta según la implementación de tu PermisosService.',
                            ),
                          ),
                          SizedBox(height: 8),
                          _PermisosMatrix(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Encabezado inline (privado de este archivo) ----------

class _InlineHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? contextText;

  const _InlineHeader({
    required this.title,
    required this.subtitle,
    this.contextText,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface.withOpacity(.7);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 1.5,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                child: Text(
                  (title.isNotEmpty ? title[0] : 'A').toUpperCase(),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: onSurface)),
                    if (contextText != null && contextText!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(contextText!, style: TextStyle(color: onSurface, fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Widgets auxiliares existentes ----------

class _PermisoTile extends StatelessWidget {
  final String label;
  final bool? value; // true=permitido, false=denegado, null=N/A

  const _PermisoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String trailingText;

    if (value == null) {
      icon = Icons.remove_circle_outline;
      color = Theme.of(context).colorScheme.outline;
      trailingText = 'N/A';
    } else if (value == true) {
      icon = Icons.check_circle_outline;
      color = Colors.green;
      trailingText = 'Permitido';
    } else {
      icon = Icons.block;
      color = Colors.redAccent;
      trailingText = 'Denegado';
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(trailingText, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          Icon(icon, color: color),
        ],
      ),
    );
  }
}

class _PermisosMatrix extends StatelessWidget {
  const _PermisosMatrix();

  Widget _c(bool v) =>
      Icon(v ? Icons.check : Icons.close, size: 18, color: v ? Colors.green : Colors.redAccent);

  @override
  Widget build(BuildContext context) {
    final rows = <_RowPerm>[
      _RowPerm('Ver proyectos',            [true,  true,  true,  true,  true]),
      _RowPerm('Crear proyecto',           [true,  false, true,  false, false]),
      _RowPerm('Editar proyecto propio',   [true,  true,  true,  false, false]),
      _RowPerm('Editar cualquier proyecto',[true,  false, false, false, false]),
      _RowPerm('Asignar supervisor',       [true,  true,  false, false, false]),
      _RowPerm('Gestionar colaboradores',  [true,  true,  true,  false, false]),
      _RowPerm('Ver observaciones',        [true,  true,  true,  true,  true]),
      _RowPerm('Aprobar/validar obs.',     [true,  true,  false, false, false]),
    ];

    final headerStyle = TextStyle(
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurface.withOpacity(.8),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: headerStyle,
        columns: const [
          DataColumn(label: Text('Acción')),
          DataColumn(label: Text('ADMIN')),
          DataColumn(label: Text('SUPERVISOR')),
          DataColumn(label: Text('DUEÑO')),
          DataColumn(label: Text('RECOLECTOR')),
          DataColumn(label: Text('COLABORADOR')),
        ],
        rows: rows.map((r) {
          return DataRow(cells: [
            DataCell(Text(r.accion)),
            DataCell(_c(r.cols[0])),
            DataCell(_c(r.cols[1])),
            DataCell(_c(r.cols[2])),
            DataCell(_c(r.cols[3])),
            DataCell(_c(r.cols[4])),
          ]);
        }).toList(),
      ),
    );
  }
}

class _RowPerm {
  final String accion;
  final List<bool> cols; // [admin, supervisor, dueño, recolector, colaborador]
  _RowPerm(this.accion, this.cols);
}
