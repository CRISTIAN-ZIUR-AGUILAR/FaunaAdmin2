// lib/ui/screens/observaciones/editar_observacion_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/providers/observacion_provider.dart';
import 'package:faunadmin2/services/permisos_service.dart';
import 'package:faunadmin2/services/foto_service.dart';

// Widget de advertencia para observaciones rechazadas
import 'package:faunadmin2/ui/widgets/observacion_rechazo_warning.dart';

class EditarObservacionScreen extends StatefulWidget {
  const EditarObservacionScreen({super.key});

  @override
  State<EditarObservacionScreen> createState() =>
      _EditarObservacionScreenState();
}

class _EditarObservacionScreenState extends State<EditarObservacionScreen> {
  // --- args (solo cloud) ---
  String? _obsId;
  bool _forceReadonly = false;

  // --- estado cloud ---
  Observacion? _obs;

  bool _loading = true;
  bool _saving = false;

  // --- límite de fotos (igual que en agregar) ---
  static const int _maxFotos = 4;

  // --- fotos: preferimos media_* y resolvemos a HTTPS
  final FotoService _fotoSvc = FotoService();
  List<String> _fotoUrls = <String>[]; // URLs https (o resueltas)
  List<String> _fotoPaths = <String>[]; // storage paths paralelos
  // (Compat) si tienes lógica que usa _fotos en otros widgets, lo mantenemos en sync
  List<String> _fotos = <String>[];

  // form controllers
  final _fechaCtrl = TextEditingController();
  final _especieCtrl = TextEditingController(); // nombre científico (libre)
  final _lugarNombreCtrl = TextEditingController();
  final _lugarTipoCtrl = TextEditingController();
  final _municipioCtrl = TextEditingController();
  final _estadoPaisCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _altCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();

  String _condicion = EstadosAnimal.vivo;
  String? _rastroTipo;
  final _rastroDetalleCtrl = TextEditingController();

