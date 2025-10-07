// lib/ui/screens/proyectos/agregar_proyecto_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:faunadmin2/models/categoria.dart';
import 'package:faunadmin2/models/proyecto.dart';
import 'package:faunadmin2/models/rol.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/services/firestore_service.dart';
import 'package:faunadmin2/services/permisos_service.dart'; // 👈 NUEVO

class AgregarProyectoScreen extends StatefulWidget {
  const AgregarProyectoScreen({super.key});
  @override
  State<AgregarProyectoScreen> createState() => _AgregarProyectoScreenState();
}

class _AgregarProyectoScreenState extends State<AgregarProyectoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  int? _idCategoriaSel;
  String? _categoriaNombreSel;
  bool _saving = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// ¿Tiene el rol global indicado? (id_proyecto == null)
  bool _hasGlobalRole(AuthProvider auth, int idRol) {
    return auth.rolesProyectos.any(
          (r) => r.idRol == idRol && r.idProyecto == null,
    );
  }

  /// ✅ Puede crear: Admin único **o** Dueño de Proyecto (global)
  bool _puedeCrear(AuthProvider auth) {
    final permisos = PermisosService(auth);
    return permisos.isAdminGlobal || _hasGlobalRole(auth, Rol.duenoProyecto);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    if (_idCategoriaSel == null ||
        (_categoriaNombreSel == null || _categoriaNombreSel!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una categoría')),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    if (!_puedeCrear(auth)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes permiso para crear proyectos (requiere Admin único o rol global Dueño de Proyecto).')),
      );
      return;
    }

    final uid = auth.usuario?.uid; // 👈 usar 'usuario' para ser consistente
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo identificar al usuario actual')),
      );
      return;
    }

    setState(() => _saving = true);
    final fs = FirestoreService();

    try {
      final nuevo = Proyecto(
        id: null, // se asignará en Firestore
        nombre: _nombreCtrl.text.trim(),
        descripcion: _descCtrl.text.trim(),
        idCategoria: _idCategoriaSel,
        categoriaNombre: _categoriaNombreSel, // denormalizado
        uidDueno: uid, // 👈 aseguramos dueño en el modelo
      );

      // Guarda garantizando uid_dueno
      final nuevoId = await fs.createProyecto(nuevo, uidDueno: uid);

      if (!mounted) return;
      // 👇 devolver el ID al caller (útil para abrirlo directo)
      Navigator.pop(context, nuevoId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Proyecto creado (ID: $nuevoId)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();
    final auth = context.watch<AuthProvider>();
    final puedeCrear = _puedeCrear(auth);

    return Scaffold(
      appBar: AppBar(title: const Text('Agregar Proyecto')),
      body: AbsorbPointer(
        absorbing: _saving || !puedeCrear,
        child: Opacity(
          opacity: _saving ? 0.7 : 1,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!puedeCrear) ...[
                  const Card(
                    margin: EdgeInsets.only(bottom: 16),
                    child: ListTile(
                      leading: Icon(Icons.lock_outline),
                      title: Text('No puedes crear proyectos'),
                      subtitle: Text('Solicita al administrador el rol global "Dueño de Proyecto" o usa una cuenta de Administrador.'),
                    ),
                  ),
                ],
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 12),

                // Categoría (global, mostrando NOMBRE)
                StreamBuilder<List<Categoria>>(
                  stream: fs.streamCategoriasGlobales(),
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
                        'No hay categorías globales. Crea una en Admin → Categorías (pestaña Globales).',
                      );
                    }

                    return DropdownButtonFormField<int>(
                      value: _idCategoriaSel,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      items: categorias
                          .map((c) => DropdownMenuItem<int>(
                        value: c.id,
                        child: Text(c.nombre),
                      ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _idCategoriaSel = v;
                          final c = categorias.firstWhere((e) => e.id == v);
                          _categoriaNombreSel = c.nombre;
                        });
                      },
                      validator: (v) => v == null ? 'Selecciona una categoría' : null,
                    );
                  },
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: (_saving || !puedeCrear) ? null : _guardar,
                  icon: _saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
