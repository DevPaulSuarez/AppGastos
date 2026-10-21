import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:primera_app_curso/data/migration.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nube de prueba: guarda todo en memoria.
class _MemoryStore implements Store {
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'al iniciar sesión se suben los datos del teléfono, una sola vez',
    () async {
      final local = LocalStore();
      await local.set('expenses', 'e1', {'category': 'Comida', 'value': 20});
      await local.set('incomes', 'i1', {
        'description': 'Sueldo',
        'amount': 500,
      });
      await local.set('settings', 'people', {
        'names': ['Paul', 'Persona 2'],
      });

      final cloud = _MemoryStore();
      expect(await moveLocalDataToCloud(local, cloud, 'paul'), 3);
      expect(cloud.data['expenses']!['e1']!['value'], 20);
      expect(cloud.data['settings']!['people']!['names'], [
        'Paul',
        'Persona 2',
      ]);

      // La segunda vez no vuelve a subir nada.
      await local.set('expenses', 'e2', {'category': 'Ocio', 'value': 60});
      expect(await moveLocalDataToCloud(local, cloud, 'paul'), 0);
      expect(cloud.data['expenses']!.length, 1);
    },
  );

  test('una cuenta que ya tiene datos en la nube no se sobrescribe', () async {
    final local = LocalStore();
    await local.set('settings', 'people', {
      'names': ['Otro'],
    });
    final cloud = _MemoryStore();
    await cloud.set('settings', 'people', {
      'names': ['Paul'],
    });

    expect(await moveLocalDataToCloud(local, cloud, 'paul'), 0);
    expect(cloud.data['settings']!['people']!['names'], ['Paul']);
  });
}
