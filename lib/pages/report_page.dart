import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
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
        ],
        builder: (context, values) {
          final expenses = values[0] as List<Expense>;
          final incomes = values[1] as List<Income>;
          final people = values[2] as List<String>;
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
                    format: format)
                : buildMonthReport(
                    month: month,
                    year: params.year,
                    expenses: expenses,
                    incomes: incomes,
                    people: people,
                    format: format),
          );
        },
      ),
    );
  }
}
