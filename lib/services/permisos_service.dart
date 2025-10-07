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
// =============================================================

import 'package:faunadmin2/models/rol.dart';
import 'package:faunadmin2/models/usuario_rol_proyecto.dart';
import 'package:faunadmin2/providers/auth_provider.dart';

class PermisosService {
  // =============================================================
  // 1) Imports y encabezado
  // =============================================================
  final AuthProvider _auth;
  PermisosService(this._auth);

  // (Legacy/UI) Estados viejos en MAYÚSCULAS.
  // Nota: el módulo nuevo usa estados: borrador|pendiente|aprobado|rechazado|archivado.
  static const String kPendiente = 'PENDIENTE';
  static const String kAprobado  = 'APROBADO';
  static const String kRechazado = 'RECHAZADO';

  // =============================================================
  // 2) Contexto actual y getters base
  // =============================================================
  UsuarioRolProyecto? get _sel => _auth.selectedRolProyecto;

  int?    get _rolActual        => _sel?.idRol;
  String? get _proyectoActualId => _sel?.idProyecto;
  String? get _uidActual        => _auth.usuario?.uid;

  bool get isLoggedIn => _auth.isLoggedIn;

  /// Admin Único (flag en documento de usuario)
  bool get isAdminUnico => _auth.usuario?.isAdmin == true;

  // Compatibilidad histórica con “globales”
  bool get isAdminGlobal => isAdminUnico; // Admin global ≡ Admin Único
  bool get isDuenoGlobal => false;        // Dueño global eliminado

  /// Admin “like”: Admin Único o Admin rol en contexto
  bool get isAdminLike => isAdminUnico || isAdmin;

  // Rol EN CONTEXTO (URP seleccionada)
  bool get isAdmin        => _rolActual == Rol.admin;
  bool get isSupervisor   => _rolActual == Rol.supervisor;
  bool get isRecolector   => _rolActual == Rol.recolector;

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

  // Helpers internos
  bool _sameProject(String? idProyecto) =>
      idProyecto != null && idProyecto == _proyectoActualId;

  bool _isAuthor(String? uid) =>
      uid != null && uid == _uidActual;

  // =============================================================
  // 3) Conjuntos de proyectos por rol (para checar pertenencia)
  // =============================================================
  Set<String> get projectIdsAsOwner => _auth.rolesProyectos
      .where((r) => r.idRol == Rol.duenoProyecto && (r.idProyecto?.isNotEmpty ?? false))
      .map((r) => r.idProyecto!)
      .toSet();

  Set<String> get projectIdsAsSupervisor => _auth.rolesProyectos
      .where((r) => r.idRol == Rol.supervisor && (r.idProyecto?.isNotEmpty ?? false))
      .map((r) => r.idProyecto!)
      .toSet();

  Set<String> get projectIdsAsColaborador => _auth.rolesProyectos
      .where((r) => r.idRol == Rol.colaborador && (r.idProyecto?.isNotEmpty ?? false))
      .map((r) => r.idProyecto!)
      .toSet();

  Set<String> get projectIdsAsRecolector => _auth.rolesProyectos
      .where((r) => r.idRol == Rol.recolector && (r.idProyecto?.isNotEmpty ?? false))
      .map((r) => r.idProyecto!)
      .toSet();

  bool get hasAnyCollaborator =>
      _auth.rolesProyectos.any((r) => r.idRol == Rol.colaborador);

  // =============================================================
  // 4) Capacidades de navegación (Proyectos)
  // =============================================================

  /// Ver listado de Proyectos:
  /// - Admin Único
  /// - Cualquier usuario con >= 1 proyecto asignado (cualquier rol)
  bool get canViewProjects {
    if (isAdminUnico || isAdmin) return true;
    if (projectIdsAsOwner.isNotEmpty) return true;
    if (projectIdsAsSupervisor.isNotEmpty) return true;
    if (projectIdsAsColaborador.isNotEmpty) return true;
    if (projectIdsAsRecolector.isNotEmpty) return true;
    return false;
  }

  /// Crear proyecto: solo Admin Único.
  bool get canCreateProject => isAdminUnico;

  /// Editar el proyecto en contexto:
  /// - Admin Único
  /// - (Opcional) Admin rol en contexto
  /// - Dueño en contexto
  bool get canEditProject => isAdminUnico || isAdmin || isDuenoEnContexto;

  /// Editar proyecto por id explícito
  bool canEditProjectFor(String projectId) {
    if (isAdminUnico || isAdmin) return true;
    return isDuenoEnContexto && _proyectoActualId == projectId;
  }

  /// Borrar proyecto: solo Admin Único.
  bool get canDeleteProject => isAdminUnico;

  /// Gestionar colaboradores del proyecto en contexto:
  /// - Admin Único
  /// - Admin rol en contexto
  /// - Dueño en contexto
  /// - Supervisor en contexto
  bool get canManageCollaborators =>
      isAdminUnico || isAdmin || isDuenoEnContexto || isSupervisorEnContexto;

  /// Variante explícita por proyecto.
  bool canManageCollaboratorsFor(String projectId) {
    if (isAdminUnico || isAdmin) return true;
    final same = (_proyectoActualId != null && _proyectoActualId == projectId);
    if (!same) return false;
    return isDuenoEnContexto || isSupervisorEnContexto;
  }

  /// ¿Puede ver un proyecto específico?
  bool canViewProject(String proyectoId) {
    if (isAdminUnico || isAdmin) return true;
    if (projectIdsAsOwner.contains(proyectoId)) return true;
    if (projectIdsAsSupervisor.contains(proyectoId)) return true;
    if (projectIdsAsColaborador.contains(proyectoId)) return true;
    if (projectIdsAsRecolector.contains(proyectoId)) return true;
    return false;
  }

