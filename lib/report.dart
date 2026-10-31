import 'dart:math';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/petty_cash.dart';
import 'package:primera_app_curso/utils.dart';

const _green = PdfColor.fromInt(0xFF059669);
const _incomeColor = PdfColor.fromInt(0xFF16A34A);
const _expenseColor = PdfColor.fromInt(0xFFDC2626);
const _savingsColor = PdfColor.fromInt(0xFF2563EB);
const _muted = PdfColor.fromInt(0xFF64748B);
const _surface = PdfColor.fromInt(0xFFF1F5F4);

PdfColor _pdfColor(String category) =>
    PdfColor.fromInt(categoryColor(category).toARGB32());

String _monthLabel(int month) {
  final name = monthNames[month - 1];
  return '${name[0]}${name.substring(1).toLowerCase()}';
}

/// Valores "redondos" para el eje del gráfico (0, 50, 100...).
List<double> _axisTicks(double maxValue) {
  if (maxValue <= 0) return [0, 10];
  final raw = maxValue / 4;
  final magnitude = pow(10, (log(raw) / ln10).floor()).toDouble();
  final step = [1, 2, 5, 10].map((m) => m * magnitude).firstWhere((s) => s >= raw);
  return [for (var v = 0.0; v <= maxValue + step; v += step) v];
}

pw.Widget _title(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _statBox(String label, double value, PdfColor color) => pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 3),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: _surface,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _muted)),
            pw.SizedBox(height: 3),
            pw.Text(pdfMoney(value),
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
      ),
    );

pw.Widget _header(String title, List<String> people) {
  final now = DateTime.now();
  final generated = '${now.day.toString().padLeft(2, '0')}/'
      '${now.month.toString().padLeft(2, '0')}/${now.year}';
  return pw.Column(children: [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('CONTROL DE GASTOS',
                  style: pw.TextStyle(
                      fontSize: 9,
                      color: _green,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.5)),
              pw.SizedBox(height: 2),
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 22, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(people.join(' y '), style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Generado el $generated',
                style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ],
        ),
      ],
    ),
    pw.Divider(color: _green, thickness: 2),
    pw.SizedBox(height: 8),
  ]);
}

pw.Widget _footer(pw.Context context) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _muted)),
    );

/// Dona y tabla con el gasto por categoría.
pw.Widget _categoriesSection(Map<String, double> byCategory) {
  final sorted = byCategory.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final total = sorted.fold(0.0, (a, e) => a + e.value);
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.SizedBox(
        width: 170,
        height: 170,
        child: pw.Chart(
          grid: pw.PieGrid(startAngle: -pi / 2),
          datasets: [
            for (final c in sorted)
              pw.PieDataSet(
                value: c.value,
                color: _pdfColor(c.key),
                innerRadius: 45,
                borderWidth: 1,
              ),
          ],
        ),
      ),
      pw.SizedBox(width: 24),
      pw.Expanded(
        child: pw.Column(
          children: [
            for (final c in sorted)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Row(children: [
                  pw.Container(
                    width: 9,
                    height: 9,
                    decoration: pw.BoxDecoration(
                      color: _pdfColor(c.key),
                      borderRadius: pw.BorderRadius.circular(2),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                      child: pw.Text(c.key,
                          style: const pw.TextStyle(fontSize: 10))),
                  pw.Text('${(c.value / total * 100).round()}%',
                      style: const pw.TextStyle(fontSize: 9, color: _muted)),
                  pw.SizedBox(
                    width: 80,
                    child: pw.Text(pdfMoney(c.value),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ),
                ]),
              ),
          ],
        ),
      ),
    ],
  );
}

