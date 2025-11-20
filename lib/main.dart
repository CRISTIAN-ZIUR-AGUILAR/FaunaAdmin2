// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:faunadmin2/firebase_options.dart';
import 'package:faunadmin2/services/firestore_service.dart';             // Servicio compartido
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/providers/proyecto_provider.dart';
import 'package:faunadmin2/providers/observacion_provider.dart';
import 'package:faunadmin2/services/photo_media_provider.dart';         // NUEVO
import 'package:faunadmin2/ui/themes/app_theme.dart';
import 'package:faunadmin2/routes.dart';

// Screens usadas en el gate inicial
import 'package:faunadmin2/ui/screens/auth/login_screen.dart';
import 'package:faunadmin2/ui/screens/auth/pending_screen.dart';
import 'package:faunadmin2/ui/screens/auth/verify_email_screen.dart';
import 'package:faunadmin2/ui/screens/admin/dashboard_admin_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Firebase una sola vez; tolera arranques duplicados.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  // Persistencia local de Firestore (evitar IndexedDB en Web).
  try {
    if (kIsWeb) {
      FirebaseFirestore.instance.settings =
      const Settings(persistenceEnabled: false);
    } else {
      FirebaseFirestore.instance.settings =
      const Settings(persistenceEnabled: true);
    }
  } catch (_) {
    // Ignorar si ya estaba configurado.
  }

  runApp(const FaunaAdmin2App());
}

class FaunaAdmin2App extends StatelessWidget {
  const FaunaAdmin2App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ===== Estado base =====
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProyectoProvider()),

        // ===== Servicio compartido (puro, no es ChangeNotifier) =====
        Provider<FirestoreService>(create: (_) => FirestoreService()),

        // ===== Observaciones (depende de Auth + FirestoreService) =====
        ChangeNotifierProxyProvider2<AuthProvider, FirestoreService, ObservacionProvider>(
          create: (ctx) => ObservacionProvider(
            ctx.read<FirestoreService>(),    // FS
            ctx.read<AuthProvider>(),        // Auth
          ),
          update: (ctx, auth, fs, prev) => prev ?? ObservacionProvider(fs, auth),
        ),

        // ===== Medios (fotos/videos por observación) =====
        // Constructor de PhotoMediaProvider espera FirebaseFirestore (1 arg).
        ChangeNotifierProvider<PhotoMediaProvider>(
          create: (_) => PhotoMediaProvider(FirebaseFirestore.instance),
        ),

        // 👇 IMPORTANT: No registramos NotificacionProvider aquí.
        // Se inyecta localmente en routes.dart SOLO para '/dashboard'
        // con: ChangeNotifierProvider(create: (ctx) => NotificacionProvider(ctx.read<AuthProvider>()), child: DashboardScreen(...))
      ],
      child: MaterialApp(
        title: 'FaunaAdmin2',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,

        // Arrancamos por "/" y dejamos que onGenerateRoute maneje el resto
        initialRoute: '/',
        routes: {
          '/': (_) => const _RootGate(),
        },
        onGenerateRoute: Routes.generate,
      ),
    );
  }
}

/// Decide la pantalla inicial según el estado de autenticación y permisos.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        // Aún no recibimos el primer evento de FirebaseAuth
        if (!auth.hasTriedFirebase) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // No logueado
        if (!auth.isLoggedIn) {
          return const LoginScreen();
        }

        // Cargando perfil/roles tras login
        if (auth.isInitializing) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Gate 1: requiere aprobación del admin
        if (!auth.isApproved) {
          return const PendingScreen();
        }

        // Si es admin global, entra directo al panel
        if (auth.isAdmin) {
          return const DashboardAdminScreen();
        }

        // Gate 2: verificación de correo (para no-admin)
        if (auth.needsEmailVerification) {
          return const VerifyEmailScreen();
        }

        // ✅ Ir SIEMPRE al dashboard (el provider de notificaciones se inyecta en routes.dart)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final nav = Navigator.of(context);
          if (nav.mounted) {
            nav.pushReplacementNamed('/dashboard');
          }
        });
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}


