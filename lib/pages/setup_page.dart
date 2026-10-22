import 'package:flutter/material.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/pages/ui/income_dialog.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
import 'package:primera_app_curso/theme.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';

/// Configuración inicial, justo después de elegir el tipo de cuenta: los
/// nombres, la moneda, los ingresos de cada persona y los gastos fijos, cada
/// uno con sus fechas. Al final muestra cuánto queda libre al mes.
/// Todo se puede saltar y completar después en Ajustes.
class SetupPage extends StatefulWidget {
  const SetupPage({Key? key}) : super(key: key);

  @override
  State<SetupPage> createState() => _SetupPageState();
}

/// Gastos fijos que casi todos tienen, para agregarlos con un toque.
const _suggestions = [
  ('Alquiler', 'Vivienda', Icons.home_rounded),
  ('Celular', 'Servicios', Icons.phone_iphone),
  ('Seguro de carro', 'Transporte', Icons.directions_car_outlined),
  ('Luz', 'Servicios', Icons.bolt),
  ('Agua', 'Servicios', Icons.water_drop_outlined),
  ('Internet', 'Servicios', Icons.wifi),
  ('Seguro de salud', 'Salud', Icons.health_and_safety_outlined),
  ('Streaming', 'Suscripciones', Icons.subscriptions_outlined),
  ('Colegio', 'Educación', Icons.school_outlined),
];

class _SetupPageState extends State<SetupPage> {
  static const _steps = 5;
  int _step = 0;

  /// Nombres escritos en el primer paso; se guardan al pasar al siguiente.
  List<TextEditingController>? _names;

  /// Dinero que tienen hoy (último paso).
  final _money = TextEditingController();

