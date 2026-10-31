import 'dart:math';

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
import 'package:primera_app_curso/petty_cash.dart';
import 'package:primera_app_curso/tithe.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/pages/church_page.dart';

enum GraphType { LINES, PIE }

const _weekdayShort = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

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

  /// Cada ingreso del mes (sueldos ya cobrados y los anotados a mano).
  final List<Income> incomeItems;
  final List<double> perDay;

  /// Gasto de cada día separado por categoría (para pintar las barras).
  final List<Map<String, double>> perDayByCategory;
  final List<double> savedPerDay;
  final Map<String, double> categories;
  final Map<String, int> counts;
  final Map<String, double> budgets;
  final List<String> people;

  /// Lo que todavía falta este mes (solo en el mes en curso).
  final List<Upcoming> upcoming;

  /// Pagos fijos del mes en curso, con su "Ya pagué".
  final List<FixedPayment> fixedPayments;

  /// Diezmo del mes en curso, si lo apartan (null si no).
  final Tithes? tithe;

  /// Dinero libre que traían al empezar el mes (de meses anteriores o del
  /// punto de partida), sin contar lo apartado como ahorro.
  final double carriedOver;

  /// Caja chica del mes, si la usan (null si no). Con caja chica el mes
  /// empieza de cero: lo de antes está en la caja y no en [carriedOver].
  final PettyCashMonth? pettyCash;

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
    this.incomeItems = const [],
    required this.budgets,
    required this.people,
    required this.pendingLoans,
    this.alert,
    this.onDismissAlert,
    this.upcoming = const [],
    this.fixedPayments = const [],
    this.tithe,
    this.carriedOver = 0,
    this.pettyCash,
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
       perDayByCategory = List.generate(days, (int index) {
         final day = <String, double>{};
         for (final doc in documents) {
           if (isSpendingCategory(doc.category) && doc.day == index + 1) {
             day[doc.category] = (day[doc.category] ?? 0) + doc.value;
           }
         }
         return day;
       }),
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

  /// Resultado del mes: lo que entró menos lo gastado, ahorrado y prestado.
  double get leftover => incomes - total - saved - lent;

  /// Lo que tienen libre hoy: lo que traían más el resultado del mes. Con
  /// caja chica, el resultado del mes más lo que sacaron de la caja.
  double get available => pettyCash == null
      ? carriedOver + leftover
      : leftover + pettyCash!.taken - pettyCash!.returned;

  /// Lo que falta devolver a la caja chica este mes.
  double get owed => pettyCash?.owed ?? 0;

  double get toReceive =>
      upcoming.where((u) => u.isIncome).fold(0.0, (a, u) => a + u.amount);

  /// Lo que falta pagar este mes, con el diezmo por dar.
  double get toPay =>
      upcoming.where((u) => !u.isIncome).fold(0.0, (a, u) => a + u.amount) +
      (tithe?.pending ?? 0);

  /// Lo que se puede gastar sin tocar la plata separada para lo que falta
  /// pagar este mes (ej. el alquiler, el diezmo).
  double get freeToSpend => available - toPay - owed;

  /// Con cuánto libre cerrarían el mes si todo lo que falta se cobra y se
  /// paga.
  double get projected => available + toReceive - toPay - owed;

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
        if (widget.pettyCash != null && !widget.pettyCash!.isEmpty) ...[
          const SizedBox(height: 12),
          _cajaChica(widget.pettyCash!),
        ],
        if (widget.incomeItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ingresos(),
        ],
        if (widget.upcoming.any((u) => !_isFixedPayment(u))) ...[
          const SizedBox(height: 12),
          _porVenir(),
        ],
        if (widget.pendingLoans.isNotEmpty) ...[
          const SizedBox(height: 12),
          _porCobrar(),
        ],
        if (widget.fixedPayments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _pagosFijos(),
        ],
        if (widget.tithe != null) ...[
          const SizedBox(height: 12),
          _diezmo(widget.tithe!),
        ],
        const SizedBox(height: 16),
        if (widget.total > 0 || widget.saved > 0) ...[
          _grafico(),
          const SizedBox(height: 24),
          Text(
            '¿En qué se fue el dinero?',
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
            if (graphType == GraphType.LINES)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Cada color es una categoría (mira la lista de abajo)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (widget.saved > 0)
                      _Legend(color: context.money.savings, label: 'Ahorro'),
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
                        byCategory: widget.perDayByCategory,
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
                    color: overBudget ? context.money.expense : null,
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
                        ? context.money.expense
                        : (value > budget * 0.8
                              ? context.money.warning
                              : context.money.income),
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
    final color = danger ? context.money.expense : context.money.warning;
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

  /// Tarjeta que se abre y se cierra (acordeón). Cerrada muestra solo el
  /// título, un resumen y el total.
  Widget _accordion({
    required String title,
    required String summary,
    required Widget total,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Sin las líneas que ExpansionTile dibuja al abrirse.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              total,
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

  /// Una fila de ingreso o gasto: flecha, nombre, fecha y monto.
  Widget _moveRow({
    required bool isIncome,
    required String name,
    required String date,
    required double amount,
    Color? dateColor,
    Widget? action,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = isIncome ? context.money.income : context.money.expense;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isIncome ? Icons.south_west : Icons.north_east,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 12,
                    color: dateColor ?? scheme.onSurfaceVariant,
                  ),
                ),
                if (action != null) action,
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isIncome ? '+' : '−'} ${money(amount)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }

  String _withPerson(String name, int person) => widget.people.length > 1
      ? '$name · ${personName(widget.people, person)}'
      : name;

  String _dayLabel(DateTime date) =>
      '${_weekdayShort[date.weekday - 1]} ${date.day}';

  /// Lo que entró en el mes, por fecha: cada sueldo cobrado y cada ingreso
  /// anotado a mano.
  Widget _ingresos() {
    final items = [...widget.incomeItems]
      ..sort((a, b) => a.day.compareTo(b.day));
    return _accordion(
      title: _isCurrentMonth
          ? 'Lo que entró este mes'
          : 'Lo que entró en ${monthNames[widget.month].toLowerCase()}',
      summary: '${items.length} ${items.length == 1 ? 'ingreso' : 'ingresos'}',
      total: Text(
        money(widget.incomes),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: context.money.income,
        ),
      ),
      children: [
        for (final income in items)
          _moveRow(
            isIncome: true,
            name: _withPerson(income.description, income.person),
            date: [
              _dayLabel(DateTime(income.year, income.month, income.day)),
              if (income.expected != null)
                'llegó incompleto (era ${money(income.expected!)})',
            ].join(' · '),
            dateColor: income.expected == null ? null : context.money.warning,
            amount: income.amount,
            onTap: income.isSalary ? () => _editSalary(income) : null,
          ),
        if (items.any((i) => i.isSalary))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '¿Un sueldo llegó menos? Tócalo para cambiar el monto.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  /// Un sueldo no siempre llega completo (ej. faltó un día): se anota lo que
  /// llegó de verdad.
  Future<void> _editSalary(Income income) async {
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    final full = income.expected ?? income.amount;
    final date = _dayLabel(DateTime(income.year, income.month, income.day));
    final values = await showFieldsDialog(
      context,
      title: '${income.description} del $date',
      hint:
          'Completo es ${money(full)}. Si faltó algún día y llegó menos, '
          'escribe lo que llegó de verdad.',
      fields: [
        DialogField(
          '¿Cuánto llegó?',
          initial: _plain(income.amount),
          number: true,
        ),
      ],
      validate: (v) =>
          (parseAmount(v[0]) ?? 0) <= 0 ? 'Escribe un monto mayor que 0' : null,
    );
    if (values == null) return;
    await finance.setIncomeAmount(income, parseAmount(values[0])!);
  }

  /// Monto para un campo de texto: sin ".0" si es entero.
  String _plain(double amount) => amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);

  /// Lo que todavía falta este mes, por fecha. Los sueldos se registran
  /// solos el día que tocan; los pagos fijos, cuando llega su día, piden el
  /// "Ya pagué" (se revisa en el banco), y los de fecha variable también.
  Widget _porVenir() {
    final today = DateTime.now().day;
    // Sin los pagos fijos, que se ven en su tarjeta.
    final toPay = widget.upcoming
        .where((u) => !u.isIncome && !_isFixedPayment(u))
        .fold(0.0, (a, u) => a + u.amount);
    final pending = [
      if (widget.toReceive > 0) 'por cobrar ${money(widget.toReceive)}',
      if (toPay > 0) 'por pagar ${money(toPay)}',
    ].join(' · ');
    return _accordion(
      title: 'Lo que falta este mes',
      summary: pending[0].toUpperCase() + pending.substring(1),
      total: const SizedBox.shrink(),
      children: [
        // Los pagos fijos tienen su propia tarjeta, encima del gráfico.
        for (final u in widget.upcoming)
          if (!_isFixedPayment(u)) _upcomingRow(u, today),
      ],
    );
  }

  bool _isFixedPayment(Upcoming u) => !u.isIncome && u.needsConfirm;

  /// Los pagos fijos del mes, cada uno con su estado: pagado, "Ya pagué"
  /// (desde su día) o la fecha en que toca.
  Widget _pagosFijos() {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final payments = widget.fixedPayments;
    final paidCount = payments.where((p) => p.paid != null).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pagos fijos',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                Text(
                  '$paidCount de ${payments.length} pagados',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final p in payments) _fixedPaymentRow(p, now),
          ],
        ),
      ),
    );
  }

  /// Un pago fijo con el ícono de su categoría. El monto se ve al pagarlo
  /// (antes de confirmar, y después en la fila).
  Widget _fixedPaymentRow(FixedPayment p, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final item = p.item;
    final paid = p.paid;
    final due = DateTime(
      now.year,
      now.month,
      min(item.day, daysInMonth(now.month, now.year)),
    );
    final today = DateTime(now.year, now.month, now.day);
    final askPaid = paid == null && !due.isAfter(today);
    final status = paid != null
        ? '✓ Pagado el ${_dayLabel(DateTime(paid.year, paid.month, paid.day))}'
        : due == today
        ? 'Toca hoy'
        : due.isBefore(today)
        ? 'Tocaba el ${_dayLabel(due)}'
        : 'Toca el ${_dayLabel(due)}';
    final statusColor = paid != null
        ? context.money.income
        : due.isBefore(today)
        ? context.money.warning
        : scheme.onSurfaceVariant;

    return InkWell(
      onTap: paid != null ? () => _unpay(item) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CategoryAvatar(item.category, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _withPerson(item.description, item.person),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${item.category} · $status',
                    style: TextStyle(fontSize: 12, color: statusColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (paid != null)
              Text(
                '− ${money(paid.value)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: context.money.expense,
                ),
              )
            else if (askPaid)
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _confirmPayment(item),
                child: const Text('Ya pagué'),
              ),
          ],
        ),
      ),
    );
  }

  /// El diezmo del mes, de cada persona por separado: el 10% de su sueldo
  /// que ya llegó (o el monto que puso), lo dado y lo que falta. Lo que falta
  /// queda separado de "Libre para gastar" hasta fin de mes, cuando se da.
  Widget _diezmo(Tithes tithes) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final couple = widget.people.length > 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CategoryAvatar(iglesiaCategory, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Diezmo',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      if (tithes.pending > 0)
                        Text(
                          '${money(tithes.pending)} apartados para darlos a '
                          'fin de mes (${_dayLabel(DateTime(widget.year, widget.month + 2, 0))})',
                          style: muted,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            for (final t in tithes.people) _diezmoPersona(t, couple, muted),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Ver informe de la iglesia'),
                onPressed: () => openChurchReport(context, widget.year),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// El diezmo de una persona: cuánto le toca, con "Cambiar" y "Ya lo di".
  Widget _diezmoPersona(Tithe t, bool couple, TextStyle muted) {
    final done = t.owed > 0 && t.pending < 0.005;
    final name = couple ? personName(widget.people, t.person) : null;
    final String detail;
    if (t.changed) {
      detail = 'Monto que pusiste este mes';
    } else if (t.income <= 0) {
      detail = couple
          ? 'Aún no llega su sueldo este mes'
          : 'Aún no llega el sueldo este mes';
    } else {
      detail = '$tithePercent% del sueldo que llegó (${money(t.income)})';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _changeTithe(t),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${name == null ? '' : '$name: '}${money(t.owed)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit_outlined, size: 16, color: muted.color),
                    ],
                  ),
                  Text(
                    t.given > 0 && !done
                        ? '$detail · ya dio ${money(t.given)}'
                        : detail,
                    style: muted,
                  ),
                ],
              ),
            ),
          ),
          if (done)
            Text(
              '✓ Dado',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: context.money.income,
              ),
            )
          else if (t.pending > 0)
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 36),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _giveTithe(t),
              child: const Text('Ya lo di'),
            ),
        ],
      ),
    );
  }

  /// Cambia cuánto dará una persona este mes. Si escriben el 10% del sueldo
  /// vuelve a calcularse solo.
  Future<void> _changeTithe(Tithe t) async {
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    final percent = Tithe(income: t.income, given: 0).owed;
    final couple = widget.people.length > 1;
    final values = await showFieldsDialog(
      context,
      title: couple
          ? 'Diezmo de ${personName(widget.people, t.person)}'
          : 'Diezmo de este mes',
      hint: t.income > 0
          ? 'El $tithePercent% del sueldo que llegó es ${money(percent)}.'
          : null,
      fields: [
        DialogField(
          '¿Cuánto vas a dar este mes?',
          initial: _plain(t.owed),
          number: true,
        ),
      ],
      validate: (v) =>
          (parseAmount(v[0]) ?? -1) < 0 ? 'Escribe un monto' : null,
    );
    if (values == null) return;
    final amount = parseAmount(values[0])!;
    await finance.setTitheAmount(
      t.person,
      widget.month + 1,
      widget.year,
      t.income > 0 && (amount - percent).abs() < 0.005 ? null : amount,
    );
  }

  /// Anota el diezmo que dio hoy una persona en la categoría de la iglesia.
  Future<void> _giveTithe(Tithe t) async {
    final db = Provider.of<ExpensesRepository>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final couple = widget.people.length > 1;
    final values = await showFieldsDialog(
      context,
      title: couple
          ? '¿${personName(widget.people, t.person)} ya dio el diezmo?'
          : '¿Ya diste el diezmo?',
      confirm: 'Sí, ya lo di',
      hint: 'Falta dar ${money(t.pending)}. Si diste otro monto, cámbialo.',
      fields: [
        DialogField('¿Cuánto diste?', initial: _plain(t.pending), number: true),
      ],
      validate: (v) =>
          (parseAmount(v[0]) ?? 0) <= 0 ? 'Escribe un monto mayor que 0' : null,
    );
    if (values == null) return;
    final amount = parseAmount(values[0])!;
    await db.add(
      iglesiaCategory,
      amount,
      DateTime.now(),
      titheNote,
      paidBy: t.person,
    );
    messenger.showSnackBar(
      SnackBar(content: Text('Diezmo anotado: ${money(amount)}')),
    );
  }

  /// Lo marcaron como pagado por error: vuelve a quedar pendiente.
  Future<void> _unpay(Recurring item) async {
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    if (await confirmDialog(
      context,
      '¿Todavía no pagaste "${item.description}" este mes?',
      confirm: 'No lo pagué',
    )) {
      await finance.unconfirmRecurring(item);
    }
  }

  Widget _upcomingRow(Upcoming u, int today) {
    // Un pago fijo pide el botón recién desde su día; antes solo se ve la
    // fecha, como un gasto que viene.
    final askPaid = u.needsConfirm && (u.isIncome || today >= u.date.day);
    return _moveRow(
      isIncome: u.isIncome,
      name: _withPerson(u.item.description, u.item.person),
      date: !askPaid
          ? _dayLabel(u.date)
          : u.isIncome
          ? 'Cerca del día ${u.date.day} · ¿ya llegó?'
          : today == u.date.day
          ? 'Toca hoy · ¿ya se pagó?'
          : 'Tocaba el ${_dayLabel(u.date)} · ¿ya se pagó?',
      dateColor: askPaid && today > u.date.day ? context.money.warning : null,
      amount: u.amount,
      action: askPaid
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _confirmPayment(u.item),
                child: Text(u.isIncome ? 'Ya llegó' : 'Ya pagué'),
              ),
            )
          : null,
    );
  }

  /// Registra un pago de fecha variable con el monto y el día reales. Un
  /// pago fijo se anota de un toque, con la fecha de hoy.
  Future<void> _confirmPayment(Recurring item) async {
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    final now = DateTime.now();
    final isIncome = item.type == RecurringType.income;
    if (!isIncome) {
      final messenger = ScaffoldMessenger.of(context);
      // El monto puede cambiar cada mes (ej. el alquiler): se escribe lo que
      // se pagó de verdad.
      final values = await showFieldsDialog(
        context,
        title: '¿Ya pagaste ${item.description}?',
        confirm: 'Sí, ya pagué',
        hint: 'Si este mes fue otro monto, cámbialo.',
        fields: [
          DialogField(
            '¿Cuánto pagaste?',
            initial: _plain(item.amount),
            number: true,
          ),
        ],
        validate: (v) => (parseAmount(v[0]) ?? 0) <= 0
            ? 'Escribe un monto mayor que 0'
            : null,
      );
      if (values == null) return;
      final amount = parseAmount(values[0])!;
      await finance.confirmRecurring(item, amount, now, now.month, now.year);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${item.description}: pagado hoy, ${money(amount)}'),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () => finance.unconfirmRecurring(item),
          ),
        ),
      );
      return;
    }
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
        DialogField.day(
          isIncome ? 'Día en que se cobró' : 'Día en que se pagó',
          initial: '${now.day}',
          month: DateTime(widget.year, widget.month + 1),
          maxDay: now.day,
        ),
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

  /// La caja chica: lo que sobró de los meses anteriores. En el mes en curso
  /// se puede sacar como préstamo y devolver; en los pasados se ve cómo
  /// quedó.
  Widget _cajaChica(PettyCashMonth box) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final current = _isCurrentMonth;
    final String detail;
    if (!current) {
      detail = box.result >= 0
          ? 'Entraron ${money(box.result)} que sobraron este mes'
          : 'Salieron ${money(-box.result)} que faltaron este mes';
    } else if (box.owed > 0) {
      detail =
          'Sacaron ${money(box.taken)} · falta devolver ${money(box.owed)}';
    } else if (box.taken > 0) {
      detail = 'Sacaron ${money(box.taken)} y ya lo devolvieron ✓';
    } else {
      detail = 'Lo que sobró de los meses anteriores';
    }
    final amount = current ? box.inBox : box.end;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pettyCashSheet(box),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: scheme.secondaryContainer,
                    child: Icon(
                      Icons.inventory_2_outlined,
                      color: scheme.onSecondaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current ? 'Caja chica' : 'Caja chica al terminar',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          detail,
                          style: box.owed > 0 && current
                              ? muted.copyWith(color: context.money.warning)
                              : muted,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    amount < 0 ? '−${money(-amount)}' : money(amount),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: amount < 0 ? context.money.expense : null,
                    ),
                  ),
                ],
              ),
              if (current)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _takeFromBox(box),
                      child: const Text('Sacar'),
                    ),
                    if (box.owed > 0) ...[
                      const SizedBox(width: 4),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _returnToBox(box),
                        child: const Text('Ya devolví'),
                      ),
                    ],
                  ],
                )
              else
                const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  /// Anota que hoy sacaron dinero de la caja chica para el mes.
  Future<void> _takeFromBox(PettyCashMonth box) async {
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final values = await showFieldsDialog(
      context,
      title: 'Sacar de la caja chica',
      confirm: 'Sacar',
      hint:
          'Hay ${money(box.inBox)} en la caja. Es un préstamo: '
          '${_solo ? 'lo devuelves' : 'lo devuelven'} en este mes, cuando '
          'llegue el sueldo.',
      fields: [
        DialogField(
          _solo ? '¿Cuánto sacaste?' : '¿Cuánto sacaron?',
          number: true,
        ),
      ],
      validate: (v) =>
          (parseAmount(v[0]) ?? 0) <= 0 ? 'Escribe un monto mayor que 0' : null,
    );
    if (values == null) return;
    final amount = parseAmount(values[0])!;
    final now = DateTime.now();
    await finance.addPettyCashMove(
      PettyCashMove(
        amount: amount,
        taken: true,
        year: now.year,
        month: now.month,
        day: now.day,
      ),
    );
    messenger.showSnackBar(
      SnackBar(content: Text('Sacaron ${money(amount)} de la caja chica')),
    );
  }

  /// Anota que hoy devolvieron (todo o una parte) a la caja chica.
  Future<void> _returnToBox(PettyCashMonth box) async {
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final values = await showFieldsDialog(
      context,
      title: _solo ? '¿Ya devolviste a la caja?' : '¿Ya devolvieron a la caja?',
      confirm: 'Sí, ya devolví',
      hint:
          'Falta devolver ${money(box.owed)}. Si devolvieron solo una parte, '
          'cambia el monto.',
      fields: [
        DialogField(
          _solo ? '¿Cuánto devolviste?' : '¿Cuánto devolvieron?',
          initial: _plain(box.owed),
          number: true,
        ),
      ],
      validate: (v) =>
          (parseAmount(v[0]) ?? 0) <= 0 ? 'Escribe un monto mayor que 0' : null,
    );
    if (values == null) return;
    final amount = parseAmount(values[0])!;
    final now = DateTime.now();
    await finance.addPettyCashMove(
      PettyCashMove(
        amount: amount,
        taken: false,
        year: now.year,
        month: now.month,
        day: now.day,
      ),
    );
    messenger.showSnackBar(
      SnackBar(content: Text('Devolvieron ${money(amount)} a la caja chica')),
    );
  }

  /// Detalle de la caja chica en el mes: con cuánto empezó, lo que sacaron
  /// y devolvieron (se puede borrar si fue un error) y "Corregir monto".
  Future<void> _pettyCashSheet(PettyCashMonth box) {
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    final current = _isCurrentMonth;
    final monthName = monthNames[widget.month].toLowerCase();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        Widget row(
          String text,
          double value, {
          Color? color,
          bool bold = false,
        }) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: bold ? FontWeight.w700 : null,
                  ),
                ),
              ),
              Text(
                value < 0 ? '−${money(-value)}' : money(value),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Caja chica de $monthName',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lo que sobra cada mes entra a la caja al terminar el mes. '
                  'Lo que sacan es un préstamo que se devuelve en el mismo mes.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                row('Al empezar el mes', box.start),
                if (box.taken > 0)
                  row(
                    '− Sacaron',
                    box.taken,
                    color: sheetContext.money.expense,
                  ),
                if (box.returned > 0)
                  row(
                    '+ Devolvieron',
                    box.returned,
                    color: sheetContext.money.income,
                  ),
                if (current) ...[
                  const Divider(),
                  row('= Hoy en la caja', box.inBox, bold: true),
                  if (box.owed > 0)
                    row(
                      'Falta devolver',
                      box.owed,
                      color: sheetContext.money.warning,
                    ),
                ] else ...[
                  row(
                    box.inHand >= 0
                        ? '+ Sobrante del mes'
                        : '− Faltante del mes',
                    box.inHand.abs(),
                    color: box.inHand >= 0
                        ? sheetContext.money.income
                        : sheetContext.money.expense,
                  ),
                  const Divider(),
                  row('= Al terminar el mes', box.end, bold: true),
                ],
                if (box.moves.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Movimientos',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  for (final m in box.moves)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        m.taken ? Icons.north_east : Icons.south_west,
                        color: m.taken
                            ? sheetContext.money.expense
                            : sheetContext.money.income,
                      ),
                      title: Text(m.taken ? 'Sacaron' : 'Devolvieron'),
                      subtitle: Text(
                        _dayLabel(DateTime(m.year, m.month, m.day)),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            money(m.amount),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          IconButton(
                            tooltip: 'Borrar',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (await confirmDialog(
                                sheetContext,
                                '¿Borrar este movimiento de la caja chica?',
                                confirm: 'Borrar',
                              )) {
                                await finance.deletePettyCashMove(m.id);
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
                if (current) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Corregir lo que hay en la caja'),
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _fixBoxAmount(box);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Escriben cuánto hay de verdad hoy en la caja chica y la app se ajusta.
  Future<void> _fixBoxAmount(PettyCashMonth box) async {
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    final values = await showFieldsDialog(
      context,
      title: '¿Cuánto hay hoy en la caja chica?',
      hint:
          'Cuenten lo que hay ahora (sin lo que sacaron este mes). '
          'La app dice ${money(box.inBox)}.',
      fields: [DialogField('Monto', initial: _plain(box.inBox), number: true)],
      validate: (v) => parseAmount(v[0]) == null ? 'Escribe un monto' : null,
    );
    if (values == null) return;
    await finance.setPettyCashAmount(parseAmount(values[0])!, box.inBox);
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

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return now.month == widget.month + 1 && now.year == widget.year;
  }

  bool get _solo => widget.people.length < 2;

  /// Tarjeta verde: responde primero "¿cuánto tengo?" y "¿cuánto me va a
  /// quedar?"; el detalle del mes va abajo, en chico.
  Widget _resumen() {
    final scheme = Theme.of(context).colorScheme;
    // En el tema oscuro, la tarjeta lleva su propio verde (más vivo que el
    // del tema) con letras blancas.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final white = dark ? _darkCardText : scheme.onPrimary;
    final soft = white.withValues(alpha: 0.85);
    final current = _isCurrentMonth;
    // En el mes en curso, lo libre: lo que tienen sin lo separado para
    // los pagos que faltan.
    final reserved = current ? widget.toPay + widget.owed : 0.0;
    final main = current ? widget.freeToSpend : widget.leftover;
    final reservedFor = widget.owed <= 0
        ? 'para los pagos del mes'
        : widget.toPay <= 0
        ? 'para devolver a la caja chica'
        : 'para los pagos del mes y la caja chica';
    // En números rojos, el número y el aviso van en rojo (en el tema
    // oscuro, el mismo rojo de los gastos).
    final red = dark ? context.money.expense : const Color(0xFFFCA5A5);
    final monthName = monthNames[widget.month].toLowerCase();

    final String title;
    if (current && reserved > 0) {
      title = 'Libre para gastar';
    } else if (current) {
      title = _solo ? 'Tienes disponible' : 'Tienen disponible';
    } else if (widget.leftover >= 0) {
      title = _solo ? 'En $monthName te sobró' : 'En $monthName les sobró';
    } else {
      title = _solo ? 'En $monthName te faltó' : 'En $monthName les faltó';
    }

    Widget stat(IconData icon, String label, double value) => Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 13, color: soft),
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(icon, size: 14, color: soft),
          ),
          TextSpan(text: ' $label '),
          TextSpan(
            text: money(value),
            style: TextStyle(fontWeight: FontWeight.w700, color: white),
          ),
        ],
      ),
    );

    // Al tocar la tarjeta se ve el detalle y se compara con el banco.
    return GestureDetector(
      onTap: () =>
          showCashSheet(context, month: widget.month + 1, year: widget.year),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: dark
                ? const [Color(0xFF2F6B44), Color(0xFF1F3725)]
                : [
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
            Text(title, style: TextStyle(color: soft, fontSize: 15)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                // Con el signo: "−S/. 349" es que falta, no que queda.
                main < 0 ? '−${money(-main)}' : money(main),
                style: TextStyle(
                  color: main < 0 ? red : white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (current && reserved > 0)
              Text(
                'De ${money(widget.available)} que ${_solo ? 'tienes' : 'tienen'}, '
                '${money(reserved)} están separados $reservedFor',
                style: TextStyle(color: soft, fontSize: 13),
              ),
            if (!current && widget.pettyCash != null)
              Text(
                widget.leftover >= 0
                    ? 'Pasó a la caja chica'
                    : 'Se cubrió con la caja chica',
                style: TextStyle(color: soft, fontSize: 13),
              ),
            if (current && main < 0)
              Text(
                widget.available >= 0
                    ? '${_solo ? 'Te' : 'Les'} faltan ${money(-main)} '
                          '$reservedFor'
                    : _solo
                    ? 'Gastaste más de lo que tenías'
                    : 'Gastaron más de lo que tenían',
                style: TextStyle(color: red, fontWeight: FontWeight.w600),
              ),
            // Sin sueldos por cobrar, a fin de mes queda lo mismo que lo
            // libre: no se repite el número.
            if (current && widget.toReceive > 0) ...[
              const SizedBox(height: 4),
              _cierre(scheme, red),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                stat(Icons.south_west, 'Entró', widget.incomes),
                stat(
                  Icons.north_east,
                  _solo ? 'Gastaste' : 'Gastaron',
                  widget.total,
                ),
                if (widget.saved > 0)
                  stat(
                    Icons.savings_outlined,
                    _solo ? 'Ahorraste' : 'Ahorraron',
                    widget.saved,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ver detalle',
                    style: TextStyle(fontSize: 13, color: soft),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: soft),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Dentro de la tarjeta verde, en una línea: con cuánto cerrarían el mes
  /// si se cobra y se paga todo lo que falta.
  Widget _cierre(ColorScheme scheme, Color red) {
    final white = Theme.of(context).brightness == Brightness.dark
        ? _darkCardText
        : scheme.onPrimary;
    final projected = widget.projected;
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 15, color: white.withValues(alpha: 0.9)),
        children: [
          TextSpan(
            text: _solo
                ? 'A fin de mes te quedará '
                : 'A fin de mes les quedará ',
          ),
          TextSpan(
            text: money(projected),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: projected < 0 ? red : white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Letras de la tarjeta verde en el tema oscuro.
const _darkCardText = Colors.white;

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
