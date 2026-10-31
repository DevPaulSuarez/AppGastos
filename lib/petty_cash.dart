import 'dart:math';

import 'package:primera_app_curso/cash.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/models.dart';

/// Lo que sacaron de la caja chica (préstamo para el mes) o lo que le
/// devolvieron. Solo mueve dinero de un lado a otro: no es gasto ni ingreso.
class PettyCashMove {
  final String id;
  final double amount;

  /// true si lo sacaron de la caja; false si lo devolvieron.
  final bool taken;
  final int year;
  final int month;
  final int day;

  const PettyCashMove({
    this.id = '',
    required this.amount,
    required this.taken,
    required this.year,
    required this.month,
    required this.day,
  });

  factory PettyCashMove.fromMap(String id, Map<String, dynamic> map) =>
      PettyCashMove(
        id: id,
        amount: currencySettings.convert(
          (map['amount'] as num).toDouble(),
          map['currency'] as String?,
        ),
        taken: map['taken'] as bool? ?? true,
        year: map['year'] as int,
        month: map['month'] as int,
        day: map['day'] as int,
      );

  Map<String, dynamic> toMap() => {
    'amount': amount,
    'currency': currencySettings.code,
    'taken': taken,
    'year': year,
    'month': month,
    'day': day,
  };
}

/// La caja chica en un mes. Lo que sobra cada mes entra solo a la caja al
/// terminar el mes, así cada mes empieza de cero. Si un mes falta dinero
/// (ej. el alquiler llega antes que el sueldo), se saca de la caja como
/// préstamo y se devuelve en el mismo mes.
class PettyCashMonth {
  final int month;
  final int year;

  /// Lo que había en la caja al empezar el mes: lo que sobró de los meses
  /// anteriores (con el punto de partida).
  final double start;

  /// Resultado del mes: lo que entró menos lo gastado, ahorrado y prestado.
  final double result;
  final List<PettyCashMove> moves;

  const PettyCashMonth({
    required this.month,
    required this.year,
    required this.start,
    required this.result,
    this.moves = const [],
  });

  /// Caja chica del mes [month]/[year] según todo lo registrado.
  factory PettyCashMonth.of(
    List<Income> incomes,
    List<Expense> expenses,
    CashCheck? check,
    int people,
    List<PettyCashMove> moves,
    int month,
    int year,
  ) {
    double freeUntil(DateTime d) =>
        cashSummaryUntil(incomes, expenses, check, people, d).free;
    final start = freeUntil(DateTime(year, month, 0));
    return PettyCashMonth(
      month: month,
      year: year,
      start: start,
      result: freeUntil(DateTime(year, month + 1, 0)) - start,
      moves: moves.where((m) => m.month == month && m.year == year).toList()
        ..sort((a, b) => a.day.compareTo(b.day)),
    );
  }

  double get taken =>
      moves.where((m) => m.taken).fold(0.0, (a, m) => a + m.amount);

  double get returned =>
      moves.where((m) => !m.taken).fold(0.0, (a, m) => a + m.amount);

  /// Lo que todavía deben devolver a la caja este mes.
  double get owed => max(0, taken - returned);

  /// Lo que hay ahora en la caja (sin lo que sacaron).
  double get inBox => start - taken + returned;

  /// Lo que tienen para el mes: su resultado más lo que sacaron de la caja.
  double get inHand => result + taken - returned;

  /// Lo que queda en la caja al cerrar el mes: el sobrante (o faltante) del
  /// mes entra a la caja y cubre lo que no devolvieron.
  double get end => start + result;

  bool get isEmpty =>
      moves.isEmpty && start.abs() < 0.005 && result.abs() < 0.005;
}
