// lib/utils/constants.dart
import 'package:faunadmin2/models/rol.dart';

/// ==============================
///  ROLES / IDS CANÓNICOS
/// ==============================
/// Delegamos SIEMPRE a `Rol.*` para evitar desalineaciones con semillas
/// o catálogos. Si cambias los IDs en `Rol,
class RoleIds {
  static const int admin         = Rol.admin;
  static const int supervisor    = Rol.supervisor;
  static const int recolector    = Rol.recolector;
  static const int dueno         = Rol.duenoProyecto;
  static const int colaborador   = Rol.colaborador;

  // Alias de compatibilidad con código existente
  static const int duenoProyecto = dueno;
}

/// Etiquetas legibles de roles (para UI)
const Map<int, String> kRoleLabels = {
  RoleIds.admin:       'ADMINISTRADOR',
  RoleIds.supervisor:  'SUPERVISOR',
  RoleIds.recolector:  'RECOLECTOR',
  RoleIds.dueno:       'DUEÑO DE PROYECTO',
  RoleIds.colaborador: 'COLABORADOR',
};

/// ==============================
///  NOMBRES DE COLECCIONES
/// ==============================
class Collections {
  static const String usuarios           = 'usuarios';
  static const String roles              = 'roles';
  static const String proyectos          = 'proyectos';
  static const String categorias         = 'categorias';
  static const String observaciones      = 'observaciones';
  static const String usuarioRolProyecto = 'usuario_rol_proyecto';
}

/// ==============================
///  CAMPOS (REFERENCIALES)
/// ==============================
/// Úsalos solo si de verdad te ayudan a evitar strings mágicos.
/// No son requeridos por el sistema.
class UsuarioFields {
  static const String nombre       = 'nombre';
  static const String correo       = 'correo';
  static const String estadoCuenta = 'estado_cuenta'; // 'pendiente' | 'aprobado' | ...
  static const String esAdmin      = 'is_admin';      // bool
}

class ProyectoFields {
  static const String nombre       = 'nombre';
  static const String descripcion  = 'descripcion';
  static const String estado       = 'estado';        // 'pendiente' | 'en_proceso' | 'terminado'
  static const String categoriaId  = 'categoria_id';
  static const String uidDueno     = 'uid_dueno';
  static const String fechaInicio  = 'fecha_inicio';
}

class URPFields {
  static const String idProyecto = 'id_proyecto';
  static const String uidUsuario = 'uid_usuario';
  static const String idRol      = 'id_rol';
  static const String createdAt  = 'created_at';
}

/// ==============================
///  ESTADOS DE PROYECTO / CUENTA
/// ==============================
class EstadosProyecto {
  static const String pendiente = 'pendiente';
  static const String enProceso = 'en_proceso';
  static const String terminado = 'terminado';
}

class EstadosCuenta {
  static const String pendiente  = 'pendiente';
  static const String aprobado   = 'aprobado';
  static const String inactivo   = 'inactivo';
  static const String reactivado = 'reactivado';
}

/// Lista útil para filtros de proyectos "activos"
const List<String> kEstadosProyectoActivos = [
  EstadosProyecto.pendiente,
  EstadosProyecto.enProceso,
];

/// Tamaño recomendado para dividir listas en consultas whereIn
const int kWhereInChunkSize = 10;

/// ==============================
///  HELPERS
/// ==============================

/// Genera un ID de documento idempotente para `usuario_rol_proyecto`
/// Formato: "<idProyecto>_<uidUsuario>_<idRol>"
String urpDocId({
  required String idProyecto,
  required String uidUsuario,
  required int idRol,
}) =>
    '${idProyecto}_${uidUsuario}_$idRol';
/// ==============================
///  TÉRMINOS Y CONDICIONES
/// ==============================

/// Versión vigente de los términos (cámbiala cuando edites el .md)
const String kTerminosVersion = 'v1-2025-09-09';

/// Ruta del asset con el texto (por si la necesitas en más pantallas)
const String kTerminosAssetPath =
    'assets/politicas/terminos_condiciones_v1-2025-09-09.md';

/// Colección opcional para bitácora ligera de consentimientos
class ConsentCollections {
  static const String consentLogs = 'consent_logs';
}

/// Helper para construir el string que guardamos en usuarios/{uid}.terminos
String buildTerminosValue({
  String version = kTerminosVersion,
  DateTime? whenUtc,
}) {
  final t = (whenUtc ?? DateTime.now().toUtc()).toIso8601String();
  return '$version|ACEPTADO|$t';
}
/// ==============================
///  ESTADOS DE OBSERVACIÓN
/// ==============================
class EstadosObservacion {
  static const String pendiente = 'pendiente';
  static const String aprobado  = 'aprobado';
  static const String rechazado = 'rechazado';
}

/// ==============================
///  AGRUPADORES DE ROLES (helpers)
/// ==============================
class RoleSets {
  /// Quienes pueden gestionar equipo del proyecto (según nuestra lógica)
  static const Set<int> gestoresEquipo = {
    RoleIds.admin,
    RoleIds.supervisor,
    RoleIds.dueno,
  };

  /// Quienes pueden capturar observaciones con proyecto en contexto
  static const Set<int> captoresConProyecto = {
    RoleIds.admin,
    RoleIds.supervisor,
    RoleIds.dueno,
    RoleIds.colaborador,
    RoleIds.recolector,
  };
}
