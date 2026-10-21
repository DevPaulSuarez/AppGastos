import 'package:flutter/material.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/utils.dart';

class DayExpenseListTile extends StatelessWidget {
  const DayExpenseListTile({
    Key? key,
    required this.document,
    this.paidBy,
    this.onTap,
  }) : super(key: key);

  final Expense document;
  final String? paidBy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final month = monthNames[document.month - 1].substring(0, 3);

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              document.day.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.0,
                color: scheme.onSecondaryContainer,
              ),
            ),
            Text(
              month,
              style: TextStyle(
                fontSize: 10,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
      title: Text(
        document.description.isEmpty ? document.category : document.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: document.allowanceFor != null
          ? const Text('Se descuenta de la propina (ya contada)')
          : document.withAllowance
          ? Text(paidBy == null ? 'Con propina' : 'Con propina de $paidBy')
          : paidBy == null
          ? null
          : Text("Pagó $paidBy"),
      trailing: Text(
        money(document.value),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );
  }
}
