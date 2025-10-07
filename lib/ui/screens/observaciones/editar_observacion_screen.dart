// lib/ui/screens/observaciones/editar_observacion_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/providers/observacion_provider.dart';
import 'package:faunadmin2/services/local_file_storage.dart';
import 'package:faunadmin2/services/sync_observaciones_service.dart';
import 'package:faunadmin2/services/permisos_service.dart';

class EditarObservacionScreen extends StatefulWidget {
  const EditarObservacionScreen({super.key});

  @override
  State<EditarObservacionScreen> createState() => _EditarObservacionScreenState();
}

class _EditarObservacionScreenState extends State<EditarObservacionScreen> {
  // --- argumentos ---
  late String _mode; // 'local' | 'cloud'
  String? _idLocal;  // si mode=local (formato previo)
  String? _obsId;    // si mode=cloud
  bool _forceReadonly = false;

  // --- local/cloud state ---
  Directory? _carpetaLocal;        // carpeta local si mode=local
  Map<String, dynamic>? _meta;     // cache meta.json si mode=local
  Observacion? _obs;               // doc online si mode=cloud

  bool _loading = true;
  bool _saving  = false;

  // form controllers (comparten para local/cloud)
  final _fechaCtrl        = TextEditingController();
  final _especieCtrl      = TextEditingController();
  final _lugarNombreCtrl  = TextEditingController();
  final _lugarTipoCtrl    = TextEditingController();
  final _municipioCtrl    = TextEditingController();
  final _estadoPaisCtrl   = TextEditingController();
  final _latCtrl          = TextEditingController();
  final _lngCtrl          = TextEditingController();
  final _altCtrl          = TextEditingController();
  final _notasCtrl        = TextEditingController();

  String _condicion = EstadosAnimal.vivo;
  String? _rastroTipo;
  final _rastroDetalleCtrl = TextEditingController();

