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
        title: Text('Resumen de ${monthNames[params.month - 1].toLowerCase()}'),
        actions: [
          IconButton(
            tooltip: 'Informe en PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => Navigator.of(context).pushNamed(
              '/report',
              arguments: ReportParams(params.year, month: params.month),
            ),
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
    final lent = sum(
      expenses.where((e) => e.category == prestamoCategory).map((e) => e.value),
    );
    final leftover = totalIncomes - spent - saved - lent;
    final paidBy = [
      for (var i = 0; i < people.length; i++)
        sum(
          expenses
              .where((e) => isSpending(e) && e.paidBy == i)
              .map((e) => e.value),
        ),
    ];

    // Ingresos y gastos de los últimos 6 meses, terminando en este mes.
    final trend =
        [for (var i = 5; i >= 0; i--) DateTime(params.year, params.month - i)]
            .map(
              (d) => TrendMonth(
                monthNames[d.month - 1].substring(0, 3),
                sum(
                  allIncomes
                      .where((x) => x.month == d.month && x.year == d.year)
                      .map((x) => x.amount),
                ),
                sum(
                  allExpenses
                      .where(
                        (e) =>
                            isSpending(e) &&
                            e.month == d.month &&
                            e.year == d.year,
                      )
                      .map((e) => e.value),
                ),
              ),
            )
            .toList();
    // Los meses de antes de empezar a usar la app (sin nada anotado) no se
    // muestran.
    while (trend.isNotEmpty &&
        trend.first.incomes == 0 &&
        trend.first.expenses == 0) {
      trend.removeAt(0);
    }
    final monthName = monthNames[params.month - 1].toLowerCase();

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _Card(
          children: [
            _row(
              'Ingresos',
              totalIncomes,
              color: incomeColor,
              onTap: () => _showIncomes(context, 'Ingresos de $monthName', [
                ...incomes,
              ], people),
            ),
            _row(
              'Gastos',
              -spent,
              color: expenseColor,
              onTap: () => _showExpenses(
                context,
                'Gastos de $monthName',
                expenses.where(isSpending).toList(),
                people,
              ),
            ),
            if (saved != 0)
              _row('Separado para ahorro', -saved, color: savingsColor),
            if (lent != 0)
              _row(
                lent > 0 ? 'Prestado (por cobrar)' : 'Te devolvieron préstamos',
                -lent,
              ),
            const Divider(),
            _row(
              'Sobrante del mes',
              leftover,
              bold: true,
              color: leftover < 0 ? expenseColor : incomeColor,
            ),
            if (leftover < 0)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  'Este mes se gastó más de lo que entró.',
                  style: TextStyle(color: expenseColor),
                ),
              ),
          ],
        ),
        if (trend.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Accordion(
            title: trend.length == 1
                ? 'Ingresos y gastos'
                : 'Últimos ${trend.length} meses',
            summary: trend.length == 1
                ? 'Cuánto entró y cuánto salió este mes'
                : 'Ingresos y gastos de cada mes',
            children: [
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
            ],
          ),
        ],
        const SizedBox(height: 16),
        _Accordion(
          title: 'Ingresos del mes',
          summary:
              '${incomes.length} '
              '${incomes.length == 1 ? 'ingreso' : 'ingresos'}',
          total: Text(
            money(totalIncomes),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: incomeColor,
            ),
          ),
          children: [
            if (incomes.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Aún no hay ingresos este mes.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            for (final income in incomes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.payments, color: incomeColor),
                title: Text(
                  income.description.isEmpty ? 'Ingreso' : income.description,
                ),
                subtitle: Text(
                  people.length > 1
                      ? '${personName(people, income.person)} · '
                            '${_date(income.day)}'
                      : _date(income.day),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      money(income.amount),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirmDialog(
                          context,
                          '¿Borrar este ingreso de ${money(income.amount)}?',
                          confirm: 'Borrar',
                        )) {
                          finance.deleteIncome(income.id);
                        }
                      },
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Agregar ingreso'),
                onPressed: () => _addIncome(context, finance, people),
              ),
            ),
          ],
        ),
        // En cuenta individual repetiría los números de arriba.
        if (people.length > 1) ...[
          _title('Por persona'),
          _Card(
            children: [
              for (var i = 0; i < people.length; i++) ...[
                Text(
                  people[i],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16.0,
                  ),
                ),
                _row(
                  'Aportó (ingresos)',
                  sum(incomes.where((x) => x.person == i).map((x) => x.amount)),
                ),
                _row(
                  spent > 0
                      ? 'Pagó en gastos (${(100 * paidBy[i] / spent).round()}%)'
                      : 'Pagó en gastos',
                  paidBy[i],
                ),
                _row(
                  'Propinas',
                  sum(
                    expenses
                        .where(
                          (e) => e.paidBy == i && e.category == propinaCategory,
                        )
                        .map((e) => e.value),
                  ),
                ),
                if (i < people.length - 1) const Divider(),
              ],
              if (expenses.any((e) => isSpending(e) && e.paidBy == null)) ...[
                const Divider(),
                _row(
                  'Gastos sin asignar',
                  sum(
                    expenses
                        .where((e) => isSpending(e) && e.paidBy == null)
                        .map((e) => e.value),
                  ),
                ),
              ],
            ],
          ),
        ],
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

  Future<void> _addIncome(
    BuildContext context,
    FinanceRepository finance,
    List<String> people,
  ) async {
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
    await finance.addIncome(
      people.indexOf(values[0]),
      values[1],
      parseAmount(values[2])!,
      params.month,
      params.year,
      day: isCurrent ? now.day : 1,
    );
  }

  Widget _title(String text, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
                color: null,
              ),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  /// Fila con un monto. Con [onTap], se puede tocar para ver el detalle.
  Widget _row(
    String label,
    double value, {
    Color? color,
    bool bold = false,
    VoidCallback? onTap,
  }) {
    final style = TextStyle(
      fontSize: bold ? 18.0 : 15.0,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          // Los montos que restan se muestran "− S/. 10.00", no "S/. -10.00".
          Text(value < 0 ? '− ${money(-value)}' : money(value), style: style),
          if (onTap != null) Icon(Icons.chevron_right, size: 20, color: color),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: row,
    );
  }

  /// Hoja con cada movimiento del mes, del más reciente al más antiguo.
  void _showMoves(
    BuildContext context, {
    required String title,
    required double total,
    required Color color,
    required List<Widget> rows,
  }) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${rows.length} '
                          '${rows.length == 1 ? 'movimiento' : 'movimientos'}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    money(total),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No hay movimientos este mes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 24),
                  children: rows,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _date(int day) {
    final date = DateTime(params.year, params.month, day);
    const days = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    return '${days[date.weekday - 1]} $day';
  }

  void _showIncomes(
    BuildContext context,
    String title,
    List<Income> incomes,
    List<String> people,
  ) {
    incomes.sort((a, b) => b.day.compareTo(a.day));
    _showMoves(
      context,
      title: title,
      total: incomes.fold(0.0, (a, i) => a + i.amount),
      color: incomeColor,
      rows: [
        for (final income in incomes)
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0x2216A34A),
              child: Icon(Icons.south_west, color: incomeColor),
            ),
            title: Text(
              income.description,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              people.length > 1
                  ? '${_date(income.day)} · ${personName(people, income.person)}'
                  : _date(income.day),
            ),
            trailing: Text(
              '+ ${money(income.amount)}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: incomeColor,
              ),
            ),
          ),
      ],
    );
  }

  void _showExpenses(
    BuildContext context,
    String title,
    List<Expense> expenses,
    List<String> people,
  ) {
    expenses.sort((a, b) => b.day.compareTo(a.day));
    _showMoves(
      context,
      title: title,
      total: expenses.fold(0.0, (a, e) => a + e.value),
      color: expenseColor,
      rows: [
        for (final e in expenses)
          ListTile(
            leading: CategoryAvatar(e.category, size: 40),
            title: Text(
              e.description.isEmpty ? e.category : e.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              people.length > 1 && e.paidBy != null
                  ? '${_date(e.day)} · ${e.category} · '
                        'pagó ${personName(people, e.paidBy)}'
                  : '${_date(e.day)} · ${e.category}',
            ),
            trailing: Text(
              '− ${money(e.value)}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: expenseColor,
              ),
            ),
          ),
      ],
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
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

/// Tarjeta que se abre y se cierra (acordeón): cerrada muestra solo el
/// título, un resumen y, si hay, el total.
class _Accordion extends StatelessWidget {
  final String title;
  final String summary;
  final Widget? total;
  final List<Widget> children;

  const _Accordion({
    required this.title,
    required this.summary,
    required this.children,
    this.total,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Sin las líneas que ExpansionTile dibuja al abrirse.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              ?total,
            ],
          ),
          subtitle: Text(
            summary,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          children: children,
        ),
      ),
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
