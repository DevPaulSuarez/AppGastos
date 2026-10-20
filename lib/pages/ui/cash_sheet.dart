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
      (e) =>
          e.category == ahorroCategory && e.month == month && e.year == year,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isCurrent
                  ? '¿Cuánto deberían tener hoy?'
                  : '¿Cuánto tenían al terminar $label?',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Entre bancos y efectivo, según lo registrado en $label $year.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                money(end.total),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: end.total < 0 ? expenseColor : null,
                ),
              ),
            ),

            section('El mes de $label'),
            row(
              'Al empezar el mes tenían',
              money(start.total),
              hint: check == null
                  ? 'Aún no comparan con sus cuentas: parte de 0'
                  : null,
            ),
            row(
              '+ Les entró este mes',
              money(end.income - start.income),
              color: incomeColor,
            ),
            row(
              '− Pagaron este mes',
              money(end.spent - start.spent),
              color: expenseColor,
              hint: 'Gastos y préstamos. Lo que apartaron como ahorro sigue '
                  'siendo suyo.',
            ),
            const Divider(),
            row(
              _isCurrent ? '= Deberían tener hoy' : '= Al terminar el mes',
              money(end.total),
              bold: true,
            ),

            section('Por persona'),
            for (var i = 0; i < people.length; i++)
              row(
                people[i],
                money(end.people[i].total),
                hint:
                    'Empezó con ${money(start.people[i].total)} · '
                    'entró ${money(end.people[i].income - start.people[i].income)} · '
                    'pagó ${money(end.people[i].spent - start.people[i].spent)}',
              ),
            if (end.receivable > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Además les deben ${money(end.receivable)} por préstamos '
                  '(no está en sus cuentas todavía).',
                  style: const TextStyle(fontSize: 13, color: warningColor),
                ),
              ),

            if (_isCurrent) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.account_balance),
                label: Text(
                  check == null
                      ? 'Indicar cuánto tenemos hoy'
                      : 'Comparar con nuestras cuentas',
                ),
                onPressed: () => _compare(context, end),
              ),
              const SizedBox(height: 6),
              Text(
                check == null
                    ? 'Cada uno escribe cuánto tiene hoy (bancos + efectivo). '
                          'Eso será el punto de partida.'
                    : 'Cada uno escribe cuánto tiene hoy y la app les dice '
                          'si coincide con lo registrado. Última comparación: '
                          '${check!.date.day}/${check!.date.month}/${check!.date.year}.',
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
              color: progress >= 1 ? warningColor : savingsColor,
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
    final values = await showFieldsDialog(
      context,
      title: '¿Cuánto tiene cada uno hoy?',
      confirm: check == null ? 'Guardar' : 'Comparar',
      hint:
          'Sumen bancos y efectivo de cada uno. Lo que les deben no se '
          'cuenta.',
      fields: [
        for (final name in people)
          DialogField('$name (bancos + efectivo)', initial: '0', number: true),
      ],
    );
    if (values == null || !context.mounted) return;
    final real = [for (final v in values) parseAmount(v)!];

    // Se ajusta con lo registrado hasta hoy (lo de días futuros aún no pasó).
    bool upToToday(int y, int m, int d) =>
        !DateTime(y, m, d).isAfter(_until);
    final reconciled = reconcile(
      incomes.where((i) => upToToday(i.year, i.month, i.day)).toList(),
      expenses.where((e) => upToToday(e.year, e.month, e.day)).toList(),
      real,
    );

    // La primera vez solo se toma como punto de partida.
    if (check == null) {
      await finance.saveCashCheck(reconciled);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Listo: desde ahora la app parte de '
            '${money(reconciled.realTotal)}',
          ),
        ),
      );
      return;
    }

    String line(String who, double expected, double actual) {
      final diff = actual - expected;
      if (diff.abs() < 0.01) return '✓ $who: coincide (${money(actual)})';
      return '• $who tiene ${money(diff.abs())} ${diff < 0 ? 'menos' : 'más'} '
          '(app: ${money(expected)}, real: ${money(actual)})';
    }

    final totalDiff = reconciled.realTotal - today.total;
    final matches = [
      for (var i = 0; i < people.length; i++)
        (real[i] - today.people[i].total).abs() < 0.01,
    ].every((ok) => ok);

    final adjust = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          matches ? Icons.check_circle : Icons.compare_arrows,
          color: matches ? incomeColor : warningColor,
          size: 40,
        ),
        title: Text(matches ? '¡Coincide!' : 'No coincide'),
        content: Text(
          [
            for (var i = 0; i < people.length; i++)
              line(people[i], today.people[i].total, real[i]),
            if (!matches) ...[
              '',
              totalDiff < 0
                  ? 'Entre los dos tienen ${money(-totalDiff)} menos de lo '
                        'registrado: puede ser un gasto que no anotaron.'
                  : totalDiff > 0
                  ? 'Entre los dos tienen ${money(totalDiff)} más de lo '
                        'registrado: puede ser un ingreso que no anotaron.'
                  : 'En total coincide; solo cambia quién tiene el dinero '
                        '(por ejemplo, uno le pasó plata al otro).',
              '',
              'Si encuentran lo que falta, regístrenlo. Si no, ajusten la app '
                  'a lo real (no se crea ningún gasto ni ingreso).',
            ],
          ].join('\n'),
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
