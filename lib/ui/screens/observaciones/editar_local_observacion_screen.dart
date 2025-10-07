import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:faunadmin2/services/local_file_storage.dart';

class EditarLocalObservacionScreen extends StatefulWidget {
  const EditarLocalObservacionScreen({super.key});

  @override
  State<EditarLocalObservacionScreen> createState() => _EditarLocalObservacionScreenState();
}

class _EditarLocalObservacionScreenState extends State<EditarLocalObservacionScreen> {
  final _form = GlobalKey<FormState>();
  final _local = LocalFileStorage.instance;

  late Directory _dir;
  Map<String, dynamic> _meta = {};
  bool _loading = true;

  // Campos editables comunes
  final _ctrlEspecie  = TextEditingController();
  final _ctrlLugar    = TextEditingController();
  final _ctrlLugarTipo= TextEditingController();
  final _ctrlNotas    = TextEditingController();

  @override
  void initState() {
    super.initState();
    // args: { 'dirPath': String, 'meta': Map } — como los mandamos desde la lista
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)!.settings.arguments as Map?;
      final dirPath = (args?['dirPath'] ?? '') as String;
      _dir = Directory(dirPath);

      final metaArg = (args?['meta'] as Map?)?.cast<String, dynamic>();
      _meta = metaArg ?? (await _local.leerMeta(_dir) ?? {});

      // Inicializa controles
      _ctrlEspecie.text   = (_meta['especie_nombre'] ?? '') as String;
      _ctrlLugar.text     = (_meta['lugar_nombre'] ?? '') as String;
      _ctrlLugarTipo.text = (_meta['lugar_tipo'] ?? '') as String;
      _ctrlNotas.text     = (_meta['notas'] ?? '') as String;

      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _ctrlEspecie.dispose();
    _ctrlLugar.dispose();
    _ctrlLugarTipo.dispose();
    _ctrlNotas.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;

    // Actualiza meta y persiste
    _meta['especie_nombre'] = _ctrlEspecie.text.trim();
    _meta['lugar_nombre']   = _ctrlLugar.text.trim();
    _meta['lugar_tipo']     = _ctrlLugarTipo.text.trim();
    _meta['notas']          = _ctrlNotas.text.trim();

    // Mantén/asegura banderas mínimas:
    _meta['status'] = (_meta['status'] ?? 'READY').toString().toUpperCase();
    _meta['updated_local_at'] = DateTime.now().toUtc().toIso8601String();

    final file = File('${_dir.path}/meta.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(_meta), flush: true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado local')));
    Navigator.pop(context, true); // indica a la lista que recargue si quieres
  }

  @override
  Widget build(BuildContext context) {
    final fotosFuture = _loading ? null : _local.listarFotos(_dir);

    return Scaffold(
      appBar: AppBar(title: const Text('Editar (local)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<File>>(
        future: fotosFuture,
        builder: (ctx, snap) {
          final fotos = snap.data ?? const <File>[];
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (fotos.isNotEmpty)
                  SizedBox(
                    height: 92,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: fotos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(fotos[i], width: 92, height: 92, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ctrlEspecie,
                  decoration: const InputDecoration(
                    labelText: 'Especie (nombre libre)',
                    prefixIcon: Icon(Icons.pets_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ctrlLugar,
                  decoration: const InputDecoration(
                    labelText: 'Lugar / Sitio',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ctrlLugarTipo,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de lugar (p. ej. “bosque”, “matorral”)',
                    prefixIcon: Icon(Icons.park_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ctrlNotas,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notas',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _guardar,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar en teléfono'),
                ),
                const SizedBox(height: 8),
                Text(
                  'ID local: ${_meta['id_local'] ?? '—'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
