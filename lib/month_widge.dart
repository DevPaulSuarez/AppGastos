import 'package:flutter/material.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/alerts.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:provider/provider.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/graph_widget.dart';
import 'package:primera_app_curso/pages/detail_page_container.dart';
import 'package:primera_app_curso/pages/ui/cash_sheet.dart';
import 'package:primera_app_curso/pages/ui/day_sheet.dart';
import 'package:primera_app_curso/theme.dart';

enum GraphType { LINES, PIE }

class MonthWidget extends StatefulWidget {
  /// Gastos del mes, sin contar lo separado como ahorro.
  final List<Expense> documents;

  /// Todos los movimientos del mes, incluido el ahorro.
  final List<Expense> allDocuments;
  final double total;
  final double saved;

  /// Prestado este mes menos lo que devolvieron.
  final double lent;

  /// Préstamos de cualquier mes que aún no devuelven.
  final List<Expense> pendingLoans;
  final double incomes;
  final List<double> perDay;
  final List<double> savedPerDay;
  final Map<String, double> categories;
  final Map<String, int> counts;
  final Map<String, double> budgets;
  final List<String> people;

  /// Sueldos o gastos de fecha variable que aún no se confirman este mes.
  final List<Recurring> pendingPayments;

  /// Alerta a mostrar arriba (null si no hay o ya se ocultó).
  final SpendingAlert? alert;
  final VoidCallback? onDismissAlert;
  final int month;
  final int year;

  MonthWidget({
    Key? key,
    required this.month,
    required this.year,
    required this.incomes,
    required this.budgets,
    required this.people,
    required this.pendingLoans,
    this.alert,
    this.onDismissAlert,
    this.pendingPayments = const [],
    required List<Expense> documents,
    required int days,
  }) : allDocuments = documents,
       documents = documents
           .where((doc) => isSpendingCategory(doc.category))
           .toList(),
       saved = documents
           .where((doc) => doc.category == ahorroCategory)
           .fold(0.0, (a, doc) => a + doc.value),
       lent = documents
           .where((doc) => doc.category == prestamoCategory)
           .fold(0.0, (a, doc) => a + doc.value),
       total = documents
           .where((doc) => isSpendingCategory(doc.category))
           .fold(0.0, (a, doc) => a + doc.value),
       perDay = List.generate(days, (int index) {
         return documents
             .where(
               (doc) =>
                   isSpendingCategory(doc.category) && doc.day == (index + 1),
             )
             .map((doc) => doc.value)
             .fold(0.0, (a, b) => a + b);
       }),
       savedPerDay = List.generate(days, (int index) {
         return documents
             .where(
               (doc) =>
                   doc.category == ahorroCategory && doc.day == (index + 1),
             )
             .fold(0.0, (a, doc) => a + doc.value);
       }),
       categories = documents
           .where((doc) => isSpendingCategory(doc.category))
           .fold({}, (Map<String, double> map, document) {
             map[document.category] =
                 (map[document.category] ?? 0.0) + document.value;
             return map;
           }),
       counts = documents.where((doc) => isSpendingCategory(doc.category)).fold(
         {},
         (Map<String, int> map, document) {
           map[document.category] = (map[document.category] ?? 0) + 1;
           return map;
         },
       ),
       super(key: key);

  double get leftover => incomes - total - saved - lent;

  @override
  _MonthWidgetState createState() => _MonthWidgetState();
}

class _MonthWidgetState extends State<MonthWidget> {
  GraphType graphType = GraphType.LINES;

