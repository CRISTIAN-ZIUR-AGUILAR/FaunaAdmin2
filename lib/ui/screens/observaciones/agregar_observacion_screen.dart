// lib/ui/screens/observaciones/agregar_observacion_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:exif/exif.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/models/photo_media.dart';
import 'package:faunadmin2/models/especie.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/providers/observacion_provider.dart';
import 'package:faunadmin2/services/permisos_service.dart';
import 'package:faunadmin2/services/foto_service.dart';
import 'package:faunadmin2/services/local_file_storage.dart';
// ---- NUEVO: conectividad
import 'package:connectivity_plus/connectivity_plus.dart';

/// ================== Helpers UI (estilo sutil mejorado) ==================
class _CardSection extends StatelessWidget {
  final String title;
  final List<_SpanChild> children;
  final EdgeInsets margin;
  const _CardSection({
    required this.title,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 16),
  });

  int _colsForWidth(double w) {
    if (w >= 1200) return 3;
    if (w >= 801) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = _colsForWidth(constraints.maxWidth);
      const gap = 12.0;
      final colW = (constraints.maxWidth - gap * (cols - 1)) / cols;

      final items = <Widget>[];
      for (final sc in children) {
        final span = sc.span?.call(cols) ?? 1;
        final width = (span.clamp(1, cols) * colW) + (gap * (span - 1));
        items.add(SizedBox(width: width, child: sc.child));
      }

      return Card(
        elevation: 1.5,
        margin: margin,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 6,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12.0,
                runSpacing: 12.0,
                children: items,
              ),
            ],
          ),
        ),
      );
    });
  }
}

// === AUTOCOMPLETE: modelos ligeros para ubicaciones ===
class PlaceHit {
  final String codigo; // docId o campo "id"
  final String nombre;

  // —— Metadatos del municipio:
  final String? estado; // p.ej. "Oaxaca"
  final String? region; // p.ej. "Valles Centrales"
  final String? distrito; // p.ej. "Ejutla"
  final double? lat;
  final double? lng;

  PlaceHit({
    required this.codigo,
    required this.nombre,
    this.estado,
    this.region,
    this.distrito,
    this.lat,
    this.lng,
  });

  @override
  String toString() => nombre;
}

class AgregarObservacionScreen extends StatefulWidget {
  const AgregarObservacionScreen({super.key});

  @override
  State<AgregarObservacionScreen> createState() =>
      _AgregarObservacionScreenState();
}

class _AgregarObservacionScreenState extends State<AgregarObservacionScreen> {
  final _formKey = GlobalKey<FormState>();

  // Catálogo simple de tipo de lugar
  static const _tiposLugar = <String>[
    'URBANO',
    'RURAL',
    'BOSQUE',
    'SELVA',
    'AGRICOLA',
    'RIBEREÑO',
    'OTRO'
  ];

  // Máximo de fotos por observación
  static const int _maxFotos = 4;

  // Política de evidencia: permitir o no galería
  final bool _permitirGaleria = true;

  // ----------- Campos del formulario -----------
  DateTime? _fechaCaptura = DateTime.now();
  int? _edadAproximada;

  // Especie
  String? _especieIdSel; // docId en 'especies'
  final _especieCientCtrl = TextEditingController();
  final _especieComunCtrl = TextEditingController();

  // Rehidratación/estabilización visual del TypeAhead (texto mostrado)
  String _especieTexto = ''; // SIEMPRE refleja lo que se ve en el campo visible
  String _municipioTexto = ''; // idem

  // Taxonomía auto (solo lectura)
  String? _taxClase;
  String? _taxOrden;
  String? _taxFamilia;
  final _taxClaseCtrl = TextEditingController();
  final _taxOrdenCtrl = TextEditingController();
  final _taxFamiliaCtrl = TextEditingController();

  // Lugar
  String? _lugarNombre;
  String _lugarTipo = _tiposLugar.first;
  String? _municipio;
  String? _estadoPais;
  double? _lat;
  double? _lng;
  double? _altitud;
  String? _notas;

  // —— Metadatos del municipio seleccionado (canónicos)
  String? _ubicEstado;
  String? _ubicRegion;
  String? _ubicDistrito;

  // Controllers para mostrar esos metadatos en UI (solo lectura)
  final _ubicEstadoCtrl = TextEditingController();
  final _ubicRegionCtrl = TextEditingController();
  final _ubicDistritoCtrl = TextEditingController();

  // ----------- Condición del animal / rastro -----------
  String _condicionAnimal = EstadosAnimal.vivo; // vivo | muerto | rastro
  String? _rastroTipo; // TiposRastro.* (opcional)
  final _rastroDetalleCtrl = TextEditingController();

  // ----------- Controllers UI numéricos -----------
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _altCtrl = TextEditingController();
  final _municipioCtrl = TextEditingController(); // fallback
  final _estadoCtrl = TextEditingController(); // fallback
  final _lugarNombreCtrl = TextEditingController();

  // ----------- Estado UI -----------
  bool _submitting = false;
  bool _enviarRevision = false;
  bool _argsAplicados = false;

  // ----------- Fotos locales -----------
  final _picker = ImagePicker();
  final List<dynamic> _fotos = []; // File (mobile/desktop) o XFile (web)
  final _fotoSvc = FotoService();

  // =========================
  // AUTOCOMPLETE: Firestore
  // =========================
  final _db = FirebaseFirestore.instance;

  // Ubicación
  final _estadoAutoCtrl = TextEditingController();
  final _municipioAutoCtrl = TextEditingController();
  Timer? _debounceMuni;
  List<PlaceHit> _municipioOpts = [];
  String? _estadoCodigoSel; // opcional, si se resuelve por GPS
  String? _municipioNombreSel; // nombre municipio seleccionado

  // ===== Referencias a los controllers visibles del TypeAhead =====
  TextEditingController? _especieInputCtrl;
  TextEditingController? _municipioInputCtrl;

