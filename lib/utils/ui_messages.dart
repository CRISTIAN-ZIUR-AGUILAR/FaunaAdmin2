// lib/utils/ui_messages.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

// Si aún no tienes AppError, puedes comentar esta línea.
// Pero es muy recomendable usarlo para errores tipados desde los services.
import 'app_error.dart' show AppError;

/// Mensaje legible para mostrar en la UI (SnackBar/Alert).
/// Usa errores tipados cuando existen y hace fallback a heurísticas de texto.
String uiMsg(Object? error, {String fallback = 'Ocurrió un error. Inténtalo de nuevo.'}) {
  if (error == null) return fallback;

  // 1) Errores tipados propios
  if (error is AppError) {
    final msg = _strip(error.message);
    switch (error.code) {
      case 'owner_conflict':
        return msg.isNotEmpty ? msg : 'El dueño no puede realizar esa acción en su propio proyecto.';
      case 'collab_conflict':
        return msg.isNotEmpty ? msg : 'El usuario ya es COLABORADOR en este proyecto.';
      case 'sup_conflict':
        return msg.isNotEmpty ? msg : 'El usuario ya es SUPERVISOR en este proyecto.';
      case 'already_assigned':
        return msg.isNotEmpty ? msg : 'El usuario ya estaba asignado.';
      default:
        return msg.isNotEmpty ? msg : fallback;
    }
  }

  // 2) Firebase Auth
  if (error is fb.FirebaseAuthException) {
    switch ((error.code).toLowerCase()) {
      case 'invalid-email':         return 'El correo no es válido.';
      case 'user-disabled':         return 'Tu cuenta está deshabilitada.';
      case 'user-not-found':        return 'No existe una cuenta con ese correo.';
      case 'wrong-password':        return 'La contraseña no es correcta.';
      case 'too-many-requests':     return 'Demasiados intentos. Inténtalo más tarde.';
      case 'network-request-failed':return 'Sin conexión. Verifica tu internet.';
      case 'email-already-in-use':  return 'Ese correo ya está registrado.';
      case 'weak-password':         return 'La contraseña es demasiado débil.';
      case 'requires-recent-login': return 'Vuelve a iniciar sesión para continuar.';
      default:
        return _strip(error.message ?? fallback);
    }
  }

  // 3) Firestore (FirebaseException)
  if (error is FirebaseException) {
    final code = (error.code).toLowerCase();
    switch (code) {
      case 'permission-denied':   return 'No tienes permisos para realizar esta acción.';
      case 'unavailable':         return 'Servicio temporalmente no disponible. Intenta de nuevo.';
      case 'deadline-exceeded':   return 'La operación tardó demasiado. Reintenta.';
      case 'aborted':             return 'La operación fue cancelada. Intenta de nuevo.';
      case 'not-found':           return 'No se encontró el recurso solicitado.';
      case 'already-exists':      return 'El registro ya existe.';
      case 'failed-precondition': return 'La operación no puede realizarse en este estado.';
      case 'cancelled':           return 'Operación cancelada.';
      case 'internal':            return 'Ocurrió un error interno. Intenta de nuevo.';
      default:
        return _strip(error.message ?? fallback);
    }
  }

  // 4) Heurísticas por texto (fallback para servicios no tipados)
  final sRaw = _strip(error.toString());
  final s = sRaw.toLowerCase();

  // Dueño ↔ restricciones
  if ((s.contains('dueño') && s.contains('supervisor')) ||
      s.contains('owner_conflict')) {
    return 'El dueño no puede ser supervisor de su propio proyecto.';
  }
  if (s.contains('owned') || (s.contains('dueño') && s.contains('colaborador'))) {
    return 'No puedes agregar al DUEÑO como COLABORADOR.';
  }

  // Conflictos de rol
  if (s.contains('ya es supervisor') && s.contains('colaborador')) {
    return 'Este usuario ya es SUPERVISOR. Retíralo como supervisor o cámbialo desde la pestaña de Supervisores.';
  }
  if (s.contains('ya es colaborador') && s.contains('supervisor')) {
    return 'Este usuario ya es COLABORADOR. Retíralo como colaborador o cámbialo desde la pestaña de Colaboradores.';
  }
  if (s.contains('sup_conflict'))    return 'Este usuario ya es SUPERVISOR en el proyecto.';
  if (s.contains('collab_conflict')) return 'Este usuario ya es COLABORADOR en el proyecto.';

  // Duplicados / ya asignado
  if (s.contains('ya existe') || s.contains('duplicate') || s.contains('already')) {
    return 'El usuario ya estaba asignado.';
  }

  // Fallback final
  return sRaw.isNotEmpty ? sRaw : fallback;
}

/// (Opcional) Devuelve un "código" detectable a partir del error.
/// Útil si la UI quiere tomar decisiones (ej. mostrar diálogo de “cambiar rol”).
String? uiCode(Object? error) {
  if (error == null) return null;

  if (error is AppError) return error.code;

  if (error is fb.FirebaseAuthException) return error.code;
  if (error is FirebaseException)       return error.code;

  final s = _strip(error.toString()).toLowerCase();
  if (s.contains('owner_conflict') || (s.contains('dueño') && s.contains('supervisor'))) {
    return 'owner_conflict';
  }
  if (s.contains('collab_conflict') || (s.contains('ya es colaborador') && s.contains('supervisor'))) {
    return 'collab_conflict';
  }
  if (s.contains('sup_conflict') || (s.contains('ya es supervisor') && s.contains('colaborador'))) {
    return 'sup_conflict';
  }
  if (s.contains('already') || s.contains('duplicate') || s.contains('ya existe')) {
    return 'already_assigned';
  }
  return null;
}

/// Alias de compatibilidad: si en tu código viejo llamabas a `errMsg(...)`,
/// seguirá funcionando. Internamente usa `uiMsg(...)`.
String errMsg(Object? e) => uiMsg(e);

/// Quita prefijos tipo "Exception:" / "Error:" y trim.
String _strip(String? raw) {
  final t = (raw ?? '').trim();
  return t.replaceFirst(RegExp(r'^(Exception|Error):\s*', caseSensitive: false), '').trim();
}
