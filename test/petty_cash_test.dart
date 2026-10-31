import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primera_app_curso/cash.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/month_widge.dart';
import 'package:primera_app_curso/petty_cash.dart';
import 'package:primera_app_curso/report.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_store.dart';

Income _income(double amount, int day, int month, int year) => Income(
  id: 'i$day-$month',
  person: 0,
  description: 'Sueldo',
  amount: amount,
  day: day,
  month: month,
  year: year,
);

Expense _expense(double value, int day, int month, int year) => Expense(
  id: 'e$day-$month-$value',
  category: 'Vivienda',
  value: value,
  day: day,
  month: month,
  year: year,
  description: 'Alquiler',
);

void main() {
  group('PettyCashMonth', () {
    // Septiembre: entró 2000 y se gastó 1500 → sobraron 500.
    // Octubre: el 5 pagan 800 de alquiler sacando de la caja; el 15 llega
    // el sueldo (2000) y devuelven.
    final incomes = [_income(2000, 15, 9, 2026), _income(2000, 15, 10, 2026)];
    final expenses = [_expense(1500, 10, 9, 2026), _expense(800, 5, 10, 2026)];
    final check = CashCheck(
      offsets: const [1000],
      realAmounts: const [1000],
      date: DateTime(2026, 9, 1),
    );
    const moves = [
      PettyCashMove(amount: 800, taken: true, year: 2026, month: 10, day: 5),
      PettyCashMove(amount: 500, taken: false, year: 2026, month: 10, day: 15),
    ];

    test('lo que sobra un mes entra a la caja del siguiente', () {
      final sept = PettyCashMonth.of(
        incomes,
        expenses,
        check,
        1,
        moves,
        9,
        2026,
      );
      expect(sept.start, 1000);
      expect(sept.result, 500);
      expect(sept.end, 1500);
      expect(sept.moves, isEmpty);

      final oct = PettyCashMonth.of(
        incomes,
        expenses,
        check,
        1,
        moves,
        10,
        2026,
      );
      expect(oct.start, 1500);
      expect(oct.taken, 800);
      expect(oct.returned, 500);
      expect(oct.owed, 300);
      expect(oct.inBox, 1200);
      // Del mes: 2000 − 800 = 1200, más lo que sacaron y no devolvieron.
      expect(oct.result, 1200);
      expect(oct.inHand, 1500);
      // Al cerrar, el sobrante entra y cubre lo que faltaba devolver.
      expect(oct.end, 2700);
    });

    test('los informes en PDF incluyen la caja chica', () async {
      final months = [
        for (final m in [9, 10])
          PettyCashMonth.of(incomes, expenses, check, 1, moves, m, 2026),
      ];
      final month = await buildMonthReport(
        month: 10,
        year: 2026,
        expenses: expenses.where((e) => e.month == 10).toList(),
        incomes: incomes.where((i) => i.month == 10).toList(),
        people: const ['Yo'],
        pettyCash: [months.last],
      );
      final year = await buildYearReport(
        year: 2026,
        expenses: expenses,
        incomes: incomes,
        people: const ['Yo'],
        pettyCash: months,
      );
      expect(month, isNotEmpty);
      expect(year, isNotEmpty);
    });

    test('los movimientos se guardan y se leen', () async {
      SharedPreferences.setMockInitialValues({});
      final finance = FinanceRepository(MemoryStore());
      expect(await finance.watchPettyCashOn().first, isFalse);
      await finance.setPettyCashOn(true);
      expect(await finance.watchPettyCashOn().first, isTrue);
      await finance.addPettyCashMove(moves.first);
      final saved = await finance.watchPettyCash().first;
      expect(saved.single.amount, 800);
      expect(saved.single.taken, isTrue);
      await finance.deletePettyCashMove(saved.single.id);
      expect(await finance.watchPettyCash().first, isEmpty);
    });

    test('corregir lo que hay en la caja mueve el punto de partida', () async {
      SharedPreferences.setMockInitialValues({});
      final finance = FinanceRepository(MemoryStore());
      await finance.setPettyCashAmount(700, 500);
      expect((await finance.watchCashCheck().first)!.offsets.first, 200);
      await finance.setPettyCashAmount(600, 700);
      expect((await finance.watchCashCheck().first)!.offsets.first, 100);
    });
  });

  testWidgets('con caja chica el mes empieza de cero y lo sacado se devuelve', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();

    await tester.pumpWidget(
      Provider.value(
        value: FinanceRepository(LocalStore()),
        child: MaterialApp(
          home: Scaffold(
            body: MonthWidget(
              month: now.month - 1,
              year: now.year,
              incomes: 0,
              budgets: const {},
              people: const ['Ana', 'Luis'],
              pendingLoans: const [],
              days: 31,
              // Esto ya no se suma: está en la caja.
              carriedOver: 1500,
              pettyCash: PettyCashMonth(
                month: now.month,
                year: now.year,
                start: 1500,
                result: -800,
                moves: [
                  PettyCashMove(
                    amount: 800,
                    taken: true,
                    year: now.year,
                    month: now.month,
                    day: now.day,
                  ),
                ],
              ),
              documents: [_expense(800, now.day, now.month, now.year)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tienen los 800 que sacaron, pero hay que devolverlos.
    expect(find.text('Libre para gastar'), findsOneWidget);
    expect(find.text('−S/. 800.00'), findsOneWidget);
    expect(
      find.text(
        'De S/. 0.00 que tienen, S/. 800.00 están separados para '
        'devolver a la caja chica',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Les faltan S/. 800.00 para devolver a la caja chica'),
      findsOneWidget,
    );
    expect(find.text('Caja chica'), findsOneWidget);
    expect(find.text('S/. 700.00'), findsOneWidget);
    expect(
      find.text('Sacaron S/. 800.00 · falta devolver S/. 800.00'),
      findsOneWidget,
    );
    expect(find.text('Ya devolví'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