  // --- tracking de cambios / autoguarda ---
  Map<String, dynamic> _originalSnapshot = {};
  bool _dirty = false;
  Timer? _autosaveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _autosaveDebounce?.cancel();
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
    // Acepta String (obsId directo) o Map({'obsId': ...})
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is String && raw.trim().isNotEmpty) {
      _obsId = raw.trim();
    } else if (raw is Map) {
      _obsId = (raw['obsId'] ?? raw['id']) as String?;
      _forceReadonly = (raw['readonly'] == true);
    }

    if (_obsId == null || _obsId!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falta el ID de la observación.')),
        );
        Navigator.of(context).pop();
      }
      return;
    }

    try {
      await _loadCloudSafe();
      // snapshot base para comparar cambios
      _originalSnapshot = _currentSnapshot();
      _dirty = false;
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

  /// Carga CLOUD con fallback si no está en memoria.
  Future<void> _loadCloudSafe() async {
    final prov = context.read<ObservacionProvider>();

    // 1) Buscar en memoria
    Observacion? found;
    try {
      found = prov.observaciones.firstWhere((o) => o.id == _obsId);
    } catch (_) {
      found = null;
    }

    // 2) Intentar método del provider (si existe)
    if (found == null) {
      try {
        final maybe = await (prov as dynamic).getById(_obsId!);
        if (maybe is Observacion) found = maybe;
      } catch (_) {/* noop */}
    }

    // 3) Fetch directo desde Firestore
    Map<String, dynamic>? dataFromDoc;
    if (found == null) {
      final doc = await FirebaseFirestore.instance
          .collection('observaciones')
          .doc(_obsId!)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        dataFromDoc = data;
        found = Observacion(
          id: doc.id,
          fechaCaptura: _toDate(data['fecha_captura']),
          especieNombreCientifico:
          (data['especie_nombre_cientifico'] ?? data['especie_nombre'])
          as String?,
          especieNombreComun: data['especie_nombre_comun'] as String?,
          especieId: data['especie_id'] as String?,
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
          uidUsuario: (data['uid_usuario'] as String?) ?? '',
          estado: (data['estado'] as String?) ?? EstadosObs.borrador,
          idProyecto: data['id_proyecto'] as String?,
        );
      } else {
        throw StateError('Observación no encontrada.');
      }
    }

    _obs = found;

    // --- Hidratar controles
    final o = _obs!;
    _fechaCtrl.text =
    (o.fechaCaptura != null) ? _fmtDate(o.fechaCaptura!) : '';
    _especieCtrl.text = o.especieNombreCientifico ?? '';
    _lugarNombreCtrl.text = o.lugarNombre ?? '';
    _lugarTipoCtrl.text = o.lugarTipo ?? '';
    _municipioCtrl.text = o.municipio ?? '';
    _estadoPaisCtrl.text = o.estadoPais ?? '';
    _latCtrl.text = (o.lat?.toString() ?? '');
    _lngCtrl.text = (o.lng?.toString() ?? '');
    _altCtrl.text = (o.altitud?.toString() ?? '');
    _notasCtrl.text = o.notas ?? '';
    _condicion = o.condicionAnimal ?? EstadosAnimal.vivo;
    _rastroTipo = o.rastroTipo;
    _rastroDetalleCtrl.text = o.rastroDetalle ?? '';

    // --- Hidratar fotos preferentemente desde media_* (compat con 'fotos')
    Map<String, dynamic> data;
    if (dataFromDoc != null) {
      data = dataFromDoc;
    } else {
      final snap = await FirebaseFirestore.instance
          .collection('observaciones')
          .doc(_obsId!)
          .get();
      data = snap.data() ?? {};
    }

    final mediaUrls = (data['media_urls'] as List?)
        ?.map((e) => e.toString())
        .toList() ??
        <String>[];
    final mediaPaths = (data['media_storage_paths'] as List?)
        ?.map((e) => e.toString())
        .toList() ??
        <String>[];

    List<String> legacy = (data['fotos'] is List)
        ? (data['fotos'] as List).map((e) => e.toString()).toList()
        : <String>[];

    if (mediaUrls.isNotEmpty) {
      _fotoUrls = mediaUrls;
      _fotoPaths = mediaPaths;
    } else {
      _fotoUrls = legacy;
      _fotoPaths = List<String>.filled(_fotoUrls.length, '');
    }

    // Resolver a HTTPS cualquier gs:// o path
    final resolved = <String>[];
    for (final u in _fotoUrls) {
      try {
        resolved.add(await _fotoSvc.resolveHttpsFromAny(u));
      } catch (_) {
        resolved.add(u);
      }
    }
    _fotoUrls = resolved;
    _fotos = List<String>.from(_fotoUrls); // compat
  }

  // ---------- helpers de snapshot / cambios ----------
  Map<String, dynamic> _currentSnapshot() {
    return {
      'fecha': _fechaCtrl.text.trim(),
      'especie': _especieCtrl.text.trim(),
      'lugarNombre': _lugarNombreCtrl.text.trim(),
      'lugarTipo': _lugarTipoCtrl.text.trim(),
      'municipio': _municipioCtrl.text.trim(),
      'estadoPais': _estadoPaisCtrl.text.trim(),
      'lat': _latCtrl.text.trim(),
      'lng': _lngCtrl.text.trim(),
      'alt': _altCtrl.text.trim(),
      'notas': _notasCtrl.text.trim(),
      'condicion': _condicion,
      'rastroTipo': _rastroTipo,
      'rastroDetalle': _rastroDetalleCtrl.text.trim(),
      // fotos (solo para indicador; las altas/bajas ya escriben en cloud)
      'fotos': List<String>.from(_fotoUrls),
    };
  }

  bool _listEquals(List a, List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return false;
  }

  bool _hasLocalChanges() {
    final now = _currentSnapshot();
    if (now['fecha'] != _originalSnapshot['fecha']) return true;
    if (now['especie'] != _originalSnapshot['especie']) return true;
    if (now['lugarNombre'] != _originalSnapshot['lugarNombre']) return true;
    if (now['lugarTipo'] != _originalSnapshot['lugarTipo']) return true;
    if (now['municipio'] != _originalSnapshot['municipio']) return true;
    if (now['estadoPais'] != _originalSnapshot['estadoPais']) return true;
    if (now['lat'] != _originalSnapshot['lat']) return true;
    if (now['lng'] != _originalSnapshot['lng']) return true;
    if (now['alt'] != _originalSnapshot['alt']) return true;
    if (now['notas'] != _originalSnapshot['notas']) return true;
    if (now['condicion'] != _originalSnapshot['condicion']) return true;
    if (now['rastroTipo'] != _originalSnapshot['rastroTipo']) return true;
    if (now['rastroDetalle'] != _originalSnapshot['rastroDetalle']) return true;
    if (!_listEquals(
        now['fotos'] as List, _originalSnapshot['fotos'] as List? ?? const [])) {
      return true;
    }
    return false;
  }

  void _markDirtyAndMaybeAutosave() {
    _dirty = _hasLocalChanges();
    // solo autoguarda en rechazado
    if (_obs?.estado != EstadosObs.rechazado) return;
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(seconds: 3), () async {
      if (!_dirty || _saving) return;
      if (!_hasLocalChanges()) return;
      setState(() => _saving = true);
      try {
        await _guardarCloud(internalCall: true);
        _originalSnapshot = _currentSnapshot();
        _dirty = false;
      } catch (_) {
        // opcional: snack silencioso
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    });
  }

  // -------------- UI --------------
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permisos = PermisosService(auth);
    final isEditable = _isCloudEditable(permisos);
    final isRejected = _obs?.estado == EstadosObs.rechazado;
    final hasRechazoMessage = isRejected &&
        (_obs?.rejectionReason?.trim().isNotEmpty ?? false);

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Editar observación'),
        actions: [
          if (isEditable)
            IconButton(
              onPressed: _saving ? null : () => _guardarCloud(),
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: 'Guardar en nube',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          if (hasRechazoMessage)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ObservacionRechazoWarning(
                motivo: _obs!.rejectionReason!.trim(),
                reviewRound: _obs!.reviewRound,
                validatedAt: _obs!.validatedAt,
                validatedBy: _obs!.validatedBy,
              ),
            ),
          if (isRejected && _hasLocalChanges())
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Chip(
                  avatar: const Icon(Icons.info_outline, size: 18),
                  label: const Text(
                      'Cambios sin guardar (se guardan al subir)'),
                ),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth >= 900; // breakpoint web
                if (!isWide) {
                  // Móvil
                  return _buildForm(
                    isEditable: isEditable,
                    isRejected: isRejected,
                  );
                }

                // Web/desktop: cards responsivas
                final maxColWidth = 520.0;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                      const BoxConstraints(maxWidth: 1200),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _card(
                            title: 'Datos de especie y fecha',
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                _sectionTitle('Especie'),
                                _buildEspecie(isEditable),
                                const SizedBox(height: 12),
                                _sectionTitle('Fecha de captura'),
                                _buildFecha(isEditable),
                              ],
                            ),
                            width: maxColWidth,
                          ),
                          _card(
                            title: 'Lugar',
                            child: _buildLugar(isEditable),
                            width: maxColWidth,
                          ),
                          _card(
                            title: 'Condición y rastro',
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                _buildCondicion(isEditable),
                                const SizedBox(height: 12),
                                if (_condicion == EstadosAnimal.rastro)
                                  _buildRastro(isEditable),
                              ],
                            ),
                            width: maxColWidth,
                          ),
                          _card(
                            title: 'Notas',
                            child: _buildNotas(isEditable),
                            width: maxColWidth,
                          ),
                          _card(
                            title: 'Fotos',
                            child: _buildFotos(isEditable),
                            width: (c.maxWidth >= 1100)
                                ? maxColWidth * 2 + 16
                                : maxColWidth,
                          ),
                          if (isEditable)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                spacing: 12,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _saving
                                        ? null
                                        : () => _guardarCloud(),
                                    icon: const Icon(Icons
                                        .cloud_upload_outlined),
                                    label: const Text(
                                        'Guardar en nube y ver detalle'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    // Guarda al salir si está rechazado y hay cambios locales (solo persistir)
    return WillPopScope(
      onWillPop: () async {
        if (_obs?.estado == EstadosObs.rechazado &&
            _hasLocalChanges() &&
            !_saving) {
          try {
            setState(() => _saving = true);
            await _guardarCloud(internalCall: true);
            _originalSnapshot = _currentSnapshot();
            _dirty = false;
          } catch (_) {
            // ignoramos silenciosamente
          } finally {
            if (mounted) setState(() => _saving = false);
          }
        }
        return true;
      },
      child: scaffold,
    );
  }

  // -------- móvil (lista) --------
  Widget _buildForm({
    required bool isEditable,
    required bool isRejected,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _sectionTitle('Especie'),
        _buildEspecie(isEditable),
        const SizedBox(height: 12),

        _sectionTitle('Fecha de captura'),
        _buildFecha(isEditable),
        const SizedBox(height: 12),

        _sectionTitle('Lugar'),
        _buildLugar(isEditable),
        const SizedBox(height: 12),

        _sectionTitle('Condición del animal'),
        _buildCondicion(isEditable),
        const SizedBox(height: 8),

        if (_condicion == EstadosAnimal.rastro) ...[
          _buildRastro(isEditable),
          const SizedBox(height: 12),
        ],

        _sectionTitle('Notas'),
        _buildNotas(isEditable),
        const SizedBox(height: 16),

        _sectionTitle('Fotos'),
        _buildFotos(isEditable),
        const SizedBox(height: 24),

        if (isEditable)
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _guardarCloud(),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Guardar en nube y ver detalle'),
          ),
      ],
    );
  }

  // -------- piezas reutilizables (no tocan lógica de fotos) --------
  Widget _card({
    required String title,
    required Widget child,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 1.5,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEspecie(bool isEditable) => TextField(
    controller: _especieCtrl,
    decoration: const InputDecoration(
      labelText: 'Nombre científico (libre)',
      hintText: 'p. ej., Odocoileus virginianus',
      border: OutlineInputBorder(),
    ),
    enabled: isEditable,
    onChanged: (_) => _markDirtyAndMaybeAutosave(),
  );

  Widget _buildFecha(bool isEditable) => _FechaField(
    controller: _fechaCtrl,
    enabled: isEditable,
    onPick: isEditable
        ? () async {
      await _pickDate();
      _markDirtyAndMaybeAutosave();
    }
        : null,
  );

  Widget _buildLugar(bool isEditable) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _lugarNombreCtrl,
        decoration: const InputDecoration(
          labelText: 'Nombre del lugar',
          border: OutlineInputBorder(),
        ),
        enabled: isEditable,
        onChanged: (_) => _markDirtyAndMaybeAutosave(),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _lugarTipoCtrl,
        decoration: const InputDecoration(
          labelText: 'Tipo de lugar (rancho, reserva, etc.)',
          border: OutlineInputBorder(),
        ),
        enabled: isEditable,
        onChanged: (_) => _markDirtyAndMaybeAutosave(),
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
              enabled: isEditable,
              onChanged: (_) => _markDirtyAndMaybeAutosave(),
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
              enabled: isEditable,
              onChanged: (_) => _markDirtyAndMaybeAutosave(),
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
              enabled: isEditable,
              onChanged: (_) => _markDirtyAndMaybeAutosave(),
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
              enabled: isEditable,
              onChanged: (_) => _markDirtyAndMaybeAutosave(),
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
              enabled: isEditable,
              onChanged: (_) => _markDirtyAndMaybeAutosave(),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _buildCondicion(bool isEditable) => Wrap(
    spacing: 8,
    children: [
      ChoiceChip(
        label: const Text('Vivo'),
        selected: _condicion == EstadosAnimal.vivo,
        onSelected: isEditable
            ? (_) {
          setState(() => _condicion = EstadosAnimal.vivo);
          _markDirtyAndMaybeAutosave();
        }
            : null,
      ),
      ChoiceChip(
        label: const Text('Muerto'),
        selected: _condicion == EstadosAnimal.muerto,
        onSelected: isEditable
            ? (_) {
          setState(() => _condicion = EstadosAnimal.muerto);
          _markDirtyAndMaybeAutosave();
        }
            : null,
      ),
      ChoiceChip(
        label: const Text('Rastro'),
        selected: _condicion == EstadosAnimal.rastro,
        onSelected: isEditable
            ? (_) {
          setState(() => _condicion = EstadosAnimal.rastro);
          _markDirtyAndMaybeAutosave();
        }
            : null,
      ),
    ],
  );

  Widget _buildRastro(bool isEditable) => Column(
    children: [
      DropdownButtonFormField<String>(
        value: _rastroTipo,
        items: const [
          DropdownMenuItem(
              value: TiposRastro.huellas, child: Text('Huellas')),
          DropdownMenuItem(
              value: TiposRastro.huesosParciales,
              child: Text('Huesos parciales')),
          DropdownMenuItem(
              value: TiposRastro.huesosCompletos,
              child: Text('Huesos completos')),
          DropdownMenuItem(
              value: TiposRastro.plumas, child: Text('Plumas')),
          DropdownMenuItem(
              value: TiposRastro.excretas, child: Text('Excretas')),
          DropdownMenuItem(
              value: TiposRastro.nido, child: Text('Nido')),
          DropdownMenuItem(
              value: TiposRastro.madriguera,
              child: Text('Madriguera')),
          DropdownMenuItem(
              value: TiposRastro.otros, child: Text('Otros')),
        ],
        onChanged: isEditable
            ? (v) {
          setState(() => _rastroTipo = v);
          _markDirtyAndMaybeAutosave();
        }
            : null,
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
        enabled: isEditable,
        onChanged: (_) => _markDirtyAndMaybeAutosave(),
      ),
    ],
  );

  Widget _buildNotas(bool isEditable) => TextField(
    controller: _notasCtrl,
    maxLines: 4,
    decoration: const InputDecoration(
      hintText: 'Observaciones adicionales…',
      border: OutlineInputBorder(),
    ),
    enabled: isEditable,
    onChanged: (_) => _markDirtyAndMaybeAutosave(),
  );

  Widget _buildFotos(bool isEditable) => _FotosGrid(
    urls: _fotoUrls, // usamos las resueltas
    canEdit: isEditable && !_saving,
    onAdd: isEditable ? _agregarFotoCloud : null,
    onDelete: isEditable ? _eliminarFotoCloud : null,
    onTapPhoto: isEditable ? _accionesFoto : _verFoto,
  );

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: Theme.of(context).textTheme.titleMedium),
  );

  // ---------------------------- FOTOS (cloud) ----------------------------
  Future<void> _agregarFotoCloud() async {
    if (_obs == null) return;

    // límite de fotos igual que en agregar
    if (_fotoUrls.length >= _maxFotos) {
      _snack('Máximo $_maxFotos fotos por observación.', exito: false);
      return;
    }

    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (picked == null) return;

      if (mounted) setState(() => _saving = true);

      final auth = context.read<AuthProvider>();
      // Igual a lista_observaciones_screen:
      final uid = auth.currentUserId ?? auth.uid ?? auth.user?.uid ?? '';
      final nombre = auth.usuario?.nombreCompleto ??
          auth.user?.displayName ??
          auth.user?.email?.split('@').first ??
          'Usuario';

      final ctxTipo =
      (_obs!.idProyecto != null) ? 'PROYECTO_INVESTIGACION' : 'OTRO';
      final ctxNombre =
      (_obs!.idProyecto != null) ? _obs!.idProyecto! : 'OBS:${_obs!.id!}';

      await _fotoSvc.subirVarias(
        fotografoUid: uid,
        fotografoNombre: nombre,
        contextoTipo: ctxTipo,
        contextoNombre: ctxNombre,
        observacionId: _obs!.id!,
        archivos: [picked],
        desdeGaleria: true,
      );

      // Refrescar arrays desde la nube
      final snap = await FirebaseFirestore.instance
          .collection('observaciones')
          .doc(_obs!.id!)
          .get();
      final data = snap.data() ?? {};
      _fotoUrls =
          ((data['media_urls'] as List?)?.cast<String>()) ?? _fotoUrls;
      _fotoPaths =
          ((data['media_storage_paths'] as List?)?.cast<String>()) ??
              _fotoPaths;

      if (!mounted) return;
      setState(() {
        _fotos = List<String>.from(_fotoUrls);
        // fotos cambiaron -> marcar dirty para rechazada
        _markDirtyAndMaybeAutosave();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto agregada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error subiendo foto: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _eliminarFotoCloud(String url) async {
    if (_obs == null) return;
    try {
      if (mounted) setState(() => _saving = true);

      final docRef =
      FirebaseFirestore.instance.collection('observaciones').doc(_obs!.id);

      // 1) Obtener arrays actuales
      final snap = await docRef.get();
      final data = snap.data() ?? {};
      final urls = ((data['media_urls'] as List?)?.cast<String>()) ??
          List<String>.from(_fotoUrls);
      final paths = ((data['media_storage_paths'] as List?)?.cast<String>()) ??
          List<String>.from(_fotoPaths);

      // 2) Encontrar índice (varios fallback)
      int idx = urls.indexOf(url);
      if (idx == -1) {
        final resolvedUrl = await _fotoSvc.resolveHttpsFromAny(url);
        idx = urls.indexOf(resolvedUrl);
      }
      if (idx == -1) {
        idx = _fotoUrls.indexOf(url);
      }
      if (idx == -1) {
        idx = urls.indexWhere((u) {
          try {
            return u.endsWith(Uri.parse(url).path);
          } catch (_) {
            return false;
          }
        });
      }

      // 3) Borrar en Storage si tenemos path; si no, desde URL
      if (idx >= 0 && idx < paths.length && paths[idx].isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref(paths[idx]).delete();
        } catch (_) {}
      } else {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }

      // 4) Remover en arrays y actualizar doc
      if (idx >= 0 && idx < urls.length) {
        urls.removeAt(idx);
        if (idx < paths.length) paths.removeAt(idx);
      }

      await docRef.update({
        'media_urls': urls,
        'media_storage_paths': paths,
        'media_count': urls.length,
        'updatedAt': FieldValue.serverTimestamp(),
        // compat con 'fotos'
        'fotos': urls,
      });

      if (!mounted) return;
      setState(() {
        _fotoUrls = urls;
        _fotoPaths = paths;
        _fotos = List<String>.from(_fotoUrls);
        _markDirtyAndMaybeAutosave();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto eliminada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error eliminando foto: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Reemplazar UNA foto conservando su posición.
  Future<void> _reemplazarFotoCloud(String oldUrl) async {
    if (_obs == null) return;
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (picked == null) return;

    try {
      if (mounted) setState(() => _saving = true);

      final auth = context.read<AuthProvider>();
      // Igual que lista_observaciones_screen:
      final uid = auth.currentUserId ?? auth.uid ?? auth.user?.uid ?? '';
      final nombre = auth.usuario?.nombreCompleto ??
          auth.user?.displayName ??
          auth.user?.email?.split('@').first ??
          'Usuario';

      final ctxTipo =
      (_obs!.idProyecto != null) ? 'PROYECTO_INVESTIGACION' : 'OTRO';
      final ctxNombre =
      (_obs!.idProyecto != null) ? _obs!.idProyecto! : 'OBS:${_obs!.id!}';

      // Subir nueva
      final res = await _fotoSvc.subirVarias(
        fotografoUid: uid,
        fotografoNombre: nombre,
        contextoTipo: ctxTipo,
        contextoNombre: ctxNombre,
        observacionId: _obs!.id!,
        archivos: [picked],
        desdeGaleria: true,
      );
      if (res.isEmpty) throw StateError('No se pudo subir la nueva foto');

      final docRef =
      FirebaseFirestore.instance.collection('observaciones').doc(_obs!.id);

      // Arrays actuales
      final snap = await docRef.get();
      final data = snap.data() ?? {};
      final urls = ((data['media_urls'] as List?)?.cast<String>()) ??
          List<String>.from(_fotoUrls);
      final paths = ((data['media_storage_paths'] as List?)?.cast<String>()) ??
          List<String>.from(_fotoPaths);

      // Índice del viejo
      int idx = urls.indexOf(oldUrl);
      if (idx == -1) {
        final resolvedOld = await _fotoSvc.resolveHttpsFromAny(oldUrl);
        idx = urls.indexOf(resolvedOld);
      }
      if (idx == -1) {
        idx = _fotoUrls.indexOf(oldUrl);
      }
      if (idx == -1) throw StateError('No se encontró la foto a reemplazar');

      // Leer arrays NUEVOS para tomar la última agregada
      final snap2 = await docRef.get();
      final data2 = snap2.data() ?? {};
      final urls2 =
          ((data2['media_urls'] as List?)?.cast<String>()) ?? <String>[];
      final paths2 =
          ((data2['media_storage_paths'] as List?)?.cast<String>()) ??
              <String>[];
      final newUrl = urls2.isNotEmpty ? urls2.last : null;
      final newPath = paths2.isNotEmpty ? paths2.last : null;
      if (newUrl == null) {
        throw StateError('No se obtuvo URL de la nueva foto');
      }

      // Reemplazo conservando posición
      urls[idx] = newUrl;
      if (idx < paths.length && newPath != null) {
        if (paths.length == urls.length) {
          paths[idx] = newPath;
        } else {
          while (paths.length < urls.length) paths.add('');
          paths[idx] = newPath;
        }
      }

      await docRef.update({
        'media_urls': urls,
        'media_storage_paths': paths,
        'media_count': urls.length,
        'updatedAt': FieldValue.serverTimestamp(),
        'fotos': urls, // compat
      });

      // Borrar archivo viejo (best-effort)
      try {
        final oldIdxInPrev = _fotoUrls.indexOf(oldUrl);
        final oldPath =
        (oldIdxInPrev >= 0 && oldIdxInPrev < _fotoPaths.length)
            ? _fotoPaths[oldIdxInPrev]
            : null;
        if (oldPath != null && oldPath.isNotEmpty) {
          await FirebaseStorage.instance.ref(oldPath).delete();
        } else {
          await FirebaseStorage.instance.refFromURL(oldUrl).delete();
        }
      } catch (_) {}

      // Actualizar UI
      if (!mounted) return;
      setState(() {
        _fotoUrls = urls;
        _fotoPaths = paths;
        _fotos = List<String>.from(_fotoUrls);
        _markDirtyAndMaybeAutosave();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto reemplazada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reemplazando foto: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // --------- acciones rápidas sobre una foto ----------
  Future<void> _accionesFoto(String url) async {
    if (_saving) return; // evita toques dobles mientras guarda
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.zoom_in),
                title: const Text('Ver'),
                onTap: () {
                  Navigator.pop(ctx);
                  _verFoto(url);
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Reemplazar'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _reemplazarFotoCloud(url);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Eliminar'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _eliminarFotoCloud(url);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _verFoto(String url) async {
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------- acciones (cloud) --------------

  void _snack(String msg, {bool exito = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: exito ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _guardarCloud({bool internalCall = false}) async {
    if (_obs == null) return;
    // Si no hay cambios y viene de autosave, no hagas roundtrip ni snack
    if (internalCall && !_hasLocalChanges()) return;

    setState(() => _saving = true);
    try {
      final prov = context.read<ObservacionProvider>();

      DateTime? fecha = _parseDate(_fechaCtrl.text.trim());
      final lat = double.tryParse(_latCtrl.text.trim());
      final lng = double.tryParse(_lngCtrl.text.trim());
      final alt = double.tryParse(_altCtrl.text.trim());

      final patch = {
        'fecha_captura': fecha,
        // Compat: guardamos ambos campos por si la UI/servicio usa uno u otro
        'especie_nombre_cientifico': _especieCtrl.text.trim(),
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
        'rastro_tipo':
        _condicion == EstadosAnimal.rastro ? _rastroTipo : null,
        'rastro_detalle': _condicion == EstadosAnimal.rastro
            ? _rastroDetalleCtrl.text.trim()
            : null,
      };

      final ok = await prov.patch(observacionId: _obs!.id!, patch: patch);
      if (!mounted) return;
      if (ok) {
        _originalSnapshot = _currentSnapshot();
        _dirty = false;
        if (!internalCall) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cambios guardados en la nube')),
          );

          // Después de guardar manualmente, mandamos a DetalleObservacion
          Navigator.of(context).pushReplacementNamed(
            '/observaciones/detalle',
            arguments: _obs!.id,
          );
        }
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

  // -------------- helpers --------------
  String _fmtDate(DateTime d) {
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${t(d.month)}-${d.day.toString().padLeft(2, '0')}';
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

    final soyAutor = (o.uidUsuario == uid);
    final editableByAuthor =
        soyAutor && (o.estado == EstadosObs.borrador || o.estado == EstadosObs.rechazado);

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
      if (mounted) setState(() {});
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

class _FotosGrid extends StatelessWidget {
  final List<String> urls;
  final bool canEdit;
  final Future<void> Function()? onAdd;
  final Future<void> Function(String url)? onDelete;
  final Future<void> Function(String url)? onTapPhoto;

  const _FotosGrid({
    required this.urls,
    required this.canEdit,
    this.onAdd,
    this.onDelete,
    this.onTapPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final total = urls.length + (canEdit ? 1 : 0);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: total,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemBuilder: (_, i) {
        if (canEdit && i == 0) {
          return InkWell(
            onTap: onAdd,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(child: Icon(Icons.add_a_photo_outlined)),
            ),
          );
        }
        final idx = canEdit ? i - 1 : i;
        final url = urls[idx];
        return Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              onTap: onTapPhoto != null ? () => onTapPhoto!(url) : null,
              child: Image.network(url, fit: BoxFit.cover),
            ),
            if (canEdit && onDelete != null)
              Positioned(
                top: 4,
                right: 4,
                child: InkWell(
                  onTap: () => onDelete!(url),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.close,
                        color: Colors.white, size: 16),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}


