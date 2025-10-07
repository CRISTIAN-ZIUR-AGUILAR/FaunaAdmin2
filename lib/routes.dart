// lib/routes.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/services/permisos_service.dart';

// 👇 IMPORTA el provider de notificaciones
import 'package:faunadmin2/providers/notificacion_provider.dart';

// Auth
import 'package:faunadmin2/ui/screens/auth/login_screen.dart';
import 'package:faunadmin2/ui/screens/auth/register_screen.dart';
import 'package:faunadmin2/ui/screens/auth/pending_screen.dart';
import 'package:faunadmin2/ui/screens/auth/verify_email_screen.dart';

// Admin
import 'package:faunadmin2/ui/screens/admin/dashboard_admin_screen.dart';
import 'package:faunadmin2/ui/screens/admin/usuarios_screen.dart';
import 'package:faunadmin2/ui/screens/admin/roles_screen.dart';
import 'package:faunadmin2/ui/screens/admin/categorias_screen.dart';
import 'package:faunadmin2/ui/screens/admin/permisos_screen.dart';
import 'package:faunadmin2/ui/screens/admin/proyectos_admin_screen.dart';

// App (no-admin)
import 'package:faunadmin2/ui/screens/seleccion_rol_proyecto_screen.dart';
import 'package:faunadmin2/ui/screens/dashboard_screen.dart';
import 'package:faunadmin2/ui/screens/perfil/perfil_screen.dart';

// Proyectos
import 'package:faunadmin2/ui/screens/proyectos/lista_proyectos_screen.dart';
import 'package:faunadmin2/ui/screens/proyectos/agregar_proyecto_screen.dart';
import 'package:faunadmin2/ui/screens/proyectos/editar_proyecto_screen.dart';
import 'package:faunadmin2/ui/screens/proyectos/equipo_proyecto_screen.dart';
import 'package:faunadmin2/ui/screens/proyectos/detalle_proyecto_screen.dart'
as proj_detalle;
import 'package:faunadmin2/ui/screens/proyectos/detalle_proyecto_dueno_screen.dart';

// Observaciones
import 'package:faunadmin2/ui/screens/observaciones/lista_observaciones_screen.dart';
import 'package:faunadmin2/ui/screens/observaciones/agregar_observacion_screen.dart';
import 'package:faunadmin2/ui/screens/observaciones/aprobar_observacion_screen.dart';
import 'package:faunadmin2/ui/screens/observaciones/detalle_observacion.dart';

// 👇 IMPORTES NUEVOS (edición nube + edición local)
import 'package:faunadmin2/ui/screens/observaciones/editar_observacion_screen.dart';
import 'package:faunadmin2/ui/screens/observaciones/editar_local_observacion_screen.dart';

/// Flag: habilitar/deshabilitar módulo Observaciones.
const bool kObservacionesHabilitadas = true;

