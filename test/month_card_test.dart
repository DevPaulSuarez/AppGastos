import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/month_widge.dart';
import 'package:primera_app_curso/models.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('la tarjeta del mes muestra lo que falta y el cierre', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final later = DateTime(now.year, now.month, now.day + 1);

    await tester.pumpWidget(
      Provider.value(
        value: FinanceRepository(LocalStore()),
        child: MaterialApp(
          home: Scaffold(
            body: MonthWidget(
              month: now.month - 1,
              year: now.year,
              incomes: 1000,
            incomeItems: [
              Income(
                id: 'i',
                person: 0,
                description: 'Bono',
                amount: 1000,
                day: 1,
                month: now.month,
                year: now.year,
              ),
            ],
              budgets: const {},
              people: const ['Ana', 'Luis'],
              pendingLoans: const [],
              days: 31,
              documents: [
                Expense(
                  id: 'c',
                  category: 'Comida',
                  value: 200,
                  day: now.day,
                  month: now.month,
                  year: now.year,
                  description: 'Mercado',
                ),
              ],
              upcoming: [
                Upcoming(
                  const Recurring(
                    type: RecurringType.income,
                    person: 0,
                    description: 'Sueldo',
                    amount: 3000,
                    day: 30,
                  ),
                  later,
                ),
                Upcoming(
                  const Recurring(
                    type: RecurringType.expense,
                    person: 1,
                    category: 'Vivienda',
                    description: 'Alquiler',
                    amount: 1200,
                    day: 25,
                    confirm: true,
                  ),
                  later,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tienen disponible'), findsOneWidget);
    // 1000 − 200
    expect(find.text('S/. 800.00'), findsOneWidget);
    // 800 + 3000 − 1200
    expect(
      find.textContaining('A fin de mes les quedará S/. 2600.00',
          findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Lo que falta este mes'), findsOneWidget);
    // Cerrados se ve el resumen; al tocarlos se abre el detalle.
    expect(find.text('Sueldo · Ana'), findsNothing);
    expect(find.text('Por cobrar S/. 3000.00 · por pagar S/. 1200.00'),
        findsOneWidget);
    await tester.tap(find.text('Lo que entró este mes'));
    await tester.tap(find.text('Lo que falta este mes'));
    await tester.pumpAndSettle();
    expect(find.text('Sueldo · Ana'), findsOneWidget);
    expect(find.text('Lo que entró este mes'), findsOneWidget);
    expect(find.text('+ S/. 1000.00'), findsOneWidget);
    expect(find.text('Ya pagué'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
