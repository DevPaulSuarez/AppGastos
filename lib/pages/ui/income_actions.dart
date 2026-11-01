import 'package:flutter/material.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/utils.dart';

const _weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

String _dateLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} '
    '${monthNames[d.month - 1].substring(0, 3).toLowerCase()}';

/// Monto para un campo de texto: sin ".0" si es entero.
String _plain(double amount) => amount == amount.roundToDouble()
    ? amount.toStringAsFixed(0)
    : amount.toStringAsFixed(2);

/// Al tocar un ingreso: cambiar el monto, la nota o la fecha, o borrarlo.
Future<void> showIncomeActions(
  BuildContext context,
  FinanceRepository finance,
  Income income,
) async {
  final date = DateTime(income.year, income.month, income.day);
  final name = income.description.isEmpty ? 'Ingreso' : income.description;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${_dateLabel(date)} · ${money(income.amount)}'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Cambiar monto'),
            onTap: () => Navigator.pop(context, 'amount'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Cambiar nota'),
            onTap: () => Navigator.pop(context, 'note'),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Cambiar fecha'),
            subtitle: const Text('Si llegó un día, pero es de otro mes'),
            onTap: () => Navigator.pop(context, 'date'),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Borrar',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'amount':
      final full = income.expected ?? income.amount;
      final values = await showFieldsDialog(
        context,
        title: '¿Cuánto llegó?',
        hint: income.isSalary
            ? 'Completo es ${money(full)}. Si faltó algún día y llegó menos, '
                  'escribe lo que llegó de verdad.'
            : null,
        fields: [
          DialogField('Monto', initial: _plain(income.amount), number: true),
        ],
        validate: (v) => (parseAmount(v[0]) ?? 0) <= 0
            ? 'Escribe un monto mayor que 0'
            : null,
      );
      if (values == null) return;
      final amount = parseAmount(values[0])!;
      if (income.isSalary) {
        // Un sueldo guarda lo que debía llegar para mostrar "incompleto".
        await finance.setIncomeAmount(income, amount);
      } else {
        await finance.updateIncome(income, amount: amount);
      }
    case 'note':
      final values = await showFieldsDialog(
        context,
        title: 'Nota del ingreso',
        confirm: 'Listo',
        fields: [DialogField('Nota', initial: income.description)],
      );
      if (values == null) return;
      await finance.updateIncome(
        income,
        description: values[0].isEmpty ? 'Ingreso' : values[0],
      );
    case 'date':
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime(2000),
        lastDate: DateTime.now(),
        helpText: '¿De qué fecha es?',
      );
      if (picked == null) return;
      await finance.updateIncome(income, date: picked);
      if (!context.mounted) return;
      if (picked.month != date.month || picked.year != date.year) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Se pasó a ${monthNames[picked.month - 1].toLowerCase()}',
            ),
          ),
        );
      }
    case 'delete':
      if (await confirmDialog(
        context,
        '¿Borrar "$name" de ${money(income.amount)}?',
        confirm: 'Borrar',
      )) {
        await finance.deleteIncome(income.id);
      }
  }
}
