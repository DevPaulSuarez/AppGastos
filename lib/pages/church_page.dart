import 'package:flutter/material.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
import 'package:primera_app_curso/tithe.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';

void openChurchReport(BuildContext context, int year) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => ChurchPage(year: year)));

/// Informe aparte de lo que se da a la iglesia: por apartado (diezmo,
/// ofrenda...) y mes a mes, con cada aporte. En el resto de la app la
/// iglesia se ve como una sola categoría.
class ChurchPage extends StatefulWidget {
  final int year;

  const ChurchPage({super.key, required this.year});

  @override
  State<ChurchPage> createState() => _ChurchPageState();
}

class _ChurchPageState extends State<ChurchPage> {
  late int year = widget.year;

  /// Apartado de un aporte: su nota, o "Sin detalle" si no tiene.
  static String _part(Expense e) {
    final note = e.description.trim();
    if (note.isEmpty || note == iglesiaCategory) return 'Sin detalle';
    return note[0].toUpperCase() + note.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<ExpensesRepository>(context);
    final finance = Provider.of<FinanceRepository>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informe de la iglesia'),
        actions: [
          IconButton(
            tooltip: 'Año anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => year--),
          ),
          Center(
            child: Text(
              '$year',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Año siguiente',
            icon: const Icon(Icons.chevron_right),
            onPressed: year >= DateTime.now().year
                ? null
                : () => setState(() => year++),
          ),
        ],
      ),
      body: MultiStreamBuilder(
        key: ValueKey(year),
        streams: [
          db.queryByYear(year),
          finance.watchIncomesByYear(year),
          finance.watchTithe(),
          finance.watchPeople(),
        ],
        builder: (context, values) {
          final all = values[0] as List<Expense>;
          final incomes = values[1] as List<Income>;
          final tithe = values[2] as TitheSettings;
          final people = values[3] as List<String>;
          final church =
              all.where((e) => e.category == iglesiaCategory).toList()..sort(
                (a, b) => b.month != a.month
                    ? b.month.compareTo(a.month)
                    : b.day.compareTo(a.day),
              );
          return _report(context, church, all, incomes, tithe, people);
        },
      ),
    );
  }

  Widget _report(
    BuildContext context,
    List<Expense> church,
    List<Expense> all,
    List<Income> incomes,
    TitheSettings tithe,
    List<String> people,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final total = church.fold(0.0, (a, e) => a + e.value);

    // Por apartado, sin importar mayúsculas: "diezmo" y "Diezmo" van juntos.
    final names = <String, String>{};
    final byPart = <String, double>{};
    for (final e in church) {
      final name = names.putIfAbsent(_part(e).toLowerCase(), () => _part(e));
      byPart[name] = (byPart[name] ?? 0) + e.value;
    }
    final parts = byPart.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final months = <int>{for (final e in church) e.month}.toList()
      ..sort((a, b) => b.compareTo(a));
    // Cada mes tiene su diezmo (puede haberse cambiado a mano).
    final yearTithe = Tithes([
      for (var m = 1; m <= 12; m++)
        ...Tithes.of(tithe, incomes, all, m, year, count: people.length).people,
    ]);

    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const CategoryAvatar(iglesiaCategory),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${church.length} '
                    '${church.length == 1 ? 'aporte' : 'aportes'} en $year',
                    style: muted,
                  ),
                ),
                Text(
                  money(total),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (tithe.on && yearTithe.owed > 0)
          Card(
            child: ListTile(
              title: const Text('Diezmo del año'),
              subtitle: Text(
                [
                  for (final p in tithe.people.toList()..sort())
                    if (p < people.length)
                      _yearLine(
                        Tithes(
                          yearTithe.people.where((t) => t.person == p).toList(),
                        ),
                        people.length > 1 ? personName(people, p) : null,
                      ),
                ].join('\n'),
              ),
            ),
          ),
        if (church.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Aún no hay nada anotado en $iglesiaCategory en $year.',
              textAlign: TextAlign.center,
              style: muted,
            ),
          )
        else ...[
          _title(context, 'Por apartado'),
          Card(
            child: Column(
              children: [
                for (final p in parts)
                  ListTile(
                    dense: true,
                    title: Text(p.key),
                    trailing: Text(
                      money(p.value),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          _title(context, 'Mes a mes'),
          for (final m in months)
            _month(context, m, church, all, incomes, tithe, people),
        ],
      ],
    );
  }

  /// Lo que tocaba dar en el año y lo que dio una persona.
  String _yearLine(Tithes t, String? name) =>
      '${name == null ? '' : '$name: '}tocaba ${money(t.owed)} · '
      'diste ${money(t.given)}';

  Widget _title(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _month(
    BuildContext context,
    int month,
    List<Expense> church,
    List<Expense> all,
    List<Income> incomes,
    TitheSettings tithe,
    List<String> people,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final items = church.where((e) => e.month == month).toList();
    final total = items.fold(0.0, (a, e) => a + e.value);
    final monthTithe = Tithes.of(
      tithe,
      incomes,
      all,
      month,
      year,
      count: people.length,
    );
    final name = monthNames[month - 1];
    final short = name.substring(0, 3).toLowerCase();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        title: Text(
          name[0] + name.substring(1).toLowerCase(),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: monthTithe.owed > 0
            ? Text(
                'Diezmo: diste ${money(monthTithe.given)} de '
                '${money(monthTithe.owed)}',
                style: TextStyle(
                  fontSize: 12,
                  color: monthTithe.pending > 0.005
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              )
            : null,
        trailing: Text(
          money(total),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          for (final e in items)
            ListTile(
              dense: true,
              leading: Text('${e.day} $short'),
              title: Text(_part(e)),
              subtitle: people.length > 1 && e.paidBy != null
                  ? Text('Dio ${personName(people, e.paidBy)}')
                  : null,
              trailing: Text(money(e.value)),
            ),
        ],
      ),
    );
  }
}