  List<String> _fotosLocales = const []; // nombres dentro de la carpeta

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _fechaCtrl.dispose();
    _especieCtrl.dispose();
    _lugarNombreCtrl.dispose();
    _lugarTipoCtrl.dispose();
    _municipioCtrl.dispose();
    _estadoPaisCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _altCtrl.dispose();
    _notasCtrl.dispose();
    _rastroDetalleCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};

    _mode    = (args['mode'] ?? 'local') as String;
    _obsId   = args['obsId'] as String?;
    _idLocal = args['idLocal'] as String?;

    // Compat locales: '/observaciones/editLocal' -> { 'dirPath': String, 'meta': Map }
    final dirPath    = args['dirPath'] as String?;
    final passedMeta = args['meta'] as Map?;

    // Respeta 'readonly' si viene
    _forceReadonly = (args['readonly'] == true);

    try {
      if (_mode == 'local') {
        await _loadLocalCompat(dirPath: dirPath, passedMeta: passedMeta);
      } else {
        await _loadCloudSafe();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Carga LOCAL compatible con:
  /// a) idLocal (formato antiguo)
  /// b) dirPath + meta (formato actual que manda la lista)
  Future<void> _loadLocalCompat({String? dirPath, Map? passedMeta}) async {
    final local = LocalFileStorage.instance;

    Directory? carpeta;
    Map<String, dynamic> meta;

    if (dirPath != null) {
      carpeta = Directory(dirPath);
      if (passedMeta != null) {
        meta = passedMeta.map((k, v) => MapEntry(k.toString(), v));
      } else {
        meta = await local.leerMeta(carpeta) ?? <String, dynamic>{};
      }
    } else {
      if (_idLocal == null) {
        throw StateError('Faltan argumentos de local: idLocal o dirPath');
      }
      carpeta = await local.findByLocalId(_idLocal!);
      if (carpeta == null) {
        throw StateError('No se encontró la carpeta local');
      }
      meta = await local.leerMeta(carpeta) ?? <String, dynamic>{};
    }

    _carpetaLocal = carpeta;
    _meta = meta;

    // hidrata campos
    final dt = _parseDate(meta['fecha_captura']);
    _fechaCtrl.text       = (dt != null) ? _fmtDate(dt) : '';
    _especieCtrl.text     = (meta['especie_nombre'] ?? '').toString();
    _lugarNombreCtrl.text = (meta['lugar_nombre'] ?? '').toString();
    _lugarTipoCtrl.text   = (meta['lugar_tipo'] ?? '').toString();
    _municipioCtrl.text   = (meta['municipio'] ?? '').toString();
    _estadoPaisCtrl.text  = (meta['estado_pais'] ?? '').toString();
    _latCtrl.text         = (meta['lat']?.toString() ?? '');
    _lngCtrl.text         = (meta['lng']?.toString() ?? '');
    _altCtrl.text         = (meta['altitud']?.toString() ?? '');
    _notasCtrl.text       = (meta['notas'] ?? '').toString();

    _condicion              = (meta['condicion_animal'] ?? EstadosAnimal.vivo) as String;
    _rastroTipo             = meta['rastro_tipo'] as String?;
    _rastroDetalleCtrl.text = (meta['rastro_detalle'] ?? '').toString();

    _fotosLocales = (meta['fotos'] is List) ? List<String>.from(meta['fotos']) : <String>[];
  }

  /// Carga CLOUD sin casts inválidos y con fallback a fetch puntual si no está en memoria.
  Future<void> _loadCloudSafe() async {
    if (_obsId == null) throw StateError('Falta obsId');

    final prov = context.read<ObservacionProvider>();

    // 1) Buscar en memoria de forma segura
    Observacion? found;
    try {
      found = prov.observaciones.firstWhere((o) => o.id == _obsId);
    } catch (_) {
      found = null;
    }

    // 2) Si no está en memoria, intentamos método del provider (si existe)
    if (found == null) {
      try {
        final maybe = await (prov as dynamic).getById(_obsId!);
        if (maybe is Observacion) found = maybe;
      } catch (_) {/* noop */}
    }

    // 3) Como última opción, fetch directo con Firestore y mapear manualmente
    if (found == null) {
      final doc = await FirebaseFirestore.instance
          .collection('observaciones')
          .doc(_obsId!)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;

        found = Observacion(
          id: doc.id,
          fechaCaptura: _toDate(data['fecha_captura']),
          especieNombre: data['especie_nombre'] as String?,
          lugarNombre: data['lugar_nombre'] as String?,
          lugarTipo: data['lugar_tipo'] as String?,
          municipio: data['municipio'] as String?,
          estadoPais: data['estado_pais'] as String?,
          lat: (data['lat'] as num?)?.toDouble(),
          lng: (data['lng'] as num?)?.toDouble(),
          altitud: (data['altitud'] as num?)?.toDouble(),
          notas: data['notas'] as String?,
          condicionAnimal: data['condicion_animal'] as String?,
          rastroTipo: data['rastro_tipo'] as String?,
          rastroDetalle: data['rastro_detalle'] as String?,

          // 🔧 estos suelen ser no-nullable en tu modelo; da fallback si vienen null
          uidUsuario: (data['uid_usuario'] as String?) ?? '',
          estado: (data['estado'] as String?) ?? EstadosObs.borrador,
          idProyecto: (data['id_proyecto'] as String?) ?? '',
        );
      } else {
        throw StateError('Observación no está disponible.');
      }
    }

    _obs = found;

    // hidrata
    final o = _obs!;
    _fechaCtrl.text       = (o.fechaCaptura != null) ? _fmtDate(o.fechaCaptura!) : '';
    _especieCtrl.text     = o.especieNombre ?? '';
    _lugarNombreCtrl.text = o.lugarNombre ?? '';
    _lugarTipoCtrl.text   = o.lugarTipo ?? '';
    _municipioCtrl.text   = o.municipio ?? '';
    _estadoPaisCtrl.text  = o.estadoPais ?? '';
    _latCtrl.text         = (o.lat?.toString() ?? '');
    _lngCtrl.text         = (o.lng?.toString() ?? '');
    _altCtrl.text         = (o.altitud?.toString() ?? '');
    _notasCtrl.text       = o.notas ?? '';
    _condicion            = o.condicionAnimal ?? EstadosAnimal.vivo;
    _rastroTipo           = o.rastroTipo;
    _rastroDetalleCtrl.text = o.rastroDetalle ?? '';
  }

  // -------------- UI --------------
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permisos = PermisosService(auth);

    final isLocal = _mode == 'local';
    final isEditableCloud = _isCloudEditable(permisos);

    return Scaffold(
      appBar: AppBar(
        title: Text(isLocal ? 'Editar borrador (teléfono)' : 'Editar observación'),
        actions: [
          if (!isLocal && isEditableCloud)
            IconButton(
              onPressed: _saving ? null : _guardarCloud,
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Guardar en nube',
            ),
          if (isLocal)
            IconButton(
              onPressed: _saving ? null : _guardarLocal,
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Guardar en teléfono',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildForm(isLocal: isLocal, isEditableCloud: isEditableCloud),
      bottomNavigationBar: isLocal
          ? SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _syncNow,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Sincronizar ahora'),
                ),
              ),
            ],
          ),
        ),
      )
          : null,
    );
  }

  Widget _buildForm({required bool isLocal, required bool isEditableCloud}) {
    final canEdit = isLocal || isEditableCloud;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _sectionTitle('Especie'),
        TextField(
          controller: _especieCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre (libre)',
            hintText: 'p. ej., Odocoileus virginianus',
            border: OutlineInputBorder(),
          ),
          enabled: canEdit,
        ),
        const SizedBox(height: 12),

        _sectionTitle('Fecha de captura'),
        _FechaField(
          controller: _fechaCtrl,
          enabled: canEdit,
          onPick: canEdit ? _pickDate : null,
        ),
        const SizedBox(height: 12),

        _sectionTitle('Lugar'),
        TextField(
          controller: _lugarNombreCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre del lugar',
            border: OutlineInputBorder(),
          ),
          enabled: canEdit,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _lugarTipoCtrl,
          decoration: const InputDecoration(
            labelText: 'Tipo de lugar (rancho, reserva, etc.)',
            border: OutlineInputBorder(),
          ),
          enabled: canEdit,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _municipioCtrl,
                decoration: const InputDecoration(
                  labelText: 'Municipio',
                  border: OutlineInputBorder(),
                ),
                enabled: canEdit,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _estadoPaisCtrl,
                decoration: const InputDecoration(
                  labelText: 'Estado / País',
                  border: OutlineInputBorder(),
                ),
                enabled: canEdit,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _latCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Lat',
                  border: OutlineInputBorder(),
                ),
                enabled: canEdit,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _lngCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Lng',
                  border: OutlineInputBorder(),
                ),
                enabled: canEdit,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _altCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Altitud (m)',
                  border: OutlineInputBorder(),
                ),
                enabled: canEdit,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _sectionTitle('Condición del animal'),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Vivo'),
              selected: _condicion == EstadosAnimal.vivo,
              onSelected: canEdit ? (_) => setState(() => _condicion = EstadosAnimal.vivo) : null,
            ),
            ChoiceChip(
              label: const Text('Muerto'),
              selected: _condicion == EstadosAnimal.muerto,
              onSelected: canEdit ? (_) => setState(() => _condicion = EstadosAnimal.muerto) : null,
            ),
            ChoiceChip(
              label: const Text('Rastro'),
              selected: _condicion == EstadosAnimal.rastro,
              onSelected: canEdit ? (_) => setState(() => _condicion = EstadosAnimal.rastro) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_condicion == EstadosAnimal.rastro) ...[
          DropdownButtonFormField<String>(
            value: _rastroTipo,
            items: const [
              DropdownMenuItem(value: TiposRastro.huellas, child: Text('Huellas')),
              DropdownMenuItem(value: TiposRastro.huesosParciales, child: Text('Huesos parciales')),
              DropdownMenuItem(value: TiposRastro.huesosCompletos, child: Text('Huesos completos')),
              DropdownMenuItem(value: TiposRastro.plumas, child: Text('Plumas')),
              DropdownMenuItem(value: TiposRastro.excretas, child: Text('Excretas')),
              DropdownMenuItem(value: TiposRastro.nido, child: Text('Nido')),
              DropdownMenuItem(value: TiposRastro.madriguera, child: Text('Madriguera')),
              DropdownMenuItem(value: TiposRastro.otros, child: Text('Otros')),
            ],
            onChanged: canEdit ? (v) => setState(() => _rastroTipo = v) : null,
            decoration: const InputDecoration(
              labelText: 'Tipo de rastro',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _rastroDetalleCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Detalle del rastro',
              border: OutlineInputBorder(),
            ),
            enabled: canEdit,
          ),
          const SizedBox(height: 12),
        ],

        _sectionTitle('Notas'),
        TextField(
          controller: _notasCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Observaciones adicionales…',
            border: OutlineInputBorder(),
          ),
          enabled: canEdit,
        ),
        const SizedBox(height: 16),

        if (_mode == 'local') _sectionTitle('Fotos (local)'),
        if (_mode == 'local') _fotosLocalGrid(canEdit: canEdit),
        const SizedBox(height: 40),

        if (_mode == 'local')
          FilledButton.icon(
            onPressed: _saving ? null : _guardarLocal,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar en teléfono'),
          ),
        if (_mode == 'cloud' && isEditableCloud)
          FilledButton.icon(
            onPressed: _saving ? null : _guardarCloud,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Guardar en nube'),
          ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _fotosLocalGrid({required bool canEdit}) {
    if (_carpetaLocal == null) return const SizedBox.shrink();
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _fotosLocales.length + (canEdit ? 1 : 0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6,
          ),
          itemBuilder: (_, i) {
            if (canEdit && i == 0) {
              return _AddPhotoTile(onAdd: _agregarFotoLocal);
            }
            final idx = canEdit ? i - 1 : i;
            final name = _fotosLocales[idx];
            final f = File('${_carpetaLocal!.path}/$name');
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.file(f, fit: BoxFit.cover),
                if (canEdit)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: () => _eliminarFotoLocal(name),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black54, borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  // -------------- acciones --------------
  Future<void> _guardarLocal() async {
    if (_carpetaLocal == null) return;
    setState(() => _saving = true);
    try {
      final local = LocalFileStorage.instance;

      DateTime? fecha = _parseDate(_fechaCtrl.text.trim());
      final lat = double.tryParse(_latCtrl.text.trim());
      final lng = double.tryParse(_lngCtrl.text.trim());
      final alt = double.tryParse(_altCtrl.text.trim());

      await local.patchMeta(_carpetaLocal!, {
        'fecha_captura': fecha?.toIso8601String(),
        'especie_nombre': _especieCtrl.text.trim(),
        'lugar_nombre': _lugarNombreCtrl.text.trim(),
        'lugar_tipo': _lugarTipoCtrl.text.trim(),
        'municipio': _municipioCtrl.text.trim(),
        'estado_pais': _estadoPaisCtrl.text.trim(),
        'lat': lat,
        'lng': lng,
        'altitud': alt,
        'notas': _notasCtrl.text.trim(),
        'condicion_animal': _condicion,
        'rastro_tipo': _condicion == EstadosAnimal.rastro ? _rastroTipo : null,
        'rastro_detalle': _condicion == EstadosAnimal.rastro ? _rastroDetalleCtrl.text.trim() : null,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cambios guardados en el teléfono')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _guardarCloud() async {
    if (_obs == null) return;
    setState(() => _saving = true);
    try {
      final prov = context.read<ObservacionProvider>();

      DateTime? fecha = _parseDate(_fechaCtrl.text.trim());
      final lat = double.tryParse(_latCtrl.text.trim());
      final lng = double.tryParse(_lngCtrl.text.trim());
      final alt = double.tryParse(_altCtrl.text.trim());

      final patch = {
        'fecha_captura': fecha,
        'especie_nombre': _especieCtrl.text.trim(),
        'lugar_nombre': _lugarNombreCtrl.text.trim(),
        'lugar_tipo': _lugarTipoCtrl.text.trim(),
        'municipio': _municipioCtrl.text.trim(),
        'estado_pais': _estadoPaisCtrl.text.trim(),
        'lat': lat,
        'lng': lng,
        'altitud': alt,
        'notas': _notasCtrl.text.trim(),
        'condicion_animal': _condicion,
        'rastro_tipo': _condicion == EstadosAnimal.rastro ? _rastroTipo : null,
        'rastro_detalle': _condicion == EstadosAnimal.rastro ? _rastroDetalleCtrl.text.trim() : null,
      };

      final ok = await prov.patch(observacionId: _obs!.id!, patch: patch);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cambios guardados en la nube')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _saving = true);
    try {
      final svc = SyncObservacionesService();
      await svc.syncPending(
        context: context,
        deleteLocalAfterUpload: true,
        onLog: (m) => debugPrint('[SYNC] $m'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sincronización lanzada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al sincronizar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _agregarFotoLocal() async {
    // Hook: aquí usa tu image picker y obtén un File (nuevaFoto)
    // await LocalFileStorage.instance.addLocalPhoto(_carpetaLocal!, nuevaFoto);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Implementa el picker y llama addLocalPhoto(...)')),
    );
  }

  Future<void> _eliminarFotoLocal(String fileName) async {
    if (_carpetaLocal == null) return;
    await LocalFileStorage.instance.removeLocalPhoto(_carpetaLocal!, fileName);
    // recarga meta + fotos
    final meta = await LocalFileStorage.instance.leerMeta(_carpetaLocal!);
    setState(() {
      _meta = meta;
      _fotosLocales = (meta?['fotos'] is List) ? List<String>.from(meta!['fotos']) : <String>[];
    });
  }

  // -------------- helpers --------------
  String _fmtDate(DateTime d) {
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${t(d.month)}-${t(d.day)}';
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) {
      try {
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
          final p = v.split('-').map(int.parse).toList();
          return DateTime(p[0], p[1], p[2]);
        }
        return DateTime.tryParse(v);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Convierte Timestamp/String/DateTime a DateTime (para Firestore).
  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  bool _isCloudEditable(PermisosService permisos) {
    if (_forceReadonly) return false;
    if (_obs == null) return false;

    final o = _obs!;
    final uid = context.read<AuthProvider>().uid;

    // Editable si soy autor y estado en {borrador, rechazado}
    final soyAutor = (o.uidUsuario == uid);
    final editableByAuthor = soyAutor &&
        (o.estado == EstadosObs.borrador || o.estado == EstadosObs.rechazado);

    // Admin siempre puede parchar (si tu backend revalida)
    final admin = context.read<AuthProvider>().isAdmin || permisos.isAdminUnico;

    return editableByAuthor || admin;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _parseDate(_fechaCtrl.text) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (d != null) {
      _fechaCtrl.text = _fmtDate(d);
      setState(() {});
    }
  }
}

class _FechaField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback? onPick;
  const _FechaField({
    required this.controller,
    required this.enabled,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: 'Fecha (YYYY-MM-DD)',
        suffixIcon: IconButton(
          onPressed: enabled ? onPick : null,
          icon: const Icon(Icons.event_outlined),
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  final VoidCallback onAdd;
  const _AddPhotoTile({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAdd,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(Icons.add_a_photo_outlined),
        ),
      ),
    );
  }
}
