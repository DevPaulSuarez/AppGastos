import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primera_app_curso/pages/ui/day_picker.dart';

void main() {
  Future<int?> pump(WidgetTester tester, {DateTime? month, int? maxDay}) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Mismo ancho que en el diálogo.
          body: SizedBox(
            width: 320,
            child: DayGrid(
              selected: 1,
              month: month,
              maxDay: maxDay,
              onSelected: (day) => picked = day,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('20'));
    return picked;
  }

  testWidgets('pagos que se repiten: días del 1 al 31', (tester) async {
    expect(await pump(tester), 20);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('L'), findsNothing);
  });

  testWidgets('mes real: con días de la semana y sin días futuros', (
    tester,
  ) async {
    // Noviembre 2026 tiene 30 días; el 20 todavía no llega.
    expect(await pump(tester, month: DateTime(2026, 11), maxDay: 10), isNull);
    expect(find.text('31'), findsNothing);
    expect(find.text('Noviembre 2026'), findsOneWidget);
    expect(find.text('J'), findsOneWidget);
    await tester.tap(find.text('5'));
  });
}
