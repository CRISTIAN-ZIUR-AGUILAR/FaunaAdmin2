// lib/services/auto_sync_observaciones_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/providers/observacion_provider.dart';
import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/services/local_file_storage.dart';
import 'package:faunadmin2/services/foto_service.dart';
import 'package:faunadmin2/services/permisos_service.dart';

class AutoSyncObservacionesService {
  AutoSyncObservacionesService._();
  static final AutoSyncObservacionesService instance =
  AutoSyncObservacionesService._();

  // OJO: sin genérico, para que acepte List<ConnectivityResult> o ConnectivityResult
  StreamSubscription? _connSub;

  bool _isSyncRunning = false;
  DateTime? _lastRunAt;

  /// Inicia el watcher de conectividad
  void start(BuildContext context) {
    if (kIsWeb) {
      debugPrint('[AUTO-SYNC] No disponible en Web.');
      return;
    }
    if (_connSub != null) {
      // Ya estaba escuchando
      debugPrint('[AUTO-SYNC] Watcher ya estaba iniciado, se reutiliza.');
      return;
    }

    final connectivity = Connectivity();
    debugPrint('[AUTO-SYNC] Iniciando watcher de conectividad...');

    // 🔹 Disparo inicial: si ya hay red cuando se llama start(), intentamos sincronizar una vez
    connectivity.checkConnectivity().then((result) async {
      final hasNet = _hasConnectionDynamic(result);
      debugPrint('[AUTO-SYNC] Estado inicial de conectividad: $result (hasNet=$hasNet)');
      if (!hasNet) return;

      final auth = _safeReadAuth(context);
      if (auth == null || auth.usuario == null) {
        debugPrint('[AUTO-SYNC] (inicio) Sin usuario autenticado; no se sincroniza.');
        return;
      }

      await _maybeRunSync(context, auth);
    }).catchError((e) {
      debugPrint('[AUTO-SYNC] Error en checkConnectivity inicial: $e');
    });

    // 🔹 Listener a cambios de conectividad
    _connSub = connectivity.onConnectivityChanged.listen(
          (result) async {
        debugPrint('[AUTO-SYNC] Conectividad cambiada: $result');

        final hasNet = _hasConnectionDynamic(result);
        if (!hasNet) {
          debugPrint('[AUTO-SYNC] Sin red (wifi/mobile), no se sincroniza.');
          return;
        }

        final auth = _safeReadAuth(context);
        if (auth == null || auth.usuario == null) {
          debugPrint('[AUTO-SYNC] Sin usuario autenticado; no se sincroniza.');
          return;
        }

        await _maybeRunSync(context, auth);
      },
      onError: (e) {
        debugPrint('[AUTO-SYNC][ERROR] $e');
      },
    );
  }

  /// Detiene el watcher
  Future<void> stop() async {
    await _connSub?.cancel();
    _connSub = null;
    debugPrint('[AUTO-SYNC] Watcher detenido.');
  }

  // =========================================================
  // Helpers internos
  // =========================================================

  /// Soporta tanto ConnectivityResult como List<ConnectivityResult>
  bool _hasConnectionDynamic(dynamic result) {
    // Caso clásico: un solo ConnectivityResult
    if (result is ConnectivityResult) {
      return result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile;
    }

    // Caso nuevo: lista de ConnectivityResult
    if (result is List<ConnectivityResult>) {
      return result.any(
            (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile,
      );
    }

    // Cualquier otra cosa: asumimos sin red
    return false;
  }

  AuthProvider? _safeReadAuth(BuildContext context) {
    try {
      return context.read<AuthProvider>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _maybeRunSync(
      BuildContext context,
      AuthProvider auth,
      ) async {
    if (_isSyncRunning) {
      debugPrint('[AUTO-SYNC] Ya hay un sync en curso, se omite.');
      return;
    }

    // Throttle: no más de una vez cada 2 minutos
    final now = DateTime.now();
    if (_lastRunAt != null &&
        now.difference(_lastRunAt!) < const Duration(minutes: 2)) {
      debugPrint('[AUTO-SYNC] Se ejecutó hace poco; esperamos un poco más.');
      return;
    }

    _isSyncRunning = true;
    _lastRunAt = now;

    try {
      final result = await _runAutoSyncWithPublicarLocal(
        context: context,
        auth: auth,
        deleteLocalAfterUpload: true,
        onLog: (m) => debugPrint('[AUTO-SYNC] $m'),
      );
      debugPrint('[AUTO-SYNC] Resultado: $result');

      // Intentamos obtener el ScaffoldMessenger de este contexto
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        debugPrint(
          '[AUTO-SYNC] No hay ScaffoldMessenger disponible; no se muestra aviso.',
        );
      } else {
        // Avisar solo si hay algo relevante
        if (result.uploadedCount > 0) {
          final msg = result.uploadedCount == 1
              ? 'Se subió 1 observación local a la nube.'
              : 'Se subieron ${result.uploadedCount} observaciones locales a la nube.';

          messenger.showSnackBar(
            SnackBar(content: Text(msg)),
          );
        } else if (result.failedCount > 0) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Algunas observaciones locales no pudieron subirse. '
                    'Revisa las observaciones locales más tarde.',
              ),
            ),
          );
        }
      }
    } catch (e, st) {
      debugPrint('[AUTO-SYNC][ERROR] $e\n$st');
    } finally {
      _isSyncRunning = false;
    }
  }
}

