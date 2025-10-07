// lib/ui/screens/observaciones/agregar_observacion_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:faunadmin2/services/local_file_storage.dart';

import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:exif/exif.dart'; // <-- leer EXIF en la primera foto

import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/models/photo_media.dart';       // 👈 para PhotoMedia
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/providers/observacion_provider.dart';
import 'package:faunadmin2/services/permisos_service.dart';
import 'package:faunadmin2/services/foto_service.dart';

class AgregarObservacionScreen extends StatefulWidget {
  const AgregarObservacionScreen({super.key});

  @override
  State<AgregarObservacionScreen> createState() => _AgregarObservacionScreenState();
}

class _AgregarObservacionScreenState extends State<AgregarObservacionScreen> {
  final _formKey = GlobalKey<FormState>();

  // Catálogo simple de tipo de lugar
  static const _tiposLugar = <String>[
    'URBANO', 'RURAL', 'BOSQUE', 'SELVA', 'AGRICOLA', 'RIBEREÑO', 'OTRO'
  ];

  // Máximo de fotos por observación
  static const int _maxFotos = 4;

  // Política de evidencia: permitir o no galería
  final bool _permitirGaleria = true; // ponlo en false si quieres forzar cámara

  // ----------- Campos del formulario (estado fuente de verdad) -----------
  DateTime? _fechaCaptura = DateTime.now();
  int?     _edadAprox;
  String?  _especieNombre;
  String?  _lugarNombre;
  String   _lugarTipo = _tiposLugar.first;
  String?  _municipio;
  String?  _estadoPais; // Guardamos SOLO el estado (México asumido)
  double?  _lat;
  double?  _lng;
  double?  _altitud;
  String?  _notas;

  // ----------- Condición del animal / rastro -----------
  String _condicionAnimal = EstadosAnimal.vivo; // vivo | muerto | rastro
  String? _rastroTipo;                          // TiposRastro.* (opcional)
  final _rastroDetalleCtrl = TextEditingController(); // libre (ej. "huesos casi completos")

  // ----------- Controllers para autocompletar campos -----------
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _altCtrl = TextEditingController();
  final _municipioCtrl = TextEditingController();
  final _estadoCtrl = TextEditingController(); // etiqueta UI: "Estado (México)"
  final _lugarNombreCtrl = TextEditingController();

  // ----------- Estado UI -----------
  bool _submitting = false;
  bool _enviarRevision = false;
  bool _argsAplicados = false;
  bool _prefillCargado = false; // evitar cargas múltiples

  // ----------- Fotos locales -----------
  final _picker = ImagePicker();
  final List<File> _fotos = [];

