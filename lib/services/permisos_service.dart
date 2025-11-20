// lib/services/permisos_service.dart
// =============================================================
//  PermisosService
//  - Modelo de permisos basado en:
//      * Admin Único (flag usuarios.is_admin)
//      * URP (Usuario-Rol-Proyecto) seleccionada en AuthProvider
//  - Sin “roles globales” salvo Admin Único
//  - Dueño/Supervisor/Colaborador/Recolector: SIEMPRE por proyecto
//
//  SECCIONES:
//   1) Imports y encabezado
//   2) Contexto actual y getters base
//   3) Conjuntos de proyectos por rol
//   4) Capacidades de navegación (Proyectos)
//   5) Capacidades sobre Observaciones (crear/editar/moderar)
//   6) Alias y azúcares semánticos para UI
//   7) Menú/visibilidad UI
//   8) Helpers V2 (flujo nuevo de observaciones)
//   9) Compatibilidad FirestoreService
// =============================================================

import 'package:faunadmin2/models/rol.dart';
import 'package:faunadmin2/models/usuario_rol_proyecto.dart';
import 'package:faunadmin2/providers/auth_provider.dart';

/// Estados V2 normalizados (minúsculas) para evitar errores de casing.
class EstadosObsV2 {
  static const borrador = 'borrador';
  static const pendiente = 'pendiente';
  static const revisarNuevo = 'revisar_nuevo';
  static const rechazado = 'rechazado';
  static const aprobado = 'aprobado';
  static const archivado = 'archivado';
}

class PermisosService {
  // =============================================================
  // 1) Imports y encabezado
  // =============================================================
  final AuthProvider _auth;
  PermisosService(this._auth);

  // (Legacy/UI) Estados viejos en MAYÚSCULAS.
  static const String kPendiente = 'PENDIENTE';
  static const String kAprobado = 'APROBADO';
  static const String kRechazado = 'RECHAZADO';

  // =============================================================
  // 2) Contexto actual y getters base
  // =============================================================
  UsuarioRolProyecto? get _sel => _auth.selectedRolProyecto;

  int? get _rolActual => _sel?.idRol;
  String? get _proyectoActualId => _sel?.idProyecto;
  String? get _uidActual => _auth.usuario?.uid;

  bool get isLoggedIn => _auth.isLoggedIn;

  bool get isAdminUnico => _auth.usuario?.isAdmin == true;

  bool get isAdminGlobal => isAdminUnico;
  bool get isDuenoGlobal => false;

  bool get isAdminLike => isAdminUnico || isAdmin;

  bool get isAdmin => _rolActual == Rol.admin;
  bool get isSupervisor => _rolActual == Rol.supervisor;
  bool get isRecolector => _rolActual == Rol.recolector;

  bool get isDuenoEnContexto =>
      _rolActual == Rol.duenoProyecto &&
          _proyectoActualId != null &&
          _proyectoActualId!.isNotEmpty;

  bool get isColaboradorEnContexto =>
      _rolActual == Rol.colaborador &&
          _proyectoActualId != null &&
          _proyectoActualId!.isNotEmpty;

  bool get isSupervisorEnContexto =>
      _rolActual == Rol.supervisor &&
          _proyectoActualId != null &&
          _proyectoActualId!.isNotEmpty;

  bool get isRecolectorEnContexto =>
      _rolActual == Rol.recolector &&
          _proyectoActualId != null &&
          _proyectoActualId!.isNotEmpty;

  /// Recolector usando el rol pero SIN proyecto seleccionado
  bool get isRecolectorSinProyecto =>
      _rolActual == Rol.recolector &&
          (_proyectoActualId == null || _proyectoActualId!.isEmpty);

  bool _sameProject(String? idProyecto) =>
      idProyecto != null && idProyecto == _proyectoActualId;

  bool _isAuthor(String? uid) => uid != null && uid == _uidActual;

