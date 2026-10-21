import 'package:flutter/material.dart';
import 'package:primera_app_curso/cash.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/pages/report_page.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
import 'package:primera_app_curso/theme.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';

/// Resumen de todo un año: totales, por persona, lo acumulado (lo que sobró
/// de todos los meses), metas y el detalle mes a mes.
class YearPage extends StatefulWidget {
  final int year;

  const YearPage({super.key, required this.year});

  @override
  State<YearPage> createState() => _YearPageState();
}

class _YearPageState extends State<YearPage> {
  late int year = widget.year;

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<ExpensesRepository>(context);
    final finance = Provider.of<FinanceRepository>(context);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Año anterior',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => year--),
            ),
            Text('Resumen $year'),
            IconButton(
              tooltip: 'Año siguiente',
              icon: const Icon(Icons.chevron_right),
              onPressed: year >= now.year ? null : () => setState(() => year++),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Informe anual en PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => Navigator.of(
              context,
            ).pushNamed('/report', arguments: ReportParams(year)),
          ),
        ],
      ),
      body: MultiStreamBuilder(
        key: ValueKey(year),
        streams: [
          finance.watchAllIncomes(),
          db.queryAll(),
          finance.watchPeople(),
          finance.watchGoals(),
          finance.watchCashCheck(),
        ],
        builder: (context, values) => _content(
          context,
          allIncomes: values[0] as List<Income>,
          allExpenses: values[1] as List<Expense>,
          people: values[2] as List<String>,
          goals: values[3] as List<Goal>,
          check: values[4] as CashCheck?,
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context, {
    required List<Income> allIncomes,
    required List<Expense> allExpenses,
    required List<String> people,
    required List<Goal> goals,
    required CashCheck? check,
  }) {
    double sum(Iterable<double> values) => values.fold(0.0, (a, b) => a + b);
    final incomes = allIncomes.where((i) => i.year == year).toList();
    final expenses = allExpenses.where((e) => e.year == year).toList();
    final spending = expenses.where((e) => isSpendingCategory(e.category));

    final totalIncome = sum(incomes.map((i) => i.amount));
    final spent = sum(spending.map((e) => e.value));
    final saved = sum(
      expenses.where((e) => e.category == ahorroCategory).map((e) => e.value),
    );
    final lent = sum(
      expenses.where((e) => e.category == prestamoCategory).map((e) => e.value),
    );
    final leftover = totalIncome - spent - saved - lent;

    final now = DateTime.now();
    final until = year >= now.year
        ? DateTime(now.year, now.month, now.day)
        : DateTime(year, 12, 31);
    final accumulated = cashSummaryUntil(
      allIncomes,
      allExpenses,
      check,
      people.length,
      until,
    );

    // Los meses de antes de empezar a usar la app no se muestran.
    final monthsWithData = [
      ...incomes.map((i) => i.month),
      ...expenses.map((e) => e.month),
    ];
    final firstMonth = monthsWithData.isEmpty
        ? 13
        : monthsWithData.reduce((a, b) => a < b ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _Card(
          title: 'Totales de $year',
          children: [
            _row('Ingresos', totalIncome, color: context.money.income),
            _row('Gastos', -spent, color: context.money.expense),
            if (saved != 0)
              _row('Apartado en ahorro y metas', -saved, color: context.money.savings),
            if (lent != 0)
              _row(
                lent > 0 ? 'Prestado (por cobrar)' : 'Les devolvieron',
                -lent,
              ),
            const Divider(),
            _row(
              'Sobrante del año',
              leftover,
              bold: true,
              color: leftover < 0 ? context.money.expense : context.money.income,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Por persona en $year',
          children: [
            for (var i = 0; i < people.length; i++) ...[
              if (i > 0) const Divider(),
              Text(
                people[i],
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              _row(
                'Ingresó',
                sum(incomes.where((x) => x.person == i).map((x) => x.amount)),
              ),
              () {
                final paid = sum(
                  spending.where((e) => e.paidBy == i).map((e) => e.value),
                );
                return _row(
                  spent > 0
                      ? 'Pagó en gastos (${(paid / spent * 100).round()}%)'
                      : 'Pagó en gastos',
                  paid,
                );
              }(),
              _row(
                'Propinas',
                sum(
                  spending
                      .where(
                        (e) => e.paidBy == i && e.category == propinaCategory,
                      )
                      .map((e) => e.value),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          title: year >= now.year
              ? 'Dinero acumulado hasta hoy'
              : 'Dinero acumulado al cerrar $year',
          children: [
            _row('Deberían tener en total', accumulated.total, bold: true),
            _row(
              'Apartado en ahorro y metas',
              accumulated.saved,
              color: context.money.savings,
            ),
            _row(
              'Libre',
              accumulated.free,
              color: accumulated.free < 0 ? context.money.expense : context.money.income,
            ),
            const SizedBox(height: 4),
            Text(
              'Incluye lo que sobró en todos los meses anteriores'
              '${check == null ? '' : ' y el punto de partida de su última comparación'}.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        if (goals.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Card(
            title: 'Metas',
            children: [
              for (final goal in goals) _goal(context, goal, allExpenses),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _Card(
          title: 'Mes a mes',
          children: [
            for (var m = 1; m <= 12; m++)
              // Desde el primer mes con algo anotado hasta el mes en curso.
              if ((year < now.year || m <= now.month) && m >= firstMonth)
                () {
                  final inc = sum(
                    incomes.where((i) => i.month == m).map((i) => i.amount),
                  );
                  final out = sum(
                    expenses.where((e) => e.month == m).map((e) => e.value),
                  );
                  final left = inc - out;
                  final name = monthNames[m - 1];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: Text(
                            '${name[0]}${name.substring(1).toLowerCase()}',
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${money(inc)} − ${money(out)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Text(
                          money(left),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: left < 0 ? context.money.expense : context.money.income,
                          ),
                        ),
                      ],
                    ),
                  );
                }(),
            const SizedBox(height: 4),
            const Text(
              'Ingresos − todo lo que salió (gastos, ahorro y préstamos) = '
              'sobrante de cada mes.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  Widget _goal(BuildContext context, Goal goal, List<Expense> allExpenses) {
    final saved = allExpenses
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
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, double value, {Color? color, bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 17 : 15,
      fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          // Los montos que restan se muestran "− S/. 10.00", no "S/. -10.00".
          Text(value < 0 ? '− ${money(-value)}' : money(value), style: style),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Card({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
