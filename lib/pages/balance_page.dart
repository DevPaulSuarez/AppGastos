import 'package:flutter/material.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/graph_widget.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/pages/report_page.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
import 'package:primera_app_curso/theme.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';

class BalanceParams {
  /// Mes de 1 a 12.
  final int month;
  final int year;

  const BalanceParams(this.month, this.year);
}

/// Balance de un mes: ingresos, gastos, ahorro, sobrante y cuánto gastó cada
/// persona. También muestra el ahorro acumulado de todos los meses.
class BalancePage extends StatelessWidget {
  final BalanceParams params;

  const BalancePage({super.key, required this.params});

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<ExpensesRepository>(context);
    final finance = Provider.of<FinanceRepository>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text("Balance · ${monthNames[params.month - 1]} ${params.year}"),
        actions: [
          IconButton(
            tooltip: 'Informe en PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => Navigator.of(context).pushNamed('/report',
                arguments: ReportParams(params.year, month: params.month)),
          ),
        ],
      ),
      body: MultiStreamBuilder(
        streams: [
          db.queryByMonth(params.month, params.year),
          finance.watchIncomes(params.month, params.year),
          finance.watchPeople(),
          finance.watchAllIncomes(),
          db.queryAll(),
          finance.watchGoals(),
        ],
        builder: (context, values) => _content(
          context,
          finance,
          expenses: values[0] as List<Expense>,
          incomes: values[1] as List<Income>,
          people: values[2] as List<String>,
          allIncomes: values[3] as List<Income>,
          allExpenses: values[4] as List<Expense>,
          goals: values[5] as List<Goal>,
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    FinanceRepository finance, {
    required List<Expense> expenses,
    required List<Income> incomes,
    required List<String> people,
    required List<Income> allIncomes,
    required List<Expense> allExpenses,
    required List<Goal> goals,
  }) {
    double sum(Iterable<double> values) => values.fold(0.0, (a, b) => a + b);
    bool isSaving(Expense e) => e.category == ahorroCategory;
    bool isSpending(Expense e) => isSpendingCategory(e.category);

    final totalIncomes = sum(incomes.map((i) => i.amount));
    final spent = sum(expenses.where(isSpending).map((e) => e.value));
    final saved = sum(expenses.where(isSaving).map((e) => e.value));
    // Prestado este mes menos lo que devolvieron.
    final lent = sum(expenses
        .where((e) => e.category == prestamoCategory)
        .map((e) => e.value));
    final leftover = totalIncomes - spent - saved - lent;
    final spentCount = expenses.where(isSpending).length;
    final paidBy = [
      for (var i = 0; i < people.length; i++)
        sum(expenses
            .where((e) => isSpending(e) && e.paidBy == i)
            .map((e) => e.value)),
    ];

    // Ingresos y gastos de los últimos 6 meses, terminando en este mes.
    final trend = [
      for (var i = 5; i >= 0; i--) DateTime(params.year, params.month - i)
    ]
        .map((d) => TrendMonth(
              monthNames[d.month - 1].substring(0, 3),
              sum(allIncomes
                  .where((x) => x.month == d.month && x.year == d.year)
                  .map((x) => x.amount)),
              sum(allExpenses
                  .where((e) =>
                      isSpending(e) && e.month == d.month && e.year == d.year)
                  .map((e) => e.value)),
            ))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _Card(children: [
          _row('Ingresos', totalIncomes, color: incomeColor),
          _row('Gastos', -spent, color: expenseColor),
          _row('Separado para ahorro', -saved, color: savingsColor),
          if (lent != 0)
            _row(lent > 0 ? 'Prestado (por cobrar)' : 'Te devolvieron préstamos',
                -lent),
          const Divider(),
          _row('Sobrante del mes', leftover,
              bold: true,
              color: leftover < 0 ? expenseColor : incomeColor),
          if (leftover < 0)
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text('Este mes se gastó más de lo que entró.',
                  style: TextStyle(color: expenseColor)),
            ),
          if (spentCount > 0) ...[
            const Divider(),
            _row('Gasto promedio ($spentCount '
                '${spentCount == 1 ? 'gasto' : 'gastos'})', spent / spentCount),
          ],
        ]),
        _title('Últimos 6 meses'),
        _Card(children: [
          SizedBox(height: 180, child: TrendChart(months: trend)),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Legend(color: incomeColor, label: 'Ingresos'),
              SizedBox(width: 24),
              _Legend(color: expenseColor, label: 'Gastos'),
            ],
          ),
        ]),
        _title('Ingresos del mes',
            action: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
              onPressed: () => _addIncome(context, finance, people),
            )),
        if (incomes.isEmpty)
          const Text(
              'Aún no hay ingresos. Agrega los sueldos fijos en Ajustes para '
              'que se registren solos cada mes.',
              style: TextStyle(color: Colors.grey)),
        for (final income in incomes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.payments, color: incomeColor),
            title: Text(income.description.isEmpty
                ? 'Ingreso'
                : income.description),
            subtitle: Text(
                '${personName(people, income.person)} · día ${income.day}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(money(income.amount),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await confirmDialog(
                        context, '¿Borrar este ingreso de ${money(income.amount)}?',
                        confirm: 'Borrar')) {
                      finance.deleteIncome(income.id);
                    }
                  },
                ),
              ],
            ),
          ),
        _title('Por persona'),
        _Card(children: [
          for (var i = 0; i < people.length; i++) ...[
            Text(people[i],
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16.0)),
            _row('Aportó (ingresos)',
                sum(incomes.where((x) => x.person == i).map((x) => x.amount))),
            _row(
                spent > 0
                    ? 'Pagó en gastos (${(100 * paidBy[i] / spent).round()}%)'
                    : 'Pagó en gastos',
                paidBy[i]),
            _row(
                'Propinas',
                sum(expenses
                    .where((e) =>
                        e.paidBy == i && e.category == propinaCategory)
                    .map((e) => e.value))),
            if (i < people.length - 1) const Divider(),
          ],
          if (expenses.any((e) => isSpending(e) && e.paidBy == null)) ...[
            const Divider(),
            _row(
                'Gastos sin asignar',
                sum(expenses
                    .where((e) => isSpending(e) && e.paidBy == null)
                    .map((e) => e.value))),
          ],
        ]),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text('Resumen del año ${params.year}'),
          onPressed: () =>
              Navigator.of(context).pushNamed('/year', arguments: params.year),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.savings),
          label: const Text('Metas de ahorro'),
          onPressed: () => Navigator.of(context).pushNamed('/goals'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _addIncome(BuildContext context, FinanceRepository finance,
      List<String> people) async {
    final values = await showFieldsDialog(
      context,
      title: 'Nuevo ingreso',
      fields: [
        DialogField('Persona', options: people),
        const DialogField('Descripción', initial: 'Ingreso extra'),
        const DialogField('Monto', number: true),
      ],
    );
    if (values == null) return;
    final now = DateTime.now();
    final isCurrent = now.month == params.month && now.year == params.year;
    await finance.addIncome(people.indexOf(values[0]), values[1],
        parseAmount(values[2])!, params.month, params.year,
        day: isCurrent ? now.day : 1);
  }

  Widget _title(String text, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                    color: null)),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _row(String label, double value, {Color? color, bool bold = false}) {
    final style = TextStyle(
        fontSize: bold ? 18.0 : 15.0,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(money(value), style: style),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;

  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
