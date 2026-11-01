import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:primera_app_curso/bank_import.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/couple/space_state.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/theme.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';

/// Comprueba la app contra el CSV que se baja del banco: qué coincide, qué
/// falta anotar, montos o categorías distintas y lo que solo está en la app.
class BankCheckPage extends StatefulWidget {
  const BankCheckPage({super.key});

  @override
  State<BankCheckPage> createState() => _BankCheckPageState();
}

class _BankCheckPageState extends State<BankCheckPage> {
  List<String> _people = const [];
  int _person = 0;
  String? _fileName;
  List<BankRow> _rows = const [];

  /// Desde cuándo comparar con "Todos los meses": el primer mes con datos
  /// en la app.
  DateTime? _from;

  /// Mes elegido para comparar; null = todos los meses del archivo.
  DateTime? _month;
  BankCheck? _check;
  bool _busy = false;
  String? _error;

  /// Faltantes elegidos para agregar, con el nombre y categoría que se
  /// usarán (se pueden cambiar).
  final Map<BankMissing, BankGuess> _toAdd = {};

  @override
  void initState() {
    super.initState();
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    finance.watchPeople().first.then((people) {
      if (!mounted) return;
      final me = Provider.of<SpaceState>(context, listen: false).myPerson;
      setState(() {
        _people = people;
        _person = me ?? 0;
      });
    });
  }

