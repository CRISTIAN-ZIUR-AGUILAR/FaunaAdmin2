// lib/services/firestore_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:faunadmin2/services/permisos_service.dart';
import 'package:faunadmin2/models/usuario.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/models/rol.dart';
import 'package:faunadmin2/models/categoria.dart';
import 'package:faunadmin2/models/proyecto.dart';
import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/models/usuario_rol_proyecto.dart';
import 'package:faunadmin2/models/photo_media.dart';
// IMPORTANTE: utilidades de claves de categoría
import 'package:faunadmin2/utils/categorias_utils.dart' as cats;

// NUEVO: constantes y helpers (RoleIds, urpDocId, etc.)
import 'package:faunadmin2/utils/constants.dart';

// NUEVO: errores con código para la UI
import 'package:faunadmin2/utils/app_error.dart';

// ===== Alcance de visibilidad para listados =====
enum ObsScope { all, byProjects, own }

// Helper para añadir filtro por estado de forma opcional
extension _EstadoQueryExt on Query<Map<String, dynamic>> {
  Query<Map<String, dynamic>> withEstado(String? estado) {
    if (estado == null || estado.trim().isEmpty) return this;
    return where('estado', isEqualTo: estado);
  }
}

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Helper interno para normalizar strings
  String _norm(String s) => s.trim().toUpperCase();

  // —— Helper: ¿ya existe un admin global? (id_proyecto == null, activo = true)
  Future<bool> _existeAdminGlobal({String? exceptUid}) async {
    final qs = await _db
        .collection('usuario_rol_proyecto')
        .where('id_rol', isEqualTo: RoleIds.admin)
        .where('id_proyecto', isNull: true)
        .where('activo', isEqualTo: true)
        .get();

    if (qs.docs.isEmpty) return false;
    if (exceptUid == null) return true;
    return qs.docs.any((d) => (d.data()['uid_usuario'] as String?) != exceptUid);
  }

  // ➕ Helper: resolver nombre legible del rol
  String _rolNombreFromId(int id) {
    switch (id) {
      case RoleIds.admin:
        return 'Administrador';
      case RoleIds.supervisor:
        return 'Supervisor';
      case RoleIds.duenoProyecto:
        return 'Dueño de Proyecto';
      case RoleIds.colaborador:
        return 'Colaborador';
      case RoleIds.recolector:
        return 'Recolector';
      default:
        return 'Rol $id';
    }
  }

  // ========= NUEVO: helper para checar si existe una URP exacta =========
  Future<bool> _existsUrp({
    required String idProyecto,
    required String uidUsuario,
    required int idRol,
  }) async {
    final docId = urpDocId(
      idProyecto: idProyecto,
      uidUsuario: uidUsuario,
      idRol: idRol,
    );
    final snap = await _db.collection('usuario_rol_proyecto').doc(docId).get();
    if (snap.exists) {
      final data = snap.data()!;
      final activo = data['activo'];
      return activo == null || activo == true;
    }
    // Fallback por si hay docs legados duplicados:
    final q = await _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: idProyecto)
        .where('uid_usuario', isEqualTo: uidUsuario)
        .where('id_rol', isEqualTo: idRol)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return false;
    final activo = q.docs.first.data()['activo'];
    return activo == null || activo == true;
  }

  // =======================
  //        USUARIOS
  // =======================

  Stream<List<Usuario>> streamUsuarios() => _db
      .collection('usuarios')
      .snapshots()
      .map((snap) => snap.docs.map((d) => Usuario.fromMap(d.data(), d.id)).toList());

  // 🔧 Orden estable por fecha_registro (desc)
  Stream<List<Usuario>> streamUsuariosPorEstatus(String estatus) => _db
      .collection('usuarios')
      .where('estatus', isEqualTo: estatus)
      .orderBy('fecha_registro', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Usuario.fromMap(d.data(), d.id)).toList());

  /// Alias útil para llenar dropdowns de asignación (estatus = 'aprobado')
  Stream<List<Usuario>> streamUsuariosAprobados() => streamUsuariosPorEstatus('aprobado');

  Future<Usuario> getUsuario(String uid) async {
    final ref = _db.collection('usuarios').doc(uid);
    final doc = await ref.get();

    if (!doc.exists || doc.data() == null) {
      await ref.set({
        'nombre_completo': '',
        'correo': '',
        'formacion': '',
        'nivel_academico': '',
        'estatus': 'pendiente',
        'fecha_registro': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final created = await ref.get();
      return Usuario.fromMap(created.data()!, created.id);
    }

    return Usuario.fromMap(doc.data()!, doc.id);
  }

  Future<void> setUsuario(Usuario u) =>
      _db.collection('usuarios').doc(u.uid).set(u.toMap(), SetOptions(merge: true));

  Future<void> deleteUsuario(String uid) => _db.collection('usuarios').doc(uid).delete();

  Future<void> aprobarUsuario({
    required String uidUsuario,
    required String uidAdmin,
  }) async {
    await _db.collection('usuarios').doc(uidUsuario).set({
      'estatus': 'aprobado',
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': uidAdmin,
    }, SetOptions(merge: true));
  }

  Future<void> rechazarUsuario(String uidUsuario) async {
    await _db.collection('usuarios').doc(uidUsuario).set(
      {'estatus': 'rechazado'},
      SetOptions(merge: true),
    );
  }

  /// Aprueba usuario y le asigna rol global ADMIN (id_proyecto == null).
  /// Enforce: SOLO puede existir un admin global en todo el sistema.
  Future<void> aprobarUsuarioComoAdmin({
    required String uidUsuario,
    required String uidAdmin,
  }) async {
    // Bloquear si ya hay OTRO admin global
    final hayOtro = await _existeAdminGlobal(exceptUid: uidUsuario);
    if (hayOtro) {
      throw AppError.unknown('Ya existe un Administrador global. Solo puede haber uno.');
    }

    final batch = _db.batch();

    final usuarioRef = _db.collection('usuarios').doc(uidUsuario);
    batch.set(
      usuarioRef,
      {
        'estatus': 'aprobado',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': uidAdmin,
        'is_admin': true, // Flag de admin único
      },
      SetOptions(merge: true),
    );

    // (Compat/legado) mantener un URP global de admin si ya lo usas en otros sitios
    final rolesCol = _db.collection('usuario_rol_proyecto');
    final exists = await rolesCol
        .where('uid_usuario', isEqualTo: uidUsuario)
        .where('id_rol', isEqualTo: RoleIds.admin)
        .where('id_proyecto', isNull: true)
        .limit(1)
        .get();

    if (exists.docs.isEmpty) {
      final urpRef = rolesCol.doc();
      batch.set(urpRef, {
        'uid_usuario': uidUsuario,
        'id_rol': RoleIds.admin,
        'rol_nombre': 'Administrador',
        'id_proyecto': null, // GLOBAL
        'activo': true,
        'asignadoAt': FieldValue.serverTimestamp(),
        'asignadoBy': uidAdmin,
      });
    }

    await batch.commit();
  }

  // =======================
  //         ROLES
  // =======================

  Stream<List<Rol>> streamRoles() => _db
      .collection('roles')
      .snapshots()
      .map((snap) => snap.docs.map((d) => Rol.fromMap(d.data())).toList());

  Future<List<Rol>> getRolesOnce() async {
    final qs = await _db.collection('roles').get();
    return qs.docs.map((d) => Rol.fromMap(d.data())).toList();
  }

  Future<void> setRol(Rol r) => _db.collection('roles').doc(r.id.toString()).set(r.toMap());

  Future<void> deleteRol(int id) => _db.collection('roles').doc(id.toString()).delete();

  /// Roles GLOBALes (id_proyecto == null) del usuario (devuelve IDs únicos)
  /// (⚠️ Solo se usa ya para admin legacy)
  Future<List<int>> getRolesGlobalesIds(String uid) async {
    final qs = await _db
        .collection('usuario_rol_proyecto')
        .where('uid_usuario', isEqualTo: uid)
        .where('id_proyecto', isNull: true)
        .where('activo', isEqualTo: true)
        .get();
    final ids = <int>{};
    for (final d in qs.docs) {
      final m = d.data();
      final id = (m['id_rol'] as num?)?.toInt();
      if (id != null) ids.add(id);
    }
    return ids.toList();
  }

  // =======================
  //       CATEGORÍAS
  // =======================

  // --------- Globales ---------
  Stream<List<Categoria>> streamCategoriasGlobales() {
    return _db
        .collection('categorias')
        .orderBy('nombre')
        .snapshots()
        .map((q) => q.docs.map((d) => Categoria.fromMap(d.data())).toList());
  }

  // Alias para compatibilidad con código viejo
  Stream<List<Categoria>> streamCategorias() => streamCategoriasGlobales();

  Future<int> _nextCategoriaGlobalId() async {
    final ref = _db.collection('meta').doc('categorias_counter');
    return _db.runTransaction<int>((tx) async {
      final snap = await tx.get(ref);
      final last = snap.exists ? (snap.data()!['last'] as num).toInt() : 0;
      final next = last + 1;
      tx.set(ref, {'last': next});
      return next;
    });
  }

  /// Crear global SOLO con nombre (la clave se genera y queda congelada)
  Future<void> createCategoriaGlobalNombre({required String nombre}) async {
    final name = nombre.trim();
    if (name.isEmpty) {
      throw AppError.unknown('El nombre es requerido');
    }

    final dup = await _db
        .collection('categorias')
        .where('nombre_norm', isEqualTo: _norm(name))
        .limit(1)
        .get();
    if (dup.docs.isNotEmpty) {
      throw AppError.unknown('Ya existe una categoría con ese nombre');
    }

    // Clave única: base por nombre + resolver colisiones
    final existentesSnap = await _db.collection('categorias').get();
    final existentes = existentesSnap.docs
        .map((d) => (d.data()['clave'] as String?)?.toUpperCase())
        .whereType<String>()
        .toSet();

    final base = cats.claveBaseDesdeNombre(name);
    final clave = cats.claveUnica(base, existentes);

    final id = await _nextCategoriaGlobalId();
    await _db.collection('categorias').doc(id.toString()).set({
      'id_categoria': id,
      'nombre': name,
      'nombre_norm': _norm(name),
      'clave': clave,
      'is_protected': false,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCategoriaGlobalNombre({
    required int id,
    required String nombre,
  }) async {
    final name = nombre.trim();
    if (name.isEmpty) {
      throw AppError.unknown('El nombre es requerido');
    }

    final dup =
    await _db.collection('categorias').where('nombre_norm', isEqualTo: _norm(name)).get();
    final existeOtro =
    dup.docs.any((d) => ((d.data()['id_categoria'] as num?)?.toInt() ?? -1) != id);
    if (existeOtro) {
      throw AppError.unknown('Ya existe otra categoría con ese nombre');
    }

    // Nota: NO cambiamos 'clave' para mantener estabilidad histórica
    await _db.collection('categorias').doc(id.toString()).update({
      'nombre': name,
      'nombre_norm': _norm(name),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCategoriaGlobal(int id) async {
    final doc = await _db.collection('categorias').doc(id.toString()).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    if (data['is_protected'] == true) {
      throw AppError.unknown('Categoría protegida (inborrable)');
    }

    final enUso =
    await _db.collection('proyectos').where('id_categoria', isEqualTo: id).limit(1).get();
    if (enUso.docs.isNotEmpty) {
      throw AppError.unknown('No se puede eliminar: hay proyectos que la usan');
    }

    await doc.reference.delete();
  }

  /// Sembrar básicas
  Future<void> seedCategoriasBasicas() async {
    final base = const [
      {'nombre': 'Actividades complementarias', 'clave': 'AC'},
      {'nombre': 'Ecología II', 'clave': 'EC'},
      {'nombre': 'Taller de Fauna', 'clave': 'TF'},
      {'nombre': 'Residencia', 'clave': 'RS'},
      {'nombre': 'Proyecto de Investigación', 'clave': 'PI'},
      {'nombre': 'Otro', 'clave': 'OT'},
    ];

    final ya = (await _db
        .collection('categorias')
        .where(
      'nombre_norm',
      whereIn: base.map((e) => _norm(e['nombre']!)).toList(),
    )
        .get())
        .docs
        .map((d) => (d.data()['nombre_norm'] as String))
        .toSet();

    for (final e in base) {
      if (!ya.contains(_norm(e['nombre']!))) {
        final id = await _nextCategoriaGlobalId();
        await _db.collection('categorias').doc(id.toString()).set({
          'id_categoria': id,
          'nombre': e['nombre']!,
          'nombre_norm': _norm(e['nombre']!),
          'clave': e['clave']!,
          'is_protected': true,
          'created_at': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  // --------- Por proyecto ---------
  Stream<List<Categoria>> streamCategoriasDeProyecto(String proyectoId) {
    return _db
        .collection('proyectos')
        .doc(proyectoId)
        .collection('categorias')
        .orderBy('nombre')
        .snapshots()
        .map((q) => q.docs.map((d) => Categoria.fromMap(d.data())).toList());
  }

  Future<int> _nextCategoriaProyectoId(String proyectoId) async {
    final ref =
    _db.collection('proyectos').doc(proyectoId).collection('meta').doc('categorias_counter');
    return _db.runTransaction<int>((tx) async {
      final snap = await tx.get(ref);
      final last = snap.exists ? (snap.data()!['last'] as num).toInt() : 0;
      final next = last + 1;
      tx.set(ref, {'last': next});
      return next;
    });
  }

  Future<void> createCategoriaDeProyectoNombre({
    required String proyectoId,
    required String nombre,
  }) async {
    final name = nombre.trim();
    if (name.isEmpty) {
      throw AppError.unknown('El nombre es requerido');
    }

    final dup = await _db
        .collection('proyectos')
        .doc(proyectoId)
        .collection('categorias')
        .where('nombre_norm', isEqualTo: _norm(name))
        .limit(1)
        .get();
    if (dup.docs.isNotEmpty) {
      throw AppError.unknown('Ya existe en este proyecto');
    }

    final existentesSnap =
    await _db.collection('proyectos').doc(proyectoId).collection('categorias').get();
    final existentes = existentesSnap.docs
        .map((d) => (d.data()['clave'] as String?)?.toUpperCase())
        .whereType<String>()
        .toSet();

    final base = cats.claveBaseDesdeNombre(name);
    final clave = cats.claveUnica(base, existentes);

    final id = await _nextCategoriaProyectoId(proyectoId);
    await _db
        .collection('proyectos')
        .doc(proyectoId)
        .collection('categorias')
        .doc(id.toString())
        .set({
      'id_categoria': id,
      'nombre': name,
      'nombre_norm': _norm(name),
      'clave': clave,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCategoriaDeProyectoNombre({
    required String proyectoId,
    required int idCategoria,
    required String nombre,
  }) async {
    final name = nombre.trim();
    if (name.isEmpty) {
      throw AppError.unknown('El nombre es requerido');
    }

    final dup = await _db
        .collection('proyectos')
        .doc(proyectoId)
        .collection('categorias')
        .where('nombre_norm', isEqualTo: _norm(name))
        .get();
    final existeOtro =
    dup.docs.any((d) => ((d.data()['id_categoria'] as num?)?.toInt() ?? -1) != idCategoria);
    if (existeOtro) {
      throw AppError.unknown('Ya existe otra categoría con ese nombre en este proyecto');
    }

    await _db
        .collection('proyectos')
        .doc(proyectoId)
        .collection('categorias')
        .doc(idCategoria.toString())
        .update({
      'nombre': name,
      'nombre_norm': _norm(name),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCategoriaDeProyecto(String proyectoId, int idCategoria) async {
    await _db
        .collection('proyectos')
        .doc(proyectoId)
        .collection('categorias')
        .doc(idCategoria.toString())
        .delete();
  }

  @deprecated
  Future<void> setCategoria(Categoria c) =>
      _db.collection('categorias').doc(c.id.toString()).set(c.toMap());

  @deprecated
  Future<void> deleteCategoria(int id) =>
      _db.collection('categorias').doc(id.toString()).delete();

  // =======================
  //        PROYECTOS
  // =======================

  Stream<List<Proyecto>> streamProyectos() => _db
      .collection('proyectos')
      .snapshots()
      .map((snap) => snap.docs.map((d) => Proyecto.fromMap(d.data(), d.id)).toList());

  /// Crea y devuelve el id del doc garantizando `uid_dueno` y defaults.
  Future<String> createProyecto(Proyecto p, {String? uidDueno}) async {
    final owner = (uidDueno ?? p.uidDueno);
    if (owner == null || owner.isEmpty) {
      throw AppError.unknown('uid_dueno es requerido para crear proyecto');
    }
    final data = Map<String, dynamic>.from(p.toMap());
    data['uid_dueno'] = owner; // forzamos dueño siempre
    data['fecha_inicio'] ??= FieldValue.serverTimestamp();
    data['activo'] ??= true;

    final ref = await _db.collection('proyectos').add(data);
    return ref.id;
  }

  Future<String> createProyectoConDueno(Proyecto p, {required String uidDueno}) {
    return createProyecto(p, uidDueno: uidDueno);
  }

  Future<void> addProyecto(Proyecto p) => _db.collection('proyectos').add(p.toMap());

  Future<void> updateProyecto(Proyecto p) =>
      _db.collection('proyectos').doc(p.id).update(p.toMap());

  Future<void> deleteProyecto(String id) => _db.collection('proyectos').doc(id).delete();

  /// 🔴 NUEVO: stream de proyectos cuyo `uid_dueno` == uid
  Stream<List<Proyecto>> streamProyectosByOwner(String uid) {
    return _db
        .collection('proyectos')
        .where('uid_dueno', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Proyecto.fromMap(d.data(), d.id)).toList());
  }

  /// Proyectos cuyo `uid_dueno` == uid
  Future<List<Proyecto>> queryProyectosByOwner(String uid) async {
    final qs = await _db.collection('proyectos').where('uid_dueno', isEqualTo: uid).get();
    return qs.docs.map((d) => Proyecto.fromMap(d.data(), d.id)).toList();
  }

  /// Proyectos cuyo `uid_supervisor` == uid (campo directo, compatibilidad)
  Future<List<Proyecto>> queryProyectosBySupervisor(String uid) async {
    final qs =
    await _db.collection('proyectos').where('uid_supervisor', isEqualTo: uid).get();
    return qs.docs.map((d) => Proyecto.fromMap(d.data(), d.id)).toList();
  }

  /// Asignar / limpiar supervisor del proyecto (CAMPO DIRECTO)
  /// (Compatibilidad con UI vieja; preferible usar URP)
  Future<void> setSupervisorForProject({
    required String proyectoId,
    required String uidSupervisor,
    String? asignadoBy,
  }) async {
    await _db.collection('proyectos').doc(proyectoId).set({
      'uid_supervisor': uidSupervisor,
      if (asignadoBy != null) 'supervisorAsignadoBy': asignadoBy,
      'supervisorAsignadoAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// ✅ Ya no exige “rol global de supervisor”. Basta con estar aprobado.
  Future<void> setSupervisorForProjectChecked({
    required String proyectoId,
    required String uidSupervisor,
    required String uidAdmin,
  }) async {
    final u = await getUsuario(uidSupervisor);
    if (u.estatus.toLowerCase() != 'aprobado') {
      throw AppError.unknown('El usuario seleccionado aún no está aprobado.');
    }
    await setSupervisorForProject(
      proyectoId: proyectoId,
      uidSupervisor: uidSupervisor,
      asignadoBy: uidAdmin,
    );
  }

  Future<void> clearSupervisorForProject(String proyectoId) async {
    await _db.collection('proyectos').doc(proyectoId).set({
      'uid_supervisor': FieldValue.delete(),
      'supervisorAsignadoBy': FieldValue.delete(),
      'supervisorAsignadoAt': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  /// Proyectos donde el usuario es COLABORADOR
  Future<List<Proyecto>> queryProyectosComoColaborador(String uid) async {
    final urps = await getUsuarioRolProyectosForUser(uid);
    final ids = urps
        .where((x) => x.idRol == RoleIds.colaborador && x.idProyecto != null)
        .map((x) => x.idProyecto!)
        .toSet()
        .toList();
    return getProyectosPorIds(ids);
  }

  /// Trae proyectos por IDs (chunking de 10 para whereIn)
  Future<List<Proyecto>> getProyectosPorIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final out = <Proyecto>[];
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, (i + 10 > ids.length) ? ids.length : i + 10);
      final snap = await _db
          .collection('proyectos')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      out.addAll(snap.docs.map((d) => Proyecto.fromMap(d.data(), d.id)));
    }
    return out;
  }

  /// Stream / lectura puntual del proyecto
  Stream<Proyecto?> streamProyectoById(String id) {
    return _db.collection('proyectos').doc(id).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return Proyecto.fromMap(data, doc.id);
    });
  }

  Future<Proyecto?> getProyectoOnce(String id) async {
    final doc = await _db.collection('proyectos').doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return Proyecto.fromMap(doc.data()!, doc.id);
  }

  // =======================
  //      OBSERVACIONES
  // =======================

  Query<Map<String, dynamic>> _obsBaseQuery({String? proyectoId}) {
    final col = _db.collection('observaciones');
    if (proyectoId == null) {
      return col.where('id_proyecto', isNull: true);
    }
    return col.where('id_proyecto', isEqualTo: proyectoId);
  }

  /// ======== Preflight de media para "Enviar a revisión" ========
  /// Lee observaciones/{id}/media y resume hallazgos críticos/avisos.
  /// Devuelve un mapa con:
  /// { total:int, hasManipulated:bool, hasNotAnimal:bool, hasSuspect:bool,
  ///   hasNoMetadata:bool, hasStockLike:bool, warningFlags: List<String> }
  Future<Map<String, dynamic>> _preflightMedia(String observacionId) async {
    final col = _db
        .collection('observaciones')
        .doc(observacionId)
        .collection('media');

    final snap = await col.get();
    if (snap.docs.isEmpty) {
      return {
        'total': 0,
        'hasManipulated': false,
        'hasNotAnimal': false,
        'hasSuspect': false,
        'hasNoMetadata': false,
        'hasStockLike': false,
        'warningFlags': const <String>[],
      };
    }

    int total = 0;
    bool manipulated = false;
    bool notAnimal = false;
    bool suspect = false;
    bool noMeta = false;
    bool stockLike = false;
    final warnings = <String>{};

    for (final d in snap.docs) {
      final m = d.data();
      final type = (m['type'] ?? 'photo') as String;
      if (type != 'photo') continue; // por ahora solo foto
      total++;

      final authenticity = (m['authenticity'] as String?) ?? 'unknown';
      final flags = (m['flags'] is List)
          ? (m['flags'] as List).whereType<String>().toList()
          : const <String>[];

      if (authenticity == 'manipulated') manipulated = true;
      if (authenticity == 'suspect') suspect = true;
      if (flags.contains('not_animal')) notAnimal = true;
      if (flags.contains('no_metadata')) noMeta = true;
      if (flags.contains('stock_like')) stockLike = true;

      // flags no-bloqueantes → advertencias
      const warnSet = {
        'no_metadata',
        'stock_like',
        'faces_detected',
        'watermark',
        'multiple_animals',
        'duplicate',
      };
      for (final f in flags) {
        if (warnSet.contains(f)) warnings.add(f);
      }
      if (authenticity == 'suspect') warnings.add('auth_suspect');
    }

    return {
      'total': total,
      'hasManipulated': manipulated,
      'hasNotAnimal': notAnimal,
      'hasSuspect': suspect,
      'hasNoMetadata': noMeta,
      'hasStockLike': stockLike,
      'warningFlags': warnings.toList(),
    };
  }

  /// Stream por proyecto (o sin proyecto si `proyectoId == null`),
  /// opcionalmente filtrado por estado canónico.
  Stream<List<Observacion>> streamObservacionesByProyecto({
    required String? proyectoId, // null = sin proyecto
    String? estado, // null = todos
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> q = _obsBaseQuery(proyectoId: proyectoId)
        .withEstado(estado)
    // Orden principal por fecha de captura (desc) + última modificación para desempatar
        .orderBy('fecha_captura', descending: true)
        .orderBy('ultima_modificacion', descending: true)
        .limit(limit);

    return q.snapshots().map(
          (snap) => snap.docs.map((d) => Observacion.fromMap(d.data(), d.id)).toList(),
    );
  }

  /// Stream de observaciones por alcance:
  /// - ObsScope.all        → Admin único: todas
  /// - ObsScope.byProjects → Owner/Supervisor: de sus proyectos (y opcional “sin proyecto”)
  /// - ObsScope.own        → Colaborador/Recolector: propias
  ///
  /// Maneja whereIn > 10 con chunking y fusiona streams de forma reactiva.
  Stream<List<Observacion>> streamObservacionesByScope({
    required ObsScope scope,
    String? estado,               // 'borrador'|'pendiente'|'aprobado'|'rechazado'|'archivado'|null
    String? uid,                  // requerido si scope==own
    List<String>? projectIds,     // requerido si scope==byProjects
    bool includeSinProyecto = false,
    int limit = 200,
  }) {
    final col = _db.collection('observaciones');

    List<Observacion> _map(QuerySnapshot<Map<String, dynamic>> s) =>
        s.docs.map((d) => Observacion.fromMap(d.data(), d.id)).toList();

    // A) Admin: todo
    if (scope == ObsScope.all) {
      final q = col
          .withEstado(estado)
          .orderBy('fecha_captura', descending: true)
          .limit(limit);
      return q.snapshots().map(_map);
    }

    // B) Propias
    if (scope == ObsScope.own) {
      final u = (uid ?? '').trim();
      if (u.isEmpty) return const Stream.empty();
      final q = col
          .where('uid_usuario', isEqualTo: u)
          .withEstado(estado)
          .orderBy('fecha_captura', descending: true)
          .limit(limit);
      return q.snapshots().map(_map);
    }

    // C) Por proyectos (owner/supervisor) con chunking + fusión reactiva
    final ids = (projectIds ?? const <String>[])
        .where((e) => e.isNotEmpty)
        .toList();

    if (ids.isEmpty && !includeSinProyecto) {
      return const Stream.empty();
    }

    // Partir en chunks de 10 (límite de whereIn)
    final chunks = <List<String>>[];
    const chunkSize = 10;
    for (var i = 0; i < ids.length; i += chunkSize) {
      chunks.add(ids.sublist(i, i + chunkSize > ids.length ? ids.length : i + chunkSize));
    }

    // Construir streams para cada chunk
    final projectStreams = chunks.map((chunk) {
      Query<Map<String, dynamic>> q = col
          .where('id_proyecto', whereIn: chunk)
          .withEstado(estado)
          .orderBy('fecha_captura', descending: true)
          .limit(limit);
      return q.snapshots().map(_map);
    }).toList();

    // Agregar stream de “sin proyecto” si aplica
    if (includeSinProyecto) {
      Query<Map<String, dynamic>> q = col
          .where('id_proyecto', isNull: true)
          .withEstado(estado)
          .orderBy('fecha_captura', descending: true)
          .limit(limit);
      projectStreams.add(q.snapshots().map(_map));
    }

    if (projectStreams.isEmpty) return const Stream.empty();
    if (projectStreams.length == 1) return projectStreams.first;

    // Fusión reactiva de múltiples streams:
    final controller = StreamController<List<Observacion>>.broadcast();
    final subs = <StreamSubscription<List<Observacion>>>[];
    final latestById = <String, Observacion>{};

    void emit() {
      final merged = latestById.values.toList()
        ..sort((a, b) {
          final ad = a.fechaCaptura ?? a.createdAt ?? DateTime(1900);
          final bd = b.fechaCaptura ?? b.createdAt ?? DateTime(1900);
          return bd.compareTo(ad);
        });

      controller.add(merged.take(limit).toList());
    }

    for (final s in projectStreams) {
      subs.add(s.listen((chunk) {
        for (final o in chunk) {
          latestById[o.id!] = o;
        }
        emit();
      }, onError: controller.addError));
    }

    controller.onCancel = () async {
      for (final sub in subs) {
        await sub.cancel();
      }
    };

    return controller.stream;
  }

  /// Crea una observación en BORRADOR (autor = usuario autenticado) DENTRO DE PROYECTO.
  Future<String> createObservacion({
    required AuthProvider auth,
    required String proyectoId,
    required Observacion data, // data.estado debe ser 'borrador'
  }) async {
    final permisos = PermisosService(auth);

    // Gate: crear dentro de proyecto (bloquea a Recolector en proyecto)
    if (!permisos.canCreateObservationInProject(proyectoId)) {
      throw AppError(code: 'obs_forbidden', message: 'No puedes crear observaciones en este proyecto.');
    }

    final uid = auth.uid;
    if (uid == null || data.uidUsuario != uid) {
      throw AppError(code: 'obs_forbidden', message: 'Autor inválido.');
    }
    if (data.estado != EstadosObs.borrador) {
      throw AppError(code: 'obs_invalid_state', message: 'Debe iniciar en borrador.');
    }

    final now = FieldValue.serverTimestamp();

    final payload = {
      ...data.toMap(),
      'id_proyecto': proyectoId,
      'createdAt': now,
      'createdBy': uid,
      'updatedAt': now,
      'updatedBy': uid,
      'ultima_modificacion': now,
      // IA (defaults)
      'ai_status': data.aiStatus ?? 'idle',
      'ai_top_suggestions': data.aiTopSuggestions?.map((e) => e.toMap()).toList() ?? [],
      'ai_model': data.aiModel,
      'ai_error': null,
    };

    final doc = await _db.collection('observaciones').add(payload);
    return doc.id;
  }

  /// Crea una observación en BORRADOR **SIN proyecto**
  /// (permitido solo a Recolector o Admin Único).
  Future<String> createObservacionSinProyecto({
    required AuthProvider auth,
    required Observacion data, // estado: borrador
  }) async {
    final permisos = PermisosService(auth);
    final uid = auth.uid;
    if (uid == null || data.uidUsuario != uid) {
      throw AppError(code: 'obs_forbidden', message: 'Autor inválido.');
    }
    if (!(permisos.isAdminUnico || permisos.isRecolector)) {
      throw AppError(code: 'obs_forbidden', message: 'Solo recolector o admin pueden crear sin proyecto.');
    }
    if (data.estado != EstadosObs.borrador) {
      throw AppError(code: 'obs_invalid_state', message: 'Debe iniciar en borrador.');
    }

    final now = FieldValue.serverTimestamp();
    final payload = {
      ...data.toMap(),
      'id_proyecto': null,
      'createdAt': now,
      'createdBy': uid,
      'updatedAt': now,
      'updatedBy': uid,
      'ultima_modificacion': now,
      'ai_status': data.aiStatus ?? 'idle',
      'ai_top_suggestions': data.aiTopSuggestions?.map((e) => e.toMap()).toList() ?? [],
      'ai_model': data.aiModel,
      'ai_error': null,
    };
    final doc = await _db.collection('observaciones').add(payload);
    return doc.id;
  }

  /// Patch de campos para una observación (el AUTOR puede editar cuando
  /// estado ∈ {borrador, rechazado}.
  ///
  /// Importante: el `patch` ya viene con `FieldValue.delete()` mapeado desde
  /// el Provider cuando un valor es `null`. Aquí **no** volvemos a filtrar.
  Future<void> patchObservacion({
    required AuthProvider auth,
    required String observacionId,
    required Map<String, dynamic> patch,
  }) async {
    final uid = auth.uid;
    if (uid == null) {
      throw AppError(code: 'obs_forbidden', message: 'No autenticado.');
    }

    final ref = _db.collection('observaciones').doc(observacionId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw AppError(code: 'obs_not_found', message: 'Observación no encontrada.');
    }

    final m = snap.data()!;
    final String? proyectoId = m['id_proyecto'] as String?;
    final String estado = (m['estado'] ?? '') as String;
    final String? autor = m['uid_usuario'] as String?;

    final permisos = PermisosService(auth);
    final puedeVer = (proyectoId == null)
        ? (uid == autor || permisos.isAdminUnico) // sin proyecto: autor o admin
        : permisos.canViewProject(proyectoId);
    if (!puedeVer) {
      throw AppError(code: 'obs_forbidden', message: 'Sin acceso.');
    }

    final editable = (autor == uid) &&
        (estado == EstadosObs.borrador || estado == EstadosObs.rechazado);
    if (!editable) {
      throw AppError(code: 'obs_not_editable', message: 'No editable en este estado.');
    }

    await ref.update({
      ...patch,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
      'ultima_modificacion': FieldValue.serverTimestamp(),
    });
  }

  /// Cambios de estado con validaciones de rol y flujo:
  /// - Autor: borrador/rechazado → pendiente (con auditoría de envío)
  /// - Moderador (Supervisor/Owner/Admin): pendiente → aprobado|rechazado
  ///   * Recolector SIN proyecto: solo Admin puede moderar
  ///   * Anti auto-aprobación (salvo Admin, marcado conflictOfInterest)
  /// - Archivado: moderador o autor (si estaba aprobado)
  /// - Revertir a borrador: moderador o autor (si estaba rechazado)
  Future<void> changeEstadoObservacion({
    required AuthProvider auth,
    required String observacionId,
    required String nuevoEstado,
    String? rejectionReason,
  }) async {
    final uid = auth.uid;
    if (uid == null) {
      throw AppError(code: 'obs_forbidden', message: 'No autenticado.');
    }

    final ref = _db.collection('observaciones').doc(observacionId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw AppError(code: 'obs_not_found', message: 'Observación no encontrada.');
    }

    final m = snap.data()!;
    final String? proyectoId = m['id_proyecto'] as String?;
    final String estadoActual = (m['estado'] ?? '') as String;
    final String? autor = m['uid_usuario'] as String?;

    final permisos = PermisosService(auth);
    final puedeVer = (proyectoId == null)
        ? (uid == autor || permisos.isAdminUnico) // sin proyecto
        : permisos.canViewProject(proyectoId);
    if (!puedeVer) {
      throw AppError(code: 'obs_forbidden', message: 'Sin acceso.');
    }

    final bool esAutor = autor == uid;
    final bool esModeradorDeProyecto =
        (proyectoId != null) && permisos.canModerateProject(proyectoId);
    final bool reviewerEsAdmin = permisos.isAdminUnico;

    bool ok = false;
    final upd = <String, dynamic>{
      'estado': nuevoEstado,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
      'ultima_modificacion': FieldValue.serverTimestamp(),
    };

    if (nuevoEstado == EstadosObs.pendiente) {
      // Autor puede enviar a pendiente desde borrador o rechazado (con/sin proyecto)
      ok = esAutor &&
          (estadoActual == EstadosObs.borrador || estadoActual == EstadosObs.rechazado);

      if (!ok) {
        throw AppError(code: 'obs_invalid_state', message: 'No se puede enviar a pendiente.');
      }
      // Validaciones mínimas para pendiente
      if (m['fecha_captura'] == null) {
        throw AppError(code: 'obs_invalid_state', message: 'Falta fecha de captura.');
      }

      // ⬇️ Preflight de fotos
      final pf = await _preflightMedia(observacionId);

      if ((pf['total'] as int) == 0) {
        throw AppError(code: 'obs_media_missing', message: 'Debes adjuntar al menos una fotografía.');
      }
      if (pf['hasManipulated'] == true) {
        throw AppError(
          code: 'obs_media_manipulated',
          message: 'Se detectaron señales de manipulación en la(s) fotografía(s).',
        );
      }
      if (pf['hasNotAnimal'] == true) {
        throw AppError(
          code: 'obs_media_not_animal',
          message: 'Las fotografías no parecen contener un ejemplar animal reconocible.',
        );
      }

      final warnings = (pf['warningFlags'] as List<String>?) ?? const <String>[];

      // Rol del autor al enviar (heurística rápida)
      String autorRol = 'colaborador';
      if (proyectoId == null || proyectoId.isEmpty) autorRol = 'recolector';

      upd['submittedAt'] = FieldValue.serverTimestamp();
      upd['submittedBy'] = uid;
      upd['authorRoleAtSubmission'] = autorRol;
      if (warnings.isNotEmpty) {
        upd['review_warnings'] = warnings;
      }
    } else if (nuevoEstado == EstadosObs.aprobado || nuevoEstado == EstadosObs.rechazado) {
      if (estadoActual != EstadosObs.pendiente) {
        throw AppError(code: 'obs_invalid_state', message: 'Solo desde pendiente.');
      }
      if (nuevoEstado == EstadosObs.rechazado &&
          (rejectionReason == null || rejectionReason.trim().isEmpty)) {
        throw AppError(code: 'obs_invalid_state', message: 'Motivo de rechazo requerido.');
      }

      final String autorRol = (m['authorRoleAtSubmission'] as String?) ??
          ((proyectoId == null || proyectoId.isEmpty) ? 'recolector' : 'colaborador');

      // 1) anti auto-aprobación (salvo Admin)
      if (esAutor && !reviewerEsAdmin) {
        throw AppError(code: 'obs_forbidden', message: 'No puedes aprobar tu propia observación.');
      }

      // 2) SIN proyecto (recolector): solo Admin puede moderar
      if ((proyectoId == null || proyectoId.isEmpty) &&
          autorRol == 'recolector' &&
          !reviewerEsAdmin) {
        throw AppError(code: 'obs_forbidden', message: 'Solo Admin puede moderar observaciones sin proyecto.');
      }

      // 3) CON proyecto: requiere moderador del proyecto (o Admin)
      if (proyectoId != null && proyectoId.isNotEmpty && !reviewerEsAdmin) {
        if (!esModeradorDeProyecto) {
          throw AppError(code: 'obs_forbidden', message: 'Se requiere Supervisor/Owner/Admin.');
        }
        if ((autorRol == 'supervisor' || autorRol == 'owner') && esAutor) {
          throw AppError(code: 'obs_forbidden', message: 'Otro supervisor/owner debe aprobar.');
        }
      }

      final bool coi = esAutor && reviewerEsAdmin;

      upd['validatedAt'] = FieldValue.serverTimestamp();
      upd['validatedBy'] = uid;
      upd['validatedByRol'] = reviewerEsAdmin ? 'admin' : 'moderador';
      upd['rejectionReason'] =
      (nuevoEstado == EstadosObs.rechazado) ? (rejectionReason ?? '') : null;
      upd['conflictOfInterest'] = coi;
    } else if (nuevoEstado == EstadosObs.archivado) {
      // Moderador o autor si estaba aprobado
      ok = (reviewerEsAdmin || esModeradorDeProyecto) ||
          (esAutor && estadoActual == EstadosObs.aprobado);
    } else if (nuevoEstado == EstadosObs.borrador) {
      // Revertir: moderador o autor desde rechazado
      ok = (reviewerEsAdmin || esModeradorDeProyecto) ||
          (esAutor && estadoActual == EstadosObs.rechazado);
    } else {
      throw AppError(code: 'obs_invalid_state', message: 'Estado no permitido.');
    }

    if (!ok && nuevoEstado != EstadosObs.pendiente) {
      throw AppError(code: 'obs_invalid_state', message: 'Transición inválida.');
    }

    await ref.update(upd);
  }

  /// Aplicar sugerencia de IA (solo autor en estados editables).
  Future<void> applyAiSuggestion({
    required AuthProvider auth,
    required String observacionId,
    required Map<String, dynamic> suggestion, // {nombre, taxonId?, score?}
  }) async {
    final uid = auth.uid;
    if (uid == null) {
      throw AppError(code: 'obs_forbidden', message: 'No autenticado.');
    }

    final ref = _db.collection('observaciones').doc(observacionId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw AppError(code: 'obs_not_found', message: 'Observación no encontrada.');
    }

    final m = snap.data()!;
    final autor = m['uid_usuario'] as String?;
    final estado = (m['estado'] ?? '') as String;

    if (autor != uid ||
        !(estado == EstadosObs.borrador || estado == EstadosObs.rechazado)) {
      throw AppError(code: 'obs_not_editable', message: 'No editable para sugerencia IA.');
    }

    await ref.update({
      'especie_nombre': suggestion['nombre'],
      if (suggestion.containsKey('taxonId')) 'especie_id': suggestion['taxonId'],
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
      'ultima_modificacion': FieldValue.serverTimestamp(),
    });
  }

  /// Conteos (usa agregaciones server-side si están disponibles)
  Future<int> countObservacionesProyecto(String proyectoId) async {
    final q = await _db
        .collection('observaciones')
        .where('id_proyecto', isEqualTo: proyectoId)
        .count()
        .get();
    return q.count ?? 0;
  }

  Future<int> countObservacionesSinProyecto() async {
    final q = await _db
        .collection('observaciones')
        .where('id_proyecto', isNull: true)
        .count()
        .get();
    return q.count ?? 0;
  }

  // === NUEVO: lector puntual por id (alineado con el provider) ===
  Future<DocumentSnapshot<Map<String, dynamic>>> getObservacionDoc(String id) {
    return _db.collection('observaciones').doc(id).get();
  }

  // === OPCIONAL: helper rápido para extraer autor y proyecto ===
  Future<Map<String, String?>> getAutorYProyectoDeObservacion(String id) async {
    final snap = await _db.collection('observaciones').doc(id).get();
    if (!snap.exists || snap.data() == null) {
      return {'autor': null, 'proyectoId': null};
    }
    final m = snap.data()!;
    return {
      'autor': m['uid_usuario'] as String?,
      'proyectoId': m['id_proyecto'] as String?,
    };
  }

  // =======================
  //        PHOTO MEDIA
  // =======================

  CollectionReference<Map<String, dynamic>> _mediaCol(String observacionId) =>
      _db.collection('observaciones').doc(observacionId).collection('media');

  /// Stream de fotos (y videos, si aplicas) para una observación.
  Stream<List<PhotoMedia>> streamPhotoMediaForObservacion(String observacionId) {
    return _mediaCol(observacionId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((q) => q.docs.map((d) => PhotoMedia.fromMap(d.data(), d.id)).toList());
  }

  /// Lectura puntual de todas las fotos de una observación.
  Future<List<PhotoMedia>> getPhotoMediaOnce(String observacionId) async {
    final qs =
    await _mediaCol(observacionId).orderBy('createdAt', descending: true).get();
    return qs.docs.map((d) => PhotoMedia.fromMap(d.data(), d.id)).toList();
  }

  /// Crear un PhotoMedia bajo `observaciones/{obsId}/media`.
  /// - Rellena createdAt/createdBy si vienen nulos.
  /// - Incrementa `media_count` en el doc padre.
  Future<String> addPhotoMedia({
    required AuthProvider auth,
    required String observacionId,
    required PhotoMedia media,
  }) async {
    final uid = auth.uid;
    if (uid == null) {
      throw AppError(code: 'media_forbidden', message: 'No autenticado.');
    }

    // Validar mínima coherencia
    if (media.observacionId != observacionId) {
      throw AppError(code: 'media_invalid', message: 'observacionId inconsistente.');
    }
    if (media.storagePath.isEmpty) {
      throw AppError(code: 'media_invalid', message: 'storagePath requerido.');
    }

    final now = FieldValue.serverTimestamp();
    final payload = {
      ...media.toMap(),
      'createdAt': media.createdAt ?? now,
      'createdBy': media.createdBy ?? uid,
    };

    final ref = await _mediaCol(observacionId).add(payload);

    // Mantener contador en el padre
    await _db.collection('observaciones').doc(observacionId).set({
      'media_count': FieldValue.increment(1),
      'ultima_modificacion': now,
      'updatedAt': now,
      'updatedBy': uid,
    }, SetOptions(merge: true));

    return ref.id;
  }

  /// Actualiza campos de un media (no filtra nulls: si quieres borrar una clave,
  /// envía FieldValue.delete() desde el caller).
  Future<void> updatePhotoMedia({
    required AuthProvider auth,
    required String observacionId,
    required String mediaId,
    required Map<String, dynamic> patch,
  }) async {
    final uid = auth.uid;
    if (uid == null) {
      throw AppError(code: 'media_forbidden', message: 'No autenticado.');
    }
    final ref = _mediaCol(observacionId).doc(mediaId);

    // Verifica existencia mínima
    final snap = await ref.get();
    if (!snap.exists) {
      throw AppError(code: 'media_not_found', message: 'Media no encontrado.');
    }

    await ref.update({
      ...patch,
      // no tocamos createdAt/By
    });
  }

  /// Elimina un media y decrementa `media_count` en el padre.
  Future<void> deletePhotoMedia({
    required AuthProvider auth,
    required String observacionId,
    required String mediaId,
  }) async {
    final uid = auth.uid;
    if (uid == null) {
      throw AppError(code: 'media_forbidden', message: 'No autenticado.');
    }

    // Borrar doc de subcolección
    await _mediaCol(observacionId).doc(mediaId).delete();

    // Decrementar contador en el padre (con piso en 0 mediante recompute opcional)
    await _db.collection('observaciones').doc(observacionId).set({
      'media_count': FieldValue.increment(-1),
      'ultima_modificacion': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    }, SetOptions(merge: true));
  }

  /// Recalcula `media_count` con Count() y lo vuelca al doc padre.
  Future<int> recomputeMediaCount(String observacionId) async {
    final cnt = await _mediaCol(observacionId).count().get();
    final n = cnt.count ?? 0;
    await _db.collection('observaciones').doc(observacionId).set({
      'media_count': n,
      'ultima_modificacion': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return n;
  }

  /// (Opcional) Marca un media como principal en la observación.
  Future<void> setPrimaryMedia({
    required AuthProvider auth,
    required String observacionId,
    required String mediaId,
  }) async {
    final uid = auth.uid;
    if (uid == null) {
      throw AppError(code: 'media_forbidden', message: 'No autenticado.');
    }

    // Verificar que el media exista
    final mSnap = await _mediaCol(observacionId).doc(mediaId).get();
    if (!mSnap.exists) {
      throw AppError(code: 'media_not_found', message: 'Media no encontrado.');
    }

    await _db.collection('observaciones').doc(observacionId).set({
      'primary_media_id': mediaId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
      'ultima_modificacion': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---------- Resumen de autenticidad/calidad a nivel observación (opcional) ----------

  /// Reglas simples para “peor” autenticidad y calidad:
  /// autenticidad: manipulated > suspect > unknown > genuine
  /// calidad: unusable > low > good
  String _authWorst(String a, String b) {
    const order = {
      MediaVerdict.manipulated: 3,
      MediaVerdict.suspect: 2,
      MediaVerdict.unknown: 1,
      MediaVerdict.genuine: 0,
    };
    final va = order[a] ?? -1;
    final vb = order[b] ?? -1;
    return va >= vb ? a : b;
  }

  String _qualityWorst(String a, String b) {
    const order = {
      MediaVerdict.unusable: 2,
      MediaVerdict.low: 1,
      MediaVerdict.good: 0,
    };
    final va = order[a] ?? -1;
    final vb = order[b] ?? -1;
    return va >= vb ? a : b;
  }

  /// Calcula y guarda en la observación un resumen agregado:
  /// - media_authenticity
  /// - media_quality
  /// - media_flags (unión)
  /// No bloquea flujos; sólo ayuda a mostrar advertencias globales en UI.
  Future<void> updateObservationMediaSummary(String observacionId) async {
    final items = await getPhotoMediaOnce(observacionId);
    if (items.isEmpty) {
      await _db.collection('observaciones').doc(observacionId).set({
        'media_authenticity': null,
        'media_quality': null,
        'media_flags': [],
      }, SetOptions(merge: true));
      return;
    }

    String? worstAuth;
    String? worstQuality;
    final flagsUnion = <String>{};

    for (final m in items) {
      if (m.authenticity != null) {
        worstAuth =
        (worstAuth == null) ? m.authenticity : _authWorst(worstAuth!, m.authenticity!);
      }
      if (m.quality != null) {
        worstQuality =
        (worstQuality == null) ? m.quality : _qualityWorst(worstQuality!, m.quality!);
      }
      if (m.flags != null) {
        flagsUnion.addAll(m.flags!);
      }
    }

    await _db.collection('observaciones').doc(observacionId).set({
      'media_authenticity': worstAuth,
      'media_quality': worstQuality,
      'media_flags': flagsUnion.toList(),
      'ultima_modificacion': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // =======================
  //  USUARIO-ROL-PROYECTO
  // =======================

  Stream<List<UsuarioRolProyecto>> streamUsuarioRolProyectos() => _db
      .collection('usuario_rol_proyecto')
      .snapshots()
      .map((snap) => snap.docs.map((d) => UsuarioRolProyecto.fromMap(d.data(), d.id)).toList());

  Future<List<UsuarioRolProyecto>> getUsuarioRolProyectosForUser(String uid) async {
    final qs = await _db
        .collection('usuario_rol_proyecto')
        .where('uid_usuario', isEqualTo: uid)
        .get();

    final out = <UsuarioRolProyecto>[];
    for (final d in qs.docs) {
      try {
        final urp = UsuarioRolProyecto.fromMap(d.data(), d.id);

        if (urp.uidUsuario != uid) continue;

        final okActivo = urp.activo == true;
        final okEstatus = urp.estatus == 'aprobado' || urp.estatus == 'activo';
        final okRol = urp.idRol != null;

        if (okActivo && okEstatus && okRol) {
          out.add(urp);
        }
      } catch (_) {
        // Ignora documentos mal formados sin romper el flujo
      }
    }
    return out;
  }

  /// NUEVO: stream de URPs del usuario (globales y por proyecto)
  /// Filtra en cliente: activo==true (o null → considerado activo para legacy)
  Stream<List<UsuarioRolProyecto>> streamUsuarioRolProyectosForUser(String uid) {
    return _db
        .collection('usuario_rol_proyecto')
        .where('uid_usuario', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final all = snap.docs.map((d) {
        try {
          return UsuarioRolProyecto.fromMap(d.data(), d.id);
        } catch (_) {
          return null;
        }
      }).whereType<UsuarioRolProyecto>().toList();

      return all.where((u) {
        final okActivo = u.activo != false; // true o null → OK
        final okEstatus =
            (u.estatus == null) || u.estatus == 'aprobado' || u.estatus == 'activo';
        return okActivo && okEstatus;
      }).toList();
    });
  }

  /// Stream de SUPERVISORES asignados a un proyecto (resuelve a objetos Usuario)
  Stream<List<Usuario>> streamSupervisoresDeProyecto(String proyectoId) {
    final q = _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: proyectoId)
        .where('id_rol', isEqualTo: RoleIds.supervisor)
        .where('activo', isEqualTo: true)
        .snapshots();

    // Convertimos los vínculos a usuarios reales
    return q.asyncMap((snap) async {
      final uids = snap.docs
          .map((d) => d.data()['uid_usuario'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return getUsuariosPorUids(uids);
    });
  }

  /// Asignar SUPERVISOR (bloquea si ya es COLABORADOR en el mismo proyecto).
  Future<void> asignarSupervisorAProyecto({
    required String proyectoId,
    required String uidSupervisor,
    required String uidAdmin,
    bool force = false,
  }) async {
    // 🚫 Dueño NO puede ser supervisor de su propio proyecto
    final pDoc = await _db.collection('proyectos').doc(proyectoId).get();
    final owner = pDoc.data()?['uid_dueno'] as String?;
    if (owner != null && owner == uidSupervisor) {
      throw AppError.ownerConflict('El dueño del proyecto no puede ser supervisor del mismo.');
    }

    // 🔍 ¿ya es colaborador en este proyecto?
    final esColaborador = await _existsUrp(
      idProyecto: proyectoId,
      uidUsuario: uidSupervisor,
      idRol: RoleIds.colaborador,
    );

    if (esColaborador && !force) {
      throw AppError.collabConflict(
        'El usuario ya es COLABORADOR en este proyecto. '
            'Quítalo como colaborador antes de asignarlo como supervisor.',
      );
    }

    if (esColaborador && force) {
      final colabDocId = urpDocId(
        idProyecto: proyectoId,
        uidUsuario: uidSupervisor,
        idRol: RoleIds.colaborador,
      );
      await _db.collection('usuario_rol_proyecto').doc(colabDocId).delete();
    }

    final docId = urpDocId(
      idProyecto: proyectoId,
      uidUsuario: uidSupervisor,
      idRol: RoleIds.supervisor,
    );

    await _db.collection('usuario_rol_proyecto').doc(docId).set({
      'id_proyecto': proyectoId,
      'uid_usuario': uidSupervisor,
      'id_rol': RoleIds.supervisor,
      'rol_nombre': 'Supervisor',
      'activo': true,
      'asignadoAt': FieldValue.serverTimestamp(),
      'asignadoBy': uidAdmin,
    }, SetOptions(merge: true));
  }

  /// Quitar SUPERVISOR de un proyecto (URP)
  Future<void> quitarSupervisorDeProyecto({
    required String proyectoId,
    required String uidSupervisor,
  }) async {
    final docId = urpDocId(
      idProyecto: proyectoId,
      uidUsuario: uidSupervisor,
      idRol: RoleIds.supervisor,
    );
    await _db.collection('usuario_rol_proyecto').doc(docId).delete();
  }

  /// Asignación genérica (GLOBAL si idProyecto == null). (Legacy para admin)
  Future<void> asignarRol({
    required String uidUsuario,
    required int idRol,
    String? idProyecto, // null = global
    required String uidAdmin,
    String? rolNombre,
  }) async {
    if (idRol == RoleIds.admin && idProyecto == null) {
      final hayOtro = await _existeAdminGlobal(exceptUid: uidUsuario);
      if (hayOtro) {
        throw AppError.unknown('Ya existe un Administrador global. Solo puede haber uno.');
      }
    }

    final rolesCol = _db.collection('usuario_rol_proyecto');
    final nombre = rolNombre ?? _rolNombreFromId(idRol);

    if (idProyecto != null) {
      final docId = urpDocId(
        idProyecto: idProyecto,
        uidUsuario: uidUsuario,
        idRol: idRol,
      );
      await rolesCol.doc(docId).set({
        'uid_usuario': uidUsuario,
        'id_rol': idRol,
        'rol_nombre': nombre,
        'id_proyecto': idProyecto,
        'activo': true,
        'asignadoAt': FieldValue.serverTimestamp(),
        'asignadoBy': uidAdmin,
      }, SetOptions(merge: true));
      return;
    }

    final exists = await rolesCol
        .where('uid_usuario', isEqualTo: uidUsuario)
        .where('id_rol', isEqualTo: idRol)
        .where('id_proyecto', isNull: true)
        .limit(1)
        .get();
    if (exists.docs.isNotEmpty) return;

    await rolesCol.add({
      'uid_usuario': uidUsuario,
      'id_rol': idRol,
      'rol_nombre': nombre,
      'id_proyecto': null,
      'activo': true,
      'asignadoAt': FieldValue.serverTimestamp(),
      'asignadoBy': uidAdmin,
    });
  }

  /// Wrapper COLABORADOR — bloquea si ya es SUPERVISOR en el mismo proyecto.
  Future<String> asignarUsuarioRolProyecto({
    required String uidUsuario,
    required int idRol, // debe ser RoleIds.colaborador
    required String idProyecto,
  }) async {
    if (idRol != RoleIds.colaborador) {
      throw AppError.unknown(
          'Asignación inválida: solo se permite Rol.colaborador por proyecto');
    }

    final esSupervisor = await _existsUrp(
      idProyecto: idProyecto,
      uidUsuario: uidUsuario,
      idRol: RoleIds.supervisor,
    );
    if (esSupervisor) {
      throw AppError.supConflict(
        'El usuario ya es SUPERVISOR en este proyecto. '
            'Quítalo como supervisor antes de asignarlo como colaborador.',
      );
    }

    final docId = urpDocId(
      idProyecto: idProyecto,
      uidUsuario: uidUsuario,
      idRol: idRol,
    );

    await _db.collection('usuario_rol_proyecto').doc(docId).set({
      'uid_usuario': uidUsuario,
      'id_rol': idRol,
      'rol_nombre': _rolNombreFromId(idRol),
      'id_proyecto': idProyecto,
      'activo': true,
      'asignadoAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return docId;
  }

  Future<void> addUsuarioRolProyecto(UsuarioRolProyecto urp) =>
      _db.collection('usuario_rol_proyecto').add(urp.toMap());

  late Future<void> deleteUsuarioRolProyect;
  o(String id) =>
      _db.collection('usuario_rol_proyecto').doc(id).delete();

  Future<int> eliminarRolesDeUsuario(String uidUsuario) async {
    final qs = await _db
        .collection('usuario_rol_proyecto')
        .where('uid_usuario', isEqualTo: uidUsuario)
        .get();
    final batch = _db.batch();
    for (final d in qs.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
    return qs.docs.length;
  }

  // ====== GESTIÓN COLABORADORES / RECOLECTORES POR PROYECTO ======

  // ---- Colaboradores ----
  Future<List<Map<String, dynamic>>> linksColabByProyecto(String projId) async {
    final q = await _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: projId)
        .where('id_rol', isEqualTo: RoleIds.colaborador)
        .get();
    return q.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<bool> existeAsignacionColab(String projId, String uid) async {
    final q = await _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: projId)
        .where('uid_usuario', isEqualTo: uid)
        .where('id_rol', isEqualTo: RoleIds.colaborador)
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  Future<String> asignarColaborador(String projId, String uidColab, {String? asignadoBy}) async {
    final pDoc = await _db.collection('proyectos').doc(projId).get();
    if (pDoc.exists && pDoc.data()?['uid_dueno'] == uidColab) {
      // Compat: seguimos devolviendo 'owned' (no lanzar AppError aquí)
      return 'owned';
    }

    final esSupervisor = await _existsUrp(
      idProyecto: projId,
      uidUsuario: uidColab,
      idRol: RoleIds.supervisor,
    );
    if (esSupervisor) {
      // Ahora lanza AppError con código → la UI lo muestra bonito
      throw AppError.supConflict(
        'El usuario ya es SUPERVISOR en este proyecto. '
            'Quítalo como supervisor antes de asignarlo como colaborador.',
      );
    }

    final docId = urpDocId(
      idProyecto: projId,
      uidUsuario: uidColab,
      idRol: RoleIds.colaborador,
    );

    await _db.collection('usuario_rol_proyecto').doc(docId).set({
      'id_proyecto': projId,
      'uid_usuario': uidColab,
      'id_rol': RoleIds.colaborador,
      'rol_nombre': _rolNombreFromId(RoleIds.colaborador),
      'activo': true,
      'asignadoAt': FieldValue.serverTimestamp(),
      if (asignadoBy != null) 'asignadoBy': asignadoBy,
    }, SetOptions(merge: true));

    return docId;
  }

  Future<void> retirarColaborador(String projId, String uidColab) async {
    final docId = urpDocId(
      idProyecto: projId,
      uidUsuario: uidColab,
      idRol: RoleIds.colaborador,
    );
    final ref = _db.collection('usuario_rol_proyecto').doc(docId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      return;
    }
    final q = await _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: projId)
        .where('uid_usuario', isEqualTo: uidColab)
        .where('id_rol', isEqualTo: RoleIds.colaborador)
        .get();
    if (q.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in q.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  Future<List<Usuario>> listarColaboradoresProyecto(String projId) async {
    final links = await linksColabByProyecto(projId);
    final uids = links.map((m) => m['uid_usuario'] as String).toList();
    return getUsuariosPorUids(uids);
  }

  // ---- Recolectores ----
  Future<List<Map<String, dynamic>>> linksRecolectorByProyecto(String projId) async {
    final q = await _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: projId)
        .where('id_rol', isEqualTo: RoleIds.recolector)
        .get();
    return q.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<bool> existeAsignacionRecolector(String projId, String uid) async {
    final q = await _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: projId)
        .where('uid_usuario', isEqualTo: uid)
        .where('id_rol', isEqualTo: RoleIds.recolector)
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  /// Idempotente por docId compuesto → sin duplicados.
  /// No tiene conflictos: Recolector puede coexistir con otros roles.
  Future<String> asignarRecolector(String projId, String uidRecolector, {String? asignadoBy}) async {
    final docId = urpDocId(
      idProyecto: projId,
      uidUsuario: uidRecolector,
      idRol: RoleIds.recolector,
    );
    await _db.collection('usuario_rol_proyecto').doc(docId).set({
      'id_proyecto': projId,
      'uid_usuario': uidRecolector,
      'id_rol': RoleIds.recolector,
      'rol_nombre': _rolNombreFromId(RoleIds.recolector),
      'activo': true,
      'asignadoAt': FieldValue.serverTimestamp(),
      if (asignadoBy != null) 'asignadoBy': asignadoBy,
    }, SetOptions(merge: true));
    return docId;
  }

  Future<void> retirarRecolector(String projId, String uidRecolector) async {
    final docId = urpDocId(
      idProyecto: projId,
      uidUsuario: uidRecolector,
      idRol: RoleIds.recolector,
    );
    final ref = _db.collection('usuario_rol_proyecto').doc(docId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      return;
    }
    // Fallback legacy
    final q = await _db
        .collection('usuario_rol_proyecto')
        .where('id_proyecto', isEqualTo: projId)
        .where('uid_usuario', isEqualTo: uidRecolector)
        .where('id_rol', isEqualTo: RoleIds.recolector)
        .get();
    if (q.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in q.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  // =======================
  //       UTILIDADES
  // =======================

  /// (Legacy) obtenedores de “rol global” — hoy solo aplican para admin.
  Future<List<String>> getUidsConRolGlobal(int idRol) async {
    final qs = await _db
        .collection('usuario_rol_proyecto')
        .where('id_rol', isEqualTo: idRol)
        .where('id_proyecto', isNull: true)
        .where('activo', isEqualTo: true)
        .get();
    return qs.docs
        .map((d) => d.data()['uid_usuario'] as String)
        .where((uid) => uid.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<List<Usuario>> getUsuariosConRolGlobal(int idRol) async {
    final uids = await getUidsConRolGlobal(idRol);
    return getUsuariosPorUids(uids);
  }

  /// 🔴 NUEVO: ¿Tiene rol GLOBAL? (id_proyecto == null; activo true o null)
  Future<bool> hasRolGlobal(String uid, int idRol) async {
    final qs = await _db
        .collection('usuario_rol_proyecto')
        .where('uid_usuario', isEqualTo: uid)
        .where('id_rol', isEqualTo: idRol)
        .where('id_proyecto', isNull: true)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) return false;

    final data = qs.docs.first.data();
    final activo = data['activo'];
    return (activo == null) || (activo == true);
  }

  Future<bool> userTieneRolGlobal(String uid, int idRol) async {
    final qs = await _db
        .collection('usuario_rol_proyecto')
        .where('uid_usuario', isEqualTo: uid)
        .where('id_rol', isEqualTo: idRol)
        .where('id_proyecto', isNull: true)
        .where('activo', isEqualTo: true)
        .limit(1)
        .get();
    return qs.docs.isNotEmpty;
  }

  Future<List<Usuario>> getUsuariosPorUids(List<String> uids) async {
    if (uids.isEmpty) return [];
    final out = <Usuario>[];
    for (var i = 0; i < uids.length; i += 10) {
      final chunk = uids.sublist(i, (i + 10 > uids.length) ? uids.length : i + 10);
      final snap =
      await _db.collection('usuarios').where(FieldPath.documentId, whereIn: chunk).get();
      out.addAll(snap.docs.map((d) => Usuario.fromMap(d.data(), d.id)));
    }
    return out;
  }

  // FirestoreService
  Future<Proyecto?> getProyectoPorId(String id) async {
    final doc = await FirebaseFirestore.instance.collection('proyectos').doc(id).get();
    if (!doc.exists) return null;
    return Proyecto.fromMap(doc.data()!, doc.id);
  }

  /// IDs de proyectos donde el usuario puede moderar (OWNER o SUPERVISOR).
  Future<List<String>> projectIdsModerablesPor(String uid) async {
    final qs = await _db
        .collection('usuario_rol_proyecto')
        .where('uid_usuario', isEqualTo: uid)
        .where('id_rol', whereIn: [RoleIds.duenoProyecto, RoleIds.supervisor])
        .where('activo', isEqualTo: true)
        .get();

    return qs.docs
        .map((d) => (d.data()['id_proyecto'] as String?) ?? '')
        .where((x) => x.isNotEmpty)
        .toSet()
        .toList();
  }

  // =======================
  //     DELETE EN CASCADA
  // =======================
  /// 🔥 Elimina a un usuario NO-ADMIN (único) y sus vínculos.
  Future<void> deleteUsuarioFirestoreCascadeNoAdmin(String uidUsuario) async {
    // 0) Leer usuario para ver si es admin único
    final uSnap = await _db.collection('usuarios').doc(uidUsuario).get();
    final isAdminUnico = (uSnap.data()?['is_admin'] == true);

    // 1) Candado: no permitir si es admin único o (legado) admin global por URP
    final esAdminGlobalLegacy = await userTieneRolGlobal(uidUsuario, RoleIds.admin);
    if (isAdminUnico || esAdminGlobalLegacy) {
      throw AppError.unknown('No se puede eliminar al Administrador global.');
    }

    // 2) Candado: si es dueño de al menos 1 proyecto
    final due =
    await _db.collection('proyectos').where('uid_dueno', isEqualTo: uidUsuario).limit(1).get();
    if (due.docs.isNotEmpty) {
      throw AppError.unknown(
          'Este usuario es dueño de uno o más proyectos. Reasigna/elimina esos proyectos antes de continuar.');
    }

    // 3) Borrar todos sus vínculos URP (globales y por proyecto)
    await eliminarRolesDeUsuario(uidUsuario);

    // 4) Limpiar campo directo de supervisor en proyectos (compatibilidad)
    final qSup =
    await _db.collection('proyectos').where('uid_supervisor', isEqualTo: uidUsuario).get();
    if (qSup.docs.isNotEmpty) {
      for (var i = 0; i < qSup.docs.length; i += 400) {
        final chunk = qSup.docs.sublist(
            i, i + 400 > qSup.docs.length ? qSup.docs.length : i + 400);
        final batch = _db.batch();
        for (final d in chunk) {
          batch.set(d.reference, {
            'uid_supervisor': FieldValue.delete(),
            'supervisorAsignadoBy': FieldValue.delete(),
            'supervisorAsignadoAt': FieldValue.delete(),
          }, SetOptions(merge: true));
        }
        await batch.commit();
      }
    }

    // (Opcional) Eliminar observaciones del usuario si las indexas por 'uid_usuario'
    // ...

    // 5) Eliminar el documento del usuario
    await deleteUsuario(uidUsuario);
  }

  /// Elimina todo el proyecto y relaciones.
  Future<void> deleteProyectoCascade(String proyectoId) async {
    // 1) borrar vínculos URP (colaboradores y supervisores/otros roles)
    await _deleteByQuery(
      _db.collection('usuario_rol_proyecto').where('id_proyecto', isEqualTo: proyectoId),
    );

    // 2) borrar subcolección CATEGORÍAS del proyecto
    await _deleteByQuery(
      _db.collection('proyectos').doc(proyectoId).collection('categorias'),
    );

    // 2.1) borrar meta opcional (contador de categorías)
    final metaRef = _db
        .collection('proyectos')
        .doc(proyectoId)
        .collection('meta')
        .doc('categorias_counter');
    final metaSnap = await metaRef.get();
    if (metaSnap.exists) {
      await metaRef.delete();
    }

    // 3) borrar OBSERVACIONES del proyecto
    await _deleteByQuery(
      _db.collection('observaciones').where('id_proyecto', isEqualTo: proyectoId),
    );

    // 4) borrar el DOCUMENTO del proyecto
    await _db.collection('proyectos').doc(proyectoId).delete();
  }

  /// Borra todos los docs devueltos por una query en batches.
  Future<void> _deleteByQuery(Query query) async {
    const pageSize = 200;
    while (true) {
      final snap = await query.limit(pageSize).get();
      if (snap.docs.isEmpty) break;

      // Borramos en lotes de hasta ~450 operaciones
      final docs = snap.docs;
      for (var i = 0; i < docs.length; i += 450) {
        final chunk = docs.sublist(i, i + 450 > docs.length ? docs.length : i + 450);
        final batch = _db.batch();
        for (final d in chunk) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }

      if (docs.length < pageSize) break; // no hay más
    }
  }
}


