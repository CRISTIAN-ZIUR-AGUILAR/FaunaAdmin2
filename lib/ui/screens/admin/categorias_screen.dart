// lib/ui/screens/admin/categorias_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import 'package:faunadmin2/models/categoria.dart';
import 'package:faunadmin2/services/firestore_service.dart';

class CategoriasScreen extends StatefulWidget {
  const CategoriasScreen({super.key});
  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  final _fs = FirestoreService();

  // --- Navegación segura al Dashboard Admin ---
  void _goBack() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.maybePop();
    } else {
      nav.pushReplacementNamed('/admin/dashboard');
    }
  }

  Future<void> _seed() async {
    try {
      await _fs.seedCategoriasBasicas();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catálogo base sembrado (o ya existía)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al sembrar: $e')),
      );
    }
  }

  Future<void> _crearCategoria() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Crear')),
        ],
      ),
    );
    if (ok == true) {
      final nombre = ctrl.text.trim();
      if (nombre.isEmpty) return;
      try {
        await _fs.createCategoriaGlobalNombre(nombre: nombre);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Categoría "$nombre" creada')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _editarCategoria(Categoria c) async {
    final ctrl = TextEditingController(text: c.nombre);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Renombrar categoría'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) {
      final nuevo = ctrl.text.trim();
      if (nuevo.isEmpty || nuevo == c.nombre) return;
      try {
        await _fs.updateCategoriaGlobalNombre(id: c.id, nombre: nuevo);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cambios guardados')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _eliminarCategoria(Categoria c) async {
    if (c.isProtected == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta categoría está protegida y no puede eliminarse.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Eliminar "${c.nombre}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _fs.deleteCategoriaGlobal(c.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Categoría eliminada')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          title: const Text('Categorías'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBack,
          ),
          actions: [
            IconButton(
              tooltip: 'Sembrar básicas',
              icon: const Icon(Icons.cloud_download_outlined),
              onPressed: _seed,
            ),
            IconButton(
              tooltip: 'Nueva categoría',
              icon: const Icon(Icons.add),
              onPressed: _crearCategoria,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _crearCategoria,
          icon: const Icon(Icons.add),
          label: const Text('Nueva'),
        ),
        body: Column(
          children: [
            _InlineHeader(
              title: headerTitle,
              subtitle: headerSubtitle,
              contextText: 'Catálogo global',
            ),
            Expanded(
              child: StreamBuilder<List<Categoria>>(
                stream: _fs.streamCategoriasGlobales(),
                builder: (context, snap) {
                  if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                  final cats = [...snap.data!]..sort((a, b) => a.id.compareTo(b.id));
                  if (cats.isEmpty) return _Empty(onSeed: _seed);

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: cats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = cats[i];
                      final prot = c.isProtected == true;
                      final subtitle = <String>[
                        if ((c.clave).isNotEmpty) 'Clave: ${c.clave}',
                        if (prot) 'Protegida',
                      ].join(' · ');

                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${c.id}')),
                          title: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: subtitle.isEmpty ? null : Text(subtitle),
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              IconButton(
                                tooltip: 'Renombrar',
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editarCategoria(c),
                              ),
                              IconButton(
                                tooltip: prot ? 'No permitido' : 'Eliminar',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: prot ? null : () => _eliminarCategoria(c),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------- Header inline privado ---------

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

// --------- Empty state ---------

class _Empty extends StatelessWidget {
  final VoidCallback onSeed;
  const _Empty({required this.onSeed});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.label_outline, size: 52, color: cs.primary),
            const SizedBox(height: 12),
            const Text('No hay categorías aún.', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Crea una nueva o siembra el catálogo básico.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onSeed,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Sembrar básicas'),
            ),
          ],
        ),
      ),
    );
  }
}