  // =============================================================
  // 5) Capacidades sobre Observaciones
  // =============================================================

  /// Ver Observaciones: con sesión basta; la UI limitará por proyecto.
  bool get canViewObservations => isLoggedIn;

  /// Crear Observaciones (en UI general):
  /// - SIN proyecto en contexto: Admin Único o Recolector (captura suelta)
  /// - CON proyecto en contexto: Admin Único / Admin / Supervisor / Dueño / Colaborador
  ///   (NO Recolector en proyecto)
  bool get canAddObservation {
    if (!isLoggedIn) return false;

    // Sin proyecto en contexto → captura suelta (recolector o admin)
    if (_proyectoActualId == null || _proyectoActualId!.isEmpty) {
      return isAdminUnico || isRecolector;
    }

    // Con proyecto en contexto → sin recolector
    return isAdminUnico ||
        isAdmin ||
        isSupervisorEnContexto ||
        isDuenoEnContexto ||
        isColaboradorEnContexto;
  }

  /// ¿Puede crear una observación en el proyecto {projectId}?
  /// - Admin Único / Admin → siempre
  /// - Si el proyecto coincide con el del contexto → Supervisor / Dueño / Colaborador
  /// - Recolector: NO dentro de proyecto
  bool canCreateObservationInProject(String projectId) {
    if (isAdminUnico || isAdmin) return true;
    final same = (_proyectoActualId != null && _proyectoActualId == projectId);
    if (!same) return false;
    return isSupervisorEnContexto || isDuenoEnContexto || isColaboradorEnContexto;
  }

  /// Crear observación SIN proyecto (captura suelta):
  /// - Admin Único y Recolector
  bool get canCreateObservationSinProyecto {
    if (!isLoggedIn) return false;
    return isAdminUnico || isRecolector;
  }

  /// Aprobar/Rechazar Observaciones (visión general de menús):
  /// - Admin Único / Admin en contexto
  /// - Supervisor en contexto
  /// - Dueño en contexto   👈
  bool get canApproveObservation =>
      isAdminUnico || isAdmin || isSupervisorEnContexto || isDuenoEnContexto;

  /// Variante por proyecto (observación pertenece a projectId)
  /// (Compatibilidad: sin validar autor)
  bool canApproveObservationForProject(String projectId) {
    if (isAdminUnico || isAdmin) return true;
    final same = (_proyectoActualId != null && _proyectoActualId == projectId);
    return same && (isSupervisorEnContexto || isDuenoEnContexto);
  }

  /// ✅ Nueva: moderar UNA observación concreta evitando auto-aprobación.
  /// - Admin Único / Admin: siempre
  /// - Supervisor/Dueño: mismo proyecto Y que NO sean autores
  bool canApproveObservationFor({
    required String projectId,
    required String? uidAutor,
  }) {
    if (isAdminUnico || isAdmin) return true;
    final same = (_proyectoActualId != null && _proyectoActualId == projectId);
    final notOwn = uidAutor == null ? true : (uidAutor != _uidActual);
    return same && notOwn && (isSupervisorEnContexto || isDuenoEnContexto);
  }

  /// ¿Puede editar una observación concreta?
  /// - Autor si está PENDIENTE (legacy; para UI antigua)
  /// - Admin Único/Admin
  /// - Supervisor en el mismo proyecto
  bool canEditObservation({
    required String uidAutor,
    required String estado,
    String? idProyectoObs,
  }) {
    if (!isLoggedIn) return false;
    if (_isAuthor(uidAutor) && estado == kPendiente) return true; // legacy
    if (isAdminUnico || isAdmin) return true;
    if (isSupervisorEnContexto && _sameProject(idProyectoObs)) return true;
    return false;
  }

  /// ¿Puede borrar una observación?
  /// - Admin Único/Admin
  /// (Opcional) Autor si está PENDIENTE (descomentable si se requiere)
  bool canDeleteObservation({
    required String uidAutor,
    String? idProyectoObs,
    String? estado,
  }) {
    if (isAdminUnico || isAdmin) return true;
    // if (_isAuthor(uidAutor) && estado == kPendiente) return true;
    return false;
  }

  /// —— Alias requerido por FirestoreService (Observaciones) ——
  /// Regla de compatibilidad: Admin Único/Admin o Supervisor/Dueño del mismo proyecto.
  bool canModerateProject(String projectId) {
    return canApproveObservationForProject(projectId);
  }

  // =============================================================
  // 6) Alias y azúcares semánticos para UI
  // =============================================================

  /// Azúcar semántico para UI: “asignar colaborador”
  bool canAssignCollaboratorFor(String projectId) =>
      canManageCollaboratorsFor(projectId);

  /// Asignar supervisor a un proyecto: solo Admin Único.
  bool get canAssignSupervisor => isAdminUnico;

  // =============================================================
  // 7) Menú/visibilidad UI
  // =============================================================
  Map<String, bool> buildMenuVisibility() {
    return {
      'menu_proyectos'        : canViewProjects,
      'menu_nuevo_proyecto'   : canCreateProject,
      'menu_observaciones'    : canViewObservations,
      'menu_observacion_nueva': canAddObservation,
      'menu_aprobaciones'     : canApproveObservation,
      'menu_colaboradores'    : canManageCollaborators,
      'menu_admin_panel'      : isAdminGlobal || isAdmin, // isAdminGlobal ≡ Admin Único
    };
  }

  /// Helper para UI de “Equipo” (tabs/pestañas)
  bool get showSupervisoresTab => isAdminUnico;

  bool showColaboradoresTabFor(String projectId) =>
      isAdminUnico ||
          isAdmin ||
          (isDuenoEnContexto && _proyectoActualId == projectId) ||
          (isSupervisorEnContexto && _proyectoActualId == projectId);
}