class Routes {
  static Route<dynamic> generate(RouteSettings settings) {
    return MaterialPageRoute(
      settings: settings,
      builder: (context) {
        // Providers/servicios
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final permisos = PermisosService(auth);

        // Estado de sesión / gates
        final bool isLoggedIn = auth.isLoggedIn;
        final bool approved = auth.isApproved;
        final bool emailVerified =
            fb.FirebaseAuth.instance.currentUser?.emailVerified == true;

        // “Admin like”: admin único o admin en contexto
        final bool isAdminUnico = permisos.isAdminGlobal;
        final bool isAdmin = auth.isAdmin; // si tu AuthProvider lo expone
        final bool isAdminLike = isAdminUnico || isAdmin;

        switch (settings.name) {
        // ========= AUTH =========
          case '/login':
            return const LoginScreen();
          case '/register':
            return const RegisterScreen();
          case '/pending':
            return const PendingScreen();
          case '/verifyEmail':
            return const VerifyEmailScreen();

        // ========= ADMIN =========
          case '/admin':
            return _redirect(context, '/admin/dashboard');

          case '/admin/dashboard':
            if (!isLoggedIn) return _redirect(context, '/login');
            if (!approved) return _redirect(context, '/pending');
            if (!isAdminUnico) return _redirect(context, '/dashboard');
            return const DashboardAdminScreen();

          case '/admin/usuarios':
            if (!isLoggedIn) return _redirect(context, '/login');
            if (!approved) return _redirect(context, '/pending');
            if (!isAdminUnico) return _redirect(context, '/dashboard');
            return const UsuariosScreen();

          case '/admin/roles':
            if (!isLoggedIn) return _redirect(context, '/login');
            if (!approved) return _redirect(context, '/pending');
            if (!isAdminUnico) return _redirect(context, '/dashboard');
            return const RolesScreen();

          case '/admin/categorias':
            if (!isLoggedIn) return _redirect(context, '/login');
            if (!approved) return _redirect(context, '/pending');
            if (!isAdminUnico) return _redirect(context, '/dashboard');
            return const CategoriasScreen();

          case '/admin/permisos':
            if (!isLoggedIn) return _redirect(context, '/login');
            if (!approved) return _redirect(context, '/pending');
            if (!isAdminUnico) return _redirect(context, '/dashboard');
            return const PermisosScreen();

          case '/admin/proyectos':
            if (!isLoggedIn) return _redirect(context, '/login');
            if (!approved) return _redirect(context, '/pending');
            if (!isAdminUnico) return _redirect(context, '/dashboard');
            return const ProyectosAdminScreen();

        // ========= SELECCIÓN / DASHBOARD =========
          case '/seleccion':
            if (!isLoggedIn) return const LoginScreen();
            if (!approved) return const PendingScreen();
            if (!isAdminLike && !emailVerified) {
              return const VerifyEmailScreen();
            }
            return const SeleccionRolProyectoScreen();

          case '/dashboard':
            {
              if (!isLoggedIn) return const LoginScreen();
              if (!approved) return const PendingScreen();
              if (!isAdminLike && !emailVerified) {
                return const VerifyEmailScreen();
              }

              return ChangeNotifierProvider(
                create: (ctx) => NotificacionProvider(
                  FirebaseFirestore.instance, // 👈 1er parámetro: Firestore
                  ctx.read<AuthProvider>(), // 👈 2º parámetro: AuthProvider
                ),
                child: const DashboardScreen(
                  skipAutoNavFromRoute: true,
                ),
              );
            }

        // ========= PERFIL =========
          case '/perfil':
            if (!isLoggedIn) return _redirect(context, '/login');
            if (!approved) return _redirect(context, '/pending');
            if (!isAdminLike && !emailVerified) {
              return _redirect(context, '/verifyEmail');
            }
            return const PerfilScreen();

        // ========= PROYECTOS =========
          case '/proyectos/list':
            if (!isLoggedIn) return _redirect(context, '/login');
            if (!approved) return _redirect(context, '/pending');
            if (!isAdminLike && !emailVerified) {
              return _redirect(context, '/verifyEmail');
            }
            if (!permisos.canViewProjects) {
              return _redirect(context, '/dashboard');
            }
            return const ListaProyectosScreen();

          case '/proyectos/add':
          case '/proyectos/crear':
            {
              if (!isLoggedIn) return _redirect(context, '/login');
              if (!approved) return _redirect(context, '/pending');
              if (!isAdminLike && !emailVerified) {
                return _redirect(context, '/verifyEmail');
              }

              final args = settings.arguments;
              final bool allowFromSeleccion =
                  (args is Map) && (args['allowFromSeleccion'] == true);

              final bool puedeCrear =
                  isAdminUnico || permisos.canCreateProject || allowFromSeleccion;

              if (!puedeCrear) return _redirect(context, '/proyectos/list');
              return const AgregarProyectoScreen();
            }

          case '/proyectos/edit':
            {
              if (!isLoggedIn) return _redirect(context, '/login');
              if (!approved) return _redirect(context, '/pending');
              if (!isAdminLike && !emailVerified) {
                return _redirect(context, '/verifyEmail');
              }
              if (!permisos.canEditProject) {
                return _redirect(context, '/proyectos/list');
              }

              final id = settings.arguments as String?;
              if (id == null || id.trim().isEmpty) {
                return _redirect(context, '/proyectos/list');
              }
              return EditarProyectoScreen(proyectoId: id);
            }

          case '/proyectos/equipo':
            {
              if (!isLoggedIn) return _redirect(context, '/login');
              if (!approved) return _redirect(context, '/pending');
              if (!isAdminLike && !emailVerified) {
                return _redirect(context, '/verifyEmail');
              }
              if (!permisos.canViewProjects) {
                return _redirect(context, '/proyectos/list');
              }

              final args = settings.arguments;
              String? id;
              if (args is String && args.trim().isNotEmpty) {
                id = args.trim();
              } else if (args is Map) {
                final maybe = args['proyectoId'] ?? args['id'] ?? args['pid'];
                if (maybe is String && maybe.trim().isNotEmpty) {
                  id = maybe.trim();
                }
              }
              if (id == null) return _redirect(context, '/proyectos/list');

              final bool mayManage = permisos.canManageCollaboratorsFor(id);
              if (!mayManage) return _redirect(context, '/proyectos/list');

              return EquipoProyectoScreen(proyectoId: id);
            }

          case '/proyectos/detalle':
            {
              if (!isLoggedIn) return _redirect(context, '/login');
              if (!approved) return _redirect(context, '/pending');
              if (!isAdminLike && !emailVerified) {
                return _redirect(context, '/verifyEmail');
              }
              if (!permisos.canViewProjects) {
                return _redirect(context, '/proyectos/list');
              }

              final args = settings.arguments;
              String? id;
              if (args is String && args.trim().isNotEmpty) {
                id = args.trim();
              } else if (args is Map) {
                final maybe = args['proyectoId'] ?? args['id'] ?? args['pid'];
                if (maybe is String && maybe.trim().isNotEmpty) {
                  id = maybe.trim();
                }
              }
              if (id == null) return _redirect(context, '/proyectos/list');

              final bool isOwnerContext = permisos.isDuenoEnContexto &&
                  (auth.selectedRolProyecto?.idProyecto == id);

              if (isOwnerContext) {
                return DetalleProyectoDuenoScreen(proyectoId: id);
              }
              return proj_detalle.DetalleProyectoScreen(proyectoId: id);
            }

          case '/proyectos/detalle_dueno':
            {
              if (!isLoggedIn) return _redirect(context, '/login');
              if (!approved) return _redirect(context, '/pending');
              if (!isAdminLike && !emailVerified) {
                return _redirect(context, '/verifyEmail');
              }
              if (!permisos.canViewProjects) {
                return _redirect(context, '/proyectos/list');
              }

              final args = settings.arguments;
              String? id;
              if (args is String && args.trim().isNotEmpty) {
                id = args.trim();
              } else if (args is Map) {
                final maybe = args['proyectoId'] ?? args['id'] ?? args['pid'];
                if (maybe is String && maybe.trim().isNotEmpty) {
                  id = maybe.trim();
                }
              }
              if (id == null) return _redirect(context, '/proyectos/list');

              final bool isOwnerContext = permisos.isDuenoEnContexto &&
                  (auth.selectedRolProyecto?.idProyecto == id);

              if (isAdminUnico) {
                return DetalleProyectoDuenoScreen(proyectoId: id);
              }
              if (!isOwnerContext) {
                if (permisos.isDuenoGlobal) {
                  return _redirect(context, '/proyectos/list');
                }
                return _redirect(context, '/proyectos/list');
              }
              return DetalleProyectoDuenoScreen(proyectoId: id);
            }

        // ========= OBSERVACIONES =========
          case '/observaciones/list':
            {
              if (!kObservacionesHabilitadas) {
                return _redirect(context, '/dashboard');
              }
              if (!isLoggedIn) return _redirect(context, '/login');
              if (!approved) return _redirect(context, '/pending');
              if (!isAdminLike && !emailVerified) {
                return _redirect(context, '/verifyEmail');
              }
              if (!permisos.canViewObservations) {
                return _redirect(context, '/dashboard');
              }
              return const ListaObservacionesScreen();
            }

          case '/observaciones/captura_rapida':
            {
              if (!kObservacionesHabilitadas) {
                return _redirect(context, '/dashboard');
              }
              if (!isLoggedIn) return _redirect(context, '/login');
              if (!approved) return _redirect(context, '/pending');
              if (!isAdminLike && !emailVerified) {
                return _redirect(context, '/verifyEmail');
              }

              final args = (settings.arguments as Map?) ?? const {};
              final String? proyectoId = args['proyectoId'] as String?;
              final String? uidUsuario = args['uidUsuario'] as String?;

              if (proyectoId == null || proyectoId.trim().isEmpty) {
                return _redirect(context, '/observaciones/list');
              }
              if (!permisos.canCreateObservationInProject(proyectoId)) {
                return _redirect(context, '/observaciones/list');
              }
              if (uidUsuario == null ||
                  (uidUsuario != auth.uid && !permisos.isAdminUnico)) {
                return _redirect(context, '/observaciones/list');
              }
              return CapturaRapidaScreen(
                  proyectoId: proyectoId, uidUsuario: uidUsuario);
            }

          case '/observaciones/add':
            {
              if (!kObservacionesHabilitadas) {
                return _redirect(context, '/dashboard');
              }
              if (!isLoggedIn) return _redirect(context, '/login');
              if (!approved) return _redirect(context, '/pending');
              if (!isAdminLike && !emailVerified) {
                return _redirect(context, '/verifyEmail');
              }

              final args = (settings.arguments as Map?) ?? const {};
              final String? proyectoId = args['proyectoId'] as String?;
              final String? uidUsuario = args['uidUsuario'] as String?;

              if (uidUsuario == null ||
                  uidUsuario.trim().isEmpty ||
                  (uidUsuario != auth.uid && !permisos.isAdminUnico)) {
                return _redirect(context, '/observaciones/list');
              }

              final bool puedeCrear = (proyectoId == null ||
                  proyectoId.trim().isEmpty)
                  ? permisos.canCreateObservationSinProyecto
                  : permisos.canCreateObservationInProject(proyectoId);

              if (!puedeCrear) return _redirect(context, '/observaciones/list');

              return const AgregarObservacionScreen();
            }

          case '/observaciones/approve':
            {
              if (!kObservacionesHabilitadas) {
                return _redirect(context, '/dashboard');
              }
              if (!isLoggedIn) return _redirect(context, '/login');
              if (!approved) return _redirect(context, '/pending');
              if (!isAdminLike && !emailVerified) {
                return _redirect(context, '/verifyEmail');
              }

              final args = settings.arguments;
              final String? obsId =
              (args is String && args.trim().isNotEmpty)
                  ? args.trim()
                  : null;
              if (obsId == null) {
                return _redirect(context, '/observaciones/list');
              }

              return AprobarObservacionScreen(observacionId: obsId);
            }

        // ======= NUEVOS: EDITAR (NUBE) y EDITAR LOCAL =======
          case '/observaciones/edit':
            {
              if (!kObservacionesHabilitadas) {
                return _redirect(context, '/dashboard');
              }
              if (!isLoggedIn) return _redirect(context, '/login');
              if (!approved) return _redirect(context, '/pending');
              if (!isAdminLike && !emailVerified) {
                return _redirect(context, '/verifyEmail');
              }

              // Si viene obsId como String, validamos que no esté vacío.
              final args = settings.arguments;
              final String? obsId =
              (args is String && args.trim().isNotEmpty)
                  ? args.trim()
                  : null;
              if (obsId == null) {
                return _redirect(context, '/observaciones/list');
              }

              // La pantalla leerá el obsId desde ModalRoute.
              return const EditarObservacionScreen();
            }

          case '/observaciones/editLocal':
            {
              if (!kObservacionesHabilitadas) {
                return _redirect(context, '/dashboard');
              }
              if (!isLoggedIn) return _redirect(context, '/login');
              if (!approved) return _redirect(context, '/pending');
              if (!isAdminLike && !emailVerified) {
                return _redirect(context, '/verifyEmail');
              }

              final args = (settings.arguments as Map?) ?? const {};
              final String? dirPath = args['dirPath'] as String?;

              if (dirPath == null || dirPath.trim().isEmpty) {
                return _redirect(context, '/observaciones/list');
              }

              // La pantalla leerá dirPath/meta desde ModalRoute.
              return const EditarLocalObservacionScreen();
            }

          default:
            if (!isLoggedIn) return const LoginScreen();
            if (!approved) return const PendingScreen();
            if (!isAdminLike && !emailVerified) {
              return const VerifyEmailScreen();
            }

            return ChangeNotifierProvider(
              create: (ctx) => NotificacionProvider(
                FirebaseFirestore.instance,
                ctx.read<AuthProvider>(),
              ),
              child: const DashboardScreen(),
            );
        }
      },
    );
  }

  /// Navegación diferida y segura (renderiza vacío mientras hace pushReplacementNamed).
  static Widget _redirect(BuildContext context, String route) {
    final current = ModalRoute.of(context)?.settings.name;
    if (current == route) return const SizedBox.shrink();
    Future.microtask(() {
      final nav = Navigator.of(context);
      if (!nav.mounted) return;
      nav.pushReplacementNamed(route);
    });
    return const SizedBox.shrink();
  }
}
