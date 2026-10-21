import 'package:flutter/material.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
import 'package:primera_app_curso/theme.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';

/// Compras hechas para otras personas que las van a devolver.
class LoansPage extends StatelessWidget {
  const LoansPage({super.key});

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<ExpensesRepository>(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Por cobrar')),
      body: MultiStreamBuilder(
        streams: [db.queryLoans()],
        builder: (context, values) {
          final loans = (values[0] as List<Expense>)
              .where((e) => e.isLoan)
              .toList()
            ..sort((a, b) => DateTime(b.year, b.month, b.day)
                .compareTo(DateTime(a.year, a.month, a.day)));
          final pending = loans.where((e) => e.pending > 0.001).toList();
          final paid = loans.where((e) => e.pending <= 0.001).toList();

          final byPerson = <String, List<Expense>>{};
          for (final loan in pending) {
            byPerson.putIfAbsent(loan.owedBy!, () => []).add(loan);
          }

          if (loans.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No tienen nada por cobrar.\n\nCuando le compren algo a '
                  'alguien que se lo va a devolver, al registrar el gasto '
                  'marquen "Me lo devolverá".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (pending.isEmpty)
                Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle, color: context.money.income),
                    title: Text('Ya les devolvieron todo'),
                  ),
                ),
              for (final entry in byPerson.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(entry.key,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      Text(
                        'Debe ${money(entry.value.fold(0.0, (a, e) => a + e.pending))}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: context.money.warning),
                      ),
                    ],
                  ),
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final loan in entry.value)
                        _loanTile(context, db, loan),
                    ],
                  ),
                ),
              ],
              if (paid.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
                  child: Text('Ya devueltos',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600)),
                ),
                Card(
                  child: Column(
                    children: [
                      for (final loan in paid)
                        ListTile(
                          leading: Icon(Icons.check_circle,
                              color: context.money.income),
                          title: Text(loan.description),
                          subtitle: Text('${loan.owedBy} · ${_date(loan)}'),
                          trailing: Text(money(loan.value)),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _date(Expense e) =>
      '${e.day} ${monthNames[e.month - 1].substring(0, 3).toLowerCase()} ${e.year}';

  Widget _loanTile(BuildContext context, ExpensesRepository db, Expense loan) {
    return ListTile(
      leading: const CategoryAvatar(prestamoCategory, size: 40),
      title: Text(loan.description),
      subtitle: Text(loan.repaid > 0
          ? '${_date(loan)} · devolvió ${money(loan.repaid)} de ${money(loan.value)}'
          : _date(loan)),
      trailing: FilledButton.tonal(
        // El tema hace los botones de ancho completo; aquí va uno compacto.
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onPressed: () => _repay(context, db, loan),
        child: Text('Me pagó\n${money(loan.pending)}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Future<void> _repay(
      BuildContext context, ExpensesRepository db, Expense loan) async {
    final values = await showFieldsDialog(
      context,
      title: '${loan.owedBy} te pagó',
      confirm: 'Registrar pago',
      hint: 'Por: ${loan.description}. Si te pagó solo una parte, cambia el '
          'monto y el resto queda por cobrar.',
      fields: [
        DialogField('Monto',
            initial: loan.pending.toStringAsFixed(2), number: true),
      ],
      validate: (values) {
        final amount = parseAmount(values[0])!;
        if (amount <= 0) return 'El monto debe ser mayor a 0';
        if (amount > loan.pending + 0.001) {
          return 'Solo te debe ${money(loan.pending)}';
        }
        return null;
      },
    );
    if (values == null) return;
    await db.registerRepayment(loan, parseAmount(values[0])!, DateTime.now());
  }
}
