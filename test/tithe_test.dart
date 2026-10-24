import 'package:flutter_test/flutter_test.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late LocalStore store;
  late ExpensesRepository expenses;
  late FinanceRepository finance;
  final today = DateTime(2026, 10, 20);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    currencySettings = const CurrencySettings();
    categorySettings = const CategorySettings();
    store = LocalStore();
    expenses = ExpensesRepository(store);
    finance = FinanceRepository(store);
  });

  /// Un sueldo que llegó (los registra la app sola, con id "rec_").
  Future<void> salary(String id, double amount, int day) => store.set(
    'incomes',
    'rec_$id',
    Income(
      id: 'rec_$id',
      person: 0,
      description: 'Sueldo',
      amount: amount,
      day: day,
      month: 10,
      year: 2026,
    ).toMap(),
  );

  test('el diezmo está apagado al empezar y no separa nada', () async {
    await salary('a', 2000, 15);
    expect(await finance.watchTitheOn().first, isFalse);
    expect(await finance.pendingTithe(today: today), 0);
  });

  test('prendido, aparta el 10% del sueldo menos lo ya dado', () async {
    await finance.setTitheOn(true);
    await salary('a', 2000, 15);
    await salary('b', 500, 18);
    // Un ingreso anotado a mano no es sueldo: no cuenta.
    await finance.addIncome(0, 'Extra', 300, 10, 2026, day: 18);
    expect(await finance.pendingTithe(today: today), 250);

    // Solo cuenta lo anotado como "Diezmo" en Iglesia; la ofrenda no.
    await expenses.add(iglesiaCategory, 100, DateTime(2026, 10, 19), 'diezmo');
    await expenses.add(iglesiaCategory, 40, DateTime(2026, 10, 19), 'Ofrenda');
    expect(await finance.pendingTithe(today: today), 150);

    await expenses.add(iglesiaCategory, 200, DateTime(2026, 10, 20), 'Diezmo');
    expect(await finance.pendingTithe(today: today), 0);
  });
}
