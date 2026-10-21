import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:flutter/material.dart';
import 'package:primera_app_curso/pages/ui/day_expense_list_tile.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/utils.dart';

class DetailsPage extends StatelessWidget {
  final String categoryName;
  final List<Expense> documents;
  final List<String> people;
  final Function(String) onDelete;
  final Function(Expense) onEdit;

  const DetailsPage(
      {Key? key,
      required this.categoryName,
      required this.documents,
      required this.people,
      required this.onDelete,
      required this.onEdit})
      : super(key: key);

  Future<void> _edit(BuildContext context, Expense document) async {
    final values = await showFieldsDialog(
      context,
      title: 'Editar gasto',
      fields: [
        DialogField('Monto',
            initial: document.value.toStringAsFixed(2), number: true),
        DialogField('Descripción', initial: document.description),
        DialogField('Pagó',
            initial: personName(people, document.paidBy),
            options: people),
      ],
    );
    if (values == null) return;
    onEdit(document.copyWith(
      value: parseAmount(values[0]),
      description: values[1],
      paidBy: people.indexOf(values[2]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = documents.fold(0.0, (a, e) => a + e.value);

    return Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              CategoryAvatar(categoryName, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text(categoryName)),
            ],
          ),
        ),
        body: documents.isEmpty
            ? Center(
                child: Text('No hay gastos en esta categoría',
                    style: TextStyle(color: scheme.onSurfaceVariant)))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: documents.length + 2,
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${documents.length} '
                                  '${documents.length == 1 ? 'gasto' : 'gastos'} este mes',
                                  style: TextStyle(color: scheme.onSurfaceVariant),
                                ),
                              ),
                              Text(money(total),
                                  style: const TextStyle(
                                      fontSize: 20, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  if (index == documents.length + 1) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Toca un gasto para editarlo · deslízalo para borrarlo',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    );
                  }
                  var document = documents[index - 1];

                  return Dismissible(
                    key: Key(document.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: scheme.error,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Icon(Icons.delete_outline, color: scheme.onError),
                    ),
                    confirmDismiss: (direction) => confirmDialog(
                        context, '¿Borrar este gasto de ${money(document.value)}?',
                        confirm: 'Borrar'),
                    onDismissed: (direction) {
                      onDelete(document.id);
                    },
                    child: DayExpenseListTile(
                      document: document,
                      paidBy: document.paidBy == null
                          ? null
                          : personName(people, document.paidBy),
                      onTap: () => _edit(context, document),
                    ),
                  );
                },
              ));
  }
}
