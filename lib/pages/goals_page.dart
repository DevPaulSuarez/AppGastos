import 'package:flutter/material.dart';
import 'package:primera_app_curso/cash.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
import 'package:primera_app_curso/theme.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';

/// Metas de ahorro (viaje, emergencia, etc.). Cada aporte se registra como
/// "Ahorro Neto": no es gasto, pero se aparta de lo disponible. Cuando se usa
/// el dinero de una meta, el gasto se anota y el mismo monto sale de la meta.
class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<ExpensesRepository>(context);
    final finance = Provider.of<FinanceRepository>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Metas de ahorro')),
      floatingActionButton: FloatingActionButton.extended(
        shape: const StadiumBorder(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva meta'),
        onPressed: () => _addGoal(context, finance),
      ),
      body: MultiStreamBuilder(
        streams: [
          finance.watchGoals(),
          db.queryAll(),
          finance.watchPeople(),
          finance.watchAllIncomes(),
          finance.watchCashCheck(),
          finance.watchRecurring(),
        ],
        builder: (context, values) {
          final goals = values[0] as List<Goal>;
          final all = values[1] as List<Expense>;
          final people = values[2] as List<String>;
          final savings = all
              .where((e) => e.category == ahorroCategory)
              .toList();
          // Se puede apartar lo que dice "Tienes disponible" en Inicio,
          // menos lo que todavía falta pagar este mes (ej. el alquiler).
          final now = DateTime.now();
          final toPay = FinanceRepository.toPayThisMonth(
            values[5] as List<Recurring>,
            {for (final e in all) e.id},
            now,
          );
          final available =
              cashSummaryUntil(
                values[3] as List<Income>,
                all,
                values[4] as CashCheck?,
                people.length,
                DateTime(now.year, now.month, now.day),
              ).free -
              toPay;
          final goalIds = goals.map((g) => g.id).toSet();
          // Aportes de metas que se eliminaron sin decidir qué hacer con ellos.
          final orphans = savings
              .where((e) => e.goalId != null && !goalIds.contains(e.goalId))
              .toList();

          if (goals.isEmpty && orphans.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text(
                  'Todavía no tienen metas.\nCrea una, por ejemplo '
                  '"Viaje" o "Fondo de emergencia".',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16.0, color: Colors.grey),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 96.0),
            children: [
              _availableCard(context, available, toPay),
              const SizedBox(height: 12),
              if (orphans.isNotEmpty) ...[
                _orphansCard(context, db, orphans),
                const SizedBox(height: 12),
              ],
              for (final goal in goals)
                _goalCard(
                  context,
                  db,
                  finance,
                  goal,
                  savings.where((e) => e.goalId == goal.id).toList(),
                  people,
                  available,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _availableCard(BuildContext context, double available, double toPay) {
    final ok = available > 0;
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.account_balance_wallet_outlined,
          color: ok ? context.money.income : context.money.expense,
        ),
        title: const Text('Disponible para aportar'),
        subtitle: Text(
          toPay > 0
              ? 'Lo mismo que "Libre para gastar" en Inicio: ya se '
                    'separaron ${money(toPay)} para los pagos del mes'
              : 'Lo mismo que "Tienes disponible" en Inicio',
        ),
        trailing: Text(
          money(ok ? available : 0),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: ok ? context.money.income : context.money.expense,
          ),
        ),
      ),
    );
  }

  Widget _goalCard(
    BuildContext context,
    ExpensesRepository db,
    FinanceRepository finance,
    Goal goal,
    List<Expense> contributions,
    List<String> people,
    double available,
  ) {
    final saved = contributions.fold(0.0, (a, e) => a + e.value);
    final used = contributions
        .where((e) => e.value < 0)
        .fold(0.0, (a, e) => a - e.value);
    final progress = goal.target <= 0 ? 0.0 : (saved / goal.target);
    final done = progress >= 1;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            _showContributions(context, db, goal, contributions, people),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    done ? Icons.emoji_events : Icons.savings,
                    color: done ? context.money.warning : context.money.income,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      goal.name,
                      style: const TextStyle(
                        fontSize: 18.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Eliminar meta',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        _deleteGoal(context, db, finance, goal, contributions),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
                color: done ? context.money.warning : context.money.income,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${money(saved)} de ${money(goal.target)} '
                      '(${(progress * 100).round()}%)',
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Aportar'),
                    onPressed: () =>
                        _contribute(context, db, goal, people, available),
                  ),
                ],
              ),
              if (!done)
                Text(
                  'Faltan ${money(goal.target - saved)}',
                  style: const TextStyle(color: Colors.grey),
                ),
              if (used > 0)
                Text(
                  'Ya usaste ${money(used)} de esta meta',
                  style: const TextStyle(color: Colors.grey),
                ),
              if (saved > 0.004)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('Usé este dinero'),
                    onPressed: () =>
                        _useMoney(context, db, goal, saved, people),
                  ),
                ),
              if (contributions.isNotEmpty)
                Text(
                  '${contributions.length} '
                  '${contributions.length == 1 ? 'movimiento' : 'movimientos'} · '
                  'toca para verlos o corregirlos',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orphansCard(
    BuildContext context,
    ExpensesRepository db,
    List<Expense> orphans,
  ) {
    final total = orphans.fold(0.0, (a, e) => a + e.value);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, color: context.money.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aportes de metas eliminadas: ${money(total)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${orphans.length} '
              '${orphans.length == 1 ? 'aporte quedó' : 'aportes quedaron'} '
              'sin meta. Si los registraste por error, bórralos: es como si '
              'nunca se hubieran puesto. Si de verdad separaron ese dinero, '
              'déjalo como ahorro.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () async {
                    if (await confirmDialog(
                      context,
                      'Se borrarán estos aportes como si nunca se hubieran '
                      'registrado. Sus cuentas quedan como estaban antes.',
                      confirm: 'Borrar',
                    )) {
                      await db.deleteMany(orphans.map((e) => e.id));
                    }
                  },
                  child: const Text('Fue un error: borrar'),
                ),
                TextButton(
                  onPressed: () async {
                    for (final e in orphans) {
                      await db.detachFromGoal(e);
                    }
                  },
                  child: const Text('Sí lo ahorramos: dejarlo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteGoal(
    BuildContext context,
    ExpensesRepository db,
    FinanceRepository finance,
    Goal goal,
    List<Expense> contributions,
  ) async {
    final total = contributions.fold(0.0, (a, e) => a + e.value);
    if (contributions.isEmpty) {
      if (await confirmDialog(
        context,
        '¿Eliminar la meta "${goal.name}"?',
        confirm: 'Eliminar',
      )) {
        await finance.deleteGoal(goal.id);
      }
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar "${goal.name}"'),
        content: Text(
          'Tiene ${money(total)} aportados. Si los aportes fueron un error, '
          'bórralos. Si de verdad separaron ese dinero, déjalo como ahorro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('keep'),
            child: const Text('Dejar como ahorro'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('return'),
            child: const Text('Borrar aportes'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'return') {
      await db.deleteMany(contributions.map((e) => e.id));
    } else {
      for (final e in contributions) {
        await db.detachFromGoal(e);
      }
    }
    await finance.deleteGoal(goal.id);
  }

  Future<void> _showContributions(
    BuildContext context,
    ExpensesRepository db,
    Goal goal,
    List<Expense> contributions,
    List<String> people,
  ) {
    final sorted = [...contributions]
      ..sort(
        (a, b) => DateTime(
          b.year,
          b.month,
          b.day,
        ).compareTo(DateTime(a.year, a.month, a.day)),
      );
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Movimientos de "${goal.name}"',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const Divider(height: 1),
            if (sorted.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Todavía no hay aportes.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    for (final e in sorted)
                      e.value < 0
                          // Uso del dinero de la meta.
                          ? ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.shopping_bag_outlined),
                              ),
                              title: Text(
                                '− ${money(-e.value)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: context.money.expense,
                                ),
                              ),
                              subtitle: Text(
                                '${e.day}/${e.month}/${e.year} · '
                                '${e.description}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Deshacer',
                                icon: const Icon(Icons.undo),
                                onPressed: () async {
                                  if (await confirmDialog(
                                    sheetContext,
                                    '¿Deshacer este uso de ${money(-e.value)}? '
                                    'El dinero vuelve a la meta y se borra el '
                                    'gasto que pagaste con él.',
                                    confirm: 'Deshacer',
                                  )) {
                                    await db.undoGoalUse(e);
                                    if (sheetContext.mounted) {
                                      Navigator.of(sheetContext).pop();
                                    }
                                  }
                                },
                              ),
                            )
                          : ListTile(
                              leading: const CategoryAvatar(
                                ahorroCategory,
                                size: 40,
                              ),
                              title: Text(
                                '+ ${money(e.value)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                people.length > 1
                                    ? '${e.day}/${e.month}/${e.year} · '
                                          'aportó ${personName(people, e.paidBy)}'
                                    : '${e.day}/${e.month}/${e.year} · aporte',
                              ),
                              trailing: IconButton(
                                tooltip: 'Quitar aporte',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  if (await confirmDialog(
                                    sheetContext,
                                    '¿Quitar este aporte de ${money(e.value)}? '
                                    'Ese dinero vuelve a estar disponible.',
                                    confirm: 'Quitar',
                                  )) {
                                    await db.delete(e.id);
                                    if (sheetContext.mounted) {
                                      Navigator.of(sheetContext).pop();
                                    }
                                  }
                                },
                              ),
                            ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addGoal(BuildContext context, FinanceRepository finance) async {
    final values = await showFieldsDialog(
      context,
      title: 'Nueva meta de ahorro',
      fields: const [
        DialogField('Nombre (ej. Viaje)'),
        DialogField('Monto a juntar', number: true),
      ],
    );
    if (values == null || values[0].isEmpty) return;
    await finance.addGoal(values[0], parseAmount(values[1])!);
  }

  Future<void> _contribute(
    BuildContext context,
    ExpensesRepository db,
    Goal goal,
    List<String> people,
    double available,
  ) async {
    if (available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No tienen dinero disponible para aportar: todo lo '
            'que entró ya se gastó o está en metas.',
          ),
        ),
      );
      return;
    }
    final values = await showFieldsDialog(
      context,
      title: 'Aportar a "${goal.name}"',
      confirm: 'Aportar',
      hint: 'Disponible: ${money(available)}',
      validate: (values) {
        final amount = parseAmount(values[0])!;
        if (amount <= 0) return 'El monto debe ser mayor a 0';
        if (amount > available + 0.001) {
          return 'Solo tienen ${money(available)} disponibles para aportar';
        }
        return null;
      },
      fields: [
        const DialogField('Monto', number: true),
        if (people.length > 1) DialogField('Quién aporta', options: people),
      ],
    );
    if (values == null) return;
    await db.add(
      ahorroCategory,
      parseAmount(values[0])!,
      DateTime.now(),
      'Meta: ${goal.name}',
      paidBy: people.length > 1 ? people.indexOf(values[1]) : 0,
      goalId: goal.id,
    );
  }

  /// Anota un gasto pagado con el dinero apartado en la meta (ej. los
  /// pasajes del viaje). No se resta dos veces: sale de la meta, no de lo
  /// disponible.
  Future<void> _useMoney(
    BuildContext context,
    ExpensesRepository db,
    Goal goal,
    double saved,
    List<String> people,
  ) async {
    final values = await showFieldsDialog(
      context,
      title: 'Usar el dinero de "${goal.name}"',
      confirm: 'Guardar',
      hint:
          'Se anota como gasto y sale de lo que tienes en esta meta '
          '(${money(saved)}). Lo disponible no cambia, porque ese dinero ya '
          'estaba apartado.',
      validate: (values) {
        final amount = parseAmount(values[1])!;
        if (amount <= 0) return 'El monto debe ser mayor a 0';
        if (amount > saved + 0.001) {
          return 'En esta meta solo hay ${money(saved)}';
        }
        return null;
      },
      fields: [
        DialogField('¿En qué lo usaste? (ej. Pasajes)', initial: goal.name),
        DialogField('Monto', initial: saved.toStringAsFixed(2), number: true),
        DialogField('Categoría', initial: 'Ocio', options: expenseCategories),
        if (people.length > 1) DialogField('Quién pagó', options: people),
      ],
    );
    if (values == null) return;
    final description = values[0].trim();
    await db.useGoalMoney(
      goal.id,
      parseAmount(values[1])!,
      values[2],
      description.isEmpty ? goal.name : description,
      DateTime.now(),
      paidBy: people.length > 1 ? people.indexOf(values[3]) : 0,
    );
  }
}
