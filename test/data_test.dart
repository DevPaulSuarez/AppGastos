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

  test('los fijos se registran una sola vez por mes', () async {
    await finance.saveRecurring(const Recurring(
        type: RecurringType.income,
        person: 0,
        description: 'Sueldo',
        amount: 3000,
        day: 1));
    await finance.saveRecurring(const Recurring(
        type: RecurringType.expense,
        person: 1,
        category: 'Servicios',
        description: 'Alquiler',
        amount: 1200,
        day: 31));
    await finance.applyRecurring();
    await finance.applyRecurring();

    final incomes = await finance.watchIncomes(now.month, now.year).first;
    expect(incomes.length, 1);
    expect(incomes.single.amount, 3000);

    final month = await expenses.queryByMonth(now.month, now.year).first;
    expect(month.length, 1);
    expect(month.single.paidBy, 1);
    expect(month.single.day, lessThanOrEqualTo(31));
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
    await finance.applyRecurring(today: DateTime(2026, 11, 2));

    final all = await expenses.queryAll().first;
    expect(all.map((e) => '${e.day}/${e.month} ${e.value} ${e.paidBy}'),
        unorderedEquals(['5/10 1100.0 1', '5/11 1100.0 1']));
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
