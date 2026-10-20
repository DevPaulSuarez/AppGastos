import 'package:primera_app_curso/expense.dart';
import 'package:flutter/material.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/pages/detail_page.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
import 'package:provider/provider.dart';

class DetailsParams {
  final String categoryName;
  final int month;
  final int year;

  const DetailsParams(this.categoryName, this.month, this.year);
}

class DetailsPageContainer extends StatefulWidget {
  final DetailsParams params;

  const DetailsPageContainer({Key? key, required this.params}) : super(key: key);

  @override
  _DetailsPageContainerState createState() => _DetailsPageContainerState();
}

class _DetailsPageContainerState extends State<DetailsPageContainer> {
  /// Gastos borrados que se ocultan al instante, sin esperar a la base de datos.
  final _removed = <String>{};

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<ExpensesRepository>(context);
    final finance = Provider.of<FinanceRepository>(context);

    return MultiStreamBuilder(
      streams: [
        db.queryByCategory(
          widget.params.month + 1,
          widget.params.categoryName,
          widget.params.year,
        ),
        finance.watchPeople(),
      ],
      placeholder: Scaffold(
        appBar: AppBar(title: Text(widget.params.categoryName)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      builder: (BuildContext context, List<Object?> values) {
        final documents = (values[0] as List<Expense>)
            .where((doc) => !_removed.contains(doc.id))
            .toList()
          ..sort((a, b) => a.day.compareTo(b.day));
        return DetailsPage(
          categoryName: widget.params.categoryName,
          documents: documents,
          people: values[1] as List<String>,
          onDelete: (documentid) {
            setState(() => _removed.add(documentid));
            db.delete(documentid);
          },
          onEdit: (expense) {
            db.update(expense);
          },
        );
      },
    );
  }
}
