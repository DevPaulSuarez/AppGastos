import 'dart:async';

import 'package:primera_app_curso/data/store.dart';

/// Nube de prueba: guarda todo en memoria.
class MemoryStore implements Store {
  final data = <String, Map<String, Map<String, dynamic>>>{};

  @override
  Stream<List<Doc>> watch(
    String collection, {
    Map<String, Object?> where = const {},
  }) => Stream.value([
    for (final e in (data[collection] ?? {}).entries) Doc(e.key, e.value),
  ]);

  @override
  Future<void> set(
    String collection,
    String id,
    Map<String, dynamic> d,
  ) async => (data[collection] ??= {})[id] = d;

  @override
  Future<String> add(String collection, Map<String, dynamic> d) async {
    final id = '${(data[collection] ?? {}).length}';
    await set(collection, id, d);
    return id;
  }

  @override
  Future<Doc?> get(String collection, String id) async {
    final d = data[collection]?[id];
    return d == null ? null : Doc(id, d);
  }

  @override
  Future<void> delete(String collection, String id) async =>
      data[collection]?.remove(id);

  @override
  Future<void> deleteAll(String collection) async => data.remove(collection);

  @override
  Future<void> deleteMany(String collection, Iterable<String> ids) async {
    for (final id in ids) {
      data[collection]?.remove(id);
    }
  }
}
