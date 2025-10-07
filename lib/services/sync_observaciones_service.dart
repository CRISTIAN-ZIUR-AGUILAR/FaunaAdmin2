// lib/services/sync_observaciones_service.dart
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:faunadmin2/services/local_file_storage.dart';
import 'package:faunadmin2/services/foto_service.dart';
import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/providers/observacion_provider.dart';

// Sesión Firebase
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:faunadmin2/providers/auth_provider.dart';
// (Importada pero no usamos lógica extra; no tocamos otros archivos)
import 'package:faunadmin2/services/permisos_service.dart';

/// (Opcional) Proyecto por defecto para fallback.
/// Déjalo como null si NO quieres usarlo.
const String? kDefaultProyectoId = null;

class SyncResult {
  final int uploadedCount;
  final int skippedCount;
  final int failedCount;

  const SyncResult({
    required this.uploadedCount,
    required this.skippedCount,
    required this.failedCount,
  });
}

class SyncObservacionesService {
  final _local = LocalFileStorage.instance;
  final _fotoSvc = FotoService();

  /// Sube observaciones locales (carpetas en FaunaLocal/observaciones/*) del usuario actual.
  ///
  /// Flujo:
  /// 1) Valida usuario logueado; en Web no corre (no hay FS nativo).
  /// 2) Por cada carpeta con meta.json en status READY:
  ///    - Construye Observacion en **borrador** (requisito backend).
  ///    - Crea sin proyecto o en proyecto (fallback: seleccionado; luego por defecto).
  ///    - Sube fotos (Storage) y crea espejo en `observaciones/{id}/media`.
  ///    - Parchea `media_count` y `media_urls`.
  ///    - (Opcional) Enviar a pendiente si meta['enviar_revision'] == true.
  ///    - Marca SYNCED y (opcional) borra carpeta local.
  Future<SyncResult> syncPending({
    required BuildContext context,
    bool deleteLocalAfterUpload = true,
    void Function(String msg)? onLog,
    void Function(int done, int total)? onProgress,
  }) async {
    if (kIsWeb) {
      onLog?.call('[SYNC] La sincronización offline no está disponible en Web.');
      return const SyncResult(uploadedCount: 0, skippedCount: 0, failedCount: 0);
    }

    // ✅ Usuario actual
    final uidActual = fb.FirebaseAuth.instance.currentUser?.uid;
    if (uidActual == null) {
      onLog?.call('[SYNC][ERROR] Usuario no autenticado; abortando.');
      return const SyncResult(uploadedCount: 0, skippedCount: 0, failedCount: 0);
    }

    // ✅ Proyecto seleccionado para fallback (si procede)
    final auth = context.read<AuthProvider>();
    final proyectoSeleccionado = auth.selectedRolProyecto?.idProyecto;

    // Lista de carpetas locales
    final dirs = await _local.listarObservaciones();
    final total = dirs.length;
    int done = 0, skipped = 0, failed = 0;

    onLog?.call('[SYNC] Encontradas $total carpetas locales para sincronizar');

    // Helper para leer y castear campos del meta
    T? pick<T>(Map<String, dynamic> m, String k) {
      final v = m[k];
      if (v == null) return null;
      if (T == double) {
        if (v is num) return v.toDouble() as T;
        if (v is String) return double.tryParse(v) as T?;
      }
      if (T == int) {
        if (v is num) return v.toInt() as T;
        if (v is String) return int.tryParse(v) as T?;
      }
      if (T == DateTime) {
        if (v is String) return DateTime.tryParse(v) as T?;
        if (v is int) return DateTime.fromMillisecondsSinceEpoch(v) as T;
      }
      return v as T?;
    }

    for (final carpeta in dirs) {
      try {
        final meta = await _local.leerMeta(carpeta);

        if (meta == null) {
          skipped++;
          onLog?.call('[SYNC][SKIP] meta.json ausente → ${carpeta.path}');
          onProgress?.call(done + skipped + failed, total);
          continue;
        }

        // Solo el propietario puede subir su carpeta (si meta lo trae)
        final uidAutorCarpeta = (meta['uid_usuario'] ?? '').toString();
        if (uidAutorCarpeta.isNotEmpty && uidAutorCarpeta != uidActual) {
          skipped++;
          onLog?.call('[SYNC][SKIP] carpeta de otro usuario ($uidAutorCarpeta) → ${carpeta.path}');
          onProgress?.call(done + skipped + failed, total);
          continue;
        }

        // Ya sincronizada o con remote_id
        final status = (meta['status'] ?? '').toString().toUpperCase();
        final remoteId = (meta['remote_id'] ?? '').toString();
        if (status == 'SYNCED' || remoteId.isNotEmpty) {
          skipped++;
          onLog?.call('[SYNC][SKIP] ya sincronizada → ${carpeta.path}');
          onProgress?.call(done + skipped + failed, total);
          continue;
        }

        // Archivos locales de la carpeta
        final files = await _local.listarFotos(carpeta);
        if (files.isEmpty) {
          skipped++;
          onLog?.call('[SYNC][SKIP] sin fotos → ${carpeta.path}');
          onProgress?.call(done + skipped + failed, total);
          continue;
        }

        // Armar Observación en BORRADOR (requisito backend)
        final idProyectoMeta = pick<String>(meta, 'id_proyecto');
        final obs = Observacion(
          id: null,
          idProyecto: idProyectoMeta,
          uidUsuario: uidActual,
          estado: EstadosObs.borrador, // 👈 clave para evitar obs_invalid_state
          fechaCaptura:   pick<DateTime>(meta, 'fecha_captura'),
          edadAproximada: pick<int>(meta, 'edad_aproximada'),
          especieNombre:  pick<String>(meta, 'especie_nombre'),
          especieId:      pick<String>(meta, 'especie_id'),
          lugarNombre:    pick<String>(meta, 'lugar_nombre'),
          lugarTipo:      pick<String>(meta, 'lugar_tipo'),
          municipio:      pick<String>(meta, 'municipio'),
          estadoPais:     pick<String>(meta, 'estado_pais'),
          lat:            pick<double>(meta, 'lat'),
          lng:            pick<double>(meta, 'lng'),
          altitud:        pick<double>(meta, 'altitud'),
          notas:          pick<String>(meta, 'notas'),
          aiStatus: pick<String>(meta, 'ai_status') ?? 'idle',
          aiTopSuggestions: const [],
          condicionAnimal: pick<String>(meta, 'condicion_animal') ?? EstadosAnimal.vivo,
          rastroTipo:      pick<String>(meta, 'rastro_tipo'),
          rastroDetalle:   pick<String>(meta, 'rastro_detalle'),
          mediaCount: null,
        );

        final prov = context.read<ObservacionProvider>();

        // === Intento 1: crear según venga (con/sin proyecto) ===
        String? newId;
        try {
          if (obs.idProyecto == null || obs.idProyecto!.isEmpty) {
            newId = await prov.crearSinProyecto(data: obs, toast: false);
          } else {
            newId = await prov.crearEnProyecto(
              proyectoId: obs.idProyecto!,
              data: obs,
              toast: false,
            );
          }
        } catch (e) {
          onLog?.call('[SYNC][ERROR] crear observación: $e');
          newId = null;
        }

        // === Fallback 1: proyecto seleccionado ===
        if (newId == null &&
            (obs.idProyecto == null || obs.idProyecto!.isEmpty) &&
            (proyectoSeleccionado != null && proyectoSeleccionado.isNotEmpty)) {
          onLog?.call('[SYNC] Reintentando en proyecto seleccionado: $proyectoSeleccionado');
          try {
            newId = await prov.crearEnProyecto(
              proyectoId: proyectoSeleccionado!,
              data: obs,
              toast: false,
            );
          } catch (e) {
            onLog?.call('[SYNC][ERROR] reintento en proyecto $proyectoSeleccionado: $e');
            newId = null;
          }
        }

        // === Fallback 2: proyecto por defecto (opcional) ===
        if (newId == null &&
            (obs.idProyecto == null || obs.idProyecto!.isEmpty) &&
            (proyectoSeleccionado == null || proyectoSeleccionado.isEmpty) &&
            (kDefaultProyectoId != null && kDefaultProyectoId!.isNotEmpty)) {
          onLog?.call('[SYNC] Reintentando en proyecto por defecto: $kDefaultProyectoId');
          try {
            newId = await prov.crearEnProyecto(
              proyectoId: kDefaultProyectoId!,
              data: obs,
              toast: false,
            );
          } catch (e) {
            onLog?.call('[SYNC][ERROR] reintento en proyecto por defecto $kDefaultProyectoId: $e');
            newId = null;
          }
        }

        // Si no pudo crearse, continuar con la siguiente
        if (newId == null) {
          skipped++;
          onLog?.call('[SYNC][SKIP] ${carpeta.path} → no se pudo crear (sin/proyecto/fallback).');
          onProgress?.call(done + skipped + failed, total);
          continue;
        }

        // === Subir fotos a Storage y crear espejo en media ===
        // Contexto final para metadata legible
        // === Subir fotos a Storage y crear espejo en media ===
// Contexto final para metadata legible
        final proyectoFinal = (obs.idProyecto != null && obs.idProyecto!.isNotEmpty)
            ? obs.idProyecto!
            : ((proyectoSeleccionado != null && proyectoSeleccionado.isNotEmpty)
            ? proyectoSeleccionado!
            : (kDefaultProyectoId ?? ''));
        final nombreUsuario = uidActual; // usa displayName si lo manejas
        final contextoTipo = (proyectoFinal.isEmpty) ? 'RESIDENCIA' : 'PROYECTO_INVESTIGACION';
        final contextoNombre = (proyectoFinal.isEmpty)
            ? (obs.lugarNombre ?? 'Sin nombre')
            : 'Proyecto $proyectoFinal';

        try {
          // 👇 Tipado explícito: List<Map<String, dynamic>>
          final List<Map<String, dynamic>> subidas = (await _fotoSvc.subirVarias(
            fotografoUid: uidActual,
            fotografoNombre: nombreUsuario,
            contextoTipo: contextoTipo,
            contextoNombre: contextoNombre,
            observacionId: newId,
            archivos: files,
            observaciones: obs.notas,
          )).cast<Map<String, dynamic>>();

          // 👇 Extrae URLs con null-safety (solo strings válidas)
          final List<String> urls = subidas
              .map((m) => m['url'])
              .whereType<String>()
              .toList();

          await prov.patch(
            observacionId: newId,
            patch: {
              'media_count': subidas.length,
              'media_urls': urls,
            },
            toast: false,
          );
        } catch (e) {
          onLog?.call('[SYNC] Obs $newId creada, pero falló subida de fotos: $e');
        }


        // === (Opcional) Enviar a pendiente si meta['enviar_revision'] == true ===
        final enviarRevision = (meta['enviar_revision'] == true);
        if (enviarRevision) {
          final ok = await prov.enviarAPendiente(newId);
          if (!ok) {
            onLog?.call('[SYNC] No se pudo enviar a revisión; quedó en borrador.');
          } else {
            onLog?.call('[SYNC] Enviada a revisión.');
          }
        }

        // === Marcar local como SYNCED y limpiar ===
        await _local.actualizarStatus(carpeta, 'SYNCED', remoteId: newId);
        if (deleteLocalAfterUpload) {
          try {
            await _local.eliminarObservacionDir(carpeta);
          } catch (_) {
            // ignorar fallo de borrado local
          }
        }

        done++;
        onProgress?.call(done + skipped + failed, total);
      } catch (e) {
        failed++;
        onLog?.call('[SYNC][FAIL] ${carpeta.path}: $e');
        onProgress?.call(done + skipped + failed, total);
      }
    }

    return SyncResult(uploadedCount: done, skippedCount: skipped, failedCount: failed);
  }
}
