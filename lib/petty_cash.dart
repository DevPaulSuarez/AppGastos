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

  /// Cierre del mes: de lo que sobró, [amount] se mandó al ahorro (gasto
  /// "Ahorro Neto" con id [savedId]) y el resto quedó en la caja.
  final bool closing;
  final String? savedId;
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
    this.closing = false,
    this.savedId,
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
        closing: map['closing'] as bool? ?? false,
        savedId: map['savedId'] as String?,
      );

  Map<String, dynamic> toMap() => {
    'amount': amount,
    'currency': currencySettings.code,
    'taken': taken,
    'year': year,
    'month': month,
    'day': day,
    if (closing) 'closing': true,
    if (savedId != null) 'savedId': savedId,
  };
}

/// La caja chica en un mes. Lo que sobra cada mes entra a la caja al
/// terminar el mes, así cada mes empieza de cero. Al empezar el mes siguiente
/// eligen cuánto de lo que sobró queda en la caja; el resto se va al ahorro. Si un mes falta dinero
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

  /// Cómo se repartió lo que sobró este mes (caja / ahorro), si ya lo hicieron.
  final PettyCashMove? closing;

  const PettyCashMonth({
    required this.month,
    required this.year,
    required this.start,
    required this.result,
    this.moves = const [],
    this.closing,
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
    final ofMonth = moves.where((m) => m.month == month && m.year == year);
    return PettyCashMonth(
      month: month,
      year: year,
      start: start,
      result: freeUntil(DateTime(year, month + 1, 0)) - start,
      moves: ofMonth.where((m) => !m.closing).toList()
        ..sort((a, b) => a.day.compareTo(b.day)),
      closing: ofMonth.where((m) => m.closing).firstOrNull,
    );
  }

  /// Lo que se mandó al ahorro de lo que sobró este mes.
  double get sentToSavings => closing?.amount ?? 0;

  /// Si todavía falta decidir cuánto de lo que sobró queda en la caja.
  bool get needsSplit => closing == null && result > 0.005;

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
