// lib/services/proyecto_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ProyectoService {
  final _db = FirebaseFirestore.instance;

  /// UIDs que deben ser notificados en un proyecto.
  Future<Set<String>> resolveRecipients({
    required String proyectoId,
    bool includeDueno = true,
    bool includeSupervisores = true,
    bool includeColaboradores = false,
  }) async {
    final uids = <String>{};

    final prj = await _db.collection('proyectos').doc(proyectoId).get();
    final data = prj.data() ?? {};

    if (includeDueno && data['ownerUid'] is String && (data['ownerUid'] as String).isNotEmpty) {
      uids.add(data['ownerUid'] as String);
    }

    if (includeSupervisores && data['supervisores'] is List) {
      uids.addAll((data['supervisores'] as List).whereType<String>());
    }

    if (includeColaboradores) {
      final team = await _db.collection('proyectos').doc(proyectoId).collection('equipo').get();
      for (final d in team.docs) {
        final uid = d.id; // subcolección equipo: docId = uid
        if (uid.isNotEmpty) uids.add(uid);
      }
    }

    return uids;
  }
}
