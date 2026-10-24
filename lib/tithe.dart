import 'dart:math';

import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/models.dart';

/// Nota con la que se anota el diezmo en la categoría de la iglesia.
const titheNote = 'Diezmo';

/// El diezmo es siempre el 10% de lo que entra.
const tithePercent = 10;

bool isTithe(Expense e) =>
    e.category == iglesiaCategory &&
    e.description.trim().toLowerCase() == titheNote.toLowerCase();

/// Diezmo de un mes: el 10% del sueldo neto que ya llegó (no de los
/// ingresos anotados a mano) y lo que ya se dio. Durante el mes solo se
/// aparta; se da a fin de mes.
class Tithe {
  /// Sueldo que llegó en el mes.
  final double income;

  /// Lo que ya se dio como diezmo en el mes.
  final double given;

  const Tithe({required this.income, required this.given});

  /// Ingresos y gastos de un solo mes.
  factory Tithe.of(List<Income> incomes, List<Expense> expenses) => Tithe(
    income: incomes.where((i) => i.isSalary).fold(0.0, (a, i) => a + i.amount),
    given: expenses.where(isTithe).fold(0.0, (a, e) => a + e.value),
  );

  double get owed => (income * tithePercent).roundToDouble() / 100;

  /// Lo que falta dar: queda separado, como un pago fijo.
  double get pending => max(0, owed - given);
}
