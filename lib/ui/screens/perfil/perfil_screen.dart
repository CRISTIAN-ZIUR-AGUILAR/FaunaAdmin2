// lib/ui/screens/perfil/perfil_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:faunadmin2/providers/auth_provider.dart';

class PerfilScreen extends StatelessWidget {
  const PerfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final u = auth.usuario;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        actions: [
          IconButton(
            tooltip: 'Ir a Selección de Rol/Proyecto',
            icon: const Icon(Icons.swap_horiz_rounded),
            onPressed: () {
              Navigator.of(context).pushReplacementNamed('/seleccion');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ==== Encabezado con avatar y nombre ====
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  child: Text(
                    (u?.nombreCompleto ?? 'U')
                        .substring(0, 1)
                        .toUpperCase(),
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  u?.nombreCompleto ?? '—',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(
                  u?.correo ?? '—',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(.7),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Divider(),

          // ==== Datos de cuenta ====
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Datos de cuenta',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Nombre'),
                  subtitle: Text(u?.nombreCompleto ?? '—'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Correo electrónico'),
                  subtitle: Text(u?.correo ?? '—'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ==== Espacio para futuros datos ====
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Información adicional',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Card(
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.school_outlined),
                  title: Text('Formación'),
                  subtitle: Text('Próximamente'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.workspace_premium_outlined),
                  title: Text('Nivel académico'),
                  subtitle: Text('Próximamente'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // ==== Botón para regresar a selección ====
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () {
              Navigator.of(context).pushReplacementNamed('/seleccion');
            },
            icon: const Icon(Icons.swap_horiz_rounded),
            label: const Text('Cambiar rol/proyecto'),
          ),
        ],
      ),
    );
  }
}

