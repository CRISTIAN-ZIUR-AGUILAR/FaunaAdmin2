// lib/ui/screens/proyectos/editar_proyecto_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:faunadmin2/models/proyecto.dart';
import 'package:faunadmin2/models/categoria.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/services/firestore_service.dart';
import 'package:faunadmin2/services/permisos_service.dart';

class EditarProyectoScreen extends StatefulWidget {
  final String proyectoId;
  const EditarProyectoScreen({super.key, required this.proyectoId});

  @override
  State<EditarProyectoScreen> createState() => _EditarProyectoScreenState();
}

class _EditarProyectoScreenState extends State<EditarProyectoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  final _fs = FirestoreService();

  int? _idCategoriaSel;
  String? _categoriaNombreSel;
  bool _activo = true;
  bool _saving = false;

  bool _inited = false; // para inicializar controles una sola vez

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar(Proyecto original) async {
    if (!_formKey.currentState!.validate()) return;

    if (_idCategoriaSel == null ||
        (_categoriaNombreSel == null || _categoriaNombreSel!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una categoría')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final actualizado = original.copyWith(
        nombre: _nombreCtrl.text.trim(),
        descripcion: _descCtrl.text.trim(),
        idCategoria: _idCategoriaSel,
        categoriaNombre: _categoriaNombreSel,
        activo: _activo,
        // uidDueno se preserva porque no lo cambiamos aquí
      );

      await _fs.updateProyecto(actualizado);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proyecto actualizado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permisos = PermisosService(auth);

    // Gate adicional por si alguien navega directo
    if (!permisos.canEditProject) {
      return const Scaffold(
        body: Center(child: Text('No tienes permiso para editar este proyecto')),
      );
    }

    return StreamBuilder<Proyecto?>(
      stream: _fs.streamProyectoById(widget.proyectoId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('Error: ${snap.error}')),
          );
        }
        if (!snap.hasData || snap.data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final p = snap.data!;

        // Inicializar campos solo la primera vez
        if (!_inited) {
          _nombreCtrl.text = p.nombre;
          _descCtrl.text = p.descripcion;
          _idCategoriaSel = p.idCategoria;
          _categoriaNombreSel = p.categoriaNombre;
          _activo = p.activo != false;
          _inited = true;
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Editar Proyecto')),
          body: AbsorbPointer(
            absorbing: _saving,
            child: Opacity(
              opacity: _saving ? 0.7 : 1,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration:
                      const InputDecoration(labelText: 'Descripción'),
                    ),
                    const SizedBox(height: 12),

                    // Categoría global (usa nombre denormalizado)
                    StreamBuilder<List<Categoria>>(
                      stream: _fs.streamCategoriasGlobales(),
                      builder: (context, snapCat) {
                        if (snapCat.hasError) {
                          return const Text('Error al cargar categorías');
                        }
                        if (!snapCat.hasData) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        final categorias = snapCat.data!;
                        if (categorias.isEmpty) {
                          return const Text(
                            'No hay categorías globales. Crea una en Admin → Categorías.',
                          );
                        }
                        // Asegura que el nombre se sincronice al cambiar
                        return DropdownButtonFormField<int>(
                          value: _idCategoriaSel,
                          decoration:
                          const InputDecoration(labelText: 'Categoría'),
                          items: categorias
                              .map((c) => DropdownMenuItem<int>(
                            value: c.id,
                            child: Text(c.nombre),
                          ))
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _idCategoriaSel = v;
                              final c =
                              categorias.firstWhere((e) => e.id == v);
                              _categoriaNombreSel = c.nombre;
                            });
                          },
                          validator: (v) =>
                          v == null ? 'Selecciona una categoría' : null,
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    SwitchListTile(
                      value: _activo,
                      onChanged: (v) => setState(() => _activo = v),
                      title: const Text('Proyecto activo'),
                      subtitle: const Text(
                          'Si lo desactivas, no aparecerá en listados activos'),
                    ),

                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : () => _guardar(p),
                      icon: _saving
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.save_rounded),
                      label: const Text('Guardar cambios'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