  @override
  Widget build(BuildContext context) {
    final sorted = widget.categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final alert = widget.alert;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: <Widget>[
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: alert == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _alertCard(alert),
                ),
        ),
        _resumen(),
        if (widget.pendingPayments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _pendientes(),
        ],
        if (widget.pendingLoans.isNotEmpty) ...[
          const SizedBox(height: 12),
          _porCobrar(),
        ],
        const SizedBox(height: 16),
        if (widget.total > 0 || widget.saved > 0) ...[
          _grafico(),
          const SizedBox(height: 24),
          Text(
            'Categorías',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < sorted.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 72),
                  _item(sorted[i].key, sorted[i].value),
                ],
                if (widget.saved > 0) ...[
                  if (sorted.isNotEmpty) const Divider(height: 1, indent: 72),
                  _item(ahorroCategory, widget.saved),
                ],
              ],
            ),
          ),
        ] else
          _sinGastos(),
      ],
    );
  }

  Widget _sinGastos() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.receipt_long, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            'Sin gastos este mes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Toca + para registrar un gasto',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _grafico() {
    final now = DateTime.now();
    final isCurrentMonth =
        now.month == widget.month + 1 && now.year == widget.year;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    graphType == GraphType.LINES ? 'Por día' : 'Por categoría',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SegmentedButton<GraphType>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: GraphType.LINES,
                      icon: Icon(Icons.bar_chart, size: 20),
                      tooltip: 'Por día',
                    ),
                    ButtonSegment(
                      value: GraphType.PIE,
                      icon: Icon(Icons.donut_large, size: 20),
                      tooltip: 'Por categoría',
                    ),
                  ],
                  selected: {graphType},
                  onSelectionChanged: (value) =>
                      setState(() => graphType = value.first),
                ),
              ],
            ),
            if (widget.saved > 0 && graphType == GraphType.LINES)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    _Legend(color: Color(0xFF059669), label: 'Gasto'),
                    SizedBox(width: 16),
                    _Legend(color: savingsColor, label: 'Ahorro'),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200.0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: graphType == GraphType.LINES
                    ? LinesGraphWidget(
                        key: const ValueKey('dias'),
                        data: widget.perDay,
                        saved: widget.saved > 0 ? widget.savedPerDay : null,
                        highlight: isCurrentMonth ? now.day - 1 : null,
                        onDayTap: (index) => showDayExpenses(
                          context,
                          date: DateTime(
                            widget.year,
                            widget.month + 1,
                            index + 1,
                          ),
                          expenses: widget.allDocuments
                              .where((e) => e.day == index + 1)
                              .toList(),
                          people: widget.people,
                        ),
                      )
                    : PieGraphwidget(
                        key: const ValueKey('categorias'),
                        data: {
                          ...widget.categories,
                          if (widget.saved > 0) ahorroCategory: widget.saved,
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(String nombre, double value) {
    final scheme = Theme.of(context).colorScheme;
    final budget = widget.budgets[nombre];
    final overBudget = budget != null && value > budget;
    final percent = widget.total == 0
        ? 0
        : (100 * value / widget.total).round();
    final count = widget.counts[nombre] ?? 0;

    return ListTile(
      minVerticalPadding: 12,
      onTap: () {
        Navigator.of(context).pushNamed(
          '/details',
          arguments: DetailsParams(nombre, widget.month, widget.year),
        );
      },
      leading: CategoryAvatar(nombre),
      title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: nombre == ahorroCategory
          ? const Text('Aportes a metas y ahorro · no es gasto')
          : nombre == propinaCategory
          ? Text(_propinasPorPersona())
          : budget == null
          ? Text('$percent% · $count ${count == 1 ? 'gasto' : 'gastos'}')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  overBudget
                      ? 'Te pasaste ${money(value - budget)}'
                      : 'Quedan ${money(budget - value)} de ${money(budget)}',
                  style: TextStyle(
                    color: overBudget ? expenseColor : null,
                    fontWeight: overBudget ? FontWeight.w600 : null,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (value / budget).clamp(0.0, 1.0),
                    minHeight: 6,
                    color: overBudget
                        ? expenseColor
                        : (value > budget * 0.8 ? warningColor : incomeColor),
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
      trailing: Text(
        money(value),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }

  /// Cuánto de propina recibió cada persona este mes.
  String _propinasPorPersona() {
    final tips = widget.documents.where((e) => e.category == propinaCategory);
    return [
      for (var i = 0; i < widget.people.length; i++)
        '${widget.people[i]} ${money(tips.where((e) => e.paidBy == i).fold(0.0, (a, e) => a + e.value))}',
    ].join(' · ');
  }

  Widget _alertCard(SpendingAlert alert) {
    final danger = alert.level == AlertLevel.danger;
    final color = danger ? expenseColor : warningColor;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(danger ? Icons.error_outline : Icons.speed, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(alert.message, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          if (widget.onDismissAlert != null)
            IconButton(
              tooltip: 'Ocultar',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 20),
              onPressed: widget.onDismissAlert,
            ),
        ],
      ),
    );
  }

  Widget _pendientes() {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now().day;
    final toPay = widget.pendingPayments
        .where((r) => r.type == RecurringType.expense)
        .fold(0.0, (a, r) => a + r.amount);
    final toReceive = widget.pendingPayments
        .where((r) => r.type == RecurringType.income)
        .fold(0.0, (a, r) => a + r.amount);
    final after = widget.leftover - toPay + toReceive;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pendientes de este mes',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            Text(
              'Si todo se paga y cobra, el sobrante quedaría en ${money(after)}',
              style: TextStyle(
                fontSize: 12,
                color: after < 0 ? expenseColor : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            for (final item in widget.pendingPayments)
              Row(
                children: [
                  Icon(
                    item.type == RecurringType.income
                        ? Icons.south_west
                        : Icons.north_east,
                    size: 18,
                    color: item.type == RecurringType.income
                        ? incomeColor
                        : expenseColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.description,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          today > item.day
                              ? '${money(item.amount)} · era ~día ${item.day}'
                              : '${money(item.amount)} · ~día ${item.day}',
                          style: TextStyle(
                            fontSize: 12,
                            color: today > item.day
                                ? warningColor
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _confirmPayment(item),
                    child: Text(
                      item.type == RecurringType.income ? 'Recibido' : 'Pagado',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Registra un pago de fecha variable con el monto y el día reales.
  Future<void> _confirmPayment(Recurring item) async {
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    final now = DateTime.now();
    final isIncome = item.type == RecurringType.income;
    final values = await showFieldsDialog(
      context,
      title: isIncome ? '¿Cuánto recibieron?' : '¿Cuánto pagaron?',
      confirm: 'Guardar',
      hint: item.description,
      fields: [
        DialogField(
          'Monto',
          initial: item.amount.toStringAsFixed(2),
          number: true,
        ),
        DialogField('Día', initial: '${now.day}', number: true),
      ],
      validate: (values) {
        final day = parseAmount(values[1])!.round();
        if (day < 1 || day > now.day) {
          return 'El día debe estar entre 1 y ${now.day}';
        }
        return null;
      },
    );
    if (values == null) return;
    await finance.confirmRecurring(
      item,
      parseAmount(values[0])!,
      DateTime(widget.year, widget.month + 1, parseAmount(values[1])!.round()),
      widget.month + 1,
      widget.year,
    );
  }

  Widget _porCobrar() {
    final scheme = Theme.of(context).colorScheme;
    final byPerson = <String, double>{};
    for (final loan in widget.pendingLoans) {
      byPerson[loan.owedBy!] = (byPerson[loan.owedBy!] ?? 0) + loan.pending;
    }
    final total = byPerson.values.fold(0.0, (a, b) => a + b);
    return Card(
      child: ListTile(
        onTap: () => Navigator.of(context).pushNamed('/loans'),
        leading: const CategoryAvatar(prestamoCategory, size: 40),
        title: Text(
          'Por cobrar: ${money(total)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          byPerson.entries.map((e) => '${e.key} ${money(e.value)}').join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _resumen() {
    final scheme = Theme.of(context).colorScheme;
    final used = widget.total + widget.saved;
    final ratio = widget.incomes > 0 ? used / widget.incomes : null;

    Widget dato(String label, double value, IconData icon) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: scheme.onPrimary.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                money(value),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Al tocar la tarjeta se ve cuánto dinero deberían tener en total.
    return GestureDetector(
      onTap: () => showCashSheet(
        context,
        month: widget.month + 1,
        year: widget.year,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              scheme.primary,
              Color.lerp(scheme.primary, Colors.black, 0.25)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gastado este mes',
              style: TextStyle(
                color: scheme.onPrimary.withValues(alpha: 0.85),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                money(widget.total),
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (ratio != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 8,
                  color: ratio > 1 ? const Color(0xFFFCA5A5) : scheme.onPrimary,
                  backgroundColor: scheme.onPrimary.withValues(alpha: 0.2),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                ratio > 1
                    ? 'Gastaron más de lo que ingresó'
                    : 'Usaron el ${(ratio * 100).round()}% de los ingresos',
                style: TextStyle(
                  color: scheme.onPrimary.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                dato('Ingresos', widget.incomes, Icons.south_west),
                dato('Ahorrado', widget.saved, Icons.savings_outlined),
                dato(
                  'Sobrante',
                  widget.leftover,
                  widget.leftover < 0
                      ? Icons.warning_amber
                      : Icons.account_balance_wallet_outlined,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.account_balance,
                  size: 14,
                  color: scheme.onPrimary.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '¿Cuánto dinero deberían tener? Toca aquí',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onPrimary.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onPrimary.withValues(alpha: 0.8),
                ),
              ],
            ),
          ],
        ),
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
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