  bool get _isMobile {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  // ---- NUEVO: estado de conectividad
  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _pingDebounce;

  @override
  void initState() {
    super.initState();

    // Listener: Municipio (se mantiene igual)
    _municipioAutoCtrl.addListener(() {
      final q = _municipioAutoCtrl.text.trim();
      _debounceMuni?.cancel();
      _debounceMuni = Timer(const Duration(milliseconds: 220), () async {
        if (q.isEmpty) {
          if (mounted) setState(() => _municipioOpts = []);
          return;
        }
        final estadoCodigo = _estadoCodigoSel;
        final hits = await _buscarMunicipios(q, estadoCodigo);
        if (!mounted) return;
        setState(() => _municipioOpts = hits);
      });
    });

    // 🔹 SOLO EN TELÉFONO: suscripción a conectividad + ping inicial
    if (_isMobile) {
      _connSub = Connectivity().onConnectivityChanged.listen((_) {
        _refreshOnline();
      });
      unawaited(_refreshOnline());
    } else {
      // En web/escritorio asumimos "online"
      _online = true;
    }
  }

  @override
  void dispose() {
    _debounceMuni?.cancel();

    _especieCientCtrl.dispose();
    _especieComunCtrl.dispose();

    _taxClaseCtrl.dispose();
    _taxOrdenCtrl.dispose();
    _taxFamiliaCtrl.dispose();

    _estadoAutoCtrl.dispose();
    _municipioAutoCtrl.dispose();

    _ubicEstadoCtrl.dispose();
    _ubicRegionCtrl.dispose();
    _ubicDistritoCtrl.dispose();

    _latCtrl.dispose();
    _lngCtrl.dispose();
    _altCtrl.dispose();
    _municipioCtrl.dispose();
    _estadoCtrl.dispose();
    _lugarNombreCtrl.dispose();
    _rastroDetalleCtrl.dispose();

    _connSub?.cancel(); // ---- NUEVO
    _pingDebounce?.cancel(); // ---- NUEVO

    super.dispose();
  }

  // =========================
  // Helpers num / validación
  // =========================
  double? _toDouble(String? v) {
    if (v == null) return null;
    final t = v.replaceAll(',', '.').trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  String? _validaLat(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final d = _toDouble(v);
    if (d == null) return 'Número válido';
    if (d < -90 || d > 90) return 'Rango: -90..90';
    return null;
  }

  String? _validaLng(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final d = _toDouble(v);
    if (d == null) return 'Número válido';
    if (d < -180 || d > 180) return 'Rango: -180..180';
    return null;
  }

  String? _validaNum(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final d = _toDouble(v);
    if (d == null) return 'Número válido';
    return null;
  }

  // =========================
  // Construcción preview + validación con modelo
  // =========================
  Observacion _buildPreviewForValidation() {
    final auth = context.read<AuthProvider>();
    final uid = auth.uid ?? 'tmp';

    final String? municipioDisplay =
    (_municipioNombreSel ?? _municipioAutoCtrl.text).trim().isNotEmpty
        ? (_municipioNombreSel ?? _municipioAutoCtrl.text).trim()
        : null;

    final String? lugarNombreFinal = _lugarNombreCtrl.text.trim().isNotEmpty
        ? _lugarNombreCtrl.text.trim()
        : null;

    final List<String> mediaUrlsFake =
    List.generate(_fotos.length, (i) => 'local_$i');

    return Observacion(
      id: null,
      uidUsuario: uid,
      estado: EstadosObs.borrador,
      fechaCaptura: _fechaCaptura,
      lat: _lat,
      lng: _lng,
      lugarTipo: _lugarTipo.isEmpty ? null : _lugarTipo,
      lugarNombre: lugarNombreFinal,
      municipio: municipioDisplay,
      condicionAnimal: _condicionAnimal,
      rastroTipo: _condicionAnimal == EstadosAnimal.rastro ? _rastroTipo : null,
      rastroDetalle: _condicionAnimal == EstadosAnimal.rastro
          ? (_rastroDetalleCtrl.text.trim().isEmpty
          ? null
          : _rastroDetalleCtrl.text.trim())
          : null,
      mediaUrls: mediaUrlsFake,
      mediaStoragePaths: const [],
    );
  }

  String _mapFaltantesToMensaje(List<String> faltantes) {
    if (faltantes.contains('media_urls')) {
      return 'Para enviar a revisión, agrega al menos una foto.';
    }
    if (faltantes.contains('fecha_captura')) {
      return 'Para enviar a revisión, indica la fecha/hora de captura.';
    }
    if (faltantes.contains('lat/lng')) {
      return 'Para revisión, incluye coordenadas (Latitud y Longitud).';
    }
    return 'Faltan datos mínimos: ${faltantes.join(', ')}';
  }

  // =========================
  // Validación para enviar a revisión
  // =========================
  bool _validarParaRevision() {
    final preview = _buildPreviewForValidation();

    // mínimos centralizados en el modelo
    final faltantes = preview.faltantesMinimos;
    if (faltantes.isNotEmpty) {
      final msg = _mapFaltantesToMensaje(faltantes);
      _snack(msg, exito: false);
      return false;
    }

    // fotos extra: máximo
    if (_fotos.length > _maxFotos) {
      _snack('Para enviar a revisión, máximo $_maxFotos fotos.', exito: false);
      return false;
    }

    // tipo de lugar + lugar/municipio
    if (_lugarTipo.trim().isEmpty) {
      _snack('Selecciona el tipo de lugar para enviar a revisión.', exito: false);
      return false;
    }

    if (preview.lugarNombre == null && preview.municipio == null) {
      _snack(
        'Indica el nombre del lugar o el municipio para enviar a revisión.',
        exito: false,
      );
      return false;
    }

    // condición / rastro
    if (!{EstadosAnimal.vivo, EstadosAnimal.muerto, EstadosAnimal.rastro}
        .contains(preview.condicionAnimal)) {
      _snack('Selecciona la condición del animal.', exito: false);
      return false;
    }

    if (preview.condicionAnimal == EstadosAnimal.rastro) {
      final hasTipo = (preview.rastroTipo ?? '').trim().isNotEmpty;
      final hasDetalle = (preview.rastroDetalle ?? '').trim().isNotEmpty;
      if (!hasTipo && !hasDetalle) {
        _snack(
          'Para rastro, indica el tipo de rastro o el detalle.',
          exito: false,
        );
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
  // Hook EXIF en primera foto
  // =========================
  Future<void> _rellenarDesdeExif(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final tags = await readExifFromBytes(bytes);
      // Hora/fecha
      if (_fechaCaptura == null) {
        final dtStr = tags['EXIF DateTimeOriginal']?.printable ??
            tags['Image DateTime']?.printable;
        if (dtStr != null) {
          final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$')
              .firstMatch(dtStr.trim());
          if (m != null) {
            final y = int.parse(m.group(1)!);
            final mo = int.parse(m.group(2)!);
            final d = int.parse(m.group(3)!);
            final h = int.parse(m.group(4)!);
            final mi = int.parse(m.group(5)!);
            final s = int.parse(m.group(6)!);
            _fechaCaptura = DateTime(y, mo, d, h, mi, s);
          }
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
        final lat = parseCoord(tags['GPS GPSLatitude']?.printable,
            tags['GPS GPSLatitudeRef']?.printable);
        final lng = parseCoord(tags['GPS GPSLongitude']?.printable,
            tags['GPS GPSLongitudeRef']?.printable);
        if (lat != null && lng != null) {
          setState(() {
            _lat = lat;
            _lng = lng;
            _latCtrl.text = _lat!.toStringAsFixed(6);
            _lngCtrl.text = _lng!.toStringAsFixed(6);
          });

          unawaited(_autocompletarDireccionDesdeGPS(_lat!, _lng!));
        }
      }

      // Altitud (si existe)
      if (_altitud == null) {
        final altStr = tags['GPS GPSAltitude']?.printable;
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
      // ignoramos fallos EXIF
    }
  }

  // =========================
  // Cámara / Galería (múltiple)
  // =========================
  Future<void> _agregarFoto({required bool desdeCamara}) async {
    if (_fotos.length >= _maxFotos) {
      _snack('Máximo $_maxFotos fotos por observación.', exito: false);
      return;
    }
    final x = await _picker.pickImage(
      source: desdeCamara ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 85,
    );
    if (x == null) return;

    dynamic saved;
    if (kIsWeb) {
      saved = x; // XFile
    } else {
      final file = File(x.path);
      final copy = await _guardarCopiaLocal(file);
      saved = copy ?? file; // File
    }
    if (!kIsWeb && _fotos.isEmpty && saved is File) {
      await _rellenarDesdeExif(saved);
    }
    setState(() => _fotos.add(saved));
    _snack('Foto agregada (${_fotos.length}/$_maxFotos)');
  }

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
  // GPS
  // =========================
  Future<Position?> _obtenerGPS() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      _snack('Permiso de ubicación denegado', exito: false);
      return null;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _snack('Activa el GPS en el dispositivo', exito: false);
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
      _snack('No se pudo obtener la ubicación', exito: false);
      return;
    }
    setState(() {
      _lat = pos.latitude;
      _lng = pos.longitude;
      if (pos.altitude.isFinite) {
        _altitud = pos.altitude;
      }
      _latCtrl.text = (_lat ?? 0).toStringAsFixed(6);
      _lngCtrl.text = (_lng ?? 0).toStringAsFixed(6);
      _altCtrl.text = (_altitud ?? 0).toStringAsFixed(1);
    });

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
        final muniName = (p.subAdministrativeArea ?? p.locality)?.trim();
        final edoName = (p.administrativeArea)?.trim();

        setState(() {
          _municipio = muniName;
          _estadoPais = edoName;
          _municipioCtrl.text = _municipio ?? '';
          _estadoCtrl.text = _estadoPais ?? '';
          if ((_estadoPais ?? '').isNotEmpty) {
            _estadoAutoCtrl.text = _estadoPais!;
          }
          if ((_municipio ?? '').isNotEmpty) {
            _municipioAutoCtrl.text = _municipio!;
            _municipioTexto = _municipio!;
            if (_municipioInputCtrl != null) {
              _municipioInputCtrl!.text = _municipioTexto;
              _municipioInputCtrl!.selection = TextSelection.fromPosition(
                  TextPosition(offset: _municipioInputCtrl!.text.length));
            }
          }
        });

        if ((_estadoPais ?? '').isNotEmpty) {
          await _resolverEstadoCodigoPorNombre(_estadoPais!);
        }
      }
    } catch (_) {
      // sin red
    }
  }

  /// Busca en colección 'estados' por nombre normalizado y asigna _estadoCodigoSel
  Future<void> _resolverEstadoCodigoPorNombre(String nombreEstado) async {
    try {
      final q = _normalize(nombreEstado);
      final snap = await _db
          .collection('estados')
          .where('nombre_lower', isEqualTo: q)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first;
        final m = d.data();
        setState(() {
          _estadoCodigoSel = (m['codigo'] ?? d.id).toString();
        });

        final muniTxt = _municipioAutoCtrl.text.trim();
        if (muniTxt.isNotEmpty) {
          final opts = await _buscarMunicipios(muniTxt, _estadoCodigoSel);
          if (!mounted) return;
          setState(() {
            _municipioOpts = opts;
          });
        }
      }
    } catch (_) {
      // ignorar
    }
  }

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
  }

