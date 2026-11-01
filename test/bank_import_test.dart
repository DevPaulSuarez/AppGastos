import 'package:flutter_test/flutter_test.dart';
import 'package:primera_app_curso/bank_import.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/models.dart';

const _csv = '''"Transaction List","Sep 01, 2026 to Sep 30, 2026"
"Anytime Checking","******0000"
"Balance as of 09/30/2026","100.00"
"Date","Account","Account Number","Account Type","Description","Check #","Memo","Transaction Code","Credit","Debit"
"09/25/2026","Chk","***","Chk","ARA Paperless PAYROLL (ARA Paperless TEST)","","","222","480.00",""
"09/24/2026","Chk","***","Chk","5983 POS PURCHASE WM SUPERCENTER #100 (WM SUPERCENTER SPRINGFIELD XX US)","","","821","","-40.10"
"09/23/2026","Chk","***","Chk","ONLINE XFER FROM DDA PARTNER ID:1 (ONLINE XFER FROM DDA PARTNER)","","","219","50.00",""
"09/22/2026","Chk","***","Chk","5983 COSTCO GAS #200 (COSTCO GAS SPRINGFIELD XX US)","","","719","","-45.00"
"09/21/2026","Chk","***","Chk","5983 SQ *SMILE DENTAL (SQ SMILE DENTAL SPRINGFIELD XX US)","","","719","","-200.00"
"09/20/2026","Chk","***","Chk","O'REILLY 300 (O'REILLY SPRINGFIELD)","","","221","30.00",""
"09/19/2026","Chk","***","Chk","O'REILLY 300 (O'REILLY SPRINGFIELD)","","","719","","-30.00"
"09/18/2026","Chk","***","Chk","SMITHS FOOD (SMITHS FOOD SPRINGFIELD XX US)","","","821","","-20.00"
"","","","","8 items","","","","",""
''';

Expense _e(String cat, double v, int day, String name, {int paidBy = 0}) =>
    Expense(
      id: '$name$day',
      category: cat,
      value: v,
      day: day,
      month: 9,
      year: 2026,
      description: name,
      paidBy: paidBy,
    );

void main() {
  test('lee el CSV del banco', () {
    final rows = parseBankCsv(_csv);
    expect(rows.length, 8);
    expect(rows.first.date, DateTime(2026, 9, 25));
    expect(rows.first.amount, 480.00);
    expect(rows[1].amount, -40.10);
    expect(rows[1].merchant, 'WM SUPERCENTER SPRINGFIELD XX US');
  });

  test('un archivo sin columnas conocidas avisa', () {
    expect(() => parseBankCsv('a,b\n1,2'), throwsFormatException);
  });

  test('adivina nombre y categoría', () {
    final rows = parseBankCsv(_csv);
    final g = rows.map(guessBankRow).toList();
    expect(g[0].kind, BankKind.income);
    expect(g[0].name, 'Sueldo');
    expect((g[1].name, g[1].category), ('Walmart', 'Comida'));
    expect(g[2].kind, BankKind.transfer);
    expect((g[3].name, g[3].category), ('Gasolina Costco', 'Transporte'));
    expect(g[4].category, 'Salud');
  });

  test('compara con la app', () {
    final rows = parseBankCsv(_csv);
    final check = compareBank(
      rows: rows,
      expenses: [
        _e('Comida', 40.10, 24, 'Walmart'),
        // Mismo comercio, otro monto.
        _e('Comida', 2.00, 18, "Smith's"),
        // En otra categoría que la esperada.
        _e('Otros', 45.00, 22, 'Gasolina Costco'),
        // Solo en la app.
        _e('Iglesia', 30, 14, 'Ofrenda'),
        // De la otra persona: no se cuenta como "solo en la app".
        _e('Comida', 12, 15, 'Pan', paidBy: 1),
      ],
      incomes: const [
        Income(
          id: 'r',
          person: 0,
          description: 'Sueldo',
          amount: 480.00,
          day: 25,
          month: 9,
          year: 2026,
        ),
      ],
      person: 0,
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30),
    );
    expect(check.matched.length, 3);
    expect(check.amountDiffers.single.move.name, "Smith's");
    expect(check.categoryDiffers.single.guess.category, 'Transporte');
    expect(check.missing.single.guess.category, 'Salud');
    expect(check.onlyInApp.single.name, 'Ofrenda');
    // El envío entre ustedes y la compra devuelta no se cuentan.
    expect(check.ignored.length, 3);
    expect(
      check.ignored.where((m) => m.guess.name == 'Compra devuelta').length,
      2,
    );
  });

  test('aprende el nombre y la categoría de lo que coincide', () {
    final rows = parseBankCsv(_csv);
    final check = compareBank(
      rows: rows,
      expenses: [_e('Comida', 40.10, 24, 'Súper Walmart')],
      incomes: const [],
      person: 0,
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30),
    );
    final learned = learnFrom(check.matched);
    final again = guessBankRow(rows[1], learned: learned);
    expect(again.name, 'Súper Walmart');
  });
}