  // =============================================================
  // 3) Conjuntos de proyectos por rol
  // =============================================================
  Set<String> get projectIdsAsOwner => _auth.rolesProyectos
      .where(
          (r) => r.idRol == Rol.duenoProyecto && (r.idProyecto?.isNotEmpty ?? false))
      .map((r) => r.idProyecto!)
      .toSet();

  Set<String> get projectIdsAsSupervisor => _auth.rolesProyectos
      .where(
          (r) => r.idRol == Rol.supervisor && (r.idProyecto?.isNotEmpty ?? false))
      .map((r) => r.idProyecto!)
      .toSet();

  Set<String> get projectIdsAsColaborador => _auth.rolesProyectos
      .where(
          (r) => r.idRol == Rol.colaborador && (r.idProyecto?.isNotEmpty ?? false))
      .map((r) => r.idProyecto!)
      .toSet();

  Set<String> get projectIdsAsRecolector => _auth.rolesProyectos
      .where(
          (r) => r.idRol == Rol.recolector && (r.idProyecto?.isNotEmpty ?? false))
      .map((r) => r.idProyecto!)
      .toSet();

  bool get hasAnyCollaborator =>
      _auth.rolesProyectos.any((r) => r.idRol == Rol.colaborador);

  /// 🔹 NUEVO: ¿tiene algún URP de Recolector sin proyecto? (global)
  bool get hasRecolectorSinProyectoGlobal => _auth.rolesProyectos.any(
        (r) =>
    r.idRol == Rol.recolector &&
        (r.idProyecto == null || r.idProyecto!.isEmpty),
  );

  // =============================================================
  // 4) Capacidades de navegación (Proyectos)
  // =============================================================
  bool get canViewProjects {
    if (isAdminUnico || isAdmin) return true;
    if (projectIdsAsOwner.isNotEmpty) return true;
    if (projectIdsAsSupervisor.isNotEmpty) return true;
    if (projectIdsAsColaborador.isNotEmpty) return true;
    if (projectIdsAsRecolector.isNotEmpty) return true;
    return false;
  }

  bool get canCreateProject => isAdminUnico;
  bool get canEditProject => isAdminUnico || isAdmin || isDuenoEnContexto;

  bool canEditProjectFor(String projectId) {
    if (isAdminUnico || isAdmin) return true;
    return isDuenoEnContexto && _proyectoActualId == projectId;
  }

  bool get canDeleteProject => isAdminUnico;

  bool get canManageCollaborators =>
      isAdminUnico || isAdmin || isDuenoEnContexto || isSupervisorEnContexto;

  bool canManageCollaboratorsFor(String projectId) {
    if (isAdminUnico || isAdmin) return true;
    final same = (_proyectoActualId != null && _proyectoActualId == projectId);
    if (!same) return false;
    return isDuenoEnContexto || isSupervisorEnContexto;
  }

  bool canViewProject(String proyectoId) {
    if (isAdminUnico || isAdmin) return true;
    if (projectIdsAsOwner.contains(proyectoId)) return true;
    if (projectIdsAsSupervisor.contains(proyectoId)) return true;
    if (projectIdsAsColaborador.contains(proyectoId)) return true;
    if (projectIdsAsRecolector.contains(proyectoId)) return true;
    return false;
  }

  // =============================================================
  // 5) Capacidades sobre Observaciones (legacy)
  // =============================================================
  bool get canViewObservations => isLoggedIn;

  bool get canAddObservation {
    if (!isLoggedIn) return false;

    // 🔹 Sin proyecto: reusar la misma lógica de creación sin proyecto
    if (_proyectoActualId == null || _proyectoActualId!.isEmpty) {
      return canCreateObservationSinProyecto;
    }

    // 🔹 Con proyecto en contexto: lógica normal por URP
    return isAdminUnico ||
        isAdmin ||
        isSupervisorEnContexto ||
        isDuenoEnContexto ||
        isColaboradorEnContexto;
  }

