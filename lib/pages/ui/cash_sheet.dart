import 'package:flutter/material.dart';
import 'package:primera_app_curso/cash.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
import 'package:primera_app_curso/theme.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';

/// Panel del mes: cuánto dinero deberían tener (para compararlo con bancos y
/// efectivo) y cómo van las metas. Lo acumulado de todo el año está en el
/// "Resumen del año".
Future<void> showCashSheet(
  BuildContext context, {
  required int month,
  required int year,
}) {
  final db = Provider.of<ExpensesRepository>(context, listen: false);
  final finance = Provider.of<FinanceRepository>(context, listen: false);

  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: MultiStreamBuilder(
        streams: [
          finance.watchAllIncomes(),
          db.queryAll(),
          finance.watchCashCheck(),
          finance.watchPeople(),
          finance.watchGoals(),
        ],
        placeholder: const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        builder: (context, values) => _MonthCash(
          finance: finance,
          month: month,
          year: year,
          incomes: values[0] as List<Income>,
          expenses: values[1] as List<Expense>,
          check: values[2] as CashCheck?,
          people: values[3] as List<String>,
          goals: values[4] as List<Goal>,
        ),
      ),
    ),
  );
}

class _MonthCash extends StatelessWidget {
  final FinanceRepository finance;
  final int month;
  final int year;
  final List<Income> incomes;
  final List<Expense> expenses;
  final CashCheck? check;
  final List<String> people;
  final List<Goal> goals;

  const _MonthCash({
    required this.finance,
    required this.month,
    required this.year,
    required this.incomes,
    required this.expenses,
    required this.check,
    required this.people,
    required this.goals,
  });

  bool get _isCurrent {
    final now = DateTime.now();
    return now.month == month && now.year == year;
  }

