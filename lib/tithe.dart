import 'dart:math';

import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/models.dart';

/// Nota con la que se anota el diezmo en la categoría de la iglesia.
const titheNote = 'Diezmo';

/// El diezmo es el 10% de lo que entra, salvo que cambien el monto del mes.
const tithePercent = 10;

bool isTithe(Expense e) =>
    e.category == iglesiaCategory &&
    e.description.trim().toLowerCase() == titheNote.toLowerCase();

/// Quién aparta su diezmo y los montos que cambiaron a mano. Cada persona
/// lo da por separado, de su propio sueldo.
class TitheSettings {
  /// Personas (0 o 1) que apartan su diezmo.
  final Set<int> people;

  /// Monto cambiado a mano, por mes y persona (clave de [key]).
  final Map<String, double> amounts;

  const TitheSettings({this.people = const {}, this.amounts = const {}});

  bool get on => people.isNotEmpty;

  static String key(int year, int month, int person) => '$year-$month-$person';

  /// Monto cambiado a mano de ese mes, o null si es el 10% del sueldo.
  double? amountFor(int year, int month, int person) =>
      amounts[key(year, month, person)];

  factory TitheSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const TitheSettings();
    final people = (map['people'] as List?)?.cast<num>();
    final amounts = (map['amounts'] as Map?)?.cast<String, dynamic>() ?? {};
    return TitheSettings(
      // Antes era un solo interruptor para los dos.
      people: people != null
          ? {for (final p in people) p.toInt()}
          : map['on'] == true
          ? {0, 1}
          : {},
      amounts: {
        for (final e in amounts.entries)
          e.key: currencySettings.convert(
            (e.value['value'] as num).toDouble(),
            e.value['currency'] as String?,
          ),
      },
    );
  }

  Map<String, dynamic> toMap() => {
    'people': people.toList()..sort(),
    'amounts': {
      for (final e in amounts.entries)
        e.key: {'value': e.value, 'currency': currencySettings.code},
    },
  };
}

/// Diezmo de una persona en un mes: el 10% de su sueldo neto que ya llegó
/// (no de los ingresos anotados a mano), o el monto que puso, y lo que ya
/// dio. Durante el mes solo se aparta; se da a fin de mes.
class Tithe {
  final int person;

  /// Sueldo de la persona que llegó en el mes.
  final double income;

  /// Lo que ya dio como diezmo en el mes.
  final double given;

  /// Monto cambiado a mano; null si es el 10% del sueldo.
  final double? amount;

  const Tithe({
    this.person = 0,
    required this.income,
    required this.given,
    this.amount,
  });

  /// Ingresos y gastos de un solo mes. El diezmo sin "quién lo dio" cuenta
  /// como de la primera persona.
  factory Tithe.of(
    List<Income> incomes,
    List<Expense> expenses, {
    int person = 0,
    double? amount,
  }) => Tithe(
    person: person,
    income: incomes
        .where((i) => i.isSalary && i.person == person)
        .fold(0.0, (a, i) => a + i.amount),
    given: expenses
        .where((e) => isTithe(e) && (e.paidBy ?? 0) == person)
        .fold(0.0, (a, e) => a + e.value),
    amount: amount,
  );

  double get owed => amount ?? (income * tithePercent).roundToDouble() / 100;

  bool get changed => amount != null;

  /// Lo que falta dar: queda separado, como un pago fijo.
  double get pending => max(0, owed - given);
}

/// El diezmo de quienes lo apartan, cada uno por separado, con los totales.
class Tithes {
  final List<Tithe> people;

  const Tithes(this.people);

  /// Diezmo de un mes de cada persona que lo aparta; [count] es cuántas
  /// personas lleva la cuenta (1 si es individual).
  factory Tithes.of(
    TitheSettings settings,
    List<Income> incomes,
    List<Expense> expenses,
    int month,
    int year, {
    int count = 2,
  }) {
    final monthIncomes = incomes
        .where((i) => i.month == month && i.year == year)
        .toList();
    final monthExpenses = expenses
        .where((e) => e.month == month && e.year == year)
        .toList();
    return Tithes([
      for (final p in settings.people.toList()..sort())
        if (p < count)
          Tithe.of(
            monthIncomes,
            monthExpenses,
            person: p,
            amount: settings.amountFor(year, month, p),
          ),
    ]);
  }

  bool get isEmpty => people.isEmpty;

  double get income => people.fold(0.0, (a, t) => a + t.income);
  double get given => people.fold(0.0, (a, t) => a + t.given);
  double get owed => people.fold(0.0, (a, t) => a + t.owed);
  double get pending => people.fold(0.0, (a, t) => a + t.pending);
}