// =========================================================
// Rutina nueva: auto-sync usando la misma lógica de publicarLocal
// pero respetando permisos/rol/proyecto y dueño de la carpeta
// =========================================================

class _AutoSyncResult {
  final int uploadedCount;
  final int failedCount;

  const _AutoSyncResult({
    required this.uploadedCount,
    required this.failedCount,
  });

  @override
  String toString() =>
      'AutoSyncResult(uploaded: $uploadedCount, failed: $failedCount)';
}

Future<_AutoSyncResult> _runAutoSyncWithPublicarLocal({
  required BuildContext context,
  required AuthProvider auth,
  bool deleteLocalAfterUpload = true,
  void Function(String msg)? onLog,
}) async {
  final local = LocalFileStorage.instance;
  final dirs = await local.listarObservaciones();

  if (dirs.isEmpty) {
    onLog?.call('No hay observaciones locales por sincronizar.');
    return const _AutoSyncResult(uploadedCount: 0, failedCount: 0);
  }

  ObservacionProvider prov;
  try {
    prov = context.read<ObservacionProvider>();
  } catch (_) {
    onLog?.call(
      'No se encontró ObservacionProvider en el contexto; se cancela auto-sync.',
    );
    return _AutoSyncResult(uploadedCount: 0, failedCount: dirs.length);
  }

  final fotoSvc = FotoService();
  final permisos = PermisosService(auth);

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  String? _nz(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  int uploaded = 0;
  int failed = 0;

  for (final dir in dirs) {
    try {
      final meta = await local.leerMeta(dir);
      if (meta == null) {
        onLog?.call('Carpeta sin meta.json: ${dir.path}');
        failed++;
        continue;
      }

      final m = meta;

      // 🔹 0.1) Status local: saltar cosas marcadas como no subibles
      final statusUpper = (m['status'] ?? '').toString().toUpperCase();
      if (statusUpper == 'SYNCED' ||
          statusUpper == 'OTRO_USUARIO' ||
          statusUpper.startsWith('ERROR')) {
        onLog?.call(
          'Saltando ${dir.path} por status="$statusUpper" (ya procesada / con error previo).',
        );
        continue;
      }

      // 0) UID actual y UID dueño de la carpeta (meta)
      final uidActual = (auth.uid ?? '').trim();
      if (uidActual.isEmpty) {
        onLog?.call(
          'Sin uid actual para carpeta ${dir.path}, se omite esta observación.',
        );
        failed++;
        continue;
      }

      final uidMeta = (m['uid_usuario'] ?? '').toString().trim();

      // Si la carpeta tiene dueño y no coincide con el usuario actual, NO se sube
      if (uidMeta.isNotEmpty && uidMeta != uidActual) {
        try {
          await local.patchMeta(dir, {
            'status': 'OTRO_USUARIO',
            'error_msg':
            'Observación creada por otro usuario ($uidMeta). No se puede subir con la cuenta actual ($uidActual).',
          });
        } catch (_) {
          // ignoramos errores de patch local
        }

        onLog?.call(
          'Carpeta de otro usuario (meta=$uidMeta, actual=$uidActual), se omite: ${dir.path}',
        );
        failed++;
        continue;
      }

      // Si no hay uid en meta, se lo asignamos al usuario actual para futuras corridas
      if (uidMeta.isEmpty) {
        try {
          await local.patchMeta(dir, {
            'uid_usuario': uidActual,
          });
        } catch (_) {
          // si falla, seguimos de todos modos
        }
      }

      // 1) Proyecto (solo desde meta para auto-sync)
      final idProyectoLocal = (m['id_proyecto'] ?? '').toString().trim();
      final String? idProyecto =
      idProyectoLocal.isNotEmpty ? idProyectoLocal : null;

      final rolAlCrear = (m['rol_al_crear'] ?? 'DESCONOCIDO').toString();
      onLog?.call(
        'Procesando ${dir.path} (rol_al_crear=$rolAlCrear, idProyecto=${idProyecto ?? 'SIN_PROYECTO'})',
      );

      // 1.5) Validar permisos según contexto (sin proyecto / con proyecto)
      final bool isSinProyecto = idProyecto == null || idProyecto.isEmpty;
      final bool canCreateHere = isSinProyecto
          ? permisos.canCreateObservationSinProyecto
          : permisos.canCreateObservationInProject(idProyecto);

      if (!canCreateHere) {
        onLog?.call(
          'Saltando ${dir.path}: sin permisos para crear en '
              '${isSinProyecto ? 'SIN_PROYECTO' : 'proyecto $idProyecto'} '
              'con el rol actual.',
        );

        // Marcamos error de permisos para no intentarlo en cada corrida
        try {
          await local.patchMeta(dir, {
            'status': 'ERROR_PERMISOS',
            'error_msg':
            'El rol actual no tiene permisos para crear en este contexto.',
          });
        } catch (_) {
          // ignore
        }

        failed++;
        continue;
      }

      // 2) Datos especie / estado
      final cient =
      _nz(m['especie_nombre_cientifico'] ?? m['especie_nombre']);
      final comun = _nz(m['especie_nombre_comun']);

      String estado = (m['estado'] ?? EstadosObs.borrador)
          .toString()
          .toLowerCase();

      // 🔹 Opcional: si quieres que TODO lo que se suba se vaya como "pendiente",
      // descomenta la siguiente línea:
      // if (estado == 'borrador') estado = EstadosObs.pendiente;

      // 3) Construimos Observacion igual que en _publicarLocal
      final obs = Observacion(
        id: null,
        idProyecto: idProyecto,
        uidUsuario: uidActual,
        estado: estado,
        fechaCaptura: _parseDate(m['fecha_captura']),
        createdAt: _parseDate(m['created_local_at']),
        updatedAt:
        _parseDate(m['updated_local_at'] ?? m['ultima_modificacion']),
        especieId: _nz(m['especie_id']),
        especieNombreCientifico: cient,
        especieNombreComun: comun,
        lugarNombre: _nz(m['lugar_nombre']),
        lugarTipo: _nz(m['lugar_tipo']),
        municipio: _nz(m['municipio']),
        estadoPais: _nz(m['estado_pais'] ?? m['ubic_estado']),
        lat: _toDouble(m['lat']),
        lng: _toDouble(m['lng']),
        altitud: _toDouble(m['altitud']),
        notas: _nz(m['notas']),
        aiStatus: _nz(m['ai_status']) ?? 'idle',
        condicionAnimal:
        _nz(m['condicion_animal']) ?? EstadosAnimal.vivo,
        rastroTipo: _nz(m['rastro_tipo']),
        rastroDetalle: _nz(m['rastro_detalle']),
        mediaCount: null,
      );

      // 4) Crear documento en Firestore vía ObservacionProvider
      String? newId;
      if (obs.idProyecto == null) {
        newId = await prov.crearSinProyecto(data: obs);
      } else {
        newId = await prov.crearEnProyecto(
          proyectoId: obs.idProyecto!,
          data: obs,
        );
      }
      if (newId == null || newId.isEmpty) {
        throw 'No se pudo crear la observación en la nube.';
      }

      // 5) Patch de taxonomía (si viene)
      try {
        await prov.patch(
          observacionId: newId,
          patch: {
            if (_nz(m['taxo_clase']) != null)
              'taxo_clase': _nz(m['taxo_clase']),
            if (_nz(m['taxo_orden']) != null)
              'taxo_orden': _nz(m['taxo_orden']),
            if (_nz(m['taxo_familia']) != null)
              'taxo_familia': _nz(m['taxo_familia']),
          },
          toast: false,
        );
      } catch (_) {
        // silencioso en auto-sync
      }

      // 6) Subir fotos
      final fotos = await local.listarFotos(dir);
      if (fotos.isNotEmpty) {
        final contextoTipo = (idProyecto == null || idProyecto.isEmpty)
            ? 'RESIDENCIA'
            : 'PROYECTO_INVESTIGACION';
        final contextoNombre = (idProyecto == null || idProyecto.isEmpty)
            ? (_nz(m['lugar_nombre']) ?? 'Sin nombre')
            : 'Proyecto $idProyecto';

        final subidas = await fotoSvc.subirVarias(
          fotografoUid: uidActual,
          fotografoNombre: uidActual,
          contextoTipo: contextoTipo,
          contextoNombre: contextoNombre,
          observacionId: newId,
          archivos: fotos,
        );

        final coverUrl = subidas.isNotEmpty ? subidas.first.url : null;

        await prov.patch(
          observacionId: newId,
          patch: {
            'media_count': subidas.length,
            'media_urls':
            subidas.map((m) => m.url).whereType<String>().toList(),
            if (coverUrl != null) 'cover_url': coverUrl,
            if (subidas.isNotEmpty) 'primary_media_id': subidas.first.id,
            'updatedAt': DateTime.now(),
          },
          toast: false,
        );
      }

      // 7) Borrar carpeta local o marcar como SYNCED
      if (deleteLocalAfterUpload) {
        try {
          await local.eliminarObservacionDir(dir);
        } catch (_) {
          // ignore
        }
      } else {
        try {
          await local.patchMeta(dir, {
            'status': 'SYNCED',
            'nube_observacion_id': newId,
          });
        } catch (_) {
          // ignore
        }
      }

      uploaded++;
      onLog?.call('OK: ${dir.path}');
    } catch (e) {
      failed++;
      onLog?.call('Error subiendo ${dir.path}: $e');

      // 🔹 Marcamos error genérico para que no martillee eternamente
      try {
        await local.patchMeta(dir, {
          'status': 'ERROR_SYNC',
          'error_msg': e.toString(),
        });
      } catch (_) {
        // ignore
      }
    }
  }

  return _AutoSyncResult(uploadedCount: uploaded, failedCount: failed);
}
