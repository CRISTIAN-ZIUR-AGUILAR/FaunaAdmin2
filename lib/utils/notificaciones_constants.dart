// lib/utils/notificaciones_constants.dart

/// Niveles de severidad visual/semántica
class NotiNivel {
  static const success = 'success';
  static const info    = 'info';
  static const warning = 'warning';
  static const error   = 'error';

  static const all = <String>[success, info, warning, error];
}

/// Tipos de notificación normalizados
class NotiTipo {
  // ---- Observaciones
  static const obsCreada           = 'obs.creada';
  static const obsEditada          = 'obs.editada';
  static const obsComentada        = 'obs.comentada';
  static const obsAprobada         = 'obs.aprobada';
  static const obsRechazada        = 'obs.rechazada';
  static const obsAsignadaRevision = 'obs.asignada_revision';

  // ---- Proyectos
  static const proyCreado   = 'proy.creado';
  static const proyEditado  = 'proy.editado';
  static const proyEstado   = 'proy.estado';
  static const proyAsignado = 'proy.asignado';
  static const proyRemovido = 'proy.removido';

  // ---- Roles (URP en proyecto)
  static const rolAsignado = 'rol.asignado';
  static const rolRemovido = 'rol.removido';
  static const rolCambiado = 'rol.cambiado';

  // Grupos útiles para filtros (reutiliza en Provider/UI)
  static const grupoObservaciones = <String>{
    obsCreada, obsEditada, obsComentada, obsAprobada, obsRechazada, obsAsignadaRevision,
  };

  static const grupoProyectos = <String>{
    proyCreado, proyEditado, proyEstado, proyAsignado, proyRemovido,
  };

  static const grupoRoles = <String>{
    rolAsignado, rolRemovido, rolCambiado,
  };
}
