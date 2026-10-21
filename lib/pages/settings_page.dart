import 'package:flutter/material.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/config.dart';
import 'package:primera_app_curso/data/demo_data.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/pages/report_page.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/login_state.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/pages/ui/income_dialog.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
import 'package:primera_app_curso/theme.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final finance = Provider.of<FinanceRepository>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: MultiStreamBuilder(
        // Al cambiar la moneda se vuelven a leer los montos, ya convertidos.
        key: ValueKey('${currencySettings.code}-${currencySettings.rates}'),
        streams: [
          finance.watchPeople(),
          finance.watchRecurring(),
          finance.watchBudgets(),
          finance.watchSolo(),
        ],
        builder: (context, values) {
          final people = values[0] as List<String>;
          final recurring = values[1] as List<Recurring>;
          final budgets = values[2] as Map<String, double>;
          final solo = values[3] as bool? ?? false;
          final incomes = recurring
              .where((r) => r.type == RecurringType.income)
              .toList();
          final expenses = recurring
              .where((r) => r.type == RecurringType.expense)
              .toList();
          final allowances = recurring
              .where((r) => r.type == RecurringType.allowance)
              .toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 32.0),
            children: [
              const _Section('Personas'),
              SwitchListTile(
                secondary: const Icon(Icons.people_outline),
                title: const Text('Cuenta de pareja'),
                subtitle: Text(
                  solo
                      ? 'Ahora es individual: solo tus gastos'
                      : 'Registran juntos y ven quién pagó qué',
                ),
                value: !solo,
                onChanged: (couple) => finance.setSolo(!couple),
              ),
              for (var i = 0; i < people.length; i++)
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(people[i]),
                  trailing: const Icon(Icons.edit),
                  onTap: () => _editName(context, finance, people, i),
                ),
              const _Section('Moneda'),
              ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: Text(currencySettings.currency.name),
                subtitle: Text(
                  'Los montos se muestran en '
                  '${currencySettings.currency.symbol}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _changeCurrency(context, finance),
              ),
              _Section(
                solo ? 'Mi sueldo' : 'Sueldos',
                hint: 'Se anota solo el día que llega.',
              ),
              for (final item in incomes)
                _recurringTile(
                  context,
                  finance,
                  item,
                  solo
                      ? item.schedule
                      : '${personName(people, item.person)} · ${item.schedule}',
                  people,
                ),
              _addButton(
                solo ? 'Agregar sueldo' : 'Agregar sueldo o ingreso',
                () => _editRecurring(
                  context,
                  finance,
                  people,
                  RecurringType.income,
                ),
              ),
              _Section(
                solo ? 'Mis pagos fijos' : 'Pagos fijos',
                hint: 'Se pagan una vez al mes y se anotan solos ese día.',
              ),
              for (final item in expenses)
                _recurringTile(
                  context,
                  finance,
                  item,
                  solo
                      ? item.schedule
                      : 'paga ${personName(people, item.person)} · ${item.schedule}',
                  people,
                ),
              _addButton(
                'Agregar pago fijo',
                () => _editRecurring(
                  context,
                  finance,
                  people,
                  RecurringType.expense,
                ),
              ),
              const _Section(
                'Propinas',
                hint: 'Dinero libre de cada uno para lo que quiera.',
              ),
              for (final item in allowances)
                _recurringTile(
                  context,
                  finance,
                  item,
                  '${personName(people, item.person)} · '
                  '${item.biweekly ? 'cada quincena (15 y 30)' : 'a fin de mes (30)'}',
                  people,
                ),
              _addButton(
                'Agregar propina',
                () => _addAllowance(context, finance, people),
              ),
              const _Section('Categorías'),
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('Administrar categorías'),
                subtitle: const Text('Crear nuevas, editarlas u ocultarlas'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pushNamed('/categories'),
              ),
              const _Section(
                'Presupuesto mensual por categoría',
                hint: 'Toca una categoría para ponerle un límite.',
              ),
              for (final category in expenseCategories)
                ListTile(
                  leading: Icon(categoryIcon(category)),
                  title: Text(category),
                  trailing: Text(
                    budgets[category] == null
                        ? 'Sin límite'
                        : money(budgets[category]!),
                    style: TextStyle(
                      color: budgets[category] == null ? Colors.grey : null,
                    ),
                  ),
                  onTap: () => _editBudget(
                    context,
                    finance,
                    category,
                    budgets[category],
                  ),
                ),
              const _Section('Informes'),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Informe en PDF del mes'),
                subtitle: const Text(
                  'Resumen, gráficos y detalle para compartir o imprimir',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final now = DateTime.now();
                  Navigator.of(context).pushNamed(
                    '/report',
                    arguments: ReportParams(now.year, month: now.month),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Informe anual'),
                subtitle: const Text(
                  'Cualquier año, también los anteriores a 4 años',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openYearReport(context),
              ),
              if (modoPruebas) ...[
                const _Section('Datos de prueba'),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Completar meses anteriores'),
                  subtitle: const Text(
                    'Agrega datos de prueba de enero al mes '
                    'pasado usando sus sueldos, fijos, propinas y metas. '
                    'No borra nada.',
                  ),
                  onTap: () => _loadDemo(context, finance),
                ),
                ListTile(
                  leading: const Icon(Icons.layers_clear_outlined),
                  title: const Text('Quitar datos de prueba'),
                  subtitle: const Text('Deja solo lo que registraron ustedes'),
                  onTap: () async {
                    if (await confirmDialog(
                      context,
                      '¿Quitar todos los datos de prueba?',
                      confirm: 'Quitar',
                    )) {
                      if (!context.mounted) return;
                      final messenger = ScaffoldMessenger.of(context);
                      await removeDemoData(
                        Provider.of<Store>(context, listen: false),
                      );
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Datos de prueba quitados'),
                        ),
                      );
                    }
                  },
                ),
              ],
              const _Section('Cuenta'),
              if (modoPruebas)
                const ListTile(
                  leading: Icon(Icons.science),
                  title: Text('Modo de pruebas'),
                  subtitle: Text(
                    'Los datos se guardan solo en este celular. Para usar la '
                    'nube cambia modoPruebas a false en lib/config.dart.',
                  ),
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.cloud_done_outlined),
                  title: Text(
                    Provider.of<LoginState>(
                          context,
                          listen: false,
                        ).currentUser().email ??
                        'Tu cuenta de Google',
                  ),
                  subtitle: const Text(
                    'Tus datos están guardados en la nube con esta cuenta',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: expenseColor),
                  title: const Text(
                    'Cerrar sesión',
                    style: TextStyle(color: expenseColor),
                  ),
                  onTap: () async {
                    if (await confirmDialog(
                      context,
                      '¿Cerrar sesión?',
                      confirm: 'Cerrar sesión',
                    )) {
                      if (!context.mounted) return;
                      Navigator.of(context).popUntil((route) => route.isFirst);
                      Provider.of<LoginState>(context, listen: false).logout();
                    }
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _changeCurrency(
    BuildContext context,
    FinanceRepository finance,
  ) async {
    final current = currencySettings;
    final chosen = await showDialog<Currency>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Moneda'),
        children: [
          for (final c in currencies)
            ListTile(
              leading: Icon(
                c.code == current.code
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(c.name),
              trailing: Text(
                c.symbol,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () => Navigator.of(context).pop(c),
            ),
        ],
      ),
    );
    if (chosen == null || chosen.code == current.code || !context.mounted) {
      return;
    }

    // Se pide el cambio con la moneda "más fuerte" primero (1 US$ = 3.75 S/.).
    final from = current.currency;
    final strongFirst = from.perDollar <= chosen.perDollar;
    final a = strongFirst ? from : chosen;
    final b = strongFirst ? chosen : from;
    final suggested = b.perDollar / a.perDollar;
    final values = await showFieldsDialog(
      context,
      title: 'Tipo de cambio',
      confirm: 'Cambiar a ${chosen.symbol}',
      fields: [
        DialogField(
          '1 ${a.symbol} = ¿cuántos ${b.symbol}?',
          initial: suggested.toStringAsFixed(suggested < 10 ? 2 : 0),
          number: true,
        ),
      ],
    );
    if (values == null) return;
    final value = parseAmount(values[0])!;
    if (value <= 0) return;

    // rate = cuánto vale 1 unidad de la moneda actual en la nueva.
    final rate = strongFirst ? value : 1 / value;
    final updated = current.switchTo(chosen.code, rate);
    await finance.saveCurrencySettings(updated);
    // Se aplica ya, para que esta pantalla muestre los montos convertidos.
    currencySettings = updated;
    if (mounted) setState(() {});
  }

  Future<void> _loadDemo(
    BuildContext context,
    FinanceRepository finance,
  ) async {
    if (!await confirmDialog(
      context,
      'Se agregarán gastos e ingresos ficticios de enero hasta el mes '
      'pasado, a partir de sus sueldos, pagos fijos, propinas y metas. '
      'Lo que ya registraron no se toca y se puede quitar después.',
      confirm: 'Agregar',
    )) {
      return;
    }
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await addDemoHistory(Provider.of<Store>(context, listen: false), finance);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Listo: usa la flecha ‹ para ver los meses anteriores'),
      ),
    );
  }

  Future<void> _addAllowance(
    BuildContext context,
    FinanceRepository finance,
    List<String> people, {
    Recurring? existing,
  }) async {
    const biweekly = 'Cada quincena (15 y 30)';
    const monthly = 'Solo a fin de mes (30)';
    final values = await showFieldsDialog(
      context,
      title: existing == null ? 'Nueva propina' : 'Editar propina',
      fields: [
        DialogField(
          'Para',
          initial: personName(people, existing?.person),
          options: people,
        ),
        DialogField(
          'Monto',
          initial: existing?.amount.toStringAsFixed(2) ?? '',
          number: true,
        ),
        DialogField(
          'Cada cuánto',
          initial: existing?.biweekly == false ? monthly : biweekly,
          options: const [biweekly, monthly],
        ),
      ],
    );
    if (values == null) return;
    final item = Recurring(
      type: RecurringType.allowance,
      person: people.indexOf(values[0]),
      description: 'Propina de ${values[0]}',
      amount: parseAmount(values[1])!,
      day: 15,
      biweekly: values[2] == biweekly,
    );
    if (existing == null) {
      await finance.saveRecurring(item);
    } else {
      await finance.updateRecurring(existing, item);
    }
  }

  Widget _recurringTile(
    BuildContext context,
    FinanceRepository finance,
    Recurring item,
    String subtitle,
    List<String> people,
  ) {
    return ListTile(
      onTap: () => item.type == RecurringType.allowance
          ? _addAllowance(context, finance, people, existing: item)
          : _editRecurring(context, finance, people, item.type, existing: item),
      leading: switch (item.type) {
        RecurringType.income => const Icon(Icons.payments, color: incomeColor),
        RecurringType.expense => const Icon(
          Icons.event_repeat,
          color: expenseColor,
        ),
        RecurringType.allowance => CategoryAvatar(propinaCategory, size: 36),
      },
      title: Text(item.description),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            money(item.amount),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirmDialog(
                context,
                '¿Quitar "${item.description}"? Los meses ya registrados '
                'no se borran.',
                confirm: 'Quitar',
              )) {
                finance.deleteRecurring(item.id);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _addButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text(label),
          onPressed: onPressed,
        ),
      ),
    );
  }

  Future<void> _editName(
    BuildContext context,
    FinanceRepository finance,
    List<String> people,
    int index,
  ) async {
    final values = await showFieldsDialog(
      context,
      title: 'Nombre',
      fields: [DialogField('Nombre', initial: people[index])],
    );
    if (values == null || values[0].isEmpty) return;
    final names = [...people]..[index] = values[0];
    await finance.setPeople(names);
  }

  Future<void> _editRecurring(
    BuildContext context,
    FinanceRepository finance,
    List<String> people,
    RecurringType type, {
    Recurring? existing,
  }) async {
    final isIncome = type == RecurringType.income;
    if (isIncome) {
      // El ingreso se carga en una sola pantalla (semanal por defecto).
      final choice = await showIncomeDialog(
        context,
        people: people,
        existing: existing,
      );
      if (choice == null) return;
      if (existing == null) {
        await finance.saveRecurring(
          choice.item,
          firstPayment: choice.firstPayment,
        );
      } else {
        await finance.updateRecurring(existing, choice.item);
      }
      return;
    }

    // Un pago fijo es uno solo al mes: no se pregunta cada cuánto (salvo uno
    // antiguo que ya era semanal o quincenal).
    final askFrequency =
        existing != null && existing.frequency != Frequency.monthly;
    // Lo del fin de semana importa para cuándo llega el sueldo, no para un
    // pago fijo.
    final askShift =
        existing != null && existing.weekendShift != WeekendShift.none;

    // Primero cada cuánto se repite; según eso se pide el día (o los días).
    final frequency = !askFrequency
        ? Frequency.monthly
        : await showDialog<Frequency>(
            context: context,
            builder: (context) => SimpleDialog(
              title: Text(
                isIncome
                    ? '¿Cada cuánto recibes este ingreso?'
                    : '¿Cada cuánto pagas este gasto?',
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    'Según lo que elijas, después te pedimos el día de pago (o los '
                    'dos días, si es quincenal).',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final f in Frequency.values)
                  ListTile(
                    leading: Icon(
                      f == existing.frequency
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    title: Text(switch (f) {
                      Frequency.monthly => 'Una vez al mes',
                      Frequency.biweekly => 'Dos veces al mes (quincena)',
                      Frequency.weekly => 'Cada semana',
                    }),
                    subtitle: Text(switch (f) {
                      Frequency.monthly =>
                        isIncome
                            ? 'Ej. sueldo el 15. También freelance (fecha variable)'
                            : 'Ej. alquiler el 5, luz, internet',
                      Frequency.biweekly =>
                        'Ej. el 15 y el 30, o el 10 y el 25',
                      Frequency.weekly =>
                        isIncome
                            ? 'Ej. te pagan cada viernes'
                            : 'Ej. el mercado del sábado',
                    }),
                    onTap: () => Navigator.of(context).pop(f),
                  ),
              ],
            ),
          );
    if (frequency == null || !context.mounted) return;
    final sameFrequency = existing?.frequency == frequency;

    final values = await showFieldsDialog(
      context,
      title: existing != null
          ? (isIncome ? 'Editar ingreso fijo' : 'Editar pago fijo')
          : (isIncome ? 'Nuevo ingreso fijo' : 'Nuevo pago fijo'),
      fields: [
        // En cuenta individual no hay a quién elegir.
        if (people.length > 1)
          DialogField(
            isIncome ? 'Quién lo recibe' : 'Quién paga',
            initial: personName(people, existing?.person),
            options: people,
          ),
        if (!isIncome)
          DialogField(
            'Categoría',
            initial: existing?.category ?? '',
            options: expenseCategories,
          ),
        DialogField(
          'Nombre (ej. Alquiler)',
          initial: existing?.description ?? '',
        ),
        DialogField(
          'Monto',
          initial: existing?.amount.toStringAsFixed(2) ?? '',
          number: true,
        ),
        if (frequency == Frequency.monthly) ...[
          DialogField.day(
            'Día de pago',
            initial: '${sameFrequency ? existing!.day : 1}',
          ),
          // Solo los que ya eran de fecha variable siguen con esta opción.
          if (existing?.confirm == true)
            const DialogField(
              '¿Es siempre el mismo día?',
              initial: _whenConfirm,
              options: [_whenAuto, _whenConfirm],
            ),
        ],
        if (frequency == Frequency.biweekly) ...[
          DialogField.day(
            'Día del primer pago',
            initial: '${sameFrequency ? existing!.day : 15}',
          ),
          DialogField.day(
            'Día del segundo pago',
            initial: '${sameFrequency ? existing!.secondDay : 30}',
          ),
        ],
        if (frequency == Frequency.weekly)
          DialogField(
            'Día de la semana',
            initial:
                weekdayNames[sameFrequency
                    ? (existing!.day - 1).clamp(0, 6)
                    : 4],
            options: weekdayNames,
            letters: true,
          ),
        if (askShift)
          DialogField(
            'Si ese día cae sábado o domingo, se paga',
            initial: weekendShiftLabels[existing.weekendShift]!,
            options: weekendShiftLabels.values.toList(),
          ),
      ],
    );
    if (values == null) return;

    var i = 0;
    final person = people.length > 1 ? people.indexOf(values[i++]) : 0;
    final category = isIncome ? '' : values[i++];
    final description = values[i++];
    final amount = parseAmount(values[i++])!;
    final day = switch (frequency) {
      Frequency.monthly => (parseAmount(values[i++])?.round() ?? 1).clamp(
        1,
        31,
      ),
      Frequency.weekly => weekdayNames.indexOf(values[i++]) + 1,
      Frequency.biweekly => (parseAmount(values[i++])?.round() ?? 15).clamp(
        1,
        31,
      ),
    };
    final secondDay = frequency == Frequency.biweekly
        ? (parseAmount(values[i++])?.round() ?? 30).clamp(1, 31)
        : 30;
    final confirm =
        frequency == Frequency.monthly &&
        existing?.confirm == true &&
        values[i++] == _whenConfirm;
    final shift = askShift
        ? weekendShiftLabels.entries
              .firstWhere((e) => e.value == values[i++])
              .key
        : WeekendShift.none;
    final item = Recurring(
      type: type,
      frequency: frequency,
      confirm: confirm,
      weekendShift: confirm ? WeekendShift.none : shift,
      person: person,
      category: category,
      description: description.isEmpty
          ? (isIncome ? 'Ingreso' : category)
          : description,
      amount: amount,
      day: day,
      secondDay: secondDay,
    );
    if (existing == null) {
      await finance.saveRecurring(item);
    } else {
      await finance.updateRecurring(existing, item);
    }
  }

  Future<void> _editBudget(
    BuildContext context,
    FinanceRepository finance,
    String category,
    double? current,
  ) async {
    final values = await showFieldsDialog(
      context,
      title: 'Presupuesto de $category',
      fields: [
        DialogField(
          'Monto máximo al mes (0 = sin límite)',
          initial: current?.toStringAsFixed(2) ?? '',
          number: true,
        ),
      ],
    );
    if (values == null) return;
    await finance.setBudget(category, parseAmount(values[0])!);
  }
}

const _whenAuto = 'Sí (se registra solo)';
const _whenConfirm = 'No, cambia cada mes (te pregunto)';

class _Section extends StatelessWidget {
  final String title;
  final String? hint;

  const _Section(this.title, {this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.bold,
              color: incomeColor,
            ),
          ),
          if (hint != null)
            Text(
              hint!,
              style: const TextStyle(fontSize: 12.0, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}