/// Caja chica de un mes: con cuánto empezó, lo que sacaron prestado y
/// devolvieron, lo que dejó el mes y con cuánto terminó.
List<pw.Widget> _pettyCashMonthSection(PettyCashMonth box) {
  final now = DateTime.now();
  final current = box.month == now.month && box.year == now.year;
  pw.Widget line(String text, double value, {PdfColor? color, bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Row(children: [
          pw.Expanded(
              child: pw.Text(text,
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: bold ? pw.FontWeight.bold : null))),
          pw.Text(pdfMoney(value),
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: color)),
        ]),
      );
  return [
    _title('Caja chica'),
    pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(children: [
        line('Al empezar el mes', box.start),
        line('- Sacaron prestado', box.taken, color: _expenseColor),
        line('+ Devolvieron', box.returned, color: _incomeColor),
        if (current) ...[
          pw.Divider(color: PdfColors.grey400, height: 8),
          line('= Hoy en la caja', box.inBox, bold: true),
          if (box.owed > 0)
            line('Falta devolver este mes', box.owed, color: _expenseColor),
        ] else ...[
          line(box.inHand >= 0 ? '+ Sobrante del mes' : '- Faltante del mes',
              box.inHand.abs(),
              color: box.inHand >= 0 ? _incomeColor : _expenseColor),
          pw.Divider(color: PdfColors.grey400, height: 8),
          line('= Al terminar el mes', box.end, bold: true),
        ],
      ]),
    ),
    if (box.moves.isNotEmpty) ...[
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        headers: ['Día', 'Préstamo de la caja chica', 'Monto'],
        data: [
          for (final m in box.moves)
            [
              '${m.day}',
              m.taken ? 'Sacaron' : 'Devolvieron',
              '${m.taken ? '-' : '+'} ${pdfMoney(m.amount)}',
            ],
        ],
        headerStyle: _tableHeaderStyle,
        headerDecoration: _tableHeaderDecoration,
        cellStyle: const pw.TextStyle(fontSize: 9),
        oddRowDecoration: const pw.BoxDecoration(color: _surface),
        headerAlignments: {
          0: pw.Alignment.center,
          1: pw.Alignment.centerLeft,
          2: pw.Alignment.centerRight,
        },
        cellAlignments: {
          0: pw.Alignment.center,
          2: pw.Alignment.centerRight,
        },
        columnWidths: {
          0: const pw.FixedColumnWidth(28),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FixedColumnWidth(80),
        },
        border: null,
      ),
    ],
  ];
}

/// Caja chica mes a mes en el año.
List<pw.Widget> _pettyCashYearSection(List<PettyCashMonth> months) => [
      _title('Caja chica mes a mes'),
      pw.TableHelper.fromTextArray(
        headers: [
          'Mes',
          'Al empezar',
          'Sacaron',
          'Devolvieron',
          'Sobró / faltó',
          'Al terminar',
        ],
        data: [
          for (final m in months)
            [
              _monthLabel(m.month),
              pdfMoney(m.start),
              m.taken > 0 ? pdfMoney(m.taken) : '-',
              m.returned > 0 ? pdfMoney(m.returned) : '-',
              '${m.result < 0 ? '-' : '+'} ${pdfMoney(m.result.abs())}',
              pdfMoney(m.end),
            ],
        ],
        headerStyle: _tableHeaderStyle,
        headerDecoration: _tableHeaderDecoration,
        cellStyle: const pw.TextStyle(fontSize: 9),
        oddRowDecoration: const pw.BoxDecoration(color: _surface),
        headerAlignments: {
          0: pw.Alignment.centerLeft,
          for (var c = 1; c < 6; c++) c: pw.Alignment.centerRight,
        },
        cellAlignments: {
          for (var c = 1; c < 6; c++) c: pw.Alignment.centerRight,
        },
        border: null,
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Lo que sobra (o falta) cada mes entra a la caja al terminar el mes. '
          'Lo sacado se devuelve en el mismo mes.',
          style: const pw.TextStyle(fontSize: 9, color: _muted),
        ),
      ),
    ];

const _tableHeaderDecoration = pw.BoxDecoration(color: _green);
final _tableHeaderStyle = pw.TextStyle(
    fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white);

