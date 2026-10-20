import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/expense.dart';

/// Parte de los ingresos que debería quedar libre a fin de mes. Si el
/// sobrante baja de esto, están "en rojo".
const minLeftoverRatio = 0.20;

/// Desde qué día del mes se avisa por el ritmo de gasto (los primeros días
/// el ritmo todavía no dice mucho).
const _paceFromDay = 5;

enum AlertLevel { warning, danger }

class SpendingAlert {
  final AlertLevel level;
  final String title;
  final String message;

  const SpendingAlert(this.level, this.title, this.message);
}

/// Revisa cómo van en el mes en curso.
///
/// [fixedSpent] son los gastos fijos y propinas ya registrados: no se usan
/// para calcular el ritmo, porque se pagan una vez y no se repiten.
SpendingAlert? spendingAlert({
  required double income,
  required double spent,
  required double saved,
  required double fixedSpent,
  required int day,
  required int daysInMonth,
}) {
  if (income <= 0) return null;
  final leftover = income - spent - saved;
  final limit = income * minLeftoverRatio;
  final daysLeft = daysInMonth - day + 1; // incluye hoy
  final percentLeft = (leftover / income * 100).round();

  if (leftover <= limit) {
    if (leftover < 0) {
      return SpendingAlert(
        AlertLevel.danger,
        '¡Están en rojo!',
        'Este mes ya gastaron ${money(-leftover)} más de lo que ingresó. '
            'Eviten gastos que no sean necesarios.',
      );
    }
    return SpendingAlert(
      AlertLevel.danger,
      '¡Están en rojo!',
      'Solo les queda ${money(leftover)} ($percentLeft% de los ingresos) '
          'y faltan $daysLeft ${daysLeft == 1 ? 'día' : 'días'}. Traten de no '
          'gastar más de ${money(leftover / daysLeft)} por día.',
    );
  }

  if (day < _paceFromDay || day >= daysInMonth) return null;
  final variable = (spent - fixedSpent).clamp(0, double.infinity);
  final projectedSpent = fixedSpent + variable / day * daysInMonth;
  final projectedLeftover = income - projectedSpent - saved;
  if (projectedLeftover > limit) return null;

  final usedPercent = ((spent + saved) / income * 100).round();
  final monthPercent = (day / daysInMonth * 100).round();
  return SpendingAlert(
    AlertLevel.warning,
    'Van gastando muy rápido',
    'Ya usaron el $usedPercent% de los ingresos y va el $monthPercent% del '
        'mes. A este ritmo terminarán con '
        '${projectedLeftover < 0 ? 'una deuda de ${money(-projectedLeftover)}' : 'solo ${money(projectedLeftover)}'}. '
        'Para cerrar con al menos el ${(minLeftoverRatio * 100).round()}% libre, '
        'gasten como máximo ${money((leftover - limit) / daysLeft)} por día.',
  );
}

/// Alerta del mes [month]/[year] según sus movimientos, o null si no es el
/// mes en curso o va todo bien.
///
/// [pendingPayments] son gastos de fecha variable que aún no pagan (ej. el
/// alquiler): ya están comprometidos, así que cuentan como gastados.
SpendingAlert? monthAlert(
    List<Expense> expenses, double income, int month, int year,
    {double pendingPayments = 0}) {
  final now = DateTime.now();
  if (now.month != month || now.year != year) return null;
  final spending = expenses.where((e) => isSpendingCategory(e.category));
  // Lo prestado (menos lo devuelto) también sale del bolsillo, pero no marca
  // el ritmo de gasto.
  final lent = expenses
      .where((e) => e.category == prestamoCategory)
      .fold(0.0, (a, e) => a + e.value);
  return spendingAlert(
    income: income,
    spent: spending.fold(0.0, (a, e) => a + e.value) + lent + pendingPayments,
    saved: expenses
        .where((e) => e.category == ahorroCategory)
        .fold(0.0, (a, e) => a + e.value),
    fixedSpent:
        spending.where(isFixedExpense).fold(0.0, (a, e) => a + e.value) +
            lent +
            pendingPayments,
    day: now.day,
    daysInMonth: DateTime(year, month + 1, 0).day,
  );
}

/// Gastos fijos y propinas registrados solos (no cuentan para el ritmo).
bool isFixedExpense(Expense e) => e.id.startsWith('rec_');