  List<DateTime> get _months {
    final set = <DateTime>{
      for (final r in _rows) DateTime(r.date.year, r.date.month),
    };
    return set.toList()..sort();
  }

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Elige el CSV del banco',
    );
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      final rows = parseBankCsv(text);
      if (rows.isEmpty)
        throw const FormatException('El archivo no tiene movimientos.');
      _rows = rows;
      _fileName = file.name;
      _from = await _firstMonthWithData();
      // Lo más común: revisar el último mes del archivo.
      _month = _months.last;
      await _compare();
    } on FormatException catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  /// Por defecto se compara desde el primer mes que tiene datos en la app
  /// (antes de empezar a usarla todo saldría como "falta").
  Future<DateTime> _firstMonthWithData() async {
    final db = Provider.of<ExpensesRepository>(context, listen: false);
    final expenses = await db.queryAll().first;
    final months = _months;
    DateTime? first;
    for (final e in expenses) {
      final m = DateTime(e.year, e.month);
      if (first == null || m.isBefore(first)) first = m;
    }
    if (first == null) return months.last;
    return months.firstWhere(
      (m) => !m.isBefore(first!),
      orElse: () => months.last,
    );
  }

  Future<void> _compare() async {
    final db = Provider.of<ExpensesRepository>(context, listen: false);
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    setState(() => _busy = true);
    final expenses = await db.queryAll().first;
    final incomes = await finance.watchAllIncomes().first;
    final learned = await finance.bankNames();
    final last = _rows
        .map((r) => r.date)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final check = compareBank(
      rows: _rows,
      expenses: expenses,
      incomes: incomes,
      person: _person,
      from: _month ?? _from!,
      to: _month == null ? last : DateTime(_month!.year, _month!.month + 1, 0),
      people: _people,
      learned: learned,
    );
    // Se aprende cómo llaman a cada comercio de lo que ya coincide.
    final newNames = learnFrom(check.matched);
    if (newNames.entries.any(
      (e) =>
          learned[e.key]?.name != e.value.name ||
          learned[e.key]?.category != e.value.category,
    )) {
      await finance.saveBankNames({...learned, ...newNames});
    }
    if (!mounted) return;
    setState(() {
      _check = check;
      _toAdd
        ..clear()
        ..addEntries(check.missing.map((m) => MapEntry(m, m.guess)));
      _busy = false;
    });
  }

  Future<void> _addSelected() async {
    final db = Provider.of<ExpensesRepository>(context, listen: false);
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    setState(() => _busy = true);
    final learned = await finance.bankNames();
    for (final e in _toAdd.entries) {
      final row = e.key.row;
      final g = e.value;
      if (g.kind == BankKind.income) {
        await finance.addIncome(
          _person,
          g.name,
          row.amount.abs(),
          row.date.month,
          row.date.year,
          day: row.date.day,
        );
      } else {
        await db.add(
          g.category,
          row.amount.abs(),
          row.date,
          g.name,
          paidBy: _person,
        );
        if (row.key.isNotEmpty)
          learned[row.key] = LearnedName(g.name, g.category);
      }
    }
    await finance.saveBankNames(learned);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Se agregaron ${_toAdd.length} movimientos')),
    );
    await _compare();
  }

  Future<void> _useBankAmount(BankMatch m) async {
    final amount = m.row.amount.abs();
    if (m.move.isIncome) {
      await Provider.of<FinanceRepository>(
        context,
        listen: false,
      ).updateIncome(m.move.income!, amount: amount);
    } else {
      await Provider.of<ExpensesRepository>(
        context,
        listen: false,
      ).update(m.move.expense!.copyWith(value: amount));
    }
    await _compare();
  }

  Future<void> _setCategory(BankMatch m, String category) async {
    final e = m.move.expense!;
    await Provider.of<ExpensesRepository>(
      context,
      listen: false,
    ).update(Expense.fromMap(e.id, e.toMap()..['category'] = category));
    await _compare();
  }

  /// Deja la categoría que tiene en la app y la recuerda para ese comercio.
  Future<void> _keepCategory(BankMatch m) async {
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    final learned = await finance.bankNames();
    learned[m.row.key] = LearnedName(m.move.name, m.move.category);
    await finance.saveBankNames(learned);
    await _compare();
  }

  Future<void> _editMissing(BankMissing m) async {
    final current = _toAdd[m] ?? m.guess;
    final income = current.kind == BankKind.income;
    final values = await showFieldsDialog(
      context,
      title: income ? 'Ingreso' : 'Gasto',
      confirm: 'Listo',
      hint: 'En el banco: ${m.row.merchant}',
      fields: [
        DialogField('Nombre', initial: current.name),
        if (!income)
          DialogField(
            'Categoría',
            initial: current.category,
            options: expenseCategories,
          ),
      ],
    );
    if (values == null) return;
    setState(() {
      _toAdd[m] = BankGuess(
        current.kind,
        values[0].isEmpty ? current.name : values[0],
        income ? '' : values[1],
      );
    });
  }

  String _date(DateTime d) =>
      '${d.day} ${monthNames[d.month - 1].substring(0, 3).toLowerCase()}';

  String _monthLabel(DateTime d) =>
      '${monthNames[d.month - 1][0]}${monthNames[d.month - 1].substring(1).toLowerCase()} ${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comprobar con el banco')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _intro(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: context.money.expense)),
                ],
                if (_check != null) ..._results(_check!),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _intro() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Baja de tu banco los movimientos en CSV y elígelo aquí. La '
              'app te dice qué coincide, qué falta anotar y qué es distinto.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            if (_people.length > 1) ...[
              const SizedBox(height: 16),
              const Text(
                '¿De quién es la cuenta?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (var i = 0; i < _people.length; i++)
                    ButtonSegment(value: i, label: Text(_people[i])),
                ],
                selected: {_person},
                onSelectionChanged: (v) {
                  setState(() => _person = v.first);
                  if (_rows.isNotEmpty) _compare();
                },
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(
                _fileName == null
                    ? 'Elegir archivo CSV'
                    : 'Elegir otro archivo',
              ),
              onPressed: _pickFile,
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 12),
              Text(
                '$_fileName · ${_rows.length} movimientos',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,

                children: [
                  const Text('Mes a comparar: '),
                  DropdownButton<DateTime?>(
                    value: _month,
                    items: [
                      for (final m in _months.reversed)
                        DropdownMenuItem(value: m, child: Text(_monthLabel(m))),
                      DropdownMenuItem(
                        value: null,
                        child: Text(
                          'Todos (desde ${_monthLabel(_from!).toLowerCase()})',
                        ),
                      ),
                    ],
                    onChanged: (m) {
                      setState(() => _month = m);
                      _compare();
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _results(BankCheck c) {
    final allGood =
        c.missing.isEmpty &&
        c.amountDiffers.isEmpty &&
        c.categoryDiffers.isEmpty &&
        c.onlyInApp.isEmpty;
    return [
      const SizedBox(height: 16),
      if (allGood)
        Card(
          color: context.money.income.withValues(alpha: 0.15),
          child: const ListTile(
            leading: Icon(Icons.check_circle),
            title: Text('¡Todo coincide con el banco!'),
          ),
        ),
      if (c.missing.isNotEmpty) _missingCard(c.missing),
      if (c.amountDiffers.isNotEmpty)
        _section(
          icon: Icons.compare_arrows,
          title: 'Monto distinto',
          subtitle: 'Parece el mismo movimiento, pero con otro monto',
          initiallyExpanded: true,
          children: [
            for (final m in c.amountDiffers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m.move.name),
                subtitle: Text(
                  '${_date(m.row.date)} · app ${money(m.move.amount)} · '
                  'banco ${money(m.row.amount.abs())}',
                ),
                trailing: TextButton(
                  onPressed: () => _useBankAmount(m),
                  child: const Text('Usar el del banco'),
                ),
              ),
          ],
        ),
      if (c.categoryDiffers.isNotEmpty)
        _section(
          icon: Icons.category_outlined,
          title: '¿Categoría correcta?',
          subtitle: 'En la app están en otra categoría',
          initiallyExpanded: true,
          children: [
            for (final m in c.categoryDiffers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${m.move.name} · ${money(m.move.amount)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${_date(m.row.date)} · está en ${m.move.category}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => _setCategory(m, m.guess.category),
                          child: Text('Pasar a ${m.guess.category}'),
                        ),
                        TextButton(
                          onPressed: () => _keepCategory(m),
                          child: const Text('Dejar así'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      if (c.onlyInApp.isNotEmpty)
        _section(
          icon: Icons.help_outline,
          title: 'En la app, pero no en este banco',
          subtitle:
              'A nombre de ${personName(_people, _person)}. Puede ser en '
              'efectivo, de otra cuenta, o algo para borrar.',
          children: [
            for (final m in c.onlyInApp)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(m.name),
                subtitle: Text(_date(m.date)),
                trailing: Text('${m.isIncome ? '+' : '−'} ${money(m.amount)}'),
              ),
          ],
        ),
      _section(
        icon: Icons.check_circle_outline,
        title: 'Coinciden',
        subtitle: '${c.matched.length} movimientos iguales al banco',
        children: [
          for (final m in c.matched)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(m.move.name),
              subtitle: Text(
                '${_date(m.row.date)}'
                '${m.move.category.isEmpty ? '' : ' · ${m.move.category}'}'
                ' · banco: ${m.row.merchant}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(money(m.move.amount)),
            ),
        ],
      ),
      if (c.ignored.isNotEmpty)
        _section(
          icon: Icons.swap_horiz,
          title: 'No se cuentan',
          subtitle:
              'Envíos entre ustedes, depósitos y compras devueltas: no son '
              'gasto ni ingreso',
          children: [
            for (final m in c.ignored)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(m.guess.name),
                subtitle: Text(_date(m.row.date)),
                trailing: Text(
                  '${m.row.amount > 0 ? '+' : '−'} ${money(m.row.amount.abs())}',
                ),
              ),
          ],
        ),
    ];
  }

  Widget _missingCard(List<BankMissing> missing) {
    return _section(
      icon: Icons.warning_amber_rounded,
      title: 'Faltan en la app (${missing.length})',
      subtitle:
          'Están en el banco pero no anotados. Toca uno para cambiar '
          'el nombre o la categoría.',
      initiallyExpanded: true,
      children: [
        for (final m in missing)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _toAdd.containsKey(m),
            onChanged: (on) => setState(() {
              if (on == true) {
                _toAdd[m] = m.guess;
              } else {
                _toAdd.remove(m);
              }
            }),
            title: InkWell(
              onTap: () => _editMissing(m),
              child: Text((_toAdd[m] ?? m.guess).name),
            ),
            subtitle: InkWell(
              onTap: () => _editMissing(m),
              child: Text(
                [
                  _date(m.row.date),
                  if ((_toAdd[m] ?? m.guess).kind == BankKind.income)
                    'Ingreso'
                  else
                    (_toAdd[m] ?? m.guess).category,
                ].join(' · '),
              ),
            ),
            secondary: Text(
              '${m.row.amount > 0 ? '+' : '−'} ${money(m.row.amount.abs())}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: m.row.amount > 0
                    ? context.money.income
                    : context.money.expense,
              ),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _toAdd.isEmpty ? null : _addSelected,
          child: Text('Agregar ${_toAdd.length} a la app'),
        ),
      ],
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: children,
        ),
      ),
    );
  }
}
