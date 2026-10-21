import 'package:primera_app_curso/data/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Colecciones que guarda la app.
const appCollections = [
  'expenses',
  'incomes',
  'recurring',
  'budgets',
  'goals',
  'settings',
];

/// La primera vez que alguien inicia sesión en este teléfono, sube a su
/// cuenta en la nube lo que tenía guardado en el teléfono (de cuando la app
/// funcionaba sin cuenta). Si su cuenta en la nube ya tiene datos, no se
/// toca nada. Los datos del teléfono no se borran.
///
/// Devuelve cuántos documentos se subieron.
Future<int> moveLocalDataToCloud(
  LocalStore local,
  Store cloud,
  String userId, {
  Future<void> Function(String collection, Map<String, Map<String, dynamic>>)?
  setMany,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'migrated_to_$userId';
  if (prefs.getBool(key) ?? false) return 0;

  // Una cuenta que ya se usa en la nube (con nombres, gastos o ingresos) no
  // se sobrescribe. Solo la moneda no cuenta: se elige antes de todo lo
  // demás y no debe impedir subir los datos de otro teléfono.
  final cloudSettings = await cloud.watch('settings').first;
  final inUse =
      cloudSettings.any((d) => d.id == 'people') ||
      (await cloud.watch('expenses').first).isNotEmpty ||
      (await cloud.watch('incomes').first).isNotEmpty;
  var moved = 0;
  if (!inUse) {
    for (final collection in appCollections) {
      final docs = await local.watch(collection).first;
      if (docs.isEmpty) continue;
      final data = {for (final d in docs) d.id: d.data};
      if (setMany != null) {
        await setMany(collection, data);
      } else {
        for (final e in data.entries) {
          await cloud.set(collection, e.key, e.value);
        }
      }
      moved += docs.length;
    }
  }
  await prefs.setBool(key, true);
  return moved;
}
