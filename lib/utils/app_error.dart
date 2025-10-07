// lib/utils/app_error.dart

/// Error de aplicación con código semántico + mensaje legible.
/// Úsalo para propagar fallas “de negocio” (reglas) hacia la UI.
///
/// Ejemplos:
///   throw AppError.ownerConflict('El dueño no puede ser supervisor.');
///   throw AppError(code: AppErrorCode.supConflict, message: 'Ya es SUPERVISOR');
class AppError implements Exception {
  /// Código estable para que la UI/Provider pueda reaccionar
  /// sin parsear textos.
  final String code;

  /// Mensaje legible para mostrar o para que ui_messages.dart
  /// lo tome y lo “normalice”.
  final String message;

  /// Metadatos opcionales útiles para logging/debug.
  final Object? detail;

  const AppError({
    required this.code,
    required this.message,
    this.detail,
  });

  /// Helpers de fábrica con códigos “canónicos”
  factory AppError.ownerConflict([String? msg, Object? detail]) => AppError(
    code: AppErrorCode.ownerConflict,
    message: msg ?? 'El dueño no puede realizar esa acción en su propio proyecto.',
    detail: detail,
  );

  factory AppError.collabConflict([String? msg, Object? detail]) => AppError(
    code: AppErrorCode.collabConflict,
    message: msg ?? 'El usuario ya es COLABORADOR en este proyecto.',
    detail: detail,
  );

  factory AppError.supConflict([String? msg, Object? detail]) => AppError(
    code: AppErrorCode.supConflict,
    message: msg ?? 'El usuario ya es SUPERVISOR en este proyecto.',
    detail: detail,
  );

  factory AppError.alreadyAssigned([String? msg, Object? detail]) => AppError(
    code: AppErrorCode.alreadyAssigned,
    message: msg ?? 'El usuario ya estaba asignado.',
    detail: detail,
  );

  factory AppError.unknown([String? msg, Object? detail]) => AppError(
    code: AppErrorCode.error,
    message: msg ?? 'No se pudo completar la acción.',
    detail: detail,
  );

  AppError copyWith({String? code, String? message, Object? detail}) => AppError(
    code: code ?? this.code,
    message: message ?? this.message,
    detail: detail ?? this.detail,
  );

  @override
  String toString() => 'AppError($code): $message';
}

/// Códigos canónicos (mantén estos nombres estables)
class AppErrorCode {
  static const String ok              = 'ok';
  static const String error           = 'error';
  static const String ownerConflict   = 'owner_conflict';
  static const String collabConflict  = 'collab_conflict';
  static const String supConflict     = 'sup_conflict';
  static const String alreadyAssigned = 'already_assigned';
}
