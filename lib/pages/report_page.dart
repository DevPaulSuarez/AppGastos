import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:primera_app_curso/cash.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
import 'package:primera_app_curso/petty_cash.dart';
import 'package:primera_app_curso/report.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

class ReportParams {
  final int year;

  /// Mes de 1 a 12, o null para el informe de todo el año.
  final int? month;

  const ReportParams(this.year, {this.month});
}

/// Pregunta el año (entre los que tienen datos) y abre su informe anual.
Future<void> openYearReport(BuildContext context) async {
  final db = Provider.of<ExpensesRepository>(context, listen: false);
  final finance = Provider.of<FinanceRepository>(context, listen: false);
  final years = {
    DateTime.now().year,
    for (final e in await db.queryAll().first) e.year,
    for (final i in await finance.watchAllIncomes().first) i.year,
  }.toList()
    ..sort((a, b) => b.compareTo(a));
  if (!context.mounted) return;

  final values = await showFieldsDialog(
    context,
    title: 'Informe anual',
    confirm: 'Ver informe',
    fields: [
      DialogField('Año',
          options: [for (final y in years) '$y'], initial: '${years.first}'),
    ],
  );
  if (values == null || !context.mounted) return;
  await Navigator.of(context)
      .pushNamed('/report', arguments: ReportParams(int.parse(values[0])));
}

/// Vista previa del informe en PDF (de un mes o de un año), con botones para
/// compartir e imprimir.
class ReportPage extends StatelessWidget {
  final ReportParams params;

  const ReportPage({super.key, required this.params});

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<ExpensesRepository>(context);
    final finance = Provider.of<FinanceRepository>(context);
    final month = params.month;
    final fileName = month == null
        ? 'informe-anual-${params.year}.pdf'
        : 'informe-${monthNames[month - 1].toLowerCase()}-${params.year}.pdf';

    return Scaffold(
      appBar: AppBar(
          title: Text(month == null
              ? 'Informe anual ${params.year}'
              : 'Informe en PDF')),
      body: MultiStreamBuilder(
        streams: [
          month == null
              ? db.queryByYear(params.year)
              : db.queryByMonth(month, params.year),
          month == null
              ? finance.watchIncomesByYear(params.year)
              : finance.watchIncomes(month, params.year),
          finance.watchPeople(),
          finance.watchPettyCashOn(),
          finance.watchAllIncomes(),
          db.queryAll(),
          finance.watchCashCheck(),
          finance.watchPettyCash(),
        ],
        builder: (context, values) {
          final expenses = values[0] as List<Expense>;
          final incomes = values[1] as List<Income>;
          final people = values[2] as List<String>;
          final pettyCash = values[3] as bool
              ? _pettyCash(
                  values[4] as List<Income>,
                  values[5] as List<Expense>,
                  values[6] as CashCheck?,
                  people.length,
                  values[7] as List<PettyCashMove>,
                )
              : const <PettyCashMonth>[];
          return PdfPreview(
            initialPageFormat: PdfPageFormat.a4,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: fileName,
            build: (format) => month == null
                ? buildYearReport(
                    year: params.year,
                    expenses: expenses,
                    incomes: incomes,
                    people: people,
                    pettyCash: pettyCash,
                    format: format)
                : buildMonthReport(
                    month: month,
                    year: params.year,
                    expenses: expenses,
                    incomes: incomes,
                    people: people,
                    pettyCash: pettyCash,
                    format: format),
          );
        },
      ),
    );
  }

  /// Caja chica del mes del informe, o de cada mes del año desde que hay
  /// datos y hasta el mes en curso.
  List<PettyCashMonth> _pettyCash(
    List<Income> incomes,
    List<Expense> expenses,
    CashCheck? check,
    int people,
    List<PettyCashMove> moves,
  ) {
    final now = DateTime.now();
    final month = params.month;
    final months = [
      for (final m in month == null ? [for (var m = 1; m <= 12; m++) m] : [month])
        if (!DateTime(params.year, m).isAfter(DateTime(now.year, now.month)))
          PettyCashMonth.of(
              incomes, expenses, check, people, moves, m, params.year),
    ];
    if (month != null) return months;
    // En el año, desde el primer mes con movimientos.
    final first = months.indexWhere(
        (m) => m.moves.isNotEmpty || m.result.abs() >= 0.005);
    return first < 0 ? const [] : months.sublist(first);
  }
}
