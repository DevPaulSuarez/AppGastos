import 'package:flutter/material.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/utils.dart';

const _weekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

/// Panel inferior con los gastos de un día.
Future<void> showDayExpenses(
  BuildContext context, {
  required DateTime date,
  required List<Expense> expenses,
  required List<String> people,
}) {
  final scheme = Theme.of(context).colorScheme;
  final sorted = [...expenses]..sort((a, b) => b.value.compareTo(a.value));
  final total = sorted.fold(0.0, (a, e) => a + e.value);
  final title = '${_weekdays[date.weekday - 1]} ${date.day} de '
      '${monthNames[date.month - 1].toLowerCase()}';

  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        sorted.isEmpty
                            ? 'Sin gastos'
                            : '${sorted.length} '
                                '${sorted.length == 1 ? 'gasto' : 'gastos'}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Text(money(total),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const Divider(height: 1),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Este día no registraron gastos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  for (final e in sorted)
                    ListTile(
                      leading: CategoryAvatar(e.category),
                      title: Text(
                        e.description.isEmpty ? e.category : e.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(e.category == prestamoCategory
                          ? (e.loanId == null
                              ? 'Por cobrar a ${e.owedBy}'
                              : 'Te devolvió ${e.owedBy}')
                          : e.paidBy == null
                              ? e.category
                              : '${e.category} · pagó ${personName(people, e.paidBy)}'),
                      trailing: Text(money(e.value),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
