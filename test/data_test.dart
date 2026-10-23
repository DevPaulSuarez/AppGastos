import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primera_app_curso/alerts.dart';
import 'package:primera_app_curso/cash.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/data/demo_data.dart';
import 'package:primera_app_curso/report.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late LocalStore store;
  late ExpensesRepository expenses;
  late FinanceRepository finance;
  final now = DateTime.now();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    currencySettings = const CurrencySettings();
    categorySettings = const CategorySettings();
    store = LocalStore();
    expenses = ExpensesRepository(store);
    finance = FinanceRepository(store);
  });

  test('filtra gastos por mes y categoría', () async {
    await expenses.add('Comida', 20, DateTime(2026, 10, 5), 'Almuerzo');
    await expenses.add('Comida', 15.5, DateTime(2026, 10, 6), 'Cena');
    await expenses.add('Transporte', 5, DateTime(2026, 10, 6), 'Bus');
    await expenses.add('Comida', 99, DateTime(2026, 9, 6), 'Otro mes');

    expect((await expenses.queryByMonth(10, 2026).first).length, 3);
    final comida = await expenses.queryByCategory(10, 'Comida', 2026).first;
    expect(comida.map((e) => e.value), unorderedEquals([20, 15.5]));
  });

  test('los fijos se registran el día que tocan, una sola vez', () async {
    final today = DateTime(2026, 10, 5);
    await finance.saveRecurring(
        const Recurring(
            type: RecurringType.income,
            person: 0,
            description: 'Sueldo',
            amount: 3000,
            day: 1),
        today: today);
    await finance.saveRecurring(
        const Recurring(
            type: RecurringType.expense,
            person: 1,
            category: 'Servicios',
            description: 'Alquiler',
            amount: 1200,
            day: 31),
        today: today);
    await finance.applyRecurring(today: today);
    await finance.applyRecurring(today: today);

    final incomes = await finance.watchIncomes(10, 2026).first;
    expect(incomes.length, 1);
    expect(incomes.single.amount, 3000);
    // El alquiler del 31 todavía no se paga.
    expect(await expenses.queryByMonth(10, 2026).first, isEmpty);

    await finance.applyRecurring(today: DateTime(2026, 10, 31));
    await finance.applyRecurring(today: DateTime(2026, 10, 31));
    final month = await expenses.queryByMonth(10, 2026).first;
    expect(month.length, 1);
    expect(month.single.paidBy, 1);
    expect(month.single.day, 31);
  });

  test('los datos se conservan al reabrir la app', () async {
    await expenses.add(ahorroCategory, 100, now, 'Meta: Viaje',
        paidBy: 0, goalId: 'g1');
    await finance.setPeople(['Ana', 'Luis']);
    await finance.setBudget('Comida', 800);

    final reopened = LocalStore();
    final savings = await ExpensesRepository(reopened).querySavings().first;
    expect(savings.single.goalId, 'g1');
    expect(await FinanceRepository(reopened).watchPeople().first,
        ['Ana', 'Luis']);
    expect(await FinanceRepository(reopened).watchBudgets().first,
        {'Comida': 800.0});
  });

  test('la primera vez se elige cuenta individual o de pareja', () async {
    expect(await finance.watchSolo().first, isNull);

    await finance.setSolo(true);
    expect(await finance.watchSolo().first, isTrue);
    expect(await finance.watchPeople().first, ['Yo']);

    // El nombre de la pareja se guarda aunque la cuenta sea individual.
    await finance.setPeople(['Ana']);
    await finance.setSolo(false);
    expect(await finance.watchPeople().first, ['Ana', 'Persona 2']);
  });

  test('después de elegir la cuenta sigue la configuración inicial',
      () async {
    expect(await finance.watchAccountStep().first, AccountStep.choose);
    await finance.setSolo(false);
    expect(await finance.watchAccountStep().first, AccountStep.setup);
    await finance.finishSetup();
    expect(await finance.watchAccountStep().first, AccountStep.ready);
    expect(await finance.watchSolo().first, isFalse);
  });

  test('dos pagos al mes en los días elegidos', () {
    const item = Recurring(
      type: RecurringType.income,
      frequency: Frequency.biweekly,
      person: 0,
      description: 'Sueldo',
      amount: 1000,
      day: 10,
      secondDay: 25,
      weekendShift: WeekendShift.previous,
    );
    // Octubre 2026: el 10 es sábado y el 25 domingo; se adelantan al viernes.
    expect(FinanceRepository.occurrences(item, 2026, 10),
        [DateTime(2026, 10, 9), DateTime(2026, 10, 23)]);
    final saved = Recurring.fromMap('x', item.toMap());
    expect((saved.day, saved.secondDay), (10, 25));
    // Los de antes (sin segundo día) siguen siendo el 15 y el 30.
    final old = Recurring.fromMap(
        'y', item.toMap()..remove('secondDay')..['day'] = 15);
    expect(FinanceRepository.occurrences(old, 2026, 11).map((d) => d.day),
        [13, 30]);
  });

  test('quitar un fijo recién cargado borra lo que ya registró', () async {
    await finance.saveRecurring(Recurring(
      type: RecurringType.income,
      person: 0,
      description: 'Sueldo',
      amount: 3000,
      day: 1,
    ));
    final item = (await finance.watchRecurring().first).single;
    expect(await finance.watchAllIncomes().first, isNotEmpty);
    await finance.deleteRecurringWithRecords(item.id);
    expect(await finance.watchRecurring().first, isEmpty);
    expect(await finance.watchAllIncomes().first, isEmpty);
  });

  test('las cuentas de antes siguen siendo de pareja', () async {
    await finance.setPeople(['Ana', 'Luis']);
    expect(await finance.watchSolo().first, isFalse);
  });

  test('los cambios llegan a quien está escuchando', () async {
    final updates = expenses.queryByMonth(10, 2026).take(2).toList();
    await Future<void>.delayed(Duration.zero);
    await expenses.add('Comida', 10, DateTime(2026, 10, 1), 'Pan');
    final result = await updates;
    expect(result.first, isEmpty);
    expect(result.last.single.description, 'Pan');
  });

  test('las propinas se registran el 15 y fin de mes, sin duplicar', () async {
    await finance.saveRecurring(
        const Recurring(
            type: RecurringType.allowance,
            person: 1,
            description: 'Propina',
            amount: 150,
            day: 15,
            biweekly: true),
        today: DateTime(2026, 9, 10));

    // Al crearla el 10/9 se entrega en el momento la de la quincena en curso.
    expect((await expenses.queryAll().first).map((e) => '${e.day}/${e.month}'),
        ['10/9']);

    // Se abre la app el 19 de octubre: tocaban 30/9 y 15/10 (el 15/9 ya se
    // entregó al crearla).
    await finance.applyRecurring(today: DateTime(2026, 10, 19));
    await finance.applyRecurring(today: DateTime(2026, 10, 19));
    final tips = await expenses.queryAll().first;
    expect(tips.map((e) => '${e.day}/${e.month}'),
        unorderedEquals(['10/9', '30/9', '15/10']));
    expect(tips.every((e) => e.category == propinaCategory && e.paidBy == 1),
        isTrue);
  });

  test('una propina de fin de mes ya creada se ve en el mes en curso', () async {
    // Así quedó guardada con la versión anterior: creada el 19/10.
    await store.add(
        'recurring',
        const Recurring(
                type: RecurringType.allowance,
                person: 0,
                description: 'Propina de Pol',
                amount: 150,
                day: 15,
                lastApplied: '2026-10-19')
            .toMap());
    await finance.applyRecurring(today: DateTime(2026, 10, 19));
    await finance.applyRecurring(today: DateTime(2026, 10, 31));
    await finance.applyRecurring(today: DateTime(2026, 11, 30));
    final tips = await expenses.queryAll().first;
    expect(tips.map((e) => '${e.day}/${e.month}'),
        unorderedEquals(['19/10', '30/11']));
  });

  test('las propinas se pagan el 15 y el 30; en febrero el 28 o 29', () {
    String days(int y, int m) => FinanceRepository.payoutDates(y, m, true)
        .map((d) => d.day)
        .join(',');
    expect(days(2026, 10), '15,30'); // octubre tiene 31 días
    expect(days(2026, 11), '15,30');
    expect(days(2027, 2), '15,28');
    expect(days(2028, 2), '15,29'); // 2028 es bisiesto
    expect(days(2100, 2), '15,28'); // 2100 no es bisiesto
  });

  test('editar un gasto fijo corrige también el mes en curso', () async {
    final today = DateTime(2026, 10, 20);
    await finance.saveRecurring(
        const Recurring(type: RecurringType.expense, person: 0,
            category: 'Vivienda', description: 'Alquiler', amount: 1000,
            day: 1),
        today: today);
    final saved = (await finance.watchRecurring().first).single;
    await finance.updateRecurring(
        saved,
        const Recurring(type: RecurringType.expense, person: 1,
            category: 'Vivienda', description: 'Alquiler', amount: 1100,
            day: 5));
    // El 2 de noviembre todavía no toca (es el 5).
    await finance.applyRecurring(today: DateTime(2026, 11, 2));
    expect((await expenses.queryAll().first).length, 1);
    await finance.applyRecurring(today: DateTime(2026, 11, 5));

    final all = await expenses.queryAll().first;
    expect(all.map((e) => '${e.day}/${e.month} ${e.value} ${e.paidBy}'),
        unorderedEquals(['5/10 1100.0 1', '5/11 1100.0 1']));
  });

  test('mover un fijo a un día que no llegó lo deja por venir', () async {
    final today = DateTime(2026, 10, 20);
    const rent = Recurring(type: RecurringType.expense, person: 0,
        category: 'Vivienda', description: 'Alquiler', amount: 1000, day: 1);
    await finance.saveRecurring(rent, today: today);
    final saved = (await finance.watchRecurring().first).single;
    await finance.updateRecurring(
        saved,
        const Recurring(type: RecurringType.expense, person: 0,
            category: 'Vivienda', description: 'Alquiler', amount: 1000,
            day: 25),
        today: today);
    expect(await expenses.queryAll().first, isEmpty);

    await finance.applyRecurring(today: DateTime(2026, 10, 25));
    expect((await expenses.queryAll().first).map((e) => '${e.day}/${e.month}'),
        ['25/10']);
  });

  test('lo que falta este mes, por fecha', () {
    const items = [
      Recurring(id: 's', type: RecurringType.income, person: 0,
          description: 'Sueldo', amount: 3000, day: 30),
      Recurring(id: 'q', type: RecurringType.income, person: 1,
          frequency: Frequency.biweekly, description: 'Quincena',
          amount: 1500, day: 15, secondDay: 30),
      Recurring(id: 'a', type: RecurringType.expense, person: 0,
          category: 'Vivienda', description: 'Alquiler', amount: 1200,
          day: 25),
      Recurring(id: 'l', type: RecurringType.expense, person: 0,
          category: 'Servicios', description: 'Luz', amount: 90, day: 7,
          confirm: true),
      Recurring(id: 'p', type: RecurringType.allowance, person: 1,
          description: 'Propina', amount: 100, day: 15, biweekly: true),
    ];
    final today = DateTime(2026, 10, 20);
    String show(List<Upcoming> list) => list
        .map((u) => '${u.item.description} ${u.date.day}'
            '${u.needsConfirm ? '?' : ''}')
        .join(', ');

    expect(show(FinanceRepository.upcoming(items, {}, today)),
        'Luz 7?, Alquiler 25, Sueldo 30, Quincena 30, Propina 30');
    // Confirmada la luz, ya no falta.
    expect(
        show(FinanceRepository.upcoming(items, {'rec_l_2026-10'}, today)),
        'Alquiler 25, Sueldo 30, Quincena 30, Propina 30');
  });

  test('compra con propina: no se cuenta dos veces', () async {
    final day = DateTime(2026, 10, 15);
    final incomes = [
      const Income(id: 'i', person: 0, description: 'Sueldo', amount: 1000,
          month: 10, year: 2026),
    ];
    await expenses.add(propinaCategory, 100, day, 'Propina', paidBy: 1);
    final before = monthLeftover(
        incomes, await expenses.queryByMonth(10, 2026).first);
    expect(before, 900);

    await expenses.addWithAllowance('Comida', 30, day, 'Almuerzo',
        paidBy: 1, fromAllowance: 30);
    final month = await expenses.queryByMonth(10, 2026).first;
    // El sobrante no cambia: la propina ya estaba contada.
    expect(monthLeftover(incomes, month), 900);
    expect(await expenses.allowanceLeft(1, 10, 2026), 70);
    final comida = await expenses.queryByCategory(10, 'Comida', 2026).first;
    expect(comida.single.withAllowance, isTrue);
    expect(comida.single.value, 30);
    // Lo que tiene cada uno tampoco cambia.
    expect(cashSummary(incomes, month, null, 2).people[1].spent,
        cashSummary(incomes, [month.firstWhere((e) => e.category ==
            propinaCategory && e.value > 0)], null, 2).people[1].spent);

    // Bajar el monto baja el descuento.
    await expenses.update(comida.single.copyWith(value: 20));
    expect(await expenses.allowanceLeft(1, 10, 2026), 80);
    // Subirlo no pasa de lo descontado: lo extra es gasto normal.
    await expenses.update(comida.single.copyWith(value: 50));
    expect(await expenses.allowanceLeft(1, 10, 2026), 80);

    // Borrar la compra devuelve la propina.
    await expenses.delete(comida.single.id);
    expect(await expenses.allowanceLeft(1, 10, 2026), 100);
    expect((await expenses.queryByMonth(10, 2026).first).length, 1);
  });

  test('alquiler del 5 pagado con lo del mes pasado, sueldo el 15',
      () async {
    const salary = Recurring(type: RecurringType.income, person: 0,
        description: 'Sueldo', amount: 3000, day: 15);
    const rent = Recurring(type: RecurringType.expense, person: 0,
        category: 'Vivienda', description: 'Alquiler', amount: 1200, day: 5);
    // Empieza a usar la app el 3 de octubre con 2000 en el banco.
    final start = DateTime(2026, 10, 3);
    await finance.saveRecurring(salary, today: start);
    await finance.saveRecurring(rent, today: start);
    await finance.setStartingMoney([2000], today: start);

    Future<({double carried, double available})> on(DateTime day) async {
      await finance.applyRecurring(today: day);
      final incomes = await finance.watchAllIncomes().first;
      final all = await expenses.queryAll().first;
      final check = await finance.watchCashCheck().first;
      final carried = cashSummaryUntil(
          incomes, all, check, 1, DateTime(day.year, day.month, 0)).free;
      return (
        carried: carried,
        available: cashSummaryUntil(incomes, all, check, 1, day).free,
      );
    }

    // 5 de octubre: paga el alquiler con lo que traía; no queda en negativo.
    expect(await on(DateTime(2026, 10, 5)), (carried: 2000, available: 800));
    // 15: llega el sueldo.
    expect(await on(DateTime(2026, 10, 15)), (carried: 2000, available: 3800));
    // 5 de noviembre: trae lo de octubre y vuelve a pagar el alquiler.
    expect(await on(DateTime(2026, 11, 5)), (carried: 3800, available: 2600));
  });

  test('el punto de partida descuenta lo ya registrado este mes', () async {
    // Empieza el 20: el sueldo del 15 y el alquiler del 5 ya pasaron y ya
    // están en los 2000 que tiene hoy.
    final today = DateTime(2026, 10, 20);
    await finance.saveRecurring(
        const Recurring(type: RecurringType.income, person: 0,
            description: 'Sueldo', amount: 3000, day: 15),
        today: today);
    await finance.saveRecurring(
        const Recurring(type: RecurringType.expense, person: 0,
            category: 'Vivienda', description: 'Alquiler', amount: 1200,
            day: 5),
        today: today);
    await finance.setStartingMoney([2000], today: today);
    final summary = cashSummaryUntil(
        await finance.watchAllIncomes().first,
        await expenses.queryAll().first,
        await finance.watchCashCheck().first,
        1,
        today);
    expect(summary.free, 2000);
  });

  test('cambiar la frecuencia de una propina no la duplica', () async {
    await finance.saveRecurring(
        const Recurring(type: RecurringType.allowance, person: 0,
            description: 'Propina', amount: 100, day: 15, biweekly: true),
        today: DateTime(2026, 10, 10));
    await finance.applyRecurring(today: DateTime(2026, 10, 16));
    final saved = (await finance.watchRecurring().first).single;
    await finance.updateRecurring(
        saved,
        const Recurring(type: RecurringType.allowance, person: 0,
            description: 'Propina', amount: 100, day: 15, biweekly: false));
    await finance.applyRecurring(today: DateTime(2026, 10, 30));
    final tips = await expenses.queryAll().first;
    // 10/10 (al crearla, por la quincena del 15) y 30/10 (fin de mes).
    expect(tips.map((e) => '${e.day}/${e.month}'),
        unorderedEquals(['10/10', '30/10']));
  });

  test('categorías: crear, ocultar y renombrar sin perder lo registrado',
      () async {
    await finance.saveCategorySettings(const CategorySettings(
      custom: [
        CustomCategory(
            name: 'Mascota', icon: 'mascotas', color: Color(0xFF059669)),
      ],
      hidden: {'Alcohol'},
    ));
    categorySettings = await finance.watchCategorySettings().first;
    expect(categories.keys, contains('Mascota'));
    expect(categories.keys, isNot(contains('Alcohol')));
    expect(categories.keys.toList().sublist(categories.length - 3),
        ['Otros', propinaCategory, ahorroCategory]);

    await expenses.add('Mascota', 80, DateTime(2026, 10, 3), 'Veterinario');
    await finance.setBudget('Mascota', 200);
    await finance.renameCategory('Mascota', 'Firulais');

    expect((await expenses.queryAll().first).single.category, 'Firulais');
    expect(await finance.watchBudgets().first, {'Firulais': 200.0});
    categorySettings = const CategorySettings();
  });

  test('las categorías que ya no están pasan a las nuevas, una vez', () async {
    await expenses.add('Alcohol', 40, DateTime(2026, 10, 3), 'Cerveza');
    await expenses.add('Antojitos', 12, DateTime(2026, 10, 4), 'Helado');
    await expenses.add('Hijos', 90, DateTime(2026, 10, 5), 'Colegio');
    await finance.setBudget('Compras', 300);
    expect(categories.keys, isNot(contains('Alcohol')));
    expect(categories.keys, contains('Restaurantes'));

    await finance.moveRetiredCategories();
    await finance.moveRetiredCategories();
    final all = await expenses.queryAll().first;
    expect(all.map((e) => e.category),
        unorderedEquals(['Ocio', 'Restaurantes', 'Familia']));
    expect(await finance.watchBudgets().first, {'Ropa y cuidado': 300.0});
  });

  test('cambiar de moneda convierte lo anterior sin tocar lo guardado',
      () async {
    // Datos guardados antes de poder elegir moneda: están en soles.
    await store.set('expenses', 'viejo', {
      'category': 'Comida', 'value': 375.0, 'day': 1, 'month': 9,
      'year': 2026, 'Description': 'Súper',
    });
    await finance.setBudget('Comida', 750);

    // En EE. UU.: 1 US\$ = 3.75 S/.
    currencySettings = currencySettings.switchTo('USD', 1 / 3.75);
    expect(money(12.5), 'US\$ 12.50');
    expect((await expenses.queryAll().first).single.value, closeTo(100, 0.001));
    expect((await finance.watchBudgets().first)['Comida'], closeTo(200, 0.001));
    await expenses.add('Comida', 50, DateTime(2026, 10, 2), 'Groceries');

    // De vuelta en Perú: 1 US\$ = 3.70 S/.
    currencySettings = currencySettings.switchTo('PEN', 3.70);
    final values = {
      for (final e in await expenses.queryAll().first) e.description: e.value
    };
    expect(values['Súper'], closeTo(375, 0.001)); // los soles quedan igual
    expect(values['Groceries'], closeTo(185, 0.001)); // 50 US\$ x 3.70
    expect(money(10), 'S/. 10.00');
  });

  test('alertas: en rojo, ritmo rápido y mes normal', () {
    // Sobrante menor al 20% de los ingresos: en rojo.
    final red = spendingAlert(income: 4000, spent: 3300, saved: 0,
        fixedSpent: 1400, day: 20, daysInMonth: 31);
    expect(red?.level, AlertLevel.danger);
    expect(red?.message, contains('S/. 700.00'));

    // Gastaron casi todo en la segunda semana: aún no están en rojo, pero a
    // este ritmo lo estarán.
    final fast = spendingAlert(income: 4000, spent: 2700, saved: 0,
        fixedSpent: 1000, day: 10, daysInMonth: 30);
    expect(fast?.level, AlertLevel.warning);

    // Mes tranquilo: sin aviso.
    expect(
        spendingAlert(income: 4000, spent: 1300, saved: 0, fixedSpent: 1000,
            day: 10, daysInMonth: 30),
        isNull);

    // Los primeros días no se juzga el ritmo.
    expect(
        spendingAlert(income: 4000, spent: 1800, saved: 0, fixedSpent: 1000,
            day: 3, daysInMonth: 30),
        isNull);

    // Gastaron más de lo que entró.
    expect(
        spendingAlert(income: 1000, spent: 1200, saved: 0, fixedSpent: 0,
                day: 25, daysInMonth: 30)
            ?.message,
        contains('S/. 200.00 más'));
  });

  test('el aviso cuenta lo que traían de antes, como la tarjeta verde', () {
    // Este mes entró 1000 y se gastó 975: sin lo de antes, "en rojo".
    expect(
        spendingAlert(income: 1000, spent: 975, saved: 0, fixedSpent: 800,
                day: 20, daysInMonth: 31)
            ?.level,
        AlertLevel.danger);
    // Pero traían 800: les quedan 825, no están en rojo.
    expect(
        spendingAlert(income: 1000, spent: 975, saved: 0, fixedSpent: 800,
            day: 20, daysInMonth: 31, carriedOver: 800),
        isNull);
  });

  test('sueldo semanal agregado tarde: entran los viernes ya cobrados',
      () async {
    // Lo configura el martes 20 de octubre; su primer pago fue el viernes 9
    // (por la semana del 28 de setiembre al 2 de octubre).
    final today = DateTime(2026, 10, 20);
    await finance.saveRecurring(
        const Recurring(type: RecurringType.income, person: 0,
            frequency: Frequency.weekly, description: 'Sueldo', amount: 500,
            day: DateTime.friday),
        today: today,
        firstPayment: DateTime(2026, 10, 9));
    final october = await finance.watchIncomes(10, 2026).first;
    expect(october.map((i) => i.day).toList()..sort(), [9, 16]);
    expect(october.fold(0.0, (a, i) => a + i.amount), 1000);

    // Los siguientes viernes se anotan solos.
    await finance.applyRecurring(today: DateTime(2026, 10, 23));
    expect((await finance.watchIncomes(10, 2026).first).length, 3);
  });

  test('un sueldo que llegó incompleto se puede corregir', () async {
    final today = DateTime(2026, 10, 20);
    const salary = Recurring(type: RecurringType.income, person: 0,
        frequency: Frequency.weekly, description: 'Sueldo', amount: 500,
        day: DateTime.friday);
    await finance.saveRecurring(salary,
        today: today, firstPayment: DateTime(2026, 10, 9));
    Future<List<Income>> october() async =>
        (await finance.watchIncomes(10, 2026).first)
          ..sort((a, b) => a.day.compareTo(b.day));

    // El viernes 16 faltó un día: llegaron 400.
    await finance.setIncomeAmount((await october())[1], 400);
    var incomes = await october();
    expect(incomes.map((i) => '${i.day} ${i.amount} ${i.expected}'),
        ['9 500.0 null', '16 400.0 500.0']);

    // Los siguientes viernes siguen llegando completos.
    await finance.applyRecurring(today: DateTime(2026, 10, 23));
    expect((await october()).last.amount, 500);

    // Volver a poner 500 lo deja completo.
    incomes = await october();
    await finance.setIncomeAmount(incomes[1], 500);
    expect((await october())[1].expected, isNull);
  });

  test('agregar el sueldo después de decir cuánto tenía no lo cuenta dos '
      'veces', () async {
    // El 20 dice que tiene 1000; ese dinero ya incluye los viernes 9 y 16.
    final today = DateTime(2026, 10, 20);
    await finance.setStartingMoney([1000], today: today);
    await finance.saveRecurring(
        const Recurring(type: RecurringType.income, person: 0,
            frequency: Frequency.weekly, description: 'Sueldo', amount: 500,
            day: DateTime.friday),
        today: today,
        firstPayment: DateTime(2026, 10, 9));
    Future<double> available(DateTime day) async => cashSummaryUntil(
            await finance.watchAllIncomes().first,
            await expenses.queryAll().first,
            await finance.watchCashCheck().first,
            1,
            day)
        .free;
    // Resumen muestra los 1000 cobrados, pero sigue teniendo 1000.
    expect((await finance.watchIncomes(10, 2026).first).length, 2);
    expect(await available(today), 1000);
    // El viernes 23 sí es dinero nuevo.
    await finance.applyRecurring(today: DateTime(2026, 10, 23));
    expect(await available(DateTime(2026, 10, 23)), 1500);
  });

  test('metas: aportar de lo disponible y usar el dinero sin restar dos '
      'veces', () async {
    final today = DateTime(2026, 10, 20);
    // Traía 1000 de antes y este mes cobró 500 y gastó 900: el mes solo dejó
    // 400... pero tiene 600 disponibles para apartar.
    await finance.setStartingMoney([1000], today: DateTime(2026, 10, 1));
    await finance.addIncome(0, 'Sueldo', 500, 10, 2026, day: 9);
    await expenses.add('Vivienda', 900, DateTime(2026, 10, 10), 'Alquiler',
        paidBy: 0);
    expect(await finance.freeMoneyToday(today: today), 600);

    await expenses.add(ahorroCategory, 300, DateTime(2026, 10, 15), 'Meta',
        paidBy: 0, goalId: 'viaje');
    expect(await finance.freeMoneyToday(today: today), 300);

    // Paga los pasajes con lo de la meta: lo disponible no cambia.
    await expenses.useGoalMoney(
        'viaje', 250, 'Transporte', 'Pasajes', DateTime(2026, 10, 18),
        paidBy: 0);
    expect(await finance.freeMoneyToday(today: today), 300);
    final all = await expenses.queryAll().first;
    final inGoal = all
        .where((e) => e.goalId == 'viaje')
        .fold(0.0, (a, e) => a + e.value);
    expect(inGoal, 50);
    expect(all.where((e) => e.category == 'Transporte').single.value, 250);

    // Si borra el gasto de los pasajes, el dinero vuelve a la meta.
    await expenses.delete(
        all.firstWhere((e) => e.category == 'Transporte').id);
    final after = await expenses.queryAll().first;
    expect(
        after
            .where((e) => e.goalId == 'viaje')
            .fold(0.0, (a, e) => a + e.value),
        300);
    expect(await finance.freeMoneyToday(today: today), 300);
  });

  test('recordatorio: el próximo viernes a las 7 p. m.', () {
    // Martes 20 de octubre → viernes 23.
    expect(nextWeekdayAt(DateTime(2026, 10, 20, 10), DateTime.friday, 19),
        DateTime(2026, 10, 23, 19));
    // Viernes antes de las 7: ese mismo día.
    expect(nextWeekdayAt(DateTime(2026, 10, 23, 8), DateTime.friday, 19),
        DateTime(2026, 10, 23, 19));
    // Viernes después de las 7: el siguiente.
    expect(nextWeekdayAt(DateTime(2026, 10, 23, 20), DateTime.friday, 19),
        DateTime(2026, 10, 30, 19));
  });

  test('solo se puede aportar lo que sobra', () {
    final incomes = [
      const Income(id: 'i', person: 0, description: 'Sueldo', amount: 1000,
          month: 10, year: 2026),
    ];
    final spent = [
      const Expense(id: 'a', category: 'Comida', value: 850, day: 1,
          month: 10, year: 2026, description: ''),
      const Expense(id: 'b', category: ahorroCategory, value: 50, day: 2,
          month: 10, year: 2026, description: 'Meta: Viaje', goalId: 'g'),
    ];
    // Sobrante del mes: 1000 - 850 de gasto - 50 ya aportados.
    expect(monthLeftover(incomes, spent), 100);
  });

  test('préstamos: no son gasto propio y vuelven al pagarlos', () async {
    final incomes = [
      const Income(id: 'i', person: 0, description: 'Sueldo', amount: 4000,
          month: 10, year: 2026),
    ];
    await expenses.add('Comida', 1000, DateTime(2026, 10, 5), 'Súper');
    await expenses.addLoan(
        100, DateTime(2026, 10, 6), 'Carne', 'Mi hermana', 0);

    var october = await expenses.queryByMonth(10, 2026).first;
    final loan = october.singleWhere((e) => e.isLoan);
    expect(loan.pending, 100);
    // No cuenta como gasto propio, pero sí baja lo disponible.
    expect(
        october
            .where((e) => isSpendingCategory(e.category))
            .fold(0.0, (a, e) => a + e.value),
        1000);
    expect(monthLeftover(incomes, october), 2900);

    // En noviembre devuelve una parte.
    await expenses.registerRepayment(loan, 60, DateTime(2026, 11, 3));
    final loans = await expenses.queryLoans().first;
    expect(loans.singleWhere((e) => e.isLoan).pending, 40);
    final november = await expenses.queryByMonth(11, 2026).first;
    expect(november.single.value, -60);
    expect(november.single.isLoan, isFalse);

    final all = await expenses.queryAll().first;
    expect(cashSummary(incomes, all, null, 1).total, 2960);
  });

  test('aportes de una meta borrada: devolver o dejar como ahorro', () async {
    for (final value in [300.0, 500.0]) {
      await expenses.add(ahorroCategory, value, DateTime(2026, 10, 20),
          'Meta: Viaje', goalId: 'g1');
    }
    var savings = await expenses.querySavings().first;

    // Dejar como ahorro: siguen ahí, pero sin meta.
    await expenses.detachFromGoal(savings.first);
    savings = await expenses.querySavings().first;
    expect(savings.where((e) => e.goalId == null).length, 1);

    // Devolver: desaparecen y el dinero vuelve a estar disponible.
    await expenses.deleteMany(savings.map((e) => e.id));
    expect(await expenses.querySavings().first, isEmpty);
  });

  test('dinero real: cuánto deberían tener y ajuste a sus cuentas', () async {
    final incomes = [
      const Income(id: 'i', person: 0, description: 'Sueldo', amount: 4000,
          month: 10, year: 2026),
    ];
    await expenses.add('Comida', 1000, DateTime(2026, 10, 5), 'Súper');
    await expenses.add(ahorroCategory, 300, DateTime(2026, 10, 6), 'Ahorro');
    await expenses.addLoan(100, DateTime(2026, 10, 7), 'Carne', 'Hermana', 0);
    var all = await expenses.queryAll().first;

    // Sin comparar todavía: 4000 - 1000 - 100 prestado (el ahorro sigue
    // siendo de ellos).
    var summary = cashSummary(incomes, all, null, 2);
    expect(summary.total, 2900);
    expect(summary.saved, 300);
    expect(summary.free, 2600);
    expect(summary.receivable, 100);

    // En el banco tienen 3000 (ya tenían algo antes de usar la app).
    // Paul (persona 0) tiene 2500 y su pareja 500 en sus cuentas.
    final check = reconcile(incomes, all, [2500, 500]);
    await finance.saveCashCheck(check);
    final saved = await finance.watchCashCheck().first;
    final after = cashSummary(incomes, all, saved, 2);
    expect(after.total, 3000);
    expect(after.people.map((p) => p.total), [2500, 500]);

    // Un gasto nuevo se descuenta del total ajustado.
    await expenses.add('Comida', 50, DateTime(2026, 10, 8), 'Pan');
    all = await expenses.queryAll().first;
    // Un gasto sin "quién pagó" se reparte entre los dos.
    expect(cashSummary(incomes, all, saved, 2).total, 2950);
  });

  test('ingresos semanales, quincenales y mensuales (freelance)', () async {
    // Proyecto nuevo: le pagan cada viernes desde el jueves 1 de octubre.
    await finance.saveRecurring(
        const Recurring(type: RecurringType.income, person: 0,
            description: 'Proyecto web', amount: 300, day: DateTime.friday,
            frequency: Frequency.weekly),
        today: DateTime(2026, 10, 1));
    // Su pareja cobra cada quincena, desde el 10 de octubre.
    await finance.saveRecurring(
        const Recurring(type: RecurringType.income, person: 1,
            description: 'Sueldo', amount: 1500, day: 15,
            frequency: Frequency.biweekly),
        today: DateTime(2026, 10, 10));
    // Mantenimiento mensual de un cliente, el día 5.
    await finance.saveRecurring(
        const Recurring(type: RecurringType.income, person: 0,
            description: 'Mantenimiento', amount: 200, day: 5),
        today: DateTime(2026, 10, 1));

    await finance.applyRecurring(today: DateTime(2026, 10, 20));
    await finance.applyRecurring(today: DateTime(2026, 10, 20));
    final incomes = await finance.watchAllIncomes().first;
    String show(String what) => (incomes
            .where((i) => i.description == what)
            .map((i) => '${i.day}/${i.month}')
            .toList()
          ..sort())
        .join(' ');
    expect(show('Proyecto web'), '16/10 2/10 9/10'); // viernes 2, 9 y 16
    expect(show('Sueldo'), '15/10');
    expect(show('Mantenimiento'), '5/10');

    // Lo de la app a una fecha solo cuenta los ingresos que ya llegaron.
    final until10 = cashSummaryUntil(
        incomes, const [], null, 2, DateTime(2026, 10, 10));
    expect(until10.income, 300 + 300 + 200); // 2/10, 9/10 y 5/10
  });

  test('fin de semana: el pago pasa al lunes o se adelanta al viernes', () async {
    // El 3 de octubre de 2026 es sábado.
    expect(shiftWeekend(DateTime(2026, 10, 3), WeekendShift.next),
        DateTime(2026, 10, 5));
    expect(shiftWeekend(DateTime(2026, 10, 3), WeekendShift.previous),
        DateTime(2026, 10, 2));
    expect(shiftWeekend(DateTime(2026, 10, 6), WeekendShift.next),
        DateTime(2026, 10, 6)); // martes: no cambia

    // Seguro del carro el 3 de cada mes; si cae fin de semana, al lunes.
    await finance.saveRecurring(
        const Recurring(type: RecurringType.expense, person: 0,
            category: 'Transporte', description: 'Seguro del carro',
            amount: 200, day: 3, weekendShift: WeekendShift.next),
        today: DateTime(2026, 10, 20));
    expect((await expenses.queryAll().first).single.day, 5);

    // Quincena que se adelanta al viernes: el 15/11/2026 es domingo.
    const salary = Recurring(type: RecurringType.income, person: 1,
        description: 'Sueldo', amount: 1500, day: 15,
        frequency: Frequency.biweekly, weekendShift: WeekendShift.previous);
    expect(FinanceRepository.occurrences(salary, 2026, 11).map((d) => d.day),
        [13, 30]);
  });

  test('alquiler con fecha variable: queda pendiente hasta confirmarlo',
      () async {
    await finance.saveRecurring(
        const Recurring(type: RecurringType.expense, person: 0,
            category: 'Vivienda', description: 'Alquiler', amount: 1000,
            day: 7, confirm: true),
        today: DateTime(2026, 10, 2));
    await finance.applyRecurring(today: DateTime(2026, 10, 20));
    expect(await expenses.queryAll().first, isEmpty); // no se registra solo

    final items = await finance.watchRecurring().first;
    var pending =
        FinanceRepository.pendingConfirmations(items, {}, 10, 2026);
    expect(pending.single.description, 'Alquiler');

    // Lo cobraron el 12 y fueron 1050.
    await finance.confirmRecurring(
        pending.single, 1050, DateTime(2026, 10, 12), 10, 2026);
    final paid = (await expenses.queryAll().first).single;
    expect('${paid.day}/${paid.month} ${paid.value}', '12/10 1050.0');
    pending = FinanceRepository.pendingConfirmations(
        items, {paid.id}, 10, 2026);
    expect(pending, isEmpty);
  });

  test('alquiler que pasa a fecha variable: vuelve a quedar sin pagar',
      () async {
    final today = DateTime(2026, 10, 21);
    await finance.saveRecurring(
        const Recurring(type: RecurringType.expense, person: 0,
            category: 'Vivienda', description: 'Alquiler', amount: 800,
            day: 1),
        today: DateTime(2026, 10, 1));
    expect((await expenses.queryAll().first).single.value, 800);
    // Dijo tener 2000 cuando la app ya daba el alquiler por pagado.
    await finance.setStartingMoney([2000], today: today);

    final rent = (await finance.watchRecurring().first).single;
    await finance.updateRecurring(
        rent,
        const Recurring(type: RecurringType.expense, person: 0,
            category: 'Vivienda', description: 'Alquiler', amount: 800,
            day: 1, confirm: true),
        today: today);
    expect(await expenses.queryAll().first, isEmpty);
    final items = await finance.watchRecurring().first;
    final pending = FinanceRepository.pendingConfirmations(items, {}, 10, 2026);
    expect(pending.single.description, 'Alquiler');
    // Todavía lo tiene: no cuenta como gastado.
    expect(await finance.freeMoneyToday(today: today), 2800);

    // Ya pagué: ahora sí se descuenta.
    await finance.confirmRecurring(pending.single, 800, today, 10, 2026);
    expect(await finance.freeMoneyToday(today: today), 2000);
    // Deshacer lo deja como estaba, por más veces que se haga.
    for (var i = 0; i < 3; i++) {
      await finance.unconfirmRecurring(pending.single, today: today);
      expect(await finance.freeMoneyToday(today: today), 2800);
      await finance.confirmRecurring(pending.single, 800, today, 10, 2026);
      expect(await finance.freeMoneyToday(today: today), 2000);
    }
  });

  test('pagos fijos: esperan el "Ya pagué" y se pueden desmarcar', () async {
    await finance.saveRecurring(
        Recurring(type: RecurringType.expense, person: 0,
            category: 'Vivienda', description: 'Alquiler', amount: 800,
            day: 1),
        today: DateTime(now.year, now.month, 1));
    expect((await expenses.queryAll().first).single.value, 800);

    // Lo que se anotó solo este mes vuelve a quedar sin pagar.
    await finance.fixedPaymentsWaitForPaid();
    final rent = (await finance.watchRecurring().first).single;
    expect(rent.confirm, isTrue);
    expect(await expenses.queryAll().first, isEmpty);

    // "Ya pagué" con la fecha de hoy; "No lo pagué" lo vuelve a quitar.
    await finance.confirmRecurring(rent, 800, now, now.month, now.year);
    final expense = (await expenses.queryAll().first).single;
    expect(expense.day, now.day);
    await finance.unconfirmRecurring(rent);
    expect(await expenses.queryAll().first, isEmpty);
    // Una sola vez: no vuelve a quitar lo que ya marcaron.
    await finance.confirmRecurring(rent, 800, now, now.month, now.year);
    await finance.fixedPaymentsWaitForPaid();
    expect(await expenses.queryAll().first, hasLength(1));
  });

  test('ahorro: no se puede apartar la plata del alquiler sin pagar', () async {
    final today = DateTime(now.year, now.month, now.day);
    await finance.saveRecurring(
        Recurring(type: RecurringType.expense, person: 0,
            category: 'Vivienda', description: 'Alquiler', amount: 800,
            day: 1, confirm: true),
        today: today);
    await finance.setStartingMoney([1500], today: today);
    expect(await finance.freeMoneyToday(today: today), 1500);
    // De 1500, 800 son del alquiler: solo 700 se pueden ahorrar.
    expect(await finance.freeForSavings(today: today), 700);

    final rent = (await finance.watchRecurring().first).single;
    await finance.confirmRecurring(rent, 800, today, now.month, now.year);
    expect(await finance.freeForSavings(today: today), 700);
  });

  test('avisos: día de pago fijo sin pagar y día de sueldo', () {
    // Miércoles 21 de octubre, 10 a. m.
    final now = DateTime(2026, 10, 21, 10);
    const rent = Recurring(id: 'r', type: RecurringType.expense, person: 0,
        category: 'Vivienda', description: 'Alquiler', amount: 800,
        day: 1, confirm: true);
    const phone = Recurring(id: 'c', type: RecurringType.expense, person: 0,
        category: 'Servicios', description: 'Celular', amount: 100,
        day: 25, confirm: true);
    const salary = Recurring(id: 's', type: RecurringType.income, person: 1,
        description: 'Sueldo', amount: 500, day: 5,
        frequency: Frequency.weekly);
    final reminders = Reminder.upcoming(
      [rent, phone, salary],
      {'rec_c_2026-10'}, // el celular de octubre ya se pagó
      ['Paul', 'Marisol'],
      now,
    );
    String show(Reminder r) => '${r.when.day}/${r.when.month} ${r.title}';
    expect(reminders.take(5).map(show), [
      // El alquiler del 1 sigue sin pagar: se recuerda mañana.
      '22/10 ¿Ya pagaste Alquiler?',
      '23/10 Hoy llega el sueldo de Marisol',
      '30/10 Hoy llega el sueldo de Marisol',
      '1/11 Hoy toca pagar Alquiler',
      '6/11 Hoy llega el sueldo de Marisol',
    ]);
    // El celular de octubre ya está pagado: solo avisa el de noviembre.
    expect(reminders.where((r) => r.title.contains('Celular')).map(show),
        ['25/11 Hoy toca pagar Celular']);
    expect(reminders.every((r) => r.when.hour == 9), isTrue);
  });

  test('pareja: una categoría nueva se crea cuando la otra persona acepta',
      () async {
    const gym = CustomCategory(
        name: 'Gimnasio', icon: 'otros', color: Color(0xFF22C55E));
    const pets = CustomCategory(
        name: 'Mascota', icon: 'otros', color: Color(0xFFF59E0B));
    // Paul (0) propone; todavía no existe.
    await finance.requestCategory(gym, 0);
    expect((await finance.watchCategorySettings().first).custom, isEmpty);
    var requests = await finance.watchCategoryRequests().first;
    expect(requests.single.pending, isTrue);
    expect(requests.single.by, 0);

    // Marisol acepta: se crea para los dos y la propuesta desaparece.
    await finance.answerCategoryRequest(requests.single, true);
    expect((await finance.watchCategorySettings().first).custom.single.name,
        'Gimnasio');
    expect(await finance.watchCategoryRequests().first, isEmpty);

    // Otra que Marisol rechaza: no se crea y Paul ve el rechazo.
    await finance.requestCategory(pets, 0);
    requests = await finance.watchCategoryRequests().first;
    await finance.answerCategoryRequest(requests.single, false);
    expect((await finance.watchCategorySettings().first).custom, hasLength(1));
    requests = await finance.watchCategoryRequests().first;
    expect(requests.single.status, 'rejected');
    await finance.deleteCategoryRequest(requests.single.id);
    expect(await finance.watchCategoryRequests().first, isEmpty);
  });

  test('los fijos se ponen al día si no se abrió la app varios meses', () async {
    await store.add(
        'recurring',
        const Recurring(
                type: RecurringType.income,
                person: 0,
                description: 'Sueldo',
                amount: 3000,
                day: 1,
                lastApplied: '2026-7')
            .toMap());
    await finance.applyRecurring(today: DateTime(2026, 10, 2));
    final incomes = await finance.watchAllIncomes().first;
    expect(incomes.map((i) => i.month), unorderedEquals([8, 9, 10]));
  });

  test('los datos de prueba completan meses pasados sin tocar lo del usuario',
      () async {
    final today = DateTime(2026, 10, 19);
    // Lo que el usuario ya tenía configurado y registrado.
    await finance.setPeople(['Ana', 'Luis']);
    await finance.saveRecurring(
        const Recurring(type: RecurringType.income, person: 0,
            description: 'Sueldo', amount: 4000, day: 1),
        today: today);
    await finance.saveRecurring(
        const Recurring(type: RecurringType.expense, person: 1,
            category: 'Servicios', description: 'Luz', amount: 130, day: 18),
        today: today);
    await finance.saveRecurring(
        const Recurring(type: RecurringType.allowance, person: 1,
            description: 'Propina de Luis', amount: 100, day: 15,
            biweekly: true),
        today: today);
    await finance.addGoal('Auto', 20000);
    await expenses.add('Comida', 55, DateTime(2026, 10, 18), 'Almuerzo');
    final before = await expenses.queryAll().first;
    final incomesBefore = await finance.watchAllIncomes().first;

    await addDemoHistory(store, finance, today: today);
    await addDemoHistory(store, finance, today: today); // no duplica

    final all = await expenses.queryAll().first;
    final demo = all.where((e) => e.id.startsWith(demoPrefix)).toList();
    expect(demo.map((e) => e.month).toSet(), {1, 2, 3, 4, 5, 6, 7, 8, 9});
    // Lo del usuario sigue igual.
    expect(all.where((e) => !e.id.startsWith(demoPrefix)).map((e) => e.id),
        unorderedEquals(before.map((e) => e.id)));
    expect(await finance.watchPeople().first, ['Ana', 'Luis']);
    // Su luz fija se repite cada mes y no se inventa otra.
    expect(demo.where((e) => e.description == 'Luz').length, 9);
    expect(demo.where((e) => e.category == propinaCategory).length, 18);
    expect(demo.where((e) => e.goalId != null).length, 9);
    final incomes = await finance.watchAllIncomes().first;
    expect(incomes.where((i) => i.month < 10 && i.amount == 4000).length, 9);

    final pdf = await buildMonthReport(
      month: 9,
      year: 2026,
      expenses: all.where((e) => e.month == 9).toList(),
      incomes: incomes.where((i) => i.month == 9).toList(),
      people: await finance.watchPeople().first,
    );
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

    final yearPdf = await buildYearReport(
      year: 2026,
      expenses: all,
      incomes: incomes,
      people: await finance.watchPeople().first,
    );
    expect(String.fromCharCodes(yearPdf.take(5)), '%PDF-');

    // Quitar los datos de prueba deja todo como estaba.
    await removeDemoData(store);
    expect((await expenses.queryAll().first).map((e) => e.id),
        unorderedEquals(before.map((e) => e.id)));
    expect((await finance.watchAllIncomes().first).length, incomesBefore.length);
  });
}
