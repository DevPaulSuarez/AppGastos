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

  /// Dinero libre que traían al empezar el mes (de meses anteriores o del
  /// punto de partida), sin contar lo apartado como ahorro.
  final double carriedOver;

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
    this.carriedOver = 0,
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

  /// Lo que tienen libre hoy: lo que traían más el resultado del mes.
  double get available => carriedOver + leftover;

  double get toReceive =>
      upcoming.where((u) => u.isIncome).fold(0.0, (a, u) => a + u.amount);

  double get toPay =>
      upcoming.where((u) => !u.isIncome).fold(0.0, (a, u) => a + u.amount);

  /// Con cuánto libre cerrarían el mes si todo lo que falta se cobra y se
  /// paga.
  double get projected => available + toReceive - toPay;

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
        if (widget.incomeItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ingresos(),
        ],
        if (widget.upcoming.isNotEmpty) ...[
          const SizedBox(height: 12),
          _porVenir(),
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
                      const _Legend(color: savingsColor, label: 'Ahorro'),
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
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = isIncome ? incomeColor : expenseColor;
    return Padding(
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
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: incomeColor,
        ),
      ),
      children: [
        for (final income in items)
          _moveRow(
            isIncome: true,
            name: _withPerson(income.description, income.person),
            date: _dayLabel(DateTime(income.year, income.month, income.day)),
            amount: income.amount,
          ),
      ],
    );
  }

  /// Lo que todavía falta este mes, por fecha. Los fijos se registran solos
  /// el día que tocan; los de fecha variable se confirman aquí.
  Widget _porVenir() {
    final today = DateTime.now().day;
    final pending = [
      if (widget.toReceive > 0) 'por cobrar ${money(widget.toReceive)}',
      if (widget.toPay > 0) 'por pagar ${money(widget.toPay)}',
    ].join(' · ');
    return _accordion(
      title: 'Lo que falta este mes',
      summary: pending[0].toUpperCase() + pending.substring(1),
      total: const SizedBox.shrink(),
      children: [
        for (final u in widget.upcoming)
          _moveRow(
            isIncome: u.isIncome,
            name: _withPerson(u.item.description, u.item.person),
            date: !u.needsConfirm
                ? _dayLabel(u.date)
                : u.isIncome
                ? 'Cerca del día ${u.date.day} · ¿ya llegó?'
                : 'Cerca del día ${u.date.day} · ¿ya se pagó?',
            dateColor: u.needsConfirm && today > u.date.day
                ? warningColor
                : null,
            amount: u.amount,
            action: u.needsConfirm
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
          ),
      ],
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
    final white = scheme.onPrimary;
    final soft = white.withValues(alpha: 0.85);
    final current = _isCurrentMonth;
    final main = current ? widget.available : widget.leftover;
    final monthName = monthNames[widget.month].toLowerCase();

    final String title;
    if (current) {
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
            Text(title, style: TextStyle(color: soft, fontSize: 15)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                money(main.abs()),
                style: TextStyle(
                  color: main < 0 ? const Color(0xFFFCA5A5) : white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (current && main < 0)
              Text(
                _solo
                    ? 'Gastaste más de lo que tenías'
                    : 'Gastaron más de lo que tenían',
                style: const TextStyle(color: Color(0xFFFCA5A5)),
              ),
            if (current && widget.upcoming.isNotEmpty) ...[
              const SizedBox(height: 4),
              _cierre(scheme),
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
  Widget _cierre(ColorScheme scheme) {
    final white = scheme.onPrimary;
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
              color: projected < 0 ? const Color(0xFFFCA5A5) : white,
            ),
          ),
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
