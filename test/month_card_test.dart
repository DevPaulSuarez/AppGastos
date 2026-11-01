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
    final rent = Recurring(
      type: RecurringType.expense,
      person: 1,
      category: 'Vivienda',
      description: 'Alquiler',
      amount: 1200,
      day: now.day,
      confirm: true,
    );

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
                // Ya llegó su día: pide el "Ya pagué".
                Upcoming(rent, DateTime(now.year, now.month, now.day)),
              ],
              fixedPayments: [FixedPayment(rent, null)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tienen 1000 − 200 = 800, pero el alquiler (1200) está separado.
    expect(find.text('Libre para gastar'), findsOneWidget);
    expect(find.text('−S/. 400.00'), findsOneWidget);
    expect(
      find.text(
        'De S/. 800.00 que tienen, S/. 1200.00 están separados para los '
        'pagos del mes',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Les faltan S/. 400.00 para los pagos del mes'),
      findsOneWidget,
    );
    // 800 + 3000 − 1200
    expect(
      find.textContaining('A fin de mes les quedará S/. 2600.00',
          findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Lo que falta este mes'), findsOneWidget);
    // Cerrados se ve el resumen; al tocarlos se abre el detalle.
    expect(find.text('Sueldo · Ana'), findsNothing);
    // El alquiler va en "Pagos fijos", no se repite aquí.
    expect(find.text('Por cobrar S/. 3000.00'), findsOneWidget);
    expect(find.text('Pagos fijos'), findsOneWidget);
    expect(find.text('0 de 1 pagados'), findsOneWidget);
    await tester.tap(find.text('Lo que entró este mes'));
    await tester.tap(find.text('Lo que falta este mes'));
    await tester.pumpAndSettle();
    expect(find.text('Sueldo · Ana'), findsOneWidget);
    expect(find.text('Lo que entró este mes'), findsOneWidget);
    // En pareja van por persona: cerrado se ve su total; al tocarla, el
    // detalle.
    expect(find.text('Ana S/. 1000.00 · Luis S/. 0.00'), findsOneWidget);
    expect(find.text('+ S/. 1000.00'), findsNothing);
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.text('+ S/. 1000.00'), findsOneWidget);
    // Con los ingresos abiertos, lo que falta queda más abajo.
    await tester.scrollUntilVisible(
      find.text('Ya pagué'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ya pagué'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
