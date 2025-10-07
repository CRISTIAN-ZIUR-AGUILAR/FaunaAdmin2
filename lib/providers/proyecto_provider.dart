// lib/providers/proyecto_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:faunadmin2/models/proyecto.dart';
import 'package:faunadmin2/models/usuario.dart';
import 'package:faunadmin2/services/firestore_service.dart';

// NUEVO: errores tipados desde el service
import 'package:faunadmin2/utils/app_error.dart';
// Opcional (si lo tienes): limpia prefijos "Exception:" / "Error:"
import 'package:faunadmin2/utils/ui_messages.dart' show errMsg;

/// Códigos de resultado estándar para acciones del provider.
class ProyResultCode {
  static const ok              = 'ok';
  static const ownerConflict   = 'owner_conflict';    // Intento de usar al dueño
  static const collabConflict  = 'collab_conflict';   // Al asignar SUPERVISOR pero ya es COLAB
  static const supConflict     = 'sup_conflict';      // Al asignar COLAB pero ya es SUPERVISOR
  static const alreadyAssigned = 'already_assigned';  // Ya estaba asignado (idempotente/legacy)
  static const error           = 'error';
}

class ProyectoProvider extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();

  // ----- Stream de proyectos -----
  StreamSubscription<List<Proyecto>>? _sub;
  bool _loadedOnce = false;

  List<Proyecto> _proyectos = [];
  List<Proyecto> get proyectos => _proyectos;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Estado para operaciones puntuales (asignar/quitar, etc.)
  bool _actionInProgress = false;
  bool get actionInProgress => _actionInProgress;

  /// Mensajes centralizados para la UI (snackbars / banners)
  String? _lastMessage;
  String? get lastMessage => _lastMessage;

  String? _lastError;
  String? get lastError => _lastError;

  // ===============================
  //         STREAM PROYECTOS
  // ===============================

  /// Idempotente: inicia (una sola vez) el stream de proyectos.
  void loadProyectos() {
    if (_loadedOnce && _sub != null) return;

    _isLoading = true;
    notifyListeners();

    _sub?.cancel();
    _sub = _firestore.streamProyectos().listen((lista) {
      _proyectos = lista;
      _isLoading = false;
      _loadedOnce = true;
      notifyListeners();
    }, onError: (err) {
      _isLoading = false;
      _setError('No se pudieron cargar los proyectos: ${errMsg(err)}');
    });
  }

  /// Limpia estado (útil en signOut o al cambiar de espacio)
  void clear() {
    _sub?.cancel();
    _sub = null;
    _loadedOnce = false;
    _proyectos = [];
    _isLoading = false;
    _actionInProgress = false;
    _lastMessage = null;
    _lastError = null;
    notifyListeners();
  }

  /// Limpia mensajes informativos/errores (para la UI)
  void resetStatus() {
    _lastMessage = null;
    _lastError = null;
    notifyListeners();
  }

  // ===============================
  //           CRUD PROYECTO
  // ===============================

  Future<String> addProyecto(Proyecto p, {required String uidDueno}) async {
    _isLoading = true;
    resetStatus();
    notifyListeners();
    try {
      final id = await _firestore.createProyecto(p, uidDueno: uidDueno);
      _setInfo('Proyecto creado');
      return id;
    } catch (e) {
      _setError('Error al crear proyecto: ${errMsg(e)}');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateProyecto(Proyecto p) async {
    _isLoading = true;
    resetStatus();
    notifyListeners();
    try {
      await _firestore.updateProyecto(p);
      _setInfo('Proyecto actualizado');
    } catch (e) {
      _setError('Error al actualizar proyecto: ${errMsg(e)}');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteProyecto(String id) async {
    _isLoading = true;
    resetStatus();
    notifyListeners();
    try {
      await _firestore.deleteProyecto(id);
      _setInfo('Proyecto eliminado');
    } catch (e) {
      _setError('Error al eliminar proyecto: ${errMsg(e)}');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // =========================================================
  //           ASIGNACIONES / SUPERVISORES (URP)
  // =========================================================

  /// Stream de usuarios con estatus 'aprobado' (para dropdowns).
  Stream<List<Usuario>> streamUsuariosAprobados() {
    return _firestore.streamUsuariosAprobados();
  }

  /// Stream de Supervisores asignados a un proyecto (resuelve a Usuario).
  Stream<List<Usuario>> streamSupervisoresDeProyecto(String proyectoId) {
    return _firestore.streamSupervisoresDeProyecto(proyectoId);
  }

  /// Asigna supervisor a un proyecto. Devuelve un código de resultado.
  ///
  /// Códigos posibles:
  /// - ok
  /// - ownerConflict (cuando el uid es el mismo dueño)
  /// - collabConflict (cuando ya es COLABORADOR)
  /// - error (cualquier otra excepción)
  ///
  /// `force` permite retirar el rol conflictivo y completar el cambio en un solo paso.
  Future<String> asignarSupervisor({
    required String proyectoId,
    required String uidSupervisor,
    required String uidAdmin,
    bool force = false,
  }) async {
    if (_actionInProgress) return ProyResultCode.error;
    _actionInProgress = true;
    resetStatus();
    notifyListeners();

    try {
      await _firestore.asignarSupervisorAProyecto(
        proyectoId: proyectoId,
        uidSupervisor: uidSupervisor,
        uidAdmin: uidAdmin,
        force: force,
      );
      _setInfo('Supervisor asignado');
      return ProyResultCode.ok;
    } catch (e) {
      // Preferimos errores tipados
      if (e is AppError) {
        switch (e.code) {
          case ProyResultCode.ownerConflict:
            _setError('El dueño no puede ser supervisor de su propio proyecto.');
            return ProyResultCode.ownerConflict;
          case ProyResultCode.collabConflict:
            _setError('El usuario ya es COLABORADOR en este proyecto.\n'
                'Quítalo como colaborador o usa “forzar cambio” para ascenderlo.');
            return ProyResultCode.collabConflict;
          default:
            _setError(e.message);
            return ProyResultCode.error;
        }
      }

      // Fallback legacy por texto
      final msg = (e.toString()).toLowerCase();
      if (msg.contains('dueño') && msg.contains('supervisor')) {
        _setError('El dueño no puede ser supervisor de su propio proyecto.');
        return ProyResultCode.ownerConflict;
      }
      if (msg.contains('colaborador') && msg.contains('supervisor')) {
        _setError('El usuario ya es COLABORADOR en este proyecto.\n'
            'Primero quítalo como colaborador o usa “forzar cambio” para ascenderlo.');
        return ProyResultCode.collabConflict;
      }
      if (msg.contains('collab_conflict')) {
        _setError('Conflicto: actualmente es COLABORADOR. '
            'Puedes retirarlo y asignarlo como SUPERVISOR.');
        return ProyResultCode.collabConflict;
      }

      _setError('No se pudo asignar el supervisor: ${errMsg(e)}');
      return ProyResultCode.error;
    } finally {
      _actionInProgress = false;
      notifyListeners();
    }
  }

  /// Quita supervisor de un proyecto. Devuelve un código de resultado.
  Future<String> quitarSupervisor({
    required String proyectoId,
    required String uidSupervisor,
  }) async {
    if (_actionInProgress) return ProyResultCode.error;
    _actionInProgress = true;
    resetStatus();
    notifyListeners();

    try {
      await _firestore.quitarSupervisorDeProyecto(
        proyectoId: proyectoId,
        uidSupervisor: uidSupervisor,
      );
      _setInfo('Supervisor retirado');
      return ProyResultCode.ok;
    } catch (e) {
      _setError('No se pudo retirar el supervisor: ${errMsg(e)}');
      return ProyResultCode.error;
    } finally {
      _actionInProgress = false;
      notifyListeners();
    }
  }

  // =========================================================
  //           ASIGNACIONES / COLABORADORES (URP)
  // =========================================================

  /// Asigna colaborador al proyecto con mensajes de conflicto legibles.
  ///
  /// Códigos:
  /// - ok
  /// - ownerConflict (intento con el dueño)
  /// - supConflict (ya es SUPERVISOR en ese proyecto)
  /// - alreadyAssigned (ya estaba como colaborador — idempotente/legacy)
  /// - error
  Future<String> asignarColaborador({
    required String proyectoId,
    required String uidColaborador,
    String? asignadoBy,
  }) async {
    if (_actionInProgress) return ProyResultCode.error;
    _actionInProgress = true;
    resetStatus();
    notifyListeners();

    try {
      final res = await _firestore.asignarColaborador(
        proyectoId,
        uidColaborador,
        asignadoBy: asignadoBy,
      );

      if (res == 'owned') {
        _setError('No puedes agregar al DUEÑO como COLABORADOR.');
        return ProyResultCode.ownerConflict;
      }

      _setInfo('Colaborador agregado');
      return ProyResultCode.ok;
    } catch (e) {
      if (e is AppError) {
        switch (e.code) {
          case ProyResultCode.supConflict:
            _setError('Este usuario ya es SUPERVISOR en el proyecto. '
                'Primero retíralo como supervisor o gestiona su rol desde la pestaña de Supervisores.');
            return ProyResultCode.supConflict;
          default:
            _setError(e.message);
            return ProyResultCode.error;
        }
      }

      // Fallback legacy por texto
      final msg = (e.toString()).toLowerCase();
      if (msg.contains('supervisor') && msg.contains('colaborador')) {
        _setError('Este usuario ya es SUPERVISOR en el proyecto. '
            'Primero retíralo como supervisor o gestiona su rol desde la pestaña de Supervisores.');
        return ProyResultCode.supConflict;
      }

      if (msg.contains('ya existe') || msg.contains('duplicate') || msg.contains('already')) {
        _setInfo('Este usuario ya estaba como COLABORADOR.');
        return ProyResultCode.alreadyAssigned;
      }

      _setError('No se pudo agregar al colaborador: ${errMsg(e)}');
      return ProyResultCode.error;
    } finally {
      _actionInProgress = false;
      notifyListeners();
    }
  }

  /// Retira colaborador del proyecto.
  Future<String> retirarColaborador({
    required String proyectoId,
    required String uidColaborador,
  }) async {
    if (_actionInProgress) return ProyResultCode.error;
    _actionInProgress = true;
    resetStatus();
    notifyListeners();

    try {
      await _firestore.retirarColaborador(proyectoId, uidColaborador);
      _setInfo('Colaborador eliminado');
      return ProyResultCode.ok;
    } catch (e) {
      _setError('No se pudo retirar al colaborador: ${errMsg(e)}');
      return ProyResultCode.error;
    } finally {
      _actionInProgress = false;
      notifyListeners();
    }
  }

  // ===============================
  //            HELPERS
  // ===============================

  void _setInfo(String message) {
    _lastMessage = message;
    _lastError = null;
    if (kDebugMode) print('[ProyectoProvider] INFO: $message');
    notifyListeners();
  }

  void _setError(String message) {
    _lastError = message;
    _lastMessage = null;
    if (kDebugMode) print('[ProyectoProvider] ERROR: $message');
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}