  /// Hasta dónde se cuenta: hoy en el mes en curso (lo de días que aún no
  /// llegan todavía no salió del banco) o el último día del mes.
  DateTime get _until {
    final now = DateTime.now();
    return _isCurrent
        ? DateTime(now.year, now.month, now.day)
        : DateTime(year, month, daysInMonth(month, year));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final solo = people.length < 2;
    final monthName = monthNames[month - 1];
    final label = '${monthName[0]}${monthName.substring(1).toLowerCase()}';
    final start = cashSummaryUntil(
      incomes,
      expenses,
      check,
      people.length,
      DateTime(year, month, 0),
    );
    final end = cashSummaryUntil(
      incomes,
      expenses,
      check,
      people.length,
      _until,
    );

    Widget row(
      String text,
      String value, {
      Color? color,
      bool bold = false,
      String? hint,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: bold ? FontWeight.w700 : null,
                    ),
                  ),
                  if (hint != null)
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
      ),
    );

    final monthSavings = expenses.where(
      (e) => e.category == ahorroCategory && e.month == month && e.year == year,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isCurrent
                  ? (solo ? 'Tu dinero hoy' : 'Su dinero hoy')
                  : (solo
                        ? 'Tu dinero al terminar $label'
                        : 'Su dinero al terminar $label'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                money(end.free),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: end.free < 0 ? context.money.expense : null,
                ),
              ),
            ),
            Center(
              child: Text(
                'disponible para gastar',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            row(
              solo ? 'Al empezar el mes tenías' : 'Al empezar el mes tenían',
              money(start.free),
              hint: check == null
                  ? 'Todavía no se indicó cuánto había al empezar: parte de 0'
                  : null,
            ),
            row(
              '+ Entró este mes',
              money(end.income - start.income),
              color: context.money.income,
            ),
            row(
              '− Se gastó este mes',
              money(end.spent - start.spent),
              color: context.money.expense,
            ),
            if (end.saved - start.saved > 0.004)
              row(
                '− Se apartó para ahorro',
                money(end.saved - start.saved),
                color: context.money.savings,
              ),
            const Divider(),
            row('= Disponible', money(end.free), bold: true),
            if (end.saved > 0.004)
              row(
                solo ? 'Además tienes ahorrado' : 'Además tienen ahorrado',
                money(end.saved),
                color: context.money.savings,
              ),
            if (end.receivable > 0)
              row(
                solo ? 'Y te deben' : 'Y les deben',
                money(end.receivable),
                color: context.money.warning,
                hint: 'Préstamos que todavía no devuelven',
              ),

            if (_isCurrent) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.account_balance),
                label: Text(
                  solo ? 'Comparar con mi banco' : 'Comparar con nuestro banco',
                ),
                onPressed: () => _compare(context, end),
              ),
              const SizedBox(height: 6),
              Text(
                'Escribe cuánto hay de verdad (banco + efectivo) y la app te '
                'dice si coincide.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],

            if (goals.isNotEmpty) ...[
              section('Metas'),
              for (final goal in goals) _goalRow(context, goal, monthSavings),
            ],

            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('Ver resumen del año $year'),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed('/year', arguments: year);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _goalRow(
    BuildContext context,
    Goal goal,
    Iterable<Expense> monthSavings,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final saved = expenses
        .where((e) => e.goalId == goal.id)
        .fold(0.0, (a, e) => a + e.value);
    final thisMonth = monthSavings
        .where((e) => e.goalId == goal.id)
        .fold(0.0, (a, e) => a + e.value);
    final progress = goal.target <= 0 ? 0.0 : saved / goal.target;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  goal.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text('${money(saved)} de ${money(goal.target)}'),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              color: progress >= 1 ? context.money.warning : context.money.savings,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            thisMonth > 0
                ? 'Este mes aportaron ${money(thisMonth)}'
                : 'Este mes no aportaron',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _compare(BuildContext context, CashSummary today) async {
    final solo = people.length < 2;
    final values = await showFieldsDialog(
      context,
      title: solo ? '¿Cuánto tienes hoy?' : '¿Cuánto tienen hoy?',
      confirm: 'Comparar',
      hint: 'Suma el banco y el efectivo, incluido lo que tienes ahorrado.',
      fields: [
        DialogField(
          'Banco + efectivo',
          initial: today.total.toStringAsFixed(2),
          number: true,
        ),
      ],
    );
    if (values == null || !context.mounted) return;
    final total = parseAmount(values[0])!;
    // Manejan un solo fondo: todo va en la primera persona.
    final real = [total, for (var i = 1; i < people.length; i++) 0.0];

    // Se ajusta con lo registrado hasta hoy (lo de días futuros aún no pasó).
    bool upToToday(int y, int m, int d) => !DateTime(y, m, d).isAfter(_until);
    final reconciled = reconcile(
      incomes.where((i) => upToToday(i.year, i.month, i.day)).toList(),
      expenses.where((e) => upToToday(e.year, e.month, e.day)).toList(),
      real,
    );

    final diff = total - today.total;
    final matches = diff.abs() < 0.01;
    final adjust = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          matches ? Icons.check_circle : Icons.compare_arrows,
          color: matches ? context.money.income : context.money.warning,
          size: 40,
        ),
        title: Text(matches ? '¡Coincide!' : 'No coincide'),
        content: Text(
          matches
              ? 'La app y el banco dicen lo mismo: ${money(total)}.'
              : 'Hay ${money(diff.abs())} ${diff < 0 ? 'menos' : 'más'} de lo '
                    'que dice la app.\n\n'
                    '${diff < 0 ? 'Puede ser un gasto que no se anotó.' : 'Puede ser un ingreso que no se anotó.'} '
                    'Si lo encuentras, anótalo. Si no, ajusta la app a lo '
                    'real (no se crea ningún gasto ni ingreso).',
        ),
        actions: [
          if (!matches)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Revisar primero'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(matches ? 'Listo' : 'Ajustar a lo real'),
          ),
        ],
      ),
    );
    if (adjust == true) await finance.saveCashCheck(reconciled);
  }
}
