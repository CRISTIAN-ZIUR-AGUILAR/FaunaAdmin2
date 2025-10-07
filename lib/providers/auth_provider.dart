// lib/providers/auth_provider.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/usuario.dart';
import '../models/usuario_rol_proyecto.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/constants.dart'; // RoleIds

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FirestoreService _db = FirestoreService();

  Usuario? _usuario;
  Usuario? get usuario => _usuario;

  fb.User? _fbUser;
  bool get isLoggedIn => _fbUser != null;

  // Exponer el usuario y el UID de Firebase
  fb.User? get user => _fbUser;
  String? get uid => _fbUser?.uid;

  /// ✅ Getter solicitado para otros providers (p.ej. NotificacionProvider)
  String? get currentUserId => _fbUser?.uid;

  List<UsuarioRolProyecto> _rolesProyectos = [];
  List<UsuarioRolProyecto> get rolesProyectos => _rolesProyectos;

  UsuarioRolProyecto? _selectedRolProyecto;
  UsuarioRolProyecto? get selectedRolProyecto => _selectedRolProyecto;
  String? get selectedProjectId => _selectedRolProyecto?.idProyecto;

  bool _triedFirebase = false;
  bool get hasTriedFirebase => _triedFirebase;

  StreamSubscription<fb.User?>? _subAuth;

  // Subs en tiempo real a usuario y URPs
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subUserDoc;
  StreamSubscription<List<UsuarioRolProyecto>>? _subUrps;

  AuthProvider() {
    _subAuth = _authService.authStateChanges.listen((fb.User? fbUser) {
      _triedFirebase = true;
      _onAuthStateChanged(fbUser);
    });
  }

  /// Limpia todo el estado local de sesión.
  void _clearState() {
    _usuario = null;
    _rolesProyectos = [];
    _selectedRolProyecto = null;
    _fbUser = null;

    // Cancelar subs en vivo
    _subUserDoc?.cancel();
    _subUserDoc = null;
    _subUrps?.cancel();
    _subUrps = null;

    notifyListeners();
  }

  /// Admin único → sin contexto forzado.
  /// Si solo hay un URP → lo seleccionamos.
  void _autoselectAdminIfAny() {
    final isAdminUnico = (_usuario?.isAdmin ?? false);
    if (isAdminUnico) {
      _selectedRolProyecto = null; // sin contexto obligatorio para admin
      return;
    }
    if (_rolesProyectos.length == 1) {
      _selectedRolProyecto = _rolesProyectos.first;
      return;
    }
    // en otros casos: que el usuario elija
  }

  /// Reajuste cuando cambian URPs en tiempo real.
  void _reconcileSelectedContext() {
    final isAdminUnico = (_usuario?.isAdmin ?? false);
    if (isAdminUnico) {
      _selectedRolProyecto = null; // Admin no necesita contexto
      return;
    }

    if (_rolesProyectos.isEmpty) {
      _selectedRolProyecto = null;
      return;
    }

    if (_selectedRolProyecto == null) {
      if (_rolesProyectos.length == 1) {
        _selectedRolProyecto = _rolesProyectos.first;
      }
      return;
    }

    // Si el seleccionado ya no existe, lo limpiamos o autoseleccionamos
    final stillExists = _rolesProyectos.any((r) =>
    r.id == _selectedRolProyecto!.id ||
        (r.idProyecto == _selectedRolProyecto!.idProyecto &&
            r.uidUsuario == _selectedRolProyecto!.uidUsuario &&
            r.idRol == _selectedRolProyecto!.idRol));

    if (!stillExists) {
      if (_rolesProyectos.length == 1) {
        _selectedRolProyecto = _rolesProyectos.first;
      } else {
        _selectedRolProyecto = null;
      }
    }
  }

  Future<void> _onAuthStateChanged(fb.User? fbUser) async {
    // Cancelar subs anteriores si hubiera
    _subUserDoc?.cancel();
    _subUserDoc = null;
    _subUrps?.cancel();
    _subUrps = null;

    _fbUser = fbUser;
    if (fbUser == null) {
      _clearState();
      return;
    }

    try {
      // Carga inicial (puntual)
      final results = await Future.wait([
        _db.getUsuario(fbUser.uid),
        _db.getUsuarioRolProyectosForUser(fbUser.uid),
      ]);
      _usuario = results[0] as Usuario;
      _rolesProyectos = results[1] as List<UsuarioRolProyecto>;
      _autoselectAdminIfAny();
      notifyListeners();

      // 🔴 Subs en tiempo real:
      // 1) Usuario
      _subUserDoc = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(fbUser.uid)
          .snapshots()
          .listen((snap) {
        if (!snap.exists || snap.data() == null) return;
        try {
          _usuario = Usuario.fromMap(snap.data()!, snap.id);
          _reconcileSelectedContext(); // por si cambia is_admin
          notifyListeners();
        } catch (_) {
          // tolerante a errores de parseo
        }
      });

      // 2) URPs
      _subUrps =
          _db.streamUsuarioRolProyectosForUser(fbUser.uid).listen((lista) {
            _rolesProyectos = lista;
            _reconcileSelectedContext();
            notifyListeners();
          });
    } catch (_) {
      _clearState();
      return;
    }
  }

  // -------- Contexto (rol/proyecto) ----------
  void selectRolProyecto(UsuarioRolProyecto urp) {
    _selectedRolProyecto = urp;
    notifyListeners();
  }

  void setSelectedRolProyecto(UsuarioRolProyecto? ctx) {
    _selectedRolProyecto = ctx;
    notifyListeners();
  }

  void clearSelectedRolProyecto() {
    _selectedRolProyecto = null;
    notifyListeners();
  }

  /// Asegura que, si el usuario tiene URP para `projectId`,
  /// lo dejemos seleccionado. Útil en pantallas profundas / deep links.
  void ensureContextForProject(String projectId) {
    // Si es admin único, no forzamos contexto.
    if (_usuario?.isAdmin == true) return;

    if (_selectedRolProyecto?.idProyecto == projectId) return;

    UsuarioRolProyecto? match;
    for (final r in _rolesProyectos) {
      if (r.idProyecto == projectId) {
        match = r;
        break;
      }
    }

    if (match != null) {
      _selectedRolProyecto = match;
      notifyListeners();
    } else if (_rolesProyectos.length == 1) {
      _selectedRolProyecto = _rolesProyectos.first;
      notifyListeners();
    }
  }

  // ---------- Helper de errores legibles (Auth) ----------
  String _errString(Object error) {
    if (error is fb.FirebaseAuthException) {
      final code = (error.code).toLowerCase();
      switch (code) {
        case 'invalid-email':
          return 'El correo no es válido.';
        case 'user-disabled':
          return 'Tu cuenta está deshabilitada.';
        case 'user-not-found':
          return 'No existe una cuenta con ese correo.';
        case 'wrong-password':
          return 'La contraseña no es correcta.';
        case 'too-many-requests':
          return 'Demasiados intentos. Inténtalo más tarde.';
        case 'network-request-failed':
          return 'Sin conexión. Verifica tu internet.';
        case 'email-already-in-use':
          return 'Ese correo ya está registrado.';
        case 'weak-password':
          return 'La contraseña es demasiado débil.';
        case 'operation-not-allowed':
          return 'Operación no permitida. Contacta al administrador.';
        case 'missing-email':
          return 'Ingresa un correo.';
        case 'invalid-credential':
          return 'Credenciales inválidas.';
        case 'requires-recent-login':
          return 'Vuelve a iniciar sesión para continuar.';
        case 'popup-closed-by-user':
          return 'El proceso fue cancelado.';
        case 'internal-error':
          return 'Ocurrió un error interno. Inténtalo de nuevo.';
        default:
          return error.message?.trim().isNotEmpty == true
              ? error.message!.trim()
              : 'No se pudo completar la acción. ($code)';
      }
    }
    // Otros errores genéricos
    final s = error.toString();
    if (s.contains('email-already-in-use')) return 'Ese correo ya está registrado.';
    return 'Ocurrió un error. Inténtalo de nuevo.';
  }

  // --------------- Auth -----------------------
  Future<String?> signIn(String email, String password) async {
    try {
      await _authService.signIn(email: email, password: password);

      _fbUser = fb.FirebaseAuth.instance.currentUser;
      await _fbUser?.reload();
      final current = fb.FirebaseAuth.instance.currentUser;
      if (current == null) {
        await _authService.signOut();
        return 'No se pudo iniciar sesión. Inténtalo de nuevo.';
      }

      _usuario = await _db.getUsuario(current.uid);
      _rolesProyectos = await _db.getUsuarioRolProyectosForUser(current.uid);
      _autoselectAdminIfAny();

      // Admin único (principal) — incluimos OR con admin-URP legado para compatibilidad
      final bool isAdminLocal = (_usuario?.isAdmin ?? false) ||
          _rolesProyectos.any(
                  (urp) => urp.idRol == RoleIds.admin && urp.idProyecto == null);

      // Gate 1: aprobado
      final approved = (_usuario?.estatus ?? '').toLowerCase() == 'aprobado';
      if (!approved) {
        await _authService.signOut();
        _clearState();
        return 'Tu cuenta está pendiente de aprobación.';
      }

      // Gate 2: verificación de correo (excepto admin único/legado)
      if (!isAdminLocal && current.emailVerified != true) {
        try {
          await current.sendEmailVerification();
        } catch (_) {}
        await _authService.signOut();
        _clearState();
        return 'Debes verificar tu correo antes de iniciar sesión.';
      }

      // Activar subs en vivo después del login
      _onAuthStateChanged(current);

      return null;
    } on fb.FirebaseAuthException catch (e) {
      return _errString(e);
    } catch (e) {
      return _errString(e);
    }
  }

  Future<String?> signUp({
    required String nombreCompleto,
    required String email,
    required String password,
    required String ocupacion,
    required String nivelAcademico,
    String area = '',
  }) async {
    try {
      final fb.User fbUser = await _authService.signUp(
        email: email,
        password: password,
      );

      final nuevo = Usuario(
        uid: fbUser.uid,
        nombreCompleto: nombreCompleto,
        correo: email,
        ocupacion: ocupacion,
        nivelAcademico: nivelAcademico,
        area: area,
        estatus: 'pendiente',
        fechaRegistro: DateTime.now(),
        isAdmin: false, // 👈 IMPORTANTÍSIMO: los nuevos NO son admin.
      );
      await _db.setUsuario(nuevo);

      // 👇 Mejora opcional: enviar verificación de correo al registrarse
      try {
        await fbUser.sendEmailVerification();
      } catch (_) {}

      return null;
    } on fb.FirebaseAuthException catch (e) {
      return _errString(e);
    } catch (e) {
      return _errString(e);
    }
  }

  Future<void> signOut() async {
    _clearState();
    await _authService.signOut();
  }

  /// 🔄 Refrescar usuario y URPs bajo demanda (sin re-login)
  Future<void> refreshSession() async {
    final fbUser = fb.FirebaseAuth.instance.currentUser;
    if (fbUser == null) return;
    try {
      final results = await Future.wait([
        _db.getUsuario(fbUser.uid),
        _db.getUsuarioRolProyectosForUser(fbUser.uid),
      ]);
      _usuario = results[0] as Usuario;
      _rolesProyectos = results[1] as List<UsuarioRolProyecto>;
      _reconcileSelectedContext();
    } finally {
      notifyListeners();
    }
  }

  // --------------- Flags de conveniencia ---------------
  bool get isApproved => (_usuario?.estatus ?? '').toLowerCase() == 'aprobado';

  /// Admin del sistema:
  /// - preferimos `usuarios.is_admin`
  /// - compat con un posible URP(admin, null) legado
  bool get isAdmin =>
      (_usuario?.isAdmin ?? false) ||
          _rolesProyectos.any(
                  (urp) => urp.idRol == RoleIds.admin && urp.idProyecto == null);

  /// Necesita verificar correo (solo si NO es admin)
  bool get needsEmailVerification {
    final fb.User? fbUser = fb.FirebaseAuth.instance.currentUser;
    final isAdminLocal = isAdmin;
    return !isAdminLocal && isApproved && fbUser != null && !fbUser.emailVerified;
  }

  bool get isInitializing => _fbUser != null && _usuario == null;

  @override
  void dispose() {
    _subAuth?.cancel();
    _subUserDoc?.cancel();
    _subUrps?.cancel();
    super.dispose();
  }
}

