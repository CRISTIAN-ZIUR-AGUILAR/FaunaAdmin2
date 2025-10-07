// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Cambios de sesión (login/logout)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Usuario actual (puede ser null)
  User? get currentUser => _auth.currentUser;

  /// Registro con correo/contraseña
  /// (Si quieres, activa el envío de verificación)
  Future<User> signUp({
    required String email,
    required String password,
    bool sendEmailVerification = false,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      final user = cred.user!;

      if (sendEmailVerification) {
        await user.sendEmailVerification();
      }

      return user;
    } on FirebaseAuthException catch (e) {
      // Mensajes en español
      final msg = switch (e.code) {
        'email-already-in-use' => 'Este correo ya está registrado.',
        'invalid-email' => 'El correo no es válido.',
        'weak-password' => 'La contraseña es demasiado débil (mínimo 6 caracteres).',
        'operation-not-allowed' => 'Método de registro no habilitado en Firebase.',
        'too-many-requests' => 'Demasiados intentos. Intenta más tarde.',
        'network-request-failed' => 'Sin conexión. Revisa tu red.',
        _ => 'Error al registrarte: ${e.code}',
      };
      throw FirebaseAuthException(code: e.code, message: msg);
    }
  }

  /// Login con correo/contraseña
  Future<User> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return cred.user!;
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'user-not-found' => 'No existe una cuenta con este correo.',
        'wrong-password' => 'Contraseña incorrecta.',
        'invalid-credential' => 'Credenciales inválidas.',
        'user-disabled' => 'La cuenta está deshabilitada.',
        'too-many-requests' => 'Demasiados intentos. Intenta más tarde.',
        'network-request-failed' => 'Sin conexión. Revisa tu red.',
        _ => 'Error al iniciar sesión: ${e.code}',
      };
      throw FirebaseAuthException(code: e.code, message: msg);
    }
  }

  /// Cerrar sesión
  Future<void> signOut() => _auth.signOut();

  /// Enviar email de recuperación de contraseña
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Reenviar verificación de correo al usuario actual
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }
}
