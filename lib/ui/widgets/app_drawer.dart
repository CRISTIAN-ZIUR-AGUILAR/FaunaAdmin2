import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/services/firestore_service.dart';
import 'package:faunadmin2/models/proyecto.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<void> _logout(BuildContext context) async {
    final navigator = Navigator.of(context);
    await fb.FirebaseAuth.instance.signOut();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigator.pushNamedAndRemoveUntil('/login', (_) => false);
    });
  }

  void _go(BuildContext context, String route) {
    final navigator = Navigator.of(context);
    navigator.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigator.pushReplacementNamed(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final fs = FirestoreService();

    final nombre = (auth.usuario?.nombreCompleto ?? '').trim();
    final correo = (auth.usuario?.correo ?? '').trim();
    final sel = auth.selectedRolProyecto; // puede ser null

    // ---- Subtítulo dinámico para el ListTile "Seleccionar rol/proyecto"
    Widget _subtitleSeleccion() {
      if (sel == null) {
        return const Text('Sin selección', maxLines: 1, overflow: TextOverflow.ellipsis);
      }
      final projId = sel.idProyecto;
      if (projId == null || projId.isEmpty) {
        return const Text('Rol global', maxLines: 1, overflow: TextOverflow.ellipsis);
      }
      return FutureBuilder<Proyecto?>(
        future: fs.getProyectoPorId(projId),
        builder: (context, snap) {
          final nombreProy = (snap.data?.nombre ?? 'Proyecto $projId');
          return Text('Proyecto · $nombreProy', maxLines: 1, overflow: TextOverflow.ellipsis);
        },
      );
    }

    // ---- Menú
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header simple con info del usuario (sin chips)
            UserAccountsDrawerHeader(
              accountName: Text(nombre.isNotEmpty ? nombre : 'Usuario'),
              accountEmail: Text(correo.isNotEmpty ? correo : '—'),
              currentAccountPicture: CircleAvatar(
                child: Text(
                  (nombre.isNotEmpty ? nombre[0] : 'U').toUpperCase(),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
            ),

            // Selección de rol/proyecto (lógica anterior)
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Seleccionar rol/proyecto'),
              subtitle: _subtitleSeleccion(),
              trailing: const Text('Cambiar', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => _go(context, '/seleccion'),
            ),

            const Divider(height: 1),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Mi perfil
                  ListTile(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: const Text('Mi perfil'),
                    onTap: () => _go(context, '/perfil'),
                  ),

                  // Panel admin (si aplica)
                  if (auth.isAdmin)
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_rounded),
                      title: const Text('Panel de administración'),
                      onTap: () => _go(context, '/admin/dashboard'),
                    ),
                ],
              ),
            ),

            const Divider(height: 1),

            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Cerrar sesión'),
              onTap: () => _logout(context),
            ),
          ],
        ),
      ),
    );
  }
}