/// Informe del mes en PDF: resumen, gráficos, totales por persona y la lista
/// de todos los gastos.
Future<Uint8List> buildMonthReport({
  required int month,
  required int year,
  required List<Expense> expenses,
  required List<Income> incomes,
  required List<String> people,
  PdfPageFormat format = PdfPageFormat.a4,
  List<PettyCashMonth> pettyCash = const [],
}) async {
  double sum(Iterable<double> values) => values.fold(0.0, (a, b) => a + b);
  bool isSaving(Expense e) => e.category == ahorroCategory;
  bool isLoanMove(Expense e) => e.category == prestamoCategory;

  final spentList =
      expenses.where((e) => isSpendingCategory(e.category)).toList();
  final totalIncomes = sum(incomes.map((i) => i.amount));
  final spent = sum(spentList.map((e) => e.value));
  final saved = sum(expenses.where(isSaving).map((e) => e.value));
  final lent = sum(expenses.where(isLoanMove).map((e) => e.value));
  final leftover = totalIncomes - spent - saved - lent;

  final byCategory = <String, double>{};
  for (final e in spentList) {
    byCategory[e.category] = (byCategory[e.category] ?? 0) + e.value;
  }

  final days = daysInMonth(month, year);
  final perDay = List.generate(
      days,
      (i) => sum(
          spentList.where((e) => e.day == i + 1).map((e) => e.value)));

  final detail = [...expenses]
    ..sort((a, b) => a.day != b.day
        ? a.day.compareTo(b.day)
        : a.category.compareTo(b.category));


  final yTicks = _axisTicks(perDay.fold(0.0, max));
  final dayTicks = [0, 5, 10, 15, 20, 25, days + 1];

  final doc = pw.Document(
    title: 'Informe ${_monthLabel(month)} $year',
    author: 'Control de Gastos',
  );

  doc.addPage(pw.MultiPage(
    pageFormat: format,
    margin: const pw.EdgeInsets.all(32),
    footer: _footer,
    build: (context) => [
      _header('Informe de ${_monthLabel(month)} $year', people),

      // Resumen
      pw.Row(children: [
        _statBox('Ingresos', totalIncomes, _incomeColor),
        _statBox('Gastos', spent, _expenseColor),
        _statBox('Ahorrado', saved, _savingsColor),
        _statBox('Sobrante', leftover, leftover < 0 ? _expenseColor : _green),
      ]),
      if (totalIncomes > 0)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            leftover < 0
                ? 'Este mes se gastó más de lo que ingresó.'
                : 'Se usó el ${((spent + saved + lent) / totalIncomes * 100).round()}% '
                    'de los ingresos y sobraron ${pdfMoney(leftover)}.'
                    '${lent > 0 ? ' Incluye ${pdfMoney(lent)} prestados por cobrar.' : ''}',
            style: const pw.TextStyle(fontSize: 10, color: _muted),
          ),
        ),

      if (pettyCash.isNotEmpty) ..._pettyCashMonthSection(pettyCash.first),

      // Gasto por categoría
      if (byCategory.isNotEmpty) ...[
        pw.Column(children: [
          _title('Gastos por categoría'),
          _categoriesSection(byCategory),
        ]),

        // Gasto por día
        _title('Gasto por día'),
        pw.SizedBox(
          height: 150,
          child: pw.Chart(
            grid: pw.CartesianGrid(
              xAxis: pw.FixedAxis(dayTicks,
                  format: (v) => v == 0 || v > days ? '' : '${v.toInt()}',
                  textStyle: const pw.TextStyle(fontSize: 8, color: _muted),
                  divisions: false),
              yAxis: pw.FixedAxis(yTicks,
                  format: (v) => v.toStringAsFixed(0),
                  textStyle: const pw.TextStyle(fontSize: 8, color: _muted),
                  divisions: true,
                  divisionsColor: PdfColors.grey300,
                  divisionsDashed: true),
            ),
            datasets: [
              pw.BarDataSet(
                color: _green,
                width: 6,
                drawBorder: false,
                data: [
                  for (var i = 0; i < perDay.length; i++)
                    if (perDay[i] > 0)
                      pw.PointChartValue((i + 1).toDouble(), perDay[i]),
                ],
              ),
            ],
          ),
        ),
      ],

      // Por persona
      _title('Por persona'),
      pw.TableHelper.fromTextArray(
        headers: ['Persona', 'Ingresos', 'Pagó en gastos', '% del gasto', 'Propinas'],
        data: [
          for (var i = 0; i < people.length; i++)
            () {
              final paid = sum(
                  spentList.where((e) => e.paidBy == i).map((e) => e.value));
              final tips = sum(spentList
                  .where((e) => e.paidBy == i && e.category == propinaCategory)
                  .map((e) => e.value));
              return [
                people[i],
                pdfMoney(sum(incomes
                    .where((x) => x.person == i)
                    .map((x) => x.amount))),
                pdfMoney(paid),
                spent > 0 ? '${(paid / spent * 100).round()}%' : '-',
                pdfMoney(tips),
              ];
            }(),
        ],
        headerStyle: _tableHeaderStyle,
        headerDecoration: _tableHeaderDecoration,
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerAlignments: {
          0: pw.Alignment.centerLeft,
          for (var c = 1; c < 5; c++) c: pw.Alignment.centerRight,
        },
        cellAlignments: {
          for (var c = 1; c < 5; c++) c: pw.Alignment.centerRight,
        },
        border: null,
        rowDecoration: const pw.BoxDecoration(
            border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      ),

      // Detalle
      if (detail.isNotEmpty) ...[
        _title('Detalle de movimientos (${detail.length})'),
        pw.TableHelper.fromTextArray(
          headers: ['Día', 'Concepto', 'Categoría', 'Pagó', 'Monto'],
          data: [
            for (final e in detail)
              [
                '${e.day}',
                e.description,
                e.category == ahorroCategory
                    ? 'Ahorro'
                    : e.category == prestamoCategory
                        ? (e.loanId == null
                            ? 'Préstamo a ${e.owedBy}'
                            : 'Devolución')
                        : e.category,
                personName(people, e.paidBy),
                pdfMoney(e.value),
              ],
          ],
          headerStyle: _tableHeaderStyle,
          headerDecoration: _tableHeaderDecoration,
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          oddRowDecoration: const pw.BoxDecoration(color: _surface),
          headerAlignments: {
            0: pw.Alignment.center,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerLeft,
            4: pw.Alignment.centerRight,
          },
          cellAlignments: {
            0: pw.Alignment.center,
            4: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FixedColumnWidth(28),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FixedColumnWidth(70),
          },
          border: null,
        ),
      ],
    ],
  ));

  return doc.save();
}

