import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Doc {
  final String id;
  final Map<String, dynamic> data;

  const Doc(this.id, this.data);
}

/// Almacén de documentos agrupados en colecciones. Tiene una versión local
/// (modo pruebas) y otra en Firestore, para que el resto de la app no tenga
/// que saber dónde se guardan los datos.
abstract class Store {
  Stream<List<Doc>> watch(String collection,
      {Map<String, Object?> where = const {}});

  Future<String> add(String collection, Map<String, dynamic> data);

  /// Un documento por id, o null si no existe.
  Future<Doc?> get(String collection, String id);

  Future<void> set(String collection, String id, Map<String, dynamic> data);

  Future<void> delete(String collection, String id);

  /// Borra todos los documentos de una colección.
  Future<void> deleteAll(String collection);

  /// Borra varios documentos por id.
  Future<void> deleteMany(String collection, Iterable<String> ids);
}

class FirestoreStore implements Store {
  final String userId;

  FirestoreStore(this.userId);

  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection(name);

  @override
  Stream<List<Doc>> watch(String collection,
      {Map<String, Object?> where = const {}}) {
    Query<Map<String, dynamic>> query = _collection(collection);
    where.forEach((field, value) {
      query = query.where(field, isEqualTo: value);
    });
    return query.snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => Doc(doc.id, doc.data())).toList());
  }

  @override
  Future<String> add(String collection, Map<String, dynamic> data) async {
    return (await _collection(collection).add(data)).id;
  }

  @override
  Future<Doc?> get(String collection, String id) async {
    final doc = await _collection(collection).doc(id).get();
    final data = doc.data();
    return data == null ? null : Doc(doc.id, data);
  }

  @override
  Future<void> set(String collection, String id, Map<String, dynamic> data) {
    return _collection(collection).doc(id).set(data);
  }

  @override
  Future<void> delete(String collection, String id) {
    return _collection(collection).doc(id).delete();
  }

  @override
  Future<void> deleteAll(String collection) async {
    final docs = await _collection(collection).get();
    for (final doc in docs.docs) {
      await doc.reference.delete();
    }
  }

  @override
  Future<void> deleteMany(String collection, Iterable<String> ids) async {
    for (final id in ids) {
      await _collection(collection).doc(id).delete();
    }
  }

  /// Guarda varios documentos de una vez, en tandas (Firestore acepta hasta
  /// 500 cambios por tanda).
  Future<void> setMany(
      String collection, Map<String, Map<String, dynamic>> data) async {
    final entries = data.entries.toList();
    for (var i = 0; i < entries.length; i += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final e in entries.skip(i).take(400)) {
        batch.set(_collection(collection).doc(e.key), e.value);
      }
      await batch.commit();
    }
  }
}

/// Guarda los datos en el propio dispositivo (modo pruebas).
class LocalStore implements Store {
  // Se guarda el Future para que todas las pantallas compartan el mismo mapa,
  // aunque pidan los datos a la vez mientras todavía se están leyendo.
  final _cache = <String, Future<Map<String, Map<String, dynamic>>>>{};
  final _changes = StreamController<String>.broadcast();
  int _counter = 0;

  Future<Map<String, Map<String, dynamic>>> _load(String collection) {
    return _cache[collection] ??= _read(collection);
  }

  Future<Map<String, Map<String, dynamic>>> _read(String collection) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('local_$collection');
    final decoded = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
        (id, data) => MapEntry(id, Map<String, dynamic>.from(data as Map)));
  }

  Future<void> _save(String collection) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'local_$collection', jsonEncode(await _load(collection)));
    _changes.add(collection);
  }

  @override
  Stream<List<Doc>> watch(String collection,
      {Map<String, Object?> where = const {}}) async* {
    final docs = await _load(collection);
    List<Doc> filtered() => docs.entries
        .where((doc) =>
            where.entries.every((w) => doc.value[w.key] == w.value))
        .map((doc) => Doc(doc.key, doc.value))
        .toList();

    yield filtered();
    yield* _changes.stream
        .where((changed) => changed == collection)
        .map((_) => filtered());
  }

  @override
  Future<Doc?> get(String collection, String id) async {
    final data = (await _load(collection))[id];
    return data == null ? null : Doc(id, data);
  }

  @override
  Future<String> add(String collection, Map<String, dynamic> data) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';
    await set(collection, id, data);
    return id;
  }

  @override
  Future<void> set(
      String collection, String id, Map<String, dynamic> data) async {
    final docs = await _load(collection);
    docs[id] = data;
    await _save(collection);
  }

  @override
  Future<void> delete(String collection, String id) async {
    final docs = await _load(collection);
    docs.remove(id);
    await _save(collection);
  }

  @override
  Future<void> deleteAll(String collection) async {
    final docs = await _load(collection);
    docs.clear();
    await _save(collection);
  }

  @override
  Future<void> deleteMany(String collection, Iterable<String> ids) async {
    final docs = await _load(collection);
    for (final id in ids) {
      docs.remove(id);
    }
    await _save(collection);
  }

  /// Guarda varios documentos de una vez (más rápido que uno por uno).
  Future<void> setMany(
      String collection, Map<String, Map<String, dynamic>> data) async {
    final docs = await _load(collection);
    docs.addAll(data);
    await _save(collection);
  }
}
