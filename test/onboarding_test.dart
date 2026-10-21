import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/pages/setup_page.dart';
import 'package:primera_app_curso/pages/ui/day_picker.dart';
import 'package:primera_app_curso/pages/welcome_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('primera vez: pareja, moneda, sueldo semanal y quincenal', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final finance = FinanceRepository(LocalStore());
    await _pumpApp(tester, finance);
    await tester.pumpAndSettle();

    await tester.tap(find.text('En pareja'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo se llaman?'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Tu nombre'), 'Ana');
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre de tu pareja'),
      'Luis',
    );
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(await finance.watchPeople().first, ['Ana', 'Luis']);
    expect(find.text('¿En qué moneda manejan su dinero?'), findsOneWidget);
    await tester.tap(find.text('Dólar estadounidense'));
    await tester.pumpAndSettle();
    expect((await finance.watchCurrencySettings().first).code, 'USD');
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo reciben su dinero?'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Luis'), findsOneWidget);

    // Ana: lo normal, cada semana (viene elegido el viernes).
    await tester.tap(find.text('Agregar ingreso').first);
    await tester.pumpAndSettle();
    expect(find.text('Todos los viernes'), findsOneWidget);
    expect(find.text('Quincena'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'Cuánto te pagan cada semana'),
      '500',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('US\$ 500.00'), findsOneWidget);
    expect(find.textContaining('cada semana (viernes)'), findsOneWidget);

    // Luis cobra por quincena: se elige con "¿No te pagan cada semana?".
    await tester.tap(find.text('Agregar ingreso').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('¿No te pagan cada semana?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quincena'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Cuánto te pagan cada vez'),
      '1500',
    );
    // Los días se eligen en el mini calendario.
    Future<void> pickDay(String field, int day) async {
      await tester.tap(find.text(field));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(DayGrid), matching: find.text('$day')),
      );
      await tester.pumpAndSettle();
    }

    await pickDay('Primer pago', 10);
    await pickDay('Segundo pago', 25);
    expect(find.text('Día 10'), findsOneWidget);
    expect(find.text('Día 25'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('US\$ 1500.00'), findsOneWidget);
    expect(
      find.textContaining('dos veces al mes (días 10 y 25)'),
      findsOneWidget,
    );

    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('¿Qué pagan cada mes?'), findsOneWidget);

    await tester.tap(find.text('Alquiler'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Monto'),
      '1200',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    // 500 por semana ≈ 2166.67 al mes + quincena de 1500 = 3000; menos
    // 1200 de alquiler.
    expect(find.text('US\$ 5166.67'), findsOneWidget);
    expect(find.text('US\$ 3966.67'), findsOneWidget);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cuánto dinero tienen hoy?'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Banco + efectivo'),
      '2000',
    );
    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();
    expect(find.text('Inicio'), findsOneWidget);
  });

  testWidgets('cuenta individual: se le habla de tú y no pide pareja', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final finance = FinanceRepository(LocalStore());
    await _pumpApp(tester, finance);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Solo yo'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo te llamas?'), findsOneWidget);
    expect(find.text('Nombre de tu pareja'), findsNothing);
    // Sin escribir nombre queda "Yo".
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
    }
    expect(find.text('¿Qué pagas cada mes?'), findsOneWidget);
    expect(await finance.watchPeople().first, ['Yo']);
  });
}

/// La app desde la primera pantalla, en tamaño de teléfono.
Future<void> _pumpApp(WidgetTester tester, FinanceRepository finance) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Provider.value(
      value: finance,
      child: MaterialApp(
        home: StreamBuilder<AccountStep>(
          stream: finance.watchAccountStep(),
          builder: (context, snapshot) => switch (snapshot.data) {
            AccountStep.setup => const SetupPage(),
            AccountStep.ready => const Text('Inicio'),
            _ => const WelcomePage(),
          },
        ),
      ),
    ),
  );
}