/// Informe de un año completo: totales, mes a mes, categorías, por persona y
/// los gastos más grandes. Sirve también para años que ya no se navegan en
/// la app.
Future<Uint8List> buildYearReport({
  required int year,
  required List<Expense> expenses,
  required List<Income> incomes,
  required List<String> people,
  PdfPageFormat format = PdfPageFormat.a4,
  List<PettyCashMonth> pettyCash = const [],
}) async {
  double sum(Iterable<double> values) => values.fold(0.0, (a, b) => a + b);
  bool isSaving(Expense e) => e.category == ahorroCategory;
  bool isLoanMove(Expense e) => e.category == prestamoCategory;

  final spentList =
      expenses.where((e) => isSpendingCategory(e.category)).toList();
  final totalIncomes = sum(incomes.map((i) => i.amount));
  final spent = sum(spentList.map((e) => e.value));
  final saved = sum(expenses.where(isSaving).map((e) => e.value));
  final lent = sum(expenses.where(isLoanMove).map((e) => e.value));
  final leftover = totalIncomes - spent - saved - lent;

  final months = [
    for (var m = 1; m <= 12; m++)
      (
        month: m,
        incomes: sum(incomes.where((i) => i.month == m).map((i) => i.amount)),
        spent: sum(spentList.where((e) => e.month == m).map((e) => e.value)),
        saved: sum(expenses
            .where((e) => isSaving(e) && e.month == m)
            .map((e) => e.value)),
        lent: sum(expenses
            .where((e) => isLoanMove(e) && e.month == m)
            .map((e) => e.value)),
      ),
  ];
  final activeMonths =
      months.where((m) => m.incomes > 0 || m.spent > 0 || m.saved > 0).length;

  final byCategory = <String, double>{};
  for (final e in spentList) {
    byCategory[e.category] = (byCategory[e.category] ?? 0) + e.value;
  }
  final biggest = [...spentList]..sort((a, b) => b.value.compareTo(a.value));

  final yTicks = _axisTicks(months.fold(
      0.0, (a, m) => [a, m.incomes, m.spent].reduce(max)));
  String short(int m) => _monthLabel(m).substring(0, 3);

  final doc = pw.Document(
    title: 'Informe anual $year',
    author: 'Control de Gastos',
  );

  doc.addPage(pw.MultiPage(
    pageFormat: format,
    margin: const pw.EdgeInsets.all(32),
    footer: _footer,
    build: (context) => [
      _header('Informe anual $year', people),
      pw.Row(children: [
        _statBox('Ingresos', totalIncomes, _incomeColor),
        _statBox('Gastos', spent, _expenseColor),
        _statBox('Ahorrado', saved, _savingsColor),
        _statBox('Sobrante', leftover, leftover < 0 ? _expenseColor : _green),
      ]),
      if (activeMonths > 0)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Gasto promedio por mes: ${pdfMoney(spent / activeMonths)} '
            '($activeMonths ${activeMonths == 1 ? 'mes' : 'meses'} con movimientos).',
            style: const pw.TextStyle(fontSize: 10, color: _muted),
          ),
        ),

      // Mes a mes
      _title('Mes a mes'),
      pw.SizedBox(
        height: 150,
        child: pw.Chart(
          grid: pw.CartesianGrid(
            xAxis: pw.FixedAxis(
                [for (var m = 0; m <= 13; m++) m],
                format: (v) => v < 1 || v > 12 ? '' : short(v.toInt()),
                textStyle: const pw.TextStyle(fontSize: 8, color: _muted),
                divisions: false),
            yAxis: pw.FixedAxis(yTicks,
                format: (v) => v.toStringAsFixed(0),
                textStyle: const pw.TextStyle(fontSize: 8, color: _muted),
                divisions: true,
                divisionsColor: PdfColors.grey300,
                divisionsDashed: true),
          ),
          datasets: [
            pw.BarDataSet(
              color: _incomeColor,
              width: 7,
              offset: -4,
              drawBorder: false,
              data: [
                for (final m in months)
                  pw.PointChartValue(m.month.toDouble(), m.incomes),
              ],
            ),
            pw.BarDataSet(
              color: _expenseColor,
              width: 7,
              offset: 4,
              drawBorder: false,
              data: [
                for (final m in months)
                  pw.PointChartValue(m.month.toDouble(), m.spent),
              ],
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
        for (final legend in [
          ('Ingresos', _incomeColor),
          ('Gastos', _expenseColor),
        ]) ...[
          pw.Container(width: 9, height: 9, color: legend.$2),
          pw.SizedBox(width: 4),
          pw.Text(legend.$1, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(width: 16),
        ],
      ]),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headers: ['Mes', 'Ingresos', 'Gastos', 'Ahorrado', 'Sobrante'],
        data: [
          for (final m in months)
            [
              _monthLabel(m.month),
              pdfMoney(m.incomes),
              pdfMoney(m.spent),
              pdfMoney(m.saved),
              pdfMoney(m.incomes - m.spent - m.saved - m.lent),
            ],
          ['Total', pdfMoney(totalIncomes), pdfMoney(spent), pdfMoney(saved), pdfMoney(leftover)],
        ],
        headerStyle: _tableHeaderStyle,
        headerDecoration: _tableHeaderDecoration,
        cellStyle: const pw.TextStyle(fontSize: 9),
        oddRowDecoration: const pw.BoxDecoration(color: _surface),
        headerAlignments: {
          0: pw.Alignment.centerLeft,
          for (var c = 1; c < 5; c++) c: pw.Alignment.centerRight,
        },
        cellAlignments: {
          for (var c = 1; c < 5; c++) c: pw.Alignment.centerRight,
        },
        border: null,
      ),

      if (pettyCash.isNotEmpty) ..._pettyCashYearSection(pettyCash),

      if (byCategory.isNotEmpty) ...[
        pw.Column(children: [
          _title('Gastos por categoría'),
          _categoriesSection(byCategory),
        ]),
      ],

      _title('Por persona'),
      pw.TableHelper.fromTextArray(
        headers: ['Persona', 'Ingresos', 'Pagó en gastos', '% del gasto', 'Propinas'],
        data: [
          for (var i = 0; i < people.length; i++)
            () {
              final paid = sum(
                  spentList.where((e) => e.paidBy == i).map((e) => e.value));
              return [
                people[i],
                pdfMoney(sum(incomes
                    .where((x) => x.person == i)
                    .map((x) => x.amount))),
                pdfMoney(paid),
                spent > 0 ? '${(paid / spent * 100).round()}%' : '-',
                pdfMoney(sum(spentList
                    .where((e) =>
                        e.paidBy == i && e.category == propinaCategory)
                    .map((e) => e.value))),
              ];
            }(),
        ],
        headerStyle: _tableHeaderStyle,
        headerDecoration: _tableHeaderDecoration,
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerAlignments: {
          0: pw.Alignment.centerLeft,
          for (var c = 1; c < 5; c++) c: pw.Alignment.centerRight,
        },
        cellAlignments: {
          for (var c = 1; c < 5; c++) c: pw.Alignment.centerRight,
        },
        border: null,
      ),

      if (biggest.isNotEmpty) ...[
        _title('Los 10 gastos más grandes'),
        pw.TableHelper.fromTextArray(
          headers: ['Fecha', 'Concepto', 'Categoría', 'Pagó', 'Monto'],
          data: [
            for (final e in biggest.take(10))
              [
                '${e.day.toString().padLeft(2, '0')}/${e.month.toString().padLeft(2, '0')}',
                e.description,
                e.category,
                personName(people, e.paidBy),
                pdfMoney(e.value),
              ],
          ],
          headerStyle: _tableHeaderStyle,
          headerDecoration: _tableHeaderDecoration,
          cellStyle: const pw.TextStyle(fontSize: 9),
          oddRowDecoration: const pw.BoxDecoration(color: _surface),
          headerAlignments: {
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerLeft,
          },
          cellAlignments: {
            0: pw.Alignment.center,
            4: pw.Alignment.centerRight,
          },
          border: null,
        ),
      ],
    ],
  ));

  return doc.save();
}
