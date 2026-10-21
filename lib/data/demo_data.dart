import 'dart:math';

import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/utils.dart';

/// Los datos de prueba llevan este prefijo en el id, para poder quitarlos
/// sin tocar lo que registró el usuario.
const demoPrefix = 'demo_';

/// Quita solo los gastos e ingresos de prueba.
Future<void> removeDemoData(Store store) async {
  for (final collection in ['expenses', 'incomes']) {
    final docs = await store.watch(collection).first;
    await store.deleteMany(collection,
        docs.where((d) => d.id.startsWith(demoPrefix)).map((d) => d.id));
  }
}

/// Completa con datos ficticios los meses desde enero hasta el mes pasado,
/// a partir de lo que el usuario ya tiene: sus sueldos, gastos fijos,
/// propinas y metas se repiten en cada mes, y se agregan los gastos
/// principales de un hogar con montos acordes a sus ingresos. No borra ni
/// cambia nada de lo existente; el mes actual no se toca.
Future<void> addDemoHistory(Store store, FinanceRepository finance,
    {DateTime? today}) async {
  await removeDemoData(store);

  final now = today ?? DateTime.now();
  final end = DateTime(now.year, now.month, 0); // último día del mes pasado
  final year = end.year;
  final random = Random(2026);

  final recurring = await finance.watchRecurring().first;
  final goals = await finance.watchGoals().first;

  // Los montos variables se ajustan a los ingresos de la pareja.
  final monthlyIncome = recurring
      .where((r) => r.type == RecurringType.income)
      .fold(0.0, (a, r) => a + r.amount);
  final scale = monthlyIncome <= 0 ? 1.0 : (monthlyIncome / 6500).clamp(0.4, 3.0);

  // Gastos que ya están como fijos no se inventan otra vez (ej. "Luz").
  final fixedNames = recurring
      .where((r) => r.type == RecurringType.expense)
      .map((r) => r.description.toLowerCase())
      .toSet();

  final expenses = <String, Map<String, dynamic>>{};
  final incomes = <String, Map<String, dynamic>>{};

  for (var month = 1; month <= end.month; month++) {
    final lastDay = daysInMonth(month, year);
    int between(int a, int b) => a + random.nextInt(b - a + 1);
    double amount(double min, double max) =>
        ((min + random.nextDouble() * (max - min)) * scale * 10).round() / 10;

    void add(String id, Expense expense) =>
        expenses['$demoPrefix$id'] = expense.toMap();

    void spend(String category, String note, double min, double max,
        {int? day, int? paidBy}) {
      if (fixedNames.contains(note.toLowerCase())) return;
      add(
          '${expenses.length}',
          Expense(
            id: '',
            category: category,
            value: amount(min, max),
            day: day ?? between(1, lastDay),
            month: month,
            year: year,
            description: note,
            paidBy: paidBy ?? random.nextInt(2),
          ));
    }

    void repeat(int times, String category, List<String> notes, double min,
        double max) {
      for (var i = 0; i < times; i++) {
        spend(category, notes[random.nextInt(notes.length)], min, max);
      }
    }

    // Sus sueldos, gastos fijos y propinas, repetidos en cada mes.
    for (final item in recurring) {
      final key = '${item.id}_$year-$month';
      switch (item.type) {
        case RecurringType.income:
          for (final date
              in FinanceRepository.occurrences(item, year, month)) {
            incomes['$demoPrefix${key}_${date.day}'] = Income(
              id: '',
              person: item.person,
              description: item.description,
              amount: item.amount,
              day: date.day,
              month: month,
              year: year,
            ).toMap();
          }
        case RecurringType.expense:
          for (final date
              in FinanceRepository.occurrences(item, year, month)) {
            add(
                '${key}_${date.day}',
                Expense(
                  id: '',
                  category: item.category,
                  value: item.amount,
                  day: date.day,
                  month: month,
                  year: year,
                  description: item.description,
                  paidBy: item.person,
                ));
          }
        case RecurringType.allowance:
          for (final date in FinanceRepository.payoutDates(
              year, month, item.biweekly)) {
            final day = date.day;
            add(
                '${key}_$day',
                Expense(
                  id: '',
                  category: propinaCategory,
                  value: item.amount,
                  day: day,
                  month: month,
                  year: year,
                  description: item.description,
                  paidBy: item.person,
                ));
          }
      }
    }

    // Gastos principales del hogar
    spend('Servicios', 'Luz', 110, 160, day: 18, paidBy: 0);
    spend('Servicios', 'Agua', 45, 70, day: 20, paidBy: 1);
    spend('Servicios', 'Gas', 35, 50, day: between(10, 25));
    for (final week in [3, 10, 17, 24]) {
      spend('Comida', 'Supermercado', 180, 320, day: week + between(0, 3));
    }
    repeat(4, 'Comida', ['Mercado', 'Panadería', 'Verdulería'], 30, 90);
    repeat(2, 'Transporte', ['Gasolina'], 120, 180);
    repeat(between(4, 6), 'Transporte', ['Taxi', 'Uber'], 10, 30);

    // Otros gastos del mes
    repeat(between(2, 3), 'Ocio', ['Restaurante', 'Cine', 'Salida con amigos'],
        50, 160);
    repeat(between(3, 5), 'Restaurantes', ['Café', 'Helado', 'Postre'], 6, 25);
    repeat(between(0, 2), 'Salud', ['Farmacia', 'Consulta médica'], 25, 150);
    repeat(between(1, 2), 'Ropa y cuidado', ['Ropa', 'Zapatillas', 'Regalo'], 60, 250);
    repeat(between(0, 1), 'Hogar', ['Limpieza', 'Utensilios de cocina'], 40, 180);

    // Aportes a sus metas de ahorro, a fin de mes.
    for (final goal in goals) {
      add(
          '${expenses.length}',
          Expense(
            id: '',
            category: ahorroCategory,
            value: amount(150, 400),
            day: min(28, lastDay),
            month: month,
            year: year,
            description: 'Meta: ${goal.name}',
            paidBy: random.nextInt(2),
            goalId: goal.id,
          ));
    }
  }

  if (store is LocalStore) {
    await store.setMany('expenses', expenses);
    await store.setMany('incomes', incomes);
  } else {
    for (final entry in expenses.entries) {
      await store.set('expenses', entry.key, entry.value);
    }
    for (final entry in incomes.entries) {
      await store.set('incomes', entry.key, entry.value);
    }
  }
}
