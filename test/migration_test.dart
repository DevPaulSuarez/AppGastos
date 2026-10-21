import 'package:flutter_test/flutter_test.dart';
import 'package:primera_app_curso/data/migration.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_store.dart';

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

      final cloud = MemoryStore();
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

  test('si en la nube solo está la moneda, igual se suben los datos', () async {
    final local = LocalStore();
    await local.set('settings', 'people', {
      'names': ['Paul'],
    });
    await local.set('incomes', 'i1', {'description': 'Sueldo', 'amount': 500});
    final cloud = MemoryStore();
    await cloud.set('settings', 'currency', {'code': 'USD'});

    expect(await moveLocalDataToCloud(local, cloud, 'paul'), 2);
    expect(cloud.data['incomes']!.length, 1);
  });

  test('una cuenta que ya tiene datos en la nube no se sobrescribe', () async {
    final local = LocalStore();
    await local.set('settings', 'people', {
      'names': ['Otro'],
    });
    final cloud = MemoryStore();
    await cloud.set('settings', 'people', {
      'names': ['Paul'],
    });

    expect(await moveLocalDataToCloud(local, cloud, 'paul'), 0);
    expect(cloud.data['settings']!['people']!['names'], ['Paul']);
  });
}