  bool canCreateObservationInProject(String projectId) {
    if (isAdminUnico || isAdmin) return true;
    final same = (_proyectoActualId != null && _proyectoActualId == projectId);
    if (!same) return false;
    return isSupervisorEnContexto || isDuenoEnContexto || isColaboradorEnContexto;
  }

  /// 🔹 QUIÉN puede crear observaciones **sin proyecto**
  bool get canCreateObservationSinProyecto {
    if (!isLoggedIn) return false;

    // 1) Admin único siempre puede
    if (isAdminUnico) return true;

    // 2) Recolector en contexto sin proyecto (cuando seleccionó ese rol)
    if (isRecolectorSinProyecto) return true;

    // 3) Recolector global (URP de recolector sin proyecto, aunque no esté seleccionado)
    if (hasRecolectorSinProyectoGlobal) return true;

    return false;
  }

  bool get canApproveObservation =>
      isAdminUnico || isAdmin || isSupervisorEnContexto || isDuenoEnContexto;

  bool canApproveObservationForProject(String projectId) {
    if (isAdminUnico || isAdmin) return true;
    final same = (_proyectoActualId != null && _proyectoActualId == projectId);
    return same && (isSupervisorEnContexto || isDuenoEnContexto);
  }

  bool canApproveObservationFor({
    required String projectId,
    required String? uidAutor,
  }) {
    if (isAdminUnico || isAdmin) return true;
    final same = (_proyectoActualId != null && _proyectoActualId == projectId);
    final notOwn = uidAutor == null ? true : (uidAutor != _uidActual);
    return same && notOwn && (isSupervisorEnContexto || isDuenoEnContexto);
  }

  bool canEditObservation({
    required String uidAutor,
    required String estado,
    String? idProyectoObs,
  }) {
    if (!isLoggedIn) return false;
    if (_isAuthor(uidAutor) && estado == kPendiente) return true;
    if (isAdminUnico || isAdmin) return true;
    if (isSupervisorEnContexto && _sameProject(idProyectoObs)) return true;
    return false;
  }

  bool canDeleteObservation({
    required String uidAutor,
    String? idProyectoObs,
    String? estado,
  }) {
    if (isAdminUnico || isAdmin) return true;
    if ((estado ?? '').toLowerCase() == 'borrador' && _isAuthor(uidAutor)) {
      return true;
    }
    return false;
  }

  bool canModerateProject(String projectId) =>
      canApproveObservationForProject(projectId);

  // =============================================================
  // 6) Alias y azúcares semánticos para UI
  // =============================================================
  bool canAssignCollaboratorFor(String projectId) =>
      canManageCollaboratorsFor(projectId);

  bool get canAssignSupervisor => isAdminUnico;

  // =============================================================
  // 7) Menú/visibilidad UI
  // =============================================================
  Map<String, bool> buildMenuVisibility() {
    return {
      'menu_proyectos': canViewProjects,
      'menu_nuevo_proyecto': canCreateProject,
      'menu_observaciones': canViewObservations,
      'menu_observacion_nueva': canAddObservation,
      'menu_aprobaciones': canApproveObservation,
      'menu_colaboradores': canManageCollaborators,
      'menu_admin_panel': isAdminGlobal || isAdmin,
    };
  }

  bool get showSupervisoresTab => isAdminUnico;

  bool showColaboradoresTabFor(String projectId) =>
      isAdminUnico ||
          isAdmin ||
          (isDuenoEnContexto && _proyectoActualId == projectId) ||
          (isSupervisorEnContexto && _proyectoActualId == projectId);

