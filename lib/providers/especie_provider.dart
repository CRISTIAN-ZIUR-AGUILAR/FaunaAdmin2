// lib/providers/especie_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/especie.dart';
import '../utils/normalize.dart';

class EspecieProvider extends ChangeNotifier {
  final _db = FirebaseFirestore.instance;
  final List<Especie> _cache = [];
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> loadOnce({int limit = 5000}) async {
    if (_loaded) return;
    final qs = await _db.collection('especies')
        .orderBy('norm_name')
        .limit(limit)
        .get();
    _cache
      ..clear()
      ..addAll(qs.docs.map((d) => Especie.fromMap(d.data(), d.id)));
    _loaded = true;
    notifyListeners();
  }

  /// Búsqueda simple por texto normalizado (prefijo de tokens)
  List<Especie> search(String query, {int maxResults = 20}) {
    final q = normalize(query);
    if (q.isEmpty) return _cache.take(maxResults).toList();
    final tokens = q.split(' ').where((t) => t.isNotEmpty).toList();

    bool matches(Especie e) {
      final haystack = <String>[
        e.normName,
        ...e.normComunes,
      ];
      for (final t in tokens) {
        final okToken = haystack.any((h) => h.contains(t));
        if (!okToken) return false;
      }
      return true;
    }

    final res = <Especie>[];
    for (final e in _cache) {
      if (matches(e)) {
        res.add(e);
        if (res.length >= maxResults) break;
      }
    }
    return res;
  }

  Especie? byId(String id) => _cache.firstWhere((e) => e.id == id, orElse: () => null as Especie);
}