  // =========================
  // Conectividad (NUEVO)
  // =========================
  Future<bool> _pingInternet() async {
    try {
      final res = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(seconds: 2));
      return res.isNotEmpty && res.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshOnline() async {
    _pingDebounce?.cancel();
    _pingDebounce = Timer(const Duration(milliseconds: 400), () async {
      final ok = await _pingInternet();
      if (mounted) setState(() => _online = ok);
    });
  }

  Widget _bannerConectividad() {
    if (_online) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.06),
          border: Border.all(color: Colors.green.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'Conectado: podrás guardar en la nube o localmente.',
          style: TextStyle(fontSize: 12),
        ),
      );
    } else {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.12),
          border: Border.all(color: Colors.orange.shade700),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'Sin conexión: usa “Guardar localmente”. Cuando vuelva la señal, podrás sincronizar.',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
    }
  }

  // =========================
  // Submit (remoto)
  // =========================
  Future<void> _onSubmit() async {
    // NUEVO: guardia cuando no hay internet
    if (!_online) {
      _snack('Sin conexión. Usa “Guardar localmente”.', exito: false);
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    if (_enviarRevision) {
      final ok = _validarParaRevision();
      if (!ok) return;
    } else {
      if (_fotos.isEmpty) {
        _snack('Agrega al menos una foto (evidencia).', exito: false);
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

    if (uidActual == null ||
        uidUsuarioArg == null ||
        uidUsuarioArg.trim().isEmpty ||
        (uidUsuarioArg != uidActual && !permisos.isAdminUnico)) {
      _snack('Autor inválido para crear observación', exito: false);
      return;
    }

    final bool puedeCrear = (proyectoId == null || proyectoId.trim().isEmpty)
        ? permisos.canCreateObservationSinProyecto
        : permisos.canCreateObservationInProject(proyectoId);

    if (!puedeCrear) {
      _snack('No tienes permiso para crear en este contexto', exito: false);
      return;
    }

    setState(() => _submitting = true);

    String? newId;
    bool success = false;
    String mensajeFinal = 'Observación guardada.';

    try {
      // --- Estado canónico desde selección de municipio ---
      final estadoCanonico = (_ubicEstado ?? '').trim().isNotEmpty
          ? _ubicEstado!.trim().toUpperCase()
          : null;

      // Asegura que lo visible en TypeAhead quedó en sus controllers
      if (_especieCientCtrl.text.trim().isEmpty && _especieTexto.trim().isNotEmpty) {
        _especieCientCtrl.text = _especieTexto.trim();
      }
      if (_municipioAutoCtrl.text.trim().isEmpty && _municipioTexto.trim().isNotEmpty) {
        _municipioAutoCtrl.text = _municipioTexto.trim();
      }

      // --- ¿Seleccionó especie del catálogo? ---
      final bool seleccionoCatalogo = (_especieIdSel?.trim().isNotEmpty ?? false);

      // --- Normaliza nombre científico final + fuera_catalogo ---
      final String? nombreCientFinal = (() {
        final raw = _especieCientCtrl.text.trim();
        if (raw.isEmpty) return null;
        if (seleccionoCatalogo) return _canonNombreCientifico(raw);
        final tokens = raw.split(RegExp(r'\s+'));
        return tokens.length == 1 ? _derivarGeneroSp(raw) : _canonNombreCientifico(raw);
      })();
      final bool fueraCatalogo = !seleccionoCatalogo && (nombreCientFinal?.isNotEmpty ?? false);

      // --- Taxonomía: tomar SIEMPRE lo que muestran los controllers; fallback al estado en memoria ---
      String? taxClase =
      _taxClaseCtrl.text.trim().isNotEmpty ? _taxClaseCtrl.text.trim() : _taxClase;
      String? taxOrden =
      _taxOrdenCtrl.text.trim().isNotEmpty ? _taxOrdenCtrl.text.trim() : _taxOrden;
      String? taxFamilia =
      _taxFamiliaCtrl.text.trim().isNotEmpty ? _taxFamiliaCtrl.text.trim() : _taxFamilia;
      taxClase = (taxClase?.trim().isNotEmpty ?? false) ? taxClase!.trim() : null;
      taxOrden = (taxOrden?.trim().isNotEmpty ?? false) ? taxOrden!.trim() : null;
      taxFamilia = (taxFamilia?.trim().isNotEmpty ?? false) ? taxFamilia!.trim() : null;

      // --- Municipio display (lo visible para UI) ---
      final String? municipioDisplay =
      (_municipioNombreSel ?? _municipioAutoCtrl.text).trim().isNotEmpty
          ? (_municipioNombreSel ?? _municipioAutoCtrl.text).trim()
          : null;

      // --- Construcción inicial de la observación ---
      final obs = Observacion(
        id: null,
        idProyecto: (proyectoId?.isNotEmpty ?? false) ? proyectoId : null,
        uidUsuario: uidUsuarioArg!,
        estado: EstadosObs.borrador,
        fechaCaptura: _fechaCaptura,
        edadAproximada: _edadAproximada,

        // Especie
        especieId: seleccionoCatalogo ? _especieIdSel : null,
        especieNombreCientifico: nombreCientFinal,
        especieNombreComun: (() {
          final s = _especieComunCtrl.text.trim();
          return s.isEmpty ? null : s;
        })(),

        // Lugar
        lugarNombre: (_lugarNombre ?? '').trim().isNotEmpty ? _lugarNombre!.trim() : null,
        lugarTipo: _lugarTipo.isEmpty ? null : _lugarTipo,
        municipio: municipioDisplay,
        estadoPais: estadoCanonico,

        // Coords
        lat: _lat,
        lng: _lng,
        altitud: _altitud,

        // Otros
        notas: (_notas ?? '').trim().isNotEmpty ? _notas!.trim() : null,
        aiStatus: 'idle',
        aiTopSuggestions: const [],
        condicionAnimal: _condicionAnimal,
        rastroTipo: _condicionAnimal == EstadosAnimal.rastro ? _rastroTipo : null,
        rastroDetalle: _condicionAnimal == EstadosAnimal.rastro
            ? ((_rastroDetalleCtrl.text.trim().isEmpty)
            ? null
            : _rastroDetalleCtrl.text.trim())
            : null,
        mediaCount: null,
        mediaUrls: const [],
        mediaStoragePaths: const [],
      );

      // --- Creación en Firestore ---
      newId = (obs.idProyecto == null)
          ? await prov.crearSinProyecto(data: obs)
          : await prov.crearEnProyecto(proyectoId: obs.idProyecto!, data: obs);

      if (newId == null) {
        throw Exception('No se pudo obtener ID de la observación');
      }

      // --- Patch con especie/taxonomía/ubicación (y flags) ---
      try {
        final Map<String, dynamic> p = {
          // Especie
          'especie_id': seleccionoCatalogo ? _especieIdSel : null,
          'especie_nombre_cientifico': nombreCientFinal,
          'especie_nombre_comun': (() {
            final s = _especieComunCtrl.text.trim();
            return s.isEmpty ? null : s;
          })(),
          'especie_slug': (nombreCientFinal != null) ? _slugify(nombreCientFinal) : null,
          'especie_fuera_catalogo': fueraCatalogo,

          // Taxonomía (si está)
          if (taxClase != null) 'taxo_clase': taxClase,
          if (taxOrden != null) 'taxo_orden': taxOrden,
          if (taxFamilia != null) 'taxo_familia': taxFamilia,

          // Ubicación derivada del municipio seleccionado (canónico)
          'municipio_display': municipioDisplay,
          'ubic_estado': _ubicEstado,
          'ubic_region': _ubicRegion,
          'ubic_distrito': _ubicDistrito,
          if ((_ubicEstado ?? '').trim().isNotEmpty)
            'estado_pais': _ubicEstado!.trim().toUpperCase(),
        };

        await prov.patch(
          observacionId: newId!,
          patch: p,
          toast: false,
        );
      } catch (_) {
        // No rompemos el flujo si falla el patch
      }

      // --- Subida de fotos ---
      try {
        final String uid = uidUsuarioArg;
        final contextoTipo = (proyectoId == null || proyectoId.isEmpty)
            ? 'RESIDENCIA'
            : 'PROYECTO_INVESTIGACION';
        final contextoNombre = (proyectoId == null || proyectoId.isEmpty)
            ? (_lugarNombre ?? 'Sin nombre')
            : 'Proyecto $proyectoId';

        final List<PhotoMedia> subidas = await _fotoSvc.subirVarias(
          fotografoUid: uid,
          fotografoNombre: uid,
          contextoTipo: contextoTipo,
          contextoNombre: contextoNombre,
          observacionId: newId,
          archivos: _fotos, // XFile (web) o File (móvil)
        );

        final coverUrl = subidas.isNotEmpty ? subidas.first.url : null;
        await prov.patch(
          observacionId: newId,
          patch: {
            'media_count': subidas.length,
            'media_urls': subidas.map((m) => m.url).whereType<String>().toList(),
            if (coverUrl != null) 'cover_url': coverUrl,
            if (subidas.isNotEmpty) 'primary_media_id': subidas.first.id,
          },
          toast: false,
        );
      } catch (e) {
        _snack('Observación creada, pero falló la subida de fotos: $e', exito: false);
      }

      // --- Cambio de estado si pidió enviar a revisión ---
      if (_enviarRevision) {
        final ok = await prov.enviarAPendiente(newId);
        mensajeFinal = ok
            ? 'Enviada a revisión correctamente.'
            : 'Guardada como borrador. No se pudo enviar a revisión.';
      } else {
        mensajeFinal = 'Guardada como borrador.';
      }

      success = true;
      _snack(mensajeFinal, exito: true);
    } catch (e) {
      _snack('Error al guardar: $e', exito: false);
    } finally {
      if (!mounted) return;
      setState(() => _submitting = false);
      Navigator.of(context).pop({'success': success, 'newId': newId});
    }
  }

  // =========================
  // Guardar LOCAL (borrador offline)
  // =========================
  Future<void> _onGuardarLocal() async {
    if (!_isMobile) {
      _snack('El guardado local sólo está disponible en Android/iOS.', exito: false);
      return;
    }
    if (_fotos.isEmpty) {
      _snack('Agrega al menos una foto para guardar localmente.', exito: false);
      return;
    }
    if (_fotos.length > _maxFotos) {
      _snack('Máximo $_maxFotos fotos por observación.', exito: false);
      return;
    }

    // Asegura que lo que se ve en los TypeAhead esté en nuestros controllers
    if (_especieCientCtrl.text.trim().isEmpty && _especieTexto.trim().isNotEmpty) {
      _especieCientCtrl.text = _especieTexto.trim();
    }
    if (_municipioAutoCtrl.text.trim().isEmpty && _municipioTexto.trim().isNotEmpty) {
      _municipioAutoCtrl.text = _municipioTexto.trim();
    }

    // Fecha por defecto (si quedó nula)
    _fechaCaptura ??= DateTime.now();

    // Estado canónico (del municipio)
    final estadoCanonico = (_ubicEstado ?? '').trim().isNotEmpty
        ? _ubicEstado!.trim().toUpperCase()
        : _estadoPais?.trim();

    // Fotos: en móvil son File; filtramos por seguridad
    final List<File> files = _fotos.whereType<File>().toList();
    if (files.isEmpty) {
      _snack('No hay archivos locales válidos para guardar.', exito: false);
      return;
    }

    // Autor/proyecto de args (como en remoto)
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final String? proyectoId = args?['proyectoId'] as String?;
    final String? uidUsuarioArg = args?['uidUsuario'] as String?;

    if (uidUsuarioArg == null || uidUsuarioArg.trim().isEmpty) {
      _snack('No se pudo determinar el autor para el borrador local.', exito: false);
      return;
    }

    // Nombres de archivos locales
    final mediaNames = files.map((f) => f.path.split('/').last).toList();

    // Sello de tiempo local para deduplicar
    final ahoraIso = DateTime.now().toIso8601String();

    // === Resolver nombre científico final y fuera_catalogo (igual que remoto)
    String? nombreCientFinal;
    bool fueraCatalogo = false;

    final rawNombreCient = _especieCientCtrl.text.trim();
    if ((_especieIdSel?.trim().isNotEmpty ?? false)) {
      nombreCientFinal = _canonNombreCientifico(rawNombreCient);
    } else {
      if (rawNombreCient.isNotEmpty) {
        final tokens = rawNombreCient.split(RegExp(r'\s+'));
        nombreCientFinal =
        tokens.length == 1 ? _derivarGeneroSp(rawNombreCient) : _canonNombreCientifico(rawNombreCient);
        fueraCatalogo = true;
      } else {
        nombreCientFinal = null;
      }
    }

    final municipioDisplay =
    (_municipioNombreSel ?? _municipioAutoCtrl.text).trim().isNotEmpty
        ? (_municipioNombreSel ?? _municipioAutoCtrl.text).trim()
        : null;

    // === TAXONOMÍA desde controllers con fallback a variables
    final String? txClase = () {
      final t = _taxClaseCtrl.text.trim();
      if (t.isNotEmpty) return t;
      return (_taxClase?.trim().isNotEmpty ?? false) ? _taxClase!.trim() : null;
    }();

    final String? txOrden = () {
      final t = _taxOrdenCtrl.text.trim();
      if (t.isNotEmpty) return t;
      return (_taxOrden?.trim().isNotEmpty ?? false) ? _taxOrden!.trim() : null;
    }();

    final String? txFamilia = () {
      final t = _taxFamiliaCtrl.text.trim();
      if (t.isNotEmpty) return t;
      return (_taxFamilia?.trim().isNotEmpty ?? false) ? _taxFamilia!.trim() : null;
    }();

    // Construye el meta.json
    final meta = <String, dynamic>{
      'id_proyecto': (proyectoId?.isNotEmpty ?? false) ? proyectoId : null,
      'uid_usuario': uidUsuarioArg,

      // Captura
      'fecha_captura': _fechaCaptura?.toIso8601String(),
      'edad_aproximada': _edadAproximada,

      // Especie
      'especie_id': (_especieIdSel?.trim().isNotEmpty ?? false) ? _especieIdSel : null,
      'especie_nombre': nombreCientFinal,
      'especie_nombre_cientifico': nombreCientFinal,
      'especie_nombre_comun': (() {
        final s = _especieComunCtrl.text.trim();
        return s.isEmpty ? null : s;
      })(),
      'especie_fuera_catalogo': fueraCatalogo,
      'especie_slug': (nombreCientFinal != null) ? _slugify(nombreCientFinal) : null,

      // Taxonomía
      'taxo_clase': txClase,
      'taxo_orden': txOrden,
      'taxo_familia': txFamilia,

      // Lugar
      'lugar_nombre': (_lugarNombre ?? '').trim().isNotEmpty ? _lugarNombre!.trim() : null,
      'lugar_tipo': _lugarTipo.isNotEmpty ? _lugarTipo : null,

      // Municipio + metadatos
      'municipio': municipioDisplay,
      'municipio_display': municipioDisplay,
      'ubic_estado': (_ubicEstado ?? '').trim().isNotEmpty ? _ubicEstado!.trim() : null,
      'ubic_region': (_ubicRegion ?? '').trim().isNotEmpty ? _ubicRegion!.trim() : null,
      'ubic_distrito': (_ubicDistrito ?? '').trim().isNotEmpty ? _ubicDistrito!.trim() : null,

      // Compat hacia atrás
      'estado_pais': estadoCanonico,

      // Coordenadas
      'lat': _lat,
      'lng': _lng,
      'altitud': _altitud,

      // Notas
      'notas': (_notas ?? '').trim().isNotEmpty ? _notas!.trim() : null,

      // Condición / rastro
      'condicion_animal': _condicionAnimal,
      'rastro_tipo': _condicionAnimal == EstadosAnimal.rastro ? _rastroTipo : null,
      'rastro_detalle': _condicionAnimal == EstadosAnimal.rastro
          ? ((_rastroDetalleCtrl.text.trim().isEmpty) ? null : _rastroDetalleCtrl.text.trim())
          : null,

      // Media local
      'media_local_names': mediaNames,
      'media_count': mediaNames.length,

      // Flujo/AI
      'ai_status': 'idle',
      'enviar_revision': _enviarRevision,

      // Control local
      'status': 'READY',
      'estado': 'borrador',
      'created_local_at': ahoraIso,
    };

    try {
      setState(() => _submitting = true);
      final dir = await LocalFileStorage.instance.guardarObservacionFull(
        meta: meta,
        fotos: files,
        idProyecto: proyectoId,
        uidUsuario: uidUsuarioArg,
      );

      _snack('Borrador guardado en el dispositivo.', exito: true);

      if (!mounted) return;
      setState(() => _submitting = false);

      Navigator.of(context).pop({'success': true, 'localPath': dir.path, 'local': true});
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('No se pudo guardar localmente: $e', exito: false);
    }
  }

  // =========================
  // Utilidad UI
  // =========================
  void _snack(String msg, {bool exito = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: exito ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _avisoAutenticidadBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.06),
        border: Border.all(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(10),
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

  Widget _requisitosRevisionBanner() {
    if (!_enviarRevision) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.15),
        border: Border.all(color: Colors.amber.shade700),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Para enviar a revisión: 1–4 fotos, fecha de captura, tipo de lugar, '
            'lugar o municipio, coordenadas y condición del animal. '
            'Si es “Rastro”, indica tipo o detalle.',
        style: TextStyle(fontSize: 12),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double maxWidth = constraints.maxWidth >= 1400
              ? 1200
              : (constraints.maxWidth >= 1000 ? 1000 : constraints.maxWidth);
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _submitting
                    ? const Center(child: CircularProgressIndicator())
                    : Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      // ---- NUEVO: banner de conectividad
                      _bannerConectividad(),

                      _avisoAutenticidadBanner(),
                      _requisitosRevisionBanner(),

                      // ----------- Sección: Captura -----------
                      _CardSection(
                        title: 'Captura',
                        children: [
                          _SpanChild(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Fecha/Hora de captura'),
                              subtitle: Text(
                                (_fechaCaptura ?? DateTime.now())
                                    .toLocal()
                                    .toString(),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.calendar_today),
                                onPressed: _pickFechaHora,
                              ),
                            ),
                            span: (_) => _.clamp(1, 3), // full width
                          ),
                          _SpanChild(
                            child: TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'Edad aproximada (años, opcional)',
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))
                              ],
                              onSaved: (v) => _edadAproximada =
                              (v == null || v.isEmpty) ? null : int.parse(v),
                            ),
                            span: (c) => c >= 2 ? 1 : 1,
                          ),
                        ],
                      ),

                      // ----------- Sección: Especie -----------
                      _CardSection(
                        title: 'Especie',
                        children: [
                          _SpanChild(
                            child: TypeAheadField<Especie>(
                              debounceDuration:
                              const Duration(milliseconds: 220),
                              suggestionsCallback: (pattern) =>
                                  _sugerirEspeciesPorCientifico(pattern),
                              builder:
                                  (context, textController, focusNode) {
                                _especieInputCtrl ??= textController;

                                if (textController.text != _especieTexto) {
                                  textController.text = _especieTexto;
                                  textController.selection =
                                      TextSelection.fromPosition(
                                        TextPosition(
                                            offset:
                                            textController.text.length),
                                      );
                                }

                                return TextField(
                                  controller: textController,
                                  focusNode: focusNode,
                                  decoration: const InputDecoration(
                                    labelText: 'Nombre científico',
                                    hintText:
                                    'Ej. Aechmophorus occidentalis',
                                    prefixIcon:
                                    Icon(Icons.science_outlined),
                                  ),
                                  style: const TextStyle(
                                      fontStyle: FontStyle.italic),
                                  onChanged: (v) {
                                    _especieTexto = v;
                                    _especieCientCtrl.value =
                                        textController.value;
                                  },
                                );
                              },
                              itemBuilder: (context, Especie item) {
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    item.nombreCientifico,
                                    style: const TextStyle(
                                        fontStyle: FontStyle.italic),
                                  ),
                                  subtitle:
                                  (item.nombresComunes.isNotEmpty)
                                      ? Text(item.nombresComunes
                                      .take(2)
                                      .join(', '))
                                      : null,
                                );
                              },
                              onSelected: (Especie item) =>
                                  _aplicarEspecieSeleccionada(item),
                              emptyBuilder: (ctx) => const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('Sin coincidencias'),
                              ),
                              loadingBuilder: (ctx) => const Padding(
                                padding: EdgeInsets.all(12),
                                child: LinearProgressIndicator(),
                              ),
                            ),
                            span: (c) => c, // full width
                          ),
                          _SpanChild(
                            child: TextFormField(
                              controller: _especieComunCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nombre común (opcional)',
                                hintText: 'Ej. Zambullidor occidental',
                              ),
                            ),
                            span: (c) => c >= 2 ? 1 : 1,
                          ),
                        ],
                      ),

                      // ----------- Sección: Taxonomía (auto) -----------
                      _CardSection(
                        title: 'Taxonomía (auto)',
                        children: [
                          _SpanChild(
                            child: TextFormField(
                              controller: _taxClaseCtrl,
                              decoration:
                              const InputDecoration(labelText: 'Clase'),
                              readOnly: true,
                              enabled: false,
                            ),
                          ),
                          _SpanChild(
                            child: TextFormField(
                              controller: _taxOrdenCtrl,
                              decoration:
                              const InputDecoration(labelText: 'Orden'),
                              readOnly: true,
                              enabled: false,
                            ),
                          ),
                          _SpanChild(
                            child: TextFormField(
                              controller: _taxFamiliaCtrl,
                              decoration:
                              const InputDecoration(labelText: 'Familia'),
                              readOnly: true,
                              enabled: false,
                            ),
                          ),
                        ],
                      ),

                      // ----------- Sección: Lugar -----------
                      _CardSection(
                        title: 'Lugar',
                        children: [
                          _SpanChild(
                            child: TextFormField(
                              controller: _lugarNombreCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nombre del lugar (opcional)',
                              ),
                              onSaved: (v) => _lugarNombre =
                              (v ?? '').trim().isEmpty
                                  ? null
                                  : v!.trim(),
                              textInputAction: TextInputAction.next,
                            ),
                            span: (c) => c, // full width
                          ),
                          _SpanChild(
                            child: DropdownButtonFormField<String>(
                              value: _lugarTipo,
                              items: _tiposLugar
                                  .map((e) => DropdownMenuItem(
                                  value: e, child: Text(e)))
                                  .toList(),
                              onChanged: (v) => setState(
                                      () => _lugarTipo = v ?? _lugarTipo),
                              decoration: const InputDecoration(
                                  labelText: 'Tipo de lugar'),
                            ),
                            span: (c) => c >= 2 ? 1 : 1,
                          ),
                          _SpanChild(
                            child: TypeAheadField<PlaceHit>(
                              debounceDuration:
                              const Duration(milliseconds: 220),
                              suggestionsCallback: (pattern) =>
                                  _buscarMunicipios(
                                      pattern, _estadoCodigoSel),
                              builder:
                                  (context, textController, focusNode) {
                                _municipioInputCtrl ??= textController;

                                if (textController.text != _municipioTexto) {
                                  textController.text = _municipioTexto;
                                  textController.selection =
                                      TextSelection.fromPosition(
                                        TextPosition(
                                            offset:
                                            textController.text.length),
                                      );
                                }

                                return TextField(
                                  controller: textController,
                                  focusNode: focusNode,
                                  decoration: const InputDecoration(
                                    labelText: 'Municipio',
                                    prefixIcon:
                                    Icon(Icons.location_city),
                                  ),
                                  onChanged: (v) {
                                    _municipioTexto = v;
                                    _municipioAutoCtrl.value =
                                        textController.value;
                                  },
                                );
                              },
                              itemBuilder: (context, PlaceHit item) {
                                final meta = [
                                  if ((item.distrito ?? '').isNotEmpty)
                                    'Distrito: ${item.distrito}',
                                  if ((item.region ?? '').isNotEmpty)
                                    'Región: ${item.region}',
                                  if ((item.estado ?? '').isNotEmpty)
                                    'Estado: ${item.estado}',
                                ].join(' • ');
                                return ListTile(
                                  dense: true,
                                  title: Text(item.nombre),
                                  subtitle:
                                  meta.isEmpty ? null : Text(meta),
                                );
                              },
                              onSelected: (PlaceHit item) {
                                _municipioNombreSel = item.nombre;
                                _municipioAutoCtrl.text = item.nombre;
                                _municipioTexto = item.nombre;

                                if (mounted && _municipioInputCtrl != null) {
                                  try {
                                    _municipioInputCtrl!.text =
                                        _municipioTexto;
                                    _municipioInputCtrl!.selection =
                                        TextSelection.fromPosition(
                                          TextPosition(
                                              offset: _municipioInputCtrl!
                                                  .text.length),
                                        );
                                  } catch (_) {}
                                }

                                _ubicEstado = item.estado;
                                _ubicRegion = item.region;
                                _ubicDistrito = item.distrito;

                                _ubicEstadoCtrl.text = _ubicEstado ?? '';
                                _ubicRegionCtrl.text = _ubicRegion ?? '';
                                _ubicDistritoCtrl.text =
                                    _ubicDistrito ?? '';

                                if (item.lat != null && item.lng != null) {
                                  _lat = item.lat;
                                  _lng = item.lng;
                                  _latCtrl.text =
                                      _lat!.toStringAsFixed(6);
                                  _lngCtrl.text =
                                      _lng!.toStringAsFixed(6);
                                }

                                if ((item.estado ?? '').isNotEmpty) {
                                  _estadoPais = item.estado;
                                  _estadoAutoCtrl.text = item.estado!;
                                }

                                if (mounted) setState(() {});
                                if (mounted) {
                                  FocusScope.of(context).unfocus();
                                }
                              },
                              emptyBuilder: (ctx) => const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('Sin coincidencias'),
                              ),
                              loadingBuilder: (ctx) => const Padding(
                                padding: EdgeInsets.all(12),
                                child: LinearProgressIndicator(),
                              ),
                            ),
                            span: (c) => c, // full width
                          ),
                        ],
                      ),

                      // ----------- Sección: Ubicación (auto) -----------
                      _CardSection(
                        title: 'Ubicación (auto)',
                        children: [
                          _SpanChild(
                            child: TextFormField(
                              controller: _ubicEstadoCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Estado (auto)'),
                              readOnly: true,
                              enabled: false,
                            ),
                          ),
                          _SpanChild(
                            child: TextFormField(
                              controller: _ubicRegionCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Región (auto)'),
                              readOnly: true,
                              enabled: false,
                            ),
                          ),
                          _SpanChild(
                            child: TextFormField(
                              controller: _ubicDistritoCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Distrito (auto)'),
                              readOnly: true,
                              enabled: false,
                            ),
                          ),
                        ],
                      ),

                      // ----------- Sección: Coordenadas -----------
                      _CardSection(
                        title: 'Coordenadas',
                        children: [
                          _SpanChild(
                            child: TextFormField(
                              controller: _latCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Latitud (opcional)'),
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  signed: true, decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[-0-9.,]'))
                              ],
                              validator: _validaLat,
                              onSaved: (v) => _lat = _toDouble(v),
                            ),
                            span: (c) => c >= 2 ? 1 : 1,
                          ),
                          _SpanChild(
                            child: TextFormField(
                              controller: _lngCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Longitud (opcional)'),
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  signed: true, decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[-0-9.,]'))
                              ],
                              validator: _validaLng,
                              onSaved: (v) => _lng = _toDouble(v),
                            ),
                            span: (c) => c >= 2 ? 1 : 1,
                          ),
                          _SpanChild(
                            child: TextFormField(
                              controller: _altCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Altitud (m, opcional)'),
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  signed: true, decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[-0-9.,]'))
                              ],
                              validator: _validaNum,
                              onSaved: (v) => _altitud = _toDouble(v),
                            ),
                            span: (c) => c >= 3 ? 1 : (c == 2 ? 1 : 1),
                          ),
                          _SpanChild(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.my_location),
                                label: const Text('Usar mi ubicación'),
                                onPressed:
                                _submitting ? null : _usarMiUbicacion,
                              ),
                            ),
                            span: (c) => c, // botón ancho completo
                          ),
                        ],
                      ),

                      // ----------- Sección: Condición / rastro -----------
                      _CardSection(
                        title: 'Condición del animal',
                        children: [
                          _SpanChild(
                            child: DropdownButtonFormField<String>(
                              value: _condicionAnimal,
                              decoration: const InputDecoration(
                                  labelText: 'Condición'),
                              items: const [
                                DropdownMenuItem(
                                    value: EstadosAnimal.vivo,
                                    child: Text('Vivo')),
                                DropdownMenuItem(
                                    value: EstadosAnimal.muerto,
                                    child: Text('Muerto')),
                                DropdownMenuItem(
                                    value: EstadosAnimal.rastro,
                                    child: Text('Rastro')),
                              ],
                              onChanged: (v) => setState(() {
                                _condicionAnimal =
                                    v ?? EstadosAnimal.vivo;
                                if (_condicionAnimal !=
                                    EstadosAnimal.rastro) {
                                  _rastroTipo = null;
                                  _rastroDetalleCtrl.clear();
                                }
                              }),
                            ),
                            span: (c) => c >= 2 ? 1 : 1,
                          ),
                          if (_condicionAnimal == EstadosAnimal.rastro) ...[
                            _SpanChild(
                              child: DropdownButtonFormField<String>(
                                value: _rastroTipo,
                                decoration: const InputDecoration(
                                    labelText:
                                    'Tipo de rastro (opcional)'),
                                items: const [
                                  DropdownMenuItem(
                                      value: TiposRastro.huellas,
                                      child: Text('Huellas')),
                                  DropdownMenuItem(
                                      value: TiposRastro.huesosParciales,
                                      child: Text('Huesos parciales')),
                                  DropdownMenuItem(
                                      value: TiposRastro.huesosCompletos,
                                      child:
                                      Text('Huesos casi completos')),
                                  DropdownMenuItem(
                                      value: TiposRastro.plumas,
                                      child: Text('Plumas')),
                                  DropdownMenuItem(
                                      value: TiposRastro.excretas,
                                      child: Text('Excretas')),
                                  DropdownMenuItem(
                                      value: TiposRastro.nido,
                                      child: Text('Nido')),
                                  DropdownMenuItem(
                                      value: TiposRastro.madriguera,
                                      child: Text('Madriguera')),
                                  DropdownMenuItem(
                                      value: TiposRastro.otros,
                                      child: Text('Otros')),
                                ],
                                onChanged: (v) =>
                                    setState(() => _rastroTipo = v),
                              ),
                              span: (c) => c >= 2 ? 1 : 1,
                            ),
                            _SpanChild(
                              child: TextFormField(
                                controller: _rastroDetalleCtrl,
                                decoration: const InputDecoration(
                                  labelText:
                                  'Detalle del rastro (opcional)',
                                  hintText:
                                  'Ej. huesos casi completos, plumas dispersas, etc.',
                                ),
                                maxLines: 2,
                              ),
                              span: (c) => c, // full width
                            ),
                          ],
                        ],
                      ),

                      // ----------- Sección: Notas -----------
                      _CardSection(
                        title: 'Notas / observaciones',
                        children: [
                          _SpanChild(
                            child: TextFormField(
                              decoration: const InputDecoration(
                                labelText:
                                'Notas/observaciones (opcional)',
                                hintText:
                                'Detalles relevantes de la observación…',
                              ),
                              maxLines: 3,
                              onSaved: (v) => _notas =
                              (v == null || v.trim().isEmpty)
                                  ? null
                                  : v.trim(),
                            ),
                            span: (c) => c, // full width
                          ),
                        ],
                      ),

                      // ----------- Sección: Fotos -----------
                      _CardSection(
                        title: 'Fotos (obligatorias, máximo $_maxFotos)',
                        children: [
                          _SpanChild(
                            child: Row(
                              crossAxisAlignment:
                              CrossAxisAlignment.center,
                              children: [
                                Text('Evidencia',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                                const SizedBox(width: 8),
                                Chip(
                                  label:
                                  Text('${_fotos.length}/$_maxFotos'),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            span: (c) => c >= 2 ? 1 : 1,
                          ),
                          _SpanChild(
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                        Icons.photo_camera_outlined),
                                    label: const Text('Cámara'),
                                    onPressed: _submitting || reachedMax
                                        ? null
                                        : () => _agregarFoto(
                                        desdeCamara: true),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                        Icons.photo_library_outlined),
                                    label: const Text('Galería'),
                                    onPressed: _submitting ||
                                        reachedMax ||
                                        !_permitirGaleria
                                        ? null
                                        : () => _agregarFoto(
                                        desdeCamara: false),
                                  ),
                                ),
                              ],
                            ),
                            span: (c) => c,
                          ),
                          _SpanChild(
                            child: _fotos.isEmpty
                                ? Text(
                              'Agrega al menos una foto. Al guardar se subirán y quedarán ligadas a esta observación.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                            )
                                : SizedBox(
                              height: 110,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _fotos.length,
                                separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                                itemBuilder: (_, i) {
                                  final dynamic f = _fotos[i];
                                  Widget thumb;

                                  if (kIsWeb) {
                                    final String url =
                                        (f as XFile).path;
                                    thumb = Image.network(
                                      url,
                                      height: 110,
                                      width: 140,
                                      fit: BoxFit.cover,
                                    );
                                  } else {
                                    thumb = Image.file(
                                      f as File,
                                      height: 110,
                                      width: 140,
                                      fit: BoxFit.cover,
                                    );
                                  }

                                  return Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius:
                                        BorderRadius.circular(
                                            8),
                                        child: thumb,
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: InkWell(
                                          onTap: _submitting
                                              ? null
                                              : () => setState(() =>
                                              _fotos
                                                  .removeAt(i)),
                                          child: Container(
                                            decoration:
                                            BoxDecoration(
                                              color: Colors
                                                  .black54,
                                              borderRadius:
                                              BorderRadius
                                                  .circular(
                                                  50),
                                            ),
                                            padding:
                                            const EdgeInsets
                                                .all(2),
                                            child: const Icon(
                                              Icons.close,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            span: (c) => c, // full width
                          ),
                        ],
                      ),

                      // ----------- Sección: Enviar / Guardar -----------
                      Card(
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                            children: [
                              SwitchListTile(
                                value: _enviarRevision,
                                onChanged: (v) => setState(
                                        () => _enviarRevision = v),
                                title: const Text(
                                    'Enviar a revisión al guardar'),
                                subtitle: const Text(
                                    'La observación cambiará de “borrador” a “pendiente”'),
                              ),
                              const SizedBox(height: 12),

                              // 1) Guardar en la nube (solo si hay internet)
                              FilledButton(
                                onPressed: (_submitting || !_online)
                                    ? null
                                    : _onSubmit,
                                child: _submitting
                                    ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child:
                                  CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                                    : const Text('Guardar'),
                              ),

                              // 2) Guardar localmente (siempre visible en móvil)
                              if (_isMobile) ...[
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  icon:
                                  const Icon(Icons.save_alt),
                                  onPressed: (_submitting || _online)
                                      ? null
                                      : _onGuardarLocal,
                                  label: Text(_online
                                      ? 'Guardar localmente (deshabilitado en línea)'
                                      : 'Guardar localmente'),
                                ),
                              ],

                              // 3) Cancelar
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: _submitting
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: const Text('Cancelar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // =========================
  // AUTOCOMPLETE: ESPECIES (TypeAhead)
  // =========================
  String _slugify(String s) {
    const mapa = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n'
    };
    final norm =
    s.trim().toLowerCase().split('').map((c) => mapa[c] ?? c).join();
    final only = norm.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return only.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  }

  Future<List<Especie>> _sugerirEspeciesPorCientifico(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final slug = _slugify(q);

    try {
      final snap = await _db
          .collection('especies')
          .orderBy('slug')
          .startAt([slug])
          .endAt(['$slug\uf8ff'])
          .limit(15)
          .get();

      return snap.docs.map((d) => Especie.fromMap(d.data(), d.id)).toList();
    } catch (_) {
      try {
        final snap2 = await _db
            .collection('especies')
            .orderBy('nombre_cientifico')
            .startAt([q])
            .endAt(['$q\uf8ff'])
            .limit(15)
            .get();
        return snap2.docs.map((d) => Especie.fromMap(d.data(), d.id)).toList();
      } catch (_) {
        return [];
      }
    }
  }

  Future<void> _cargarTaxonomiaEspecie(String especieId) async {
    try {
      final doc = await _db.collection('especies').doc(especieId).get();
      if (!doc.exists) return;
      final m = doc.data()!;
      setState(() {
        _taxClase = (m['clase'] ?? '').toString();
        _taxOrden = (m['orden'] ?? '').toString();
        _taxFamilia = (m['familia'] ?? '').toString();

        _taxClaseCtrl.text = _taxClase ?? '';
        _taxOrdenCtrl.text = _taxOrden ?? '';
        _taxFamiliaCtrl.text = _taxFamilia ?? '';
      });
    } catch (_) {}
  }

  // === ESPECIE: aplicar selección del catálogo (como Municipio) ===
  void _aplicarEspecieSeleccionada(Especie item) async {
    _especieIdSel = item.id;

    _especieTexto = item.nombreCientifico;
    _especieCientCtrl.text = item.nombreCientifico;
    _especieComunCtrl.text =
    item.nombresComunes.isNotEmpty ? item.nombresComunes.first : '';

    _taxClase = (item.claseTax ?? '').toString();
    _taxOrden = (item.orden ?? '').toString();
    _taxFamilia = (item.familia ?? '').toString();

    _taxClaseCtrl.text = _taxClase ?? '';
    _taxOrdenCtrl.text = _taxOrden ?? '';
    _taxFamiliaCtrl.text = _taxFamilia ?? '';

    if (mounted && _especieInputCtrl != null) {
      try {
        _especieInputCtrl!.text = _especieTexto;
        _especieInputCtrl!.selection = TextSelection.fromPosition(
          TextPosition(offset: _especieInputCtrl!.text.length),
        );
      } catch (_) {}
    }

    if (mounted) {
      setState(() {});
      FocusScope.of(context).unfocus();
    }
  }

  // =========================
  // AUTOCOMPLETE: MUNICIPIO
  // =========================
  Future<List<PlaceHit>> _buscarMunicipios(
      String text, String? estadoCodigo) async {
    try {
      final q = _toBuscable(text);
      Query<Map<String, dynamic>> base = _db.collection('municipios');

      if ((_estadoAutoCtrl.text.trim()).isNotEmpty) {
        final estadoB = _toBuscable(_estadoAutoCtrl.text);
        base = base.where('buscable_estado', isEqualTo: estadoB);
      }

      final snap = await base
          .orderBy('buscable')
          .startAt([q])
          .endAt(['$q\uf8ff'])
          .limit(20)
          .get();

      return snap.docs.map((d) {
        final m = d.data();
        return PlaceHit(
          codigo: (m['id'] ?? d.id).toString(),
          nombre: (m['nombre'] ?? '').toString(),
          estado: (m['estado'] ?? '').toString(),
          region: (m['region'] ?? '').toString(),
          distrito: (m['distrito'] ?? '').toString(),
          lat: (m['lat'] is num) ? (m['lat'] as num).toDouble() : null,
          lng: (m['lng'] is num) ? (m['lng'] as num).toDouble() : null,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // === Normalización de nombre científico ===
  String _canonNombreCientifico(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return t;
    final parts = t.split(' ');
    if (parts.isEmpty) return t;
    parts[0] = parts[0].isEmpty
        ? parts[0]
        : (parts[0][0].toUpperCase() + parts[0].substring(1).toLowerCase());
    for (int i = 1; i < parts.length; i++) {
      parts[i] = parts[i].toLowerCase();
    }
    return parts.join(' ');
  }

  /// Si solo viene el género (o no está en catálogo), derivamos "Genero sp."
  String _derivarGeneroSp(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return t;
    final gen = t.split(' ').first;
    if (gen.isEmpty) return t;
    final canonGen =
        gen[0].toUpperCase() + gen.substring(1).toLowerCase();
    return '$canonGen sp.';
  }

  String _slugEspecie(String s) => _slugify(s);

  // Normaliza: minúsculas y acentos básicos
  String _normalize(String s) {
    final lower = s.toLowerCase();
    const mapa = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n'
    };
    return lower.split('').map((c) => mapa[c] ?? c).join();
  }

  // "buscable" (MAYÚSCULAS sin acentos, colapsa espacios)
  String _toBuscable(String s) {
    const mapa = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n'
    };
    final up = s
        .trim()
        .toUpperCase()
        .split('')
        .map((c) => mapa[c.toLowerCase()]?.toUpperCase() ?? c)
        .join();
    final only = up.replaceAll(RegExp(r'[^A-Z0-9 ]+'), ' ');
    return only.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // Popup consistente para listas de opciones (si lo llegaras a usar)
  Widget _popup(BuildContext context, {required Widget child}) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280, minWidth: 320),
          child: child,
        ),
      ),
    );
  }
}

// ===== Pequeño helper para “span” responsive sin dependencias =====
class _SpanChild {
  final Widget child;
  final int Function(int cols)? span;
  _SpanChild({required this.child, this.span});
}