  // =============================================================
  // 8) Helpers V2 (flujo nuevo de observaciones)
  // =============================================================
  bool canEditObsV2({
    required String? idProyecto,
    required String uidAutor,
    required String estado,
  }) {
    final e = estado.toLowerCase();
    if (!isLoggedIn) return false;

    if (e == EstadosObsV2.borrador) {
      return _isAuthor(uidAutor) || isAdminUnico || isAdmin;
    }

    if (e == EstadosObsV2.pendiente || e == EstadosObsV2.revisarNuevo) {
      return isAdminUnico ||
          isAdmin ||
          (isSupervisorEnContexto && _sameProject(idProyecto)) ||
          (isDuenoEnContexto && _sameProject(idProyecto));
    }

    if (e == EstadosObsV2.rechazado) {
      return _isAuthor(uidAutor) ||
          isAdminUnico ||
          isAdmin ||
          (isSupervisorEnContexto && _sameProject(idProyecto)) ||
          (isDuenoEnContexto && _sameProject(idProyecto));
    }

    return isAdminUnico || isAdmin;
  }

  bool canDeleteObsV2({
    required String? idProyecto,
    required String uidAutor,
    required String estado,
  }) {
    final e = estado.toLowerCase();

    if (e == EstadosObsV2.borrador) {
      return _isAuthor(uidAutor) || isAdminUnico || isAdmin;
    }

    if (e == EstadosObsV2.pendiente || e == EstadosObsV2.revisarNuevo) {
      return isAdminUnico ||
          isAdmin ||
          (isSupervisorEnContexto && _sameProject(idProyecto)) ||
          (isDuenoEnContexto && _sameProject(idProyecto));
    }

    if (e == EstadosObsV2.rechazado) {
      return _isAuthor(uidAutor) ||
          isAdminUnico ||
          isAdmin ||
          (isSupervisorEnContexto && _sameProject(idProyecto)) ||
          (isDuenoEnContexto && _sameProject(idProyecto));
    }

    return isAdminUnico || isAdmin;
  }

  bool canSubmitToPending({
    required String uidAutor,
    required String estadoActual,
    required bool datosCompletos,
  }) {
    if ((estadoActual.toLowerCase() != EstadosObsV2.borrador) ||
        !datosCompletos) return false;
    return _isAuthor(uidAutor) || isAdminUnico || isAdmin;
  }

  bool canModeratePending({
    required String? idProyecto,
    required String? uidAutor,
  }) {
    if (isAdminUnico || isAdmin) return true;
    final same = _sameProject(idProyecto);
    final notOwn = uidAutor == null ? true : !_isAuthor(uidAutor);
    return same && notOwn && (isSupervisorEnContexto || isDuenoEnContexto);
  }

  bool canResubmitRejected({
    required String? idProyecto,
    required String uidAutor,
    required DateTime? rejectedAt,
    required DateTime? updatedAt,
  }) {
    final puedeEditar = canEditObsV2(
      idProyecto: idProyecto,
      uidAutor: uidAutor,
      estado: EstadosObsV2.rechazado,
    );
    final fueEditadoDespues =
        rejectedAt != null && updatedAt != null && updatedAt.isAfter(rejectedAt);
    return puedeEditar && fueEditadoDespues;
  }

  String? blockedReasonV2({
    required String? idProyecto,
    required String uidAutor,
    required String estado,
  }) {
    if (canEditObsV2(idProyecto: idProyecto, uidAutor: uidAutor, estado: estado)) {
      return null;
    }
    final e = estado.toLowerCase();
    switch (e) {
      case EstadosObsV2.borrador:
        return 'Solo el autor o un admin pueden editar el borrador.';
      case EstadosObsV2.pendiente:
      case EstadosObsV2.revisarNuevo:
        return 'Solo un supervisor/dueño del mismo proyecto o admin pueden editar en Pendiente.';
      case EstadosObsV2.rechazado:
        return 'Las observaciones rechazadas solo las puede editar el autor, un supervisor del proyecto o un admin.';
      case EstadosObsV2.aprobado:
      case EstadosObsV2.archivado:
        return 'Las observaciones $estado solo las puede editar un admin.';
      default:
        return 'No tienes permisos para editar esta observación.';
    }
  }

  // =============================================================
  // 9) Compatibilidad FirestoreService
  // =============================================================
  bool canModerateProjectCompat(String projectId) =>
      canApproveObservationForProject(projectId);
}