  @override
  void dispose() {
    for (final controller in _names ?? const <TextEditingController>[]) {
      controller.dispose();
    }
    _money.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final finance = Provider.of<FinanceRepository>(context);

    return Scaffold(
      body: SafeArea(
        child: MultiStreamBuilder(
          streams: [
            finance.watchPeople(),
            finance.watchRecurring(),
            finance.watchCurrencySettings(),
          ],
          builder: (context, values) {
            final people = values[0] as List<String>;
            final recurring = values[1] as List<Recurring>;
            // Los montos se guardan y muestran en la moneda elegida.
            currencySettings = values[2] as CurrencySettings;
            final solo = people.length == 1;
            // Los nombres por defecto ("Yo", "Persona 2") quedan como pista,
            // no como texto que haya que borrar.
            _names ??= [
              for (final name in people)
                TextEditingController(
                  text: FinanceRepository.isDefaultName(name) ? '' : name,
                ),
            ];

            return Column(
              children: [
                _header(context, solo),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: switch (_step) {
                      0 => _namesStep(solo),
                      1 => _currencyStep(context, finance),
                      2 => _incomesStep(context, finance, people, recurring),
                      3 => _expensesStep(context, finance, people, recurring),
                      _ => _moneyStep(context, recurring, solo),
                    },
                  ),
                ),
                _footer(context, finance, people),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, bool solo) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final titles = [
      solo ? '¿Cómo te llamas?' : '¿Cómo se llaman?',
      solo
          ? '¿En qué moneda manejas tu dinero?'
          : '¿En qué moneda manejan su dinero?',
      solo ? '¿Cómo recibes tu dinero?' : '¿Cómo reciben su dinero?',
      solo ? '¿Qué pagas cada mes?' : '¿Qué pagan cada mes?',
      solo ? '¿Cuánto dinero tienes hoy?' : '¿Cuánto dinero tienen hoy?',
    ];
    final subtitles = [
      solo
          ? 'Así te saludamos y se ve en tus registros.'
          : 'Así se distingue quién recibió o pagó cada cosa.',
      'Todos los montos se mostrarán en esta moneda. Puedes cambiarla '
          'después en Ajustes.',
      solo
          ? 'Agrega cada ingreso que recibes con su fecha. Si tienes más de '
                'uno (sueldo y freelance, por ejemplo), agrega los dos.'
          : 'Agreguen los ingresos de cada uno con su fecha. Si alguien no '
                'tiene ingresos fijos, déjenlo vacío.',
      'Los pagos fijos: los que se pagan una sola vez al mes, como el '
          'alquiler, el celular o el seguro del carro. Toca uno para '
          'agregarlo con su monto y su día.',
      solo
          ? 'Todo lo que tienes ahora en el banco y en efectivo: lo que te '
                'sobró de meses anteriores más lo que ya cobraste este mes.'
          : 'Todo lo que tienen ahora entre los dos, en el banco y en '
                'efectivo: lo que les sobró de meses anteriores más lo que ya '
                'cobraron este mes.',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < _steps; i++)
                Expanded(
                  child: Container(
                    height: 6,
                    margin: EdgeInsets.only(right: i < _steps - 1 ? 8 : 0),
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Configuración inicial · paso ${_step + 1} de $_steps',
            style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            titles[_step],
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            subtitles[_step],
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _footer(
    BuildContext context,
    FinanceRepository finance,
    List<String> people,
  ) {
    final last = _step == _steps - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        children: [
          TextButton(
            onPressed: _step == 0
                ? () => finance.finishSetup()
                : () => setState(() => _step--),
            child: Text(_step == 0 ? 'Saltar todo' : 'Atrás'),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: FilledButton(
              onPressed: () async {
                if (_step == 0) await _saveNames(finance, people);
                if (last) {
                  final money = parseAmount(_money.text);
                  if (money != null) {
                    // Todo el dinero va junto (en pareja, en la primera
                    // persona): manejan un solo fondo.
                    await finance.setStartingMoney([
                      money,
                      for (var i = 1; i < people.length; i++) 0,
                    ]);
                  }
                  await finance.finishSetup();
                } else {
                  setState(() => _step++);
                }
              },
              child: Text(last ? 'Empezar' : 'Siguiente'),
            ),
          ),
        ],
      ),
    );
  }

  // Paso 1: nombres

  Widget _namesStep(bool solo) {
    return ListView(
      key: const ValueKey('names'),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      children: [
        for (var i = 0; i < _names!.length; i++) ...[
          TextField(
            controller: _names![i],
            textCapitalization: TextCapitalization.words,
            textInputAction: i == _names!.length - 1
                ? TextInputAction.done
                : TextInputAction.next,
            decoration: InputDecoration(
              labelText: i == 0 ? 'Tu nombre' : 'Nombre de tu pareja',
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Future<void> _saveNames(FinanceRepository finance, List<String> people) {
    return finance.setPeople([
      for (var i = 0; i < people.length; i++)
        _names![i].text.trim().isEmpty ? people[i] : _names![i].text.trim(),
    ]);
  }

  // Paso 2: moneda

  Widget _currencyStep(BuildContext context, FinanceRepository finance) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      key: const ValueKey('currency'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        for (final c in currencies)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              color: c.code == currencySettings.code
                  ? scheme.primaryContainer
                  : null,
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                leading: Icon(
                  c.code == currencySettings.code
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(c.name),
                trailing: Text(
                  c.symbol,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Cuenta nueva: no hay montos que convertir, así que no se
                // pide tipo de cambio.
                onTap: () => finance.saveCurrencySettings(
                  CurrencySettings(code: c.code),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Paso 3: ingresos

  Widget _incomesStep(
    BuildContext context,
    FinanceRepository finance,
    List<String> people,
    List<Recurring> recurring,
  ) {
    final incomes = recurring
        .where((r) => r.type == RecurringType.income)
        .toList();

    return ListView(
      key: const ValueKey('incomes'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        for (var i = 0; i < people.length; i++) ...[
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(child: Text(_initial(people[i]))),
                  title: Text(
                    people[i],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _countLabel(
                      incomes.where((r) => r.person == i).length,
                      'ingreso',
                    ),
                  ),
                ),
                for (final item in incomes.where((r) => r.person == i))
                  _itemTile(finance, item, Icons.payments_outlined),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar ingreso'),
                    onPressed: () => _addIncome(context, finance, people, i),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  String _initial(String name) =>
      name.isEmpty ? '?' : name.characters.first.toUpperCase();

  String _countLabel(int count, String noun) => switch (count) {
    0 => 'Sin ${noun}s todavía',
    1 => '1 $noun',
    _ => '$count ${noun}s',
  };

  Future<void> _addIncome(
    BuildContext context,
    FinanceRepository finance,
    List<String> people,
    int person,
  ) async {
    final choice = await showIncomeDialog(
      context,
      people: people,
      person: person,
    );
    if (choice != null) {
      await finance.saveRecurring(
        choice.item,
        firstPayment: choice.firstPayment,
      );
    }
  }

  // Paso 4: gastos fijos

  Widget _expensesStep(
    BuildContext context,
    FinanceRepository finance,
    List<String> people,
    List<Recurring> recurring,
  ) {
    final expenses = recurring
        .where((r) => r.type == RecurringType.expense)
        .toList();
    final added = expenses.map((e) => e.description).toSet();

    return ListView(
      key: const ValueKey('expenses'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (name, category, icon) in _suggestions)
              ActionChip(
                avatar: Icon(
                  added.contains(name) ? Icons.check : icon,
                  size: 18,
                ),
                label: Text(name),
                onPressed: () => _addExpense(
                  context,
                  finance,
                  people,
                  name: name,
                  category: category,
                ),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Otro'),
              onPressed: () => _addExpense(context, finance, people),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _summary(context, recurring, people.length == 1),
        const SizedBox(height: 16),
        if (expenses.isNotEmpty)
          Card(
            child: Column(
              children: [
                for (final item in expenses)
                  _itemTile(
                    finance,
                    item,
                    categoryIcon(item.category),
                    people: people,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _addExpense(
    BuildContext context,
    FinanceRepository finance,
    List<String> people, {
    String? name,
    String? category,
  }) async {
    final values = await showFieldsDialog(
      context,
      title: name ?? 'Otro pago fijo',
      fields: [
        if (name == null) ...[
          const DialogField('¿Qué es? (ej. Gimnasio)'),
          DialogField(
            'Categoría',
            initial: 'Otros',
            options: expenseCategories,
          ),
        ],
        const DialogField('Monto', number: true),
        const DialogField.day('Día de pago', initial: '1'),
        if (people.length > 1)
          DialogField('Quién paga', initial: people[0], options: people),
      ],
    );
    if (values == null) return;

    var i = 0;
    final description = name ?? values[i++].trim();
    final chosenCategory = category ?? values[i++];
    final amount = parseAmount(values[i++])!;
    final day = (parseAmount(values[i++])?.round() ?? 1).clamp(1, 31);
    final person = people.length > 1 ? people.indexOf(values[i]) : 0;

    await finance.saveRecurring(
      Recurring(
        type: RecurringType.expense,
        person: person,
        category: chosenCategory,
        description: description.isEmpty ? chosenCategory : description,
        amount: amount,
        day: day,
        // Espera el "Ya pagué", cuando lo vean en el banco.
        confirm: true,
      ),
    );
  }

  // Paso 5: dinero de hoy

  Widget _moneyStep(
    BuildContext context,
    List<Recurring> recurring,
    bool solo,
  ) {
    return ListView(
      key: const ValueKey('money'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        TextField(
          controller: _money,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Banco + efectivo',
            prefixText: '${currencySettings.currency.symbol} ',
            prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ejemplo: te sobraron 1000 del mes pasado y ya cobraste 1000 '
          'este mes → escribe 2000. No hace falta anotarlo como ingreso. '
          'Puedes ajustarlo después tocando la tarjeta verde de Inicio.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _summary(context, recurring, solo),
      ],
    );
  }

  /// Cuánto entra y cuánto se va en fijos cada mes, para ver qué queda para
  /// lo demás (comida, salidas, ahorro...).
  Widget _summary(BuildContext context, List<Recurring> recurring, bool solo) {
    final scheme = Theme.of(context).colorScheme;
    double total(RecurringType type) => recurring
        .where((r) => r.type == type)
        .fold(0.0, (sum, r) => sum + r.monthlyAmount);
    final income = total(RecurringType.income);
    final fixed = total(RecurringType.expense);
    final free = income - fixed;

    Widget row(String label, String value, {bool bold = false, Color? color}) {
      final style = TextStyle(
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        fontSize: bold ? 18 : 15,
        color: color,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: style)),
            Text(value, style: style),
          ],
        ),
      );
    }

    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tu mes, aproximado',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            row('Ingresos', money(income), color: context.money.income),
            row(
              'Pagos fijos',
              '− ${money(fixed)}',
              color: context.money.expense,
            ),
            const Divider(),
            row(
              'Libre para lo demás',
              money(free),
              bold: true,
              color: free < 0 ? context.money.expense : null,
            ),
            const SizedBox(height: 4),
            Text(
              free < 0
                  ? 'Los fijos superan los ingresos. Revisa los montos.'
                  : solo
                  ? 'Es lo que te queda para comida, salidas y ahorro.'
                  : 'Es lo que les queda para comida, salidas y ahorro.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemTile(
    FinanceRepository finance,
    Recurring item,
    IconData icon, {
    List<String>? people,
  }) {
    final who = people != null && people.length > 1
        ? ' · paga ${personName(people, item.person)}'
        : '';
    return ListTile(
      leading: Icon(icon),
      title: Text('${item.description} · ${money(item.amount)}'),
      subtitle: Text('${item.schedule}$who'),
      trailing: IconButton(
        tooltip: 'Quitar',
        icon: const Icon(Icons.close),
        onPressed: () => finance.deleteRecurringWithRecords(item.id),
      ),
    );
  }
}
