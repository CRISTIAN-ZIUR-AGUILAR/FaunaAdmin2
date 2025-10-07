// lib/services/seed_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class SeedService {
  final _db = FirebaseFirestore.instance;

  /// Crea el catálogo base de roles si está vacío.
  /// Devuelve true si sembró, false si ya existían.
  Future<bool> seedRolesIfEmpty() async {
    final col = _db.collection('roles');
    final snap = await col.limit(1).get();
    if (snap.docs.isNotEmpty) return false;

    final batch = _db.batch();
    const roles = [
      {'id_rol': 1, 'descripcion': 'ADMIN'},
      {'id_rol': 2, 'descripcion': 'SUPERVISOR'},
      {'id_rol': 3, 'descripcion': 'RECOLECTOR'},
      {'id_rol': 4, 'descripcion': 'DUEÑO PROYECTO'},
      {'id_rol': 5, 'descripcion': 'COLABORADOR'},
    ];
    for (final r in roles) {
      batch.set(col.doc('${r['id_rol']}'), r);
    }
    await batch.commit();
    return true;
  }
}