  final _fotoSvc = FotoService();

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _altCtrl.dispose();
    _municipioCtrl.dispose();
    _estadoCtrl.dispose();
    _lugarNombreCtrl.dispose();
    _rastroDetalleCtrl.dispose();
    super.dispose();
  }

  // =========================
  // Helpers numéricos/validación
  // =========================
  double? _toDouble(String? v) {
    if (v == null) return null;
    final t = v.replaceAll(',', '.').trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  String? _validaLat(String? v) {
    if (v == null || v.trim().isEmpty) return null; // opcional
    final d = _toDouble(v);
    if (d == null) return 'Número válido';
    if (d < -90 || d > 90) return 'Rango: -90..90';
    return null;
  }

  String? _validaLng(String? v) {
    if (v == null || v.trim().isEmpty) return null; // opcional
    final d = _toDouble(v);
    if (d == null) return 'Número válido';
    if (d < -180 || d > 180) return 'Rango: -180..180';
    return null;
  }

  String? _validaNum(String? v) {
    if (v == null || v.trim().isEmpty) return null; // opcional
    final d = _toDouble(v);
    if (d == null) return 'Número válido';
    return null;
  }

  // =========================
  // Validación para enviar a revisión
  // =========================
  bool _validarParaRevision() {
    // 1) Fotos: 1..4
    if (_fotos.isEmpty || _fotos.length > 4) {
      _snack('Para enviar a revisión, agrega entre 1 y 4 fotos.');
      return false;
    }

    // 2) Fecha
    if (_fechaCaptura == null) {
      _snack('Para enviar a revisión, indica la fecha/hora de captura.');
      return false;
    }

    // 3) Ubicación mínima
    if (_lugarTipo.trim().isEmpty) {
      _snack('Selecciona el tipo de lugar para enviar a revisión.');
      return false;
    }
    //    - estado (México)
    final estadoOk = (_estadoPais ?? '').trim().isNotEmpty;
    if (!estadoOk) {
      _snack('Indica el Estado (de México) para enviar a revisión.');
      return false;
    }
    //    - al menos uno: lugarNombre o municipio
    final lugarOk = ((_lugarNombre ?? '').trim().isNotEmpty) || ((_municipio ?? '').trim().isNotEmpty);
    if (!lugarOk) {
      _snack('Indica el nombre del lugar o el municipio para enviar a revisión.');
      return false;
    }
    //    - lat & lng
    if (_lat == null || _lng == null) {
      _snack('Para revisión, incluye coordenadas (Latitud y Longitud).');
      return false;
    }

    // 4) Condición animal
    if (_condicionAnimal != EstadosAnimal.vivo &&
        _condicionAnimal != EstadosAnimal.muerto &&
        _condicionAnimal != EstadosAnimal.rastro) {
      _snack('Selecciona la condición del animal.');
      return false;
    }

    //    - Si rastro: exigir tipo o detalle
    if (_condicionAnimal == EstadosAnimal.rastro) {
      final hasTipo = (_rastroTipo ?? '').trim().isNotEmpty;
      final hasDetalle = _rastroDetalleCtrl.text.trim().isNotEmpty;
      if (!hasTipo && !hasDetalle) {
        _snack('Para rastro, indica el tipo de rastro o el detalle.');
        return false;
      }
    }

    return true;
  }

  // =========================
  // Fecha/hora
  // =========================
  Future<void> _pickFechaHora() async {
    final initial = _fechaCaptura ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (t == null) return;
    setState(() {
      _fechaCaptura = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  // =========================
  // Hook EXIF para primera foto
  // =========================
  Future<void> _rellenarDesdeExif(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final tags = await readExifFromBytes(bytes);

      // Hora/fecha
      if (_fechaCaptura == null) {
        final dtStr = tags['EXIF DateTimeOriginal']?.printable ?? tags['Image DateTime']?.printable;
        if (dtStr != null) {
          try {
            final norm = dtStr.replaceFirst(' ', 'T').replaceAll(':', '-');
            _fechaCaptura = DateTime.tryParse(norm);
          } catch (_) {}
        }
      }

      // GPS
      double? parseCoord(String? values, String? ref) {
        if (values == null || ref == null) return null;
        double numz(String t) {
          if (t.contains('/')) {
            final p = t.split('/');
            final a = double.tryParse(p[0]) ?? 0;
            final b = double.tryParse(p[1]) ?? 1;
            return b == 0 ? 0 : a / b;
          }
          return double.tryParse(t) ?? 0;
        }
        final parts = RegExp(r'(\d+(?:\.\d+)?(?:/\d+)?)')
            .allMatches(values)
            .map((m) => m.group(1)!)
            .toList();
        if (parts.length < 3) return null;
        final d = numz(parts[0]);
        final m = numz(parts[1]);
        final s2 = numz(parts[2]);
        var val = d + (m / 60.0) + (s2 / 3600.0);
        final r = ref.trim().toUpperCase();
        if (r == 'S' || r == 'W') val = -val;
        return val;
      }

      if (_lat == null || _lng == null) {
        final lat = parseCoord(tags['GPS GPSLatitude']?.printable, tags['GPS GPSLatitudeRef']?.printable);
        final lng = parseCoord(tags['GPS GPSLongitude']?.printable, tags['GPS GPSLongitudeRef']?.printable);
        if (lat != null && lng != null) {
          setState(() {
            _lat = lat;
            _lng = lng;
            _latCtrl.text = _lat!.toStringAsFixed(6);
            _lngCtrl.text = _lng!.toStringAsFixed(6);
          });

          // intenta autocompletar municipio/estado si hay red
          unawaited(_autocompletarDireccionDesdeGPS(_lat!, _lng!));
        }
      }

      // Altitud (no siempre disponible en EXIF)
      if (_altitud == null) {
        final altStr = tags['GPS GPSAltitude']?.printable; // suele ser "xxx/yyy"
        if (altStr != null) {
          double altNum = 0;
          if (altStr.contains('/')) {
            final p = altStr.split('/');
            final a = double.tryParse(p[0]) ?? 0;
            final b = double.tryParse(p[1]) ?? 1;
            altNum = b == 0 ? 0 : a / b;
          } else {
            altNum = double.tryParse(altStr) ?? 0;
          }
          setState(() {
            _altitud = altNum;
            _altCtrl.text = _altitud!.toStringAsFixed(1);
          });
        }
      }
    } catch (_) {
      // Si falla EXIF, no rompemos flujo
    }
  }

  // =========================
  // Cámara / Galería (múltiple) + guardado local
  // =========================
  Future<void> _agregarFoto({required bool desdeCamara}) async {
    if (_fotos.length >= _maxFotos) {
      _snack('Máximo $_maxFotos fotos por observación.');
      return;
    }
    final x = await _picker.pickImage(
      source: desdeCamara ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 85,
    );
    if (x == null) return;

    final saved = await _guardarCopiaLocal(File(x.path));
    if (saved != null) {
      // Si es la primera foto y faltan datos, intenta EXIF
      if (_fotos.isEmpty) {
        await _rellenarDesdeExif(saved);
      }

      setState(() => _fotos.add(saved));
      _snack('Foto agregada (${_fotos.length}/$_maxFotos)');
    } else {
      _snack('No se pudo guardar la foto localmente');
    }
  }

  /// Copia la imagen al directorio de documentos:
  /// <Documents>/fauna_observaciones/photo_YYYYMMDD_hhmmss_x.jpg
  Future<File?> _guardarCopiaLocal(File original) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/fauna_observaciones');
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      final ts = DateTime.now();
      final name =
          'photo_${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}${ts.second.toString().padLeft(2, '0')}_${_fotos.length + 1}.jpg';
      final dst = File('${folder.path}/$name');
      return await original.copy(dst.path);
    } catch (_) {
      return null;
    }
  }

  // =========================
  // GPS (geolocator) con fallback a última conocida
  // =========================
  Future<Position?> _obtenerGPS() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      _snack('Permiso de ubicación denegado');
      return null;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _snack('Activa el GPS en el dispositivo');
      // seguimos para intentar lastKnown
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 8),
      );
      return pos;
    } on TimeoutException {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return await Geolocator.getLastKnownPosition();
    }
  }

  Future<void> _usarMiUbicacion() async {
    final pos = await _obtenerGPS();
    if (!mounted) return;
    if (pos == null) {
      _snack('No se pudo obtener la ubicación');
      return;
    }
    setState(() {
      _lat = pos.latitude;
      _lng = pos.longitude;
      if (pos.altitude.isFinite) {
        _altitud = pos.altitude;
      }
      // Actualiza inputs visibles
      _latCtrl.text = (_lat ?? 0).toStringAsFixed(6);
      _lngCtrl.text = (_lng ?? 0).toStringAsFixed(6);
      _altCtrl.text = (_altitud ?? 0).toStringAsFixed(1);
    });

    // Autocompletar municipio/estado si hay red
    if (_lat != null && _lng != null) {
      await _autocompletarDireccionDesdeGPS(_lat!, _lng!);
    }

    _snack('Coordenadas insertadas desde GPS');
  }

  // =========================
  // Reverse geocoding
  // =========================
  Future<void> _autocompletarDireccionDesdeGPS(double lat, double lng) async {
    try {
      final ps = await geo.placemarkFromCoordinates(lat, lng);
      if (ps.isNotEmpty) {
        final p = ps.first;
        setState(() {
          _municipio  = (p.subAdministrativeArea ?? p.locality)?.trim();
          // Guardamos SOLO el ESTADO (país asumido = México)
          _estadoPais = (p.administrativeArea)?.trim();
          _municipioCtrl.text = _municipio ?? '';
          _estadoCtrl.text = _estadoPais ?? '';
        });
      }
    } catch (_) {
      // sin red o sin datos: el usuario lo puede escribir manual
    }
  }

  // =========================
  // Prefill offline (últimos valores)
  // =========================
  Future<void> _cargarPrefillLocal() async {
    if (_prefillCargado) return;
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _lugarTipo  = sp.getString('pref_lugar_tipo') ?? _lugarTipo;
      _municipio  = sp.getString('pref_municipio');
      _estadoPais = sp.getString('pref_estado_pais'); // solo estado de México
      if (_municipio != null) _municipioCtrl.text = _municipio!;
      if (_estadoPais != null) _estadoCtrl.text = _estadoPais!;
    });
    _prefillCargado = true;
  }

  Future<void> _guardarPrefillLocal() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('pref_lugar_tipo', _lugarTipo);
    await sp.setString('pref_municipio', (_municipio ?? '').trim());
    await sp.setString('pref_estado_pais', (_estadoPais ?? '').trim());
  }

  // =========================
  // Prefill por argumentos + prefill offline
  // =========================
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsAplicados) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final pre = args['prefill'];
      if (pre is Map) {
        if (pre['fecha_captura'] is DateTime) {
          _fechaCaptura = pre['fecha_captura'] as DateTime;
        }
        if (pre['lat'] is num) {
          _lat = (pre['lat'] as num).toDouble();
          _latCtrl.text = _lat!.toStringAsFixed(6);
        }
        if (pre['lng'] is num) {
          _lng = (pre['lng'] as num).toDouble();
          _lngCtrl.text = _lng!.toStringAsFixed(6);
        }
        if (pre['altitud'] is num) {
          _altitud = (pre['altitud'] as num).toDouble();
          _altCtrl.text = _altitud!.toStringAsFixed(1);
        }
        if (pre['lugar_tipo'] is String) _lugarTipo = (pre['lugar_tipo'] as String);
        if (pre['lugar_nombre'] is String) {
          _lugarNombre = (pre['lugar_nombre'] as String);
          _lugarNombreCtrl.text = _lugarNombre!;
        }
      }
    }
    _argsAplicados = true;

    // Prefill offline (últimos valores usados)
    _cargarPrefillLocal();
  }

  // =========================
  // NUEVO: meta para guardar en el teléfono (sin tocar tu lógica remota)
  // =========================
  Map<String, dynamic> _buildObservacionMetaParaTelefono() {
    return {
      'estado': EstadosObs.borrador,                      // se guarda como “borrador” local
      'fecha_captura': _fechaCaptura?.toIso8601String(),
      'edad_aproximada': _edadAprox,
      'especie_nombre': (_especieNombre ?? '').trim().isEmpty ? null : _especieNombre!.trim(),
      'lugar_nombre': (_lugarNombre ?? '').trim().isEmpty ? null : _lugarNombre!.trim(),
      'lugar_tipo': _lugarTipo,
      'municipio': (_municipio ?? '').trim().isEmpty ? null : _municipio!.trim(),
      'estado_pais': (_estadoPais ?? '').trim().isEmpty ? null : _estadoPais!.trim(),
      'lat': _lat,
      'lng': _lng,
      'altitud': _altitud,
      'notas': (_notas ?? '').trim().isEmpty ? null : _notas!.trim(),
      // Condición / rastro
      'condicion_animal': _condicionAnimal,
      'rastro_tipo': _condicionAnimal == EstadosAnimal.rastro ? _rastroTipo : null,
      'rastro_detalle': _condicionAnimal == EstadosAnimal.rastro
          ? (_rastroDetalleCtrl.text.trim().isEmpty ? null : _rastroDetalleCtrl.text.trim())
          : null,
      // Extras útiles locales
      'ai_status': 'idle',
      'ai_top_suggestions': const [],
      'media_count': _fotos.length,
      // Marca de control local (tu servicio pondrá 'PENDING' si falta)
      'status': 'DRAFT_LOCAL',
    };
  }

  Future<void> _guardarLocalEnTelefono() async {
    if (_fotos.isEmpty) {
      _snack('Agrega al menos una foto para guardar en el teléfono.');
      return;
    }
    try {
      setState(() => _submitting = true);

      final meta = _buildObservacionMetaParaTelefono();

      // Firma real del servicio que compartiste
      final folder = await LocalFileStorage.instance.guardarObservacionFull(
        meta: meta,
        fotos: _fotos,
      );

      _snack('Listo: la información y las fotos se guardaron en tu teléfono.');
      // Útil para depurar
      debugPrint('Guardado offline en carpeta: ${folder.path}');
    } catch (e) {
      _snack('No se pudo guardar en el teléfono: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // =========================
  // Submit (remoto)
  // =========================
  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    // Si se quiere enviar a revisión, validar requisitos mínimos
    if (_enviarRevision) {
      final ok = _validarParaRevision();
      if (!ok) return;
    } else {
      // En borrador, al menos 1 foto para nuestro flujo actual
      if (_fotos.isEmpty) {
        _snack('Agrega al menos una foto (evidencia).');
        return;
      }
    }

    final auth = context.read<AuthProvider>();
    final permisos = PermisosService(auth);
    final prov = context.read<ObservacionProvider>();

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final String? proyectoId = args?['proyectoId'] as String?;
    final String? uidUsuarioArg = args?['uidUsuario'] as String?;
    final uidActual = auth.uid;

    // Autor válido
    if (uidActual == null ||
        uidUsuarioArg == null ||
        uidUsuarioArg.trim().isEmpty ||
        (uidUsuarioArg != uidActual && !permisos.isAdminUnico)) {
      _snack('Autor inválido para crear observación');
      return;
    }

    // Gate de creación
    final bool puedeCrear = (proyectoId == null || proyectoId.trim().isEmpty)
        ? permisos.canCreateObservationSinProyecto
        : permisos.canCreateObservationInProject(proyectoId);

    if (!puedeCrear) {
      _snack('No tienes permiso para crear en este contexto');
      return;
    }

    setState(() => _submitting = true);

    // Construimos la observación en BORRADOR
    final obs = Observacion(
      id: null,
      idProyecto: (proyectoId?.isNotEmpty ?? false) ? proyectoId : null,
      uidUsuario: uidUsuarioArg,
      estado: EstadosObs.borrador,
      fechaCaptura: _fechaCaptura,
      edadAproximada: _edadAprox,
      especieNombre: (_especieNombre ?? '').trim().isEmpty ? null : _especieNombre!.trim(),
      especieId: null,
      lugarNombre: (_lugarNombre ?? '').trim().isEmpty ? null : _lugarNombre!.trim(),
      lugarTipo: _lugarTipo.isEmpty ? null : _lugarTipo,
      municipio: (_municipio ?? '').trim().isEmpty ? null : _municipio!.trim(),
      // Guardamos SOLO el Estado (México asumido)
      estadoPais: (_estadoPais ?? '').trim().isEmpty ? null : _estadoPais!.trim().toUpperCase(),
      lat: _lat,
      lng: _lng,
      altitud: _altitud,
      notas: (_notas ?? '').trim().isNotEmpty ? _notas!.trim() : null,
      aiStatus: 'idle',
      aiTopSuggestions: const [],
      // Condición/rastro
      condicionAnimal: _condicionAnimal,
      rastroTipo: _condicionAnimal == EstadosAnimal.rastro ? _rastroTipo : null,
      rastroDetalle: _condicionAnimal == EstadosAnimal.rastro
          ? ((_rastroDetalleCtrl.text.trim().isEmpty) ? null : _rastroDetalleCtrl.text.trim())
          : null,
      // denormalizados
      mediaCount: null, // lo parchamos después
    );

    String? newId;
    try {
      if (obs.idProyecto == null) {
        newId = await prov.crearSinProyecto(data: obs);
      } else {
        newId = await prov.crearEnProyecto(proyectoId: obs.idProyecto!, data: obs);
      }
      if (newId == null) {
        setState(() => _submitting = false);
        _snack('No se pudo crear la observación');
        return;
      }
    } catch (e) {
      setState(() => _submitting = false);
      _snack('Error al guardar: $e');
      return;
    }

    // ===== Subir fotos y enlazar =====
    try {
      final String uid = uidUsuarioArg;
      final String nombreUsuario = uid; // si tienes displayName real, ponlo aquí

      final contextoTipo = (proyectoId == null || proyectoId.isEmpty)
          ? 'RESIDENCIA'
          : 'PROYECTO_INVESTIGACION';

      final contextoNombre = (proyectoId == null || proyectoId.isEmpty)
          ? (_lugarNombre ?? 'Sin nombre')
          : 'Proyecto $proyectoId';

      // Sube y crea espejo en observaciones/{obsId}/media
      final List<PhotoMedia> subidas = await _fotoSvc.subirVarias(
        fotografoUid: uid,
        fotografoNombre: nombreUsuario,
        contextoTipo: contextoTipo,
        contextoNombre: contextoNombre,
        observacionId: newId,   // vínculo directo
        archivos: _fotos,
        // desdeGaleria: false (por defecto)
      );

      await prov.patch(
        observacionId: newId,
        patch: {
          'media_count': subidas.length,
          'media_urls': subidas
              .map((m) => m.url)
              .whereType<String>()
              .toList(),
        },
        toast: false,
      );
    } catch (e) {
      _snack('Observación creada, pero falló la subida de fotos: $e');
    }

    // Enviar a revisión si está marcado
    if (_enviarRevision) {
      final ok = await prov.enviarAPendiente(newId);
      if (!ok) {
        _snack('Guardada en borrador. No se pudo enviar a revisión.');
      } else {
        _snack('Enviada a revisión');
      }
    } else {
      _snack('Observación guardada (borrador)');
    }

    // Guarda prefill para próximas capturas (offline)
    await _guardarPrefillLocal();

    if (!mounted) return;
    setState(() => _submitting = false);
    Navigator.of(context).pop();
  }

  // =========================
  // Utilidad UI
  // =========================
  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Banner de requisitos mínimos cuando el usuario marca “Enviar a revisión”.
  Widget _requisitosRevisionBanner() {
    if (!_enviarRevision) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.15),
        border: Border.all(color: Colors.amber.shade700),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'Para enviar a revisión: 1–4 fotos, fecha de captura, tipo de lugar, '
            'Estado (México), lugar o municipio, coordenadas y condición del animal. '
            'Si es “Rastro”, indica tipo o detalle.',
        style: TextStyle(fontSize: 12),
      ),
    );
  }

  /// Banner fijo de advertencias de autenticidad/uso correcto de evidencia.
  Widget _avisoAutenticidadBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.06),
        border: Border.all(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Importante sobre la evidencia fotográfica',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6),
          Text(
            '• No subas fotos de internet ni material con marcas de agua.\n'
                '• Activa la ubicación en la cámara cuando sea posible (EXIF GPS).\n'
                '• Sube fotos donde se distinga un animal o rastro real; evita imágenes fuera de contexto.\n'
                '• Si la imagen es dudosa o carece de metadatos, podría rechazarse o requerir verificación.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permisos = PermisosService(auth);

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final String? proyectoId = args?['proyectoId'] as String?;
    final String? uidUsuario = args?['uidUsuario'] as String?;

    final bool gateOk = (proyectoId == null || proyectoId.trim().isEmpty)
        ? permisos.canCreateObservationSinProyecto
        : permisos.canCreateObservationInProject(proyectoId);

    if (!gateOk || uidUsuario == null || uidUsuario.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nueva observación')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No tienes permisos para crear observaciones aquí.'),
          ),
        ),
      );
    }

    final reachedMax = _fotos.length >= _maxFotos;

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva observación')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _submitting
            ? const Center(child: CircularProgressIndicator())
            : Form(
          key: _formKey,
          child: ListView(
            children: [
              _avisoAutenticidadBanner(),
              _requisitosRevisionBanner(),

              // ----------- Captura -----------
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fecha/Hora de captura'),
                subtitle: Text(
                  (_fechaCaptura ?? DateTime.now()).toLocal().toString(),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _pickFechaHora,
                ),
              ),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Edad aproximada (años, opcional)',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                ],
                onSaved: (v) =>
                _edadAprox = (v == null || v.isEmpty) ? null : int.parse(v),
              ),
              const SizedBox(height: 12),

              // ----------- Lugar -----------
              TextFormField(
                controller: _lugarNombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre del lugar (opcional)',
                ),
                onSaved: (v) =>
                _lugarNombre = (v ?? '').trim().isEmpty ? null : v!.trim(),
                textInputAction: TextInputAction.next,
              ),
              DropdownButtonFormField<String>(
                value: _lugarTipo,
                items: _tiposLugar
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _lugarTipo = v ?? _lugarTipo),
                decoration: const InputDecoration(labelText: 'Tipo de lugar'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _municipioCtrl,
                decoration:
                const InputDecoration(labelText: 'Municipio (opcional)'),
                onSaved: (v) =>
                _municipio = (v ?? '').trim().isEmpty ? null : v!.trim(),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _estadoCtrl,
                decoration: const InputDecoration(labelText: 'Estado (Oaxaca)'),
                onSaved: (v) =>
                _estadoPais = (v ?? '').trim().isEmpty ? null : v!.trim(),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),

              // ----------- Coordenadas -----------
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Latitud (opcional)'),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))
                      ],
                      validator: _validaLat,
                      onSaved: (v) => _lat = _toDouble(v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lngCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Longitud (opcional)'),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))
                      ],
                      validator: _validaLng,
                      onSaved: (v) => _lng = _toDouble(v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _altCtrl,
                decoration:
                const InputDecoration(labelText: 'Altitud (m, opcional)'),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))
                ],
                validator: _validaNum,
                onSaved: (v) => _altitud = _toDouble(v),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.my_location),
                  label: const Text('Usar mi ubicación'),
                  onPressed: _submitting ? null : _usarMiUbicacion,
                ),
              ),
              const SizedBox(height: 16),

              // ----------- Condición del animal / rastro -----------
              DropdownButtonFormField<String>(
                value: _condicionAnimal,
                decoration:
                const InputDecoration(labelText: 'Condición del animal'),
                items: const [
                  DropdownMenuItem(
                      value: EstadosAnimal.vivo, child: Text('Vivo')),
                  DropdownMenuItem(
                      value: EstadosAnimal.muerto, child: Text('Muerto')),
                  DropdownMenuItem(
                      value: EstadosAnimal.rastro, child: Text('Rastro')),
                ],
                onChanged: (v) => setState(() {
                  _condicionAnimal = v ?? EstadosAnimal.vivo;
                  if (_condicionAnimal != EstadosAnimal.rastro) {
                    _rastroTipo = null;
                    _rastroDetalleCtrl.clear();
                  }
                }),
              ),
              if (_condicionAnimal == EstadosAnimal.rastro) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _rastroTipo,
                  decoration: const InputDecoration(
                      labelText: 'Tipo de rastro (opcional)'),
                  items: const [
                    DropdownMenuItem(
                        value: TiposRastro.huellas, child: Text('Huellas')),
                    DropdownMenuItem(
                        value: TiposRastro.huesosParciales,
                        child: Text('Huesos parciales')),
                    DropdownMenuItem(
                        value: TiposRastro.huesosCompletos,
                        child: Text('Huesos casi completos')),
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
                  onChanged: (v) => setState(() => _rastroTipo = v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _rastroDetalleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Detalle del rastro (opcional)',
                    hintText:
                    'Ej. huesos casi completos, plumas dispersas, etc.',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
              ],

              // ----------- Especie / Notas -----------
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Especie (texto libre, opcional)',
                  hintText: 'Ej. Crotalus atrox',
                ),
                onSaved: (v) => _especieNombre =
                (v == null || v.trim().isEmpty) ? null : v.trim(),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Notas/observaciones (opcional)',
                  hintText: 'Detalles relevantes de la observación…',
                ),
                maxLines: 3,
                onSaved: (v) =>
                _notas = (v == null || v.trim().isEmpty) ? null : v.trim(),
              ),

              const SizedBox(height: 16),

              // ----------- Fotos (local) -----------
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Fotos (obligatorias, máximo $_maxFotos)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(width: 8),
                  Chip(label: Text('${_fotos.length}/$_maxFotos')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Cámara'),
                      onPressed: _submitting || reachedMax
                          ? null
                          : () => _agregarFoto(desdeCamara: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galería'),
                      onPressed: _submitting ||
                          reachedMax ||
                          !_permitirGaleria
                          ? null
                          : () => _agregarFoto(desdeCamara: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_fotos.isEmpty)
                Text(
                  'Agrega al menos una foto. Al guardar se subirán y quedarán ligadas a esta observación.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _fotos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final file = _fotos[i];
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              file,
                              height: 100,
                              width: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: InkWell(
                              onTap: _submitting
                                  ? null
                                  : () => setState(() => _fotos.removeAt(i)),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                padding: const EdgeInsets.all(2),
                                child: const Icon(Icons.close,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

              const SizedBox(height: 16),
              SwitchListTile(
                value: _enviarRevision,
                onChanged: (v) => setState(() => _enviarRevision = v),
                title: const Text('Enviar a revisión al guardar'),
                subtitle: const Text(
                    'La observación cambiará de “borrador” a “pendiente”'),
              ),

              const SizedBox(height: 24),

              // ======= BOTONES =======
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // NUEVO: Guardar en el teléfono (offline)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _guardarLocalEnTelefono,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Guardar en el teléfono (offline)'),
                    ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting ? null : _onSubmit,
                      child: _submitting
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

