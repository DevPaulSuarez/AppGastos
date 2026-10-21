import 'package:flutter/material.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/pages/ui/day_picker.dart';
import 'package:primera_app_curso/utils.dart';

/// Cómo llega un ingreso fijo.
enum _Kind { weekly, monthly, twice, variable }

const _kindLabels = {
  _Kind.weekly: 'Semanal',
  _Kind.monthly: 'Mensual',
  _Kind.twice: 'Quincena',
  _Kind.variable: 'Variable',
};

/// Ingreso fijo elegido en [showIncomeDialog] y, si es nuevo, desde qué pago
/// se anota (para que entren también los de días que ya pasaron este mes).
typedef IncomeChoice = ({Recurring item, DateTime? firstPayment});

/// Todo el ingreso fijo en una sola pantalla: nombre, monto, cada cuánto
/// llega y el día (o los días). Devuelve el ingreso sin id, o null si se
/// canceló. [person] es quién lo recibe si se agrega desde la tarjeta de una
/// persona; si no, se pregunta (solo en pareja).
Future<IncomeChoice?> showIncomeDialog(
  BuildContext context, {
  required List<String> people,
  int? person,
  Recurring? existing,
}) {
  return showDialog<IncomeChoice>(
    context: context,
    builder: (_) =>
        _IncomeDialog(people: people, person: person, existing: existing),
  );
}

class _IncomeDialog extends StatefulWidget {
  final List<String> people;
  final int? person;
  final Recurring? existing;

  const _IncomeDialog({
    required this.people,
    required this.person,
    required this.existing,
  });

  @override
  State<_IncomeDialog> createState() => _IncomeDialogState();
}

class _IncomeDialogState extends State<_IncomeDialog> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late _Kind _kind;
  late int _person;

  /// Semanal: día de la semana (1 = lunes). Mensual y variable: día del mes.
  /// Quincena: primer día.
  late int _day;
  late int _secondDay;
  late WeekendShift _shift;
  String? _error;

  /// Lo normal es cobrar cada semana; las otras formas quedan escondidas
  /// hasta que se pidan (o si el ingreso ya era de otra forma).
  late bool _showKinds;

  /// Semanal y nuevo: el primer pago de este mes que hay que anotar.
  DateTime? _firstPayment;

  /// Días de pago de este mes para el día de la semana elegido.
  List<DateTime> get _paydaysThisMonth {
    final now = DateTime.now();
    return [
      for (var d = 1; d <= daysInMonth(now.month, now.year); d++)
        if (DateTime(now.year, now.month, d).weekday == _day)
          DateTime(now.year, now.month, d),
    ];
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.description ?? 'Sueldo');
    _amount = TextEditingController(text: e?.amount.toStringAsFixed(2) ?? '');
    _person = widget.person ?? e?.person ?? 0;
    _kind = e == null
        ? _Kind.weekly
        : e.confirm
        ? _Kind.variable
        : switch (e.frequency) {
            Frequency.weekly => _Kind.weekly,
            Frequency.monthly => _Kind.monthly,
            Frequency.biweekly => _Kind.twice,
          };
    _day = e?.day ?? DateTime.friday;
    _secondDay = e?.secondDay ?? 30;
    _shift = e?.weekendShift ?? WeekendShift.previous;
    _showKinds = _kind != _Kind.weekly;
    if (e == null) _firstPayment = _paydaysThisMonth.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _changeKind(_Kind kind) {
    if (kind == _kind) return;
    setState(() {
      // Al pasar de semanal a un día del mes (o al revés) se propone un día
      // típico, porque el número ya no significa lo mismo.
      if (kind == _Kind.weekly) {
        _day = DateTime.friday;
        if (widget.existing == null) _firstPayment = _paydaysThisMonth.first;
      } else if (_kind == _Kind.weekly) {
        _day = kind == _Kind.twice ? 15 : 30;
      }
      _kind = kind;
    });
  }

  void _save() {
    final amount = parseAmount(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Escribe cuánto te pagan');
      return;
    }
    final name = _name.text.trim();
    final now = DateTime.now();
    Navigator.of(context).pop((
      // Nuevo: semanal desde el pago elegido; quincena desde el inicio del
      // mes (como un sueldo mensual, que también cuenta el de este mes).
      firstPayment: widget.existing != null
          ? null
          : switch (_kind) {
              _Kind.weekly => _firstPayment,
              _Kind.twice => DateTime(now.year, now.month, 1),
              _ => null,
            },
      item: Recurring(
        type: RecurringType.income,
        person: _person,
        description: name.isEmpty ? 'Ingreso' : name,
        amount: amount,
        day: _day,
        secondDay: _secondDay,
        frequency: switch (_kind) {
          _Kind.weekly => Frequency.weekly,
          _Kind.twice => Frequency.biweekly,
          _ => Frequency.monthly,
        },
        confirm: _kind == _Kind.variable,
        weekendShift: _kind == _Kind.monthly || _kind == _Kind.twice
            ? _shift
            : WeekendShift.none,
      ),
    ));
  }

  Future<void> _pickDay(String title, int current, ValueSetter<int> set) async {
    final day = await showDayPicker(context, title: title, initial: current);
    if (day != null) setState(() => set(day));
  }

  Widget _dayButton(String label, int day, ValueSetter<int> set) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pickDay(label, day, set),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.calendar_month_outlined),
          ),
          child: Text('Día $day', style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    return AlertDialog(
      title: Text(widget.existing == null ? 'Nuevo ingreso' : 'Editar ingreso'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.person == null && widget.people.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (var i = 0; i < widget.people.length; i++)
                      ButtonSegment(value: i, label: Text(widget.people[i])),
                  ],
                  selected: {_person},
                  onSelectionChanged: (v) => setState(() => _person = v.first),
                ),
              ),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre (ej. Sueldo, Cliente X)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: switch (_kind) {
                  _Kind.weekly => 'Cuánto te pagan cada semana',
                  _Kind.twice => 'Cuánto te pagan cada vez',
                  _Kind.variable => 'Cuánto cobras al mes, más o menos',
                  _Kind.monthly => 'Cuánto te pagan al mes',
                },
                prefixText: '${currencySettings.currency.symbol} ',
              ),
            ),
            const SizedBox(height: 16),
            if (_showKinds) ...[
              Text('Te pagan', style: small),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final kind in _Kind.values)
                    ChoiceChip(
                      label: Text(_kindLabels[kind]!),
                      selected: _kind == kind,
                      onSelected: (_) => _changeKind(kind),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            ...switch (_kind) {
              _Kind.weekly => [
                Text('Qué día te pagan', style: small),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var d = 1; d <= 7; d++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: ChoiceChip(
                            label: Text(weekdayNames[d - 1].characters.first),
                            showCheckmark: false,
                            padding: EdgeInsets.zero,
                            labelPadding: EdgeInsets.zero,
                            selected: _day == d,
                            onSelected: (_) => setState(() {
                              _day = d;
                              if (widget.existing == null) {
                                _firstPayment = _paydaysThisMonth.first;
                              }
                            }),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Todos los ${weekdayNames[(_day - 1).clamp(0, 6)].toLowerCase()}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (widget.existing == null) ...[
                  const SizedBox(height: 12),
                  Text('Primer pago de este mes', style: small),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final date in _paydaysThisMonth)
                        ChoiceChip(
                          label: Text(
                            '${weekdayNames[date.weekday - 1].substring(0, 3).toLowerCase()} '
                            '${date.day}',
                          ),
                          selected: _firstPayment == date,
                          onSelected: (_) =>
                              setState(() => _firstPayment = date),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Desde ese pago se anotan en Resumen → Ingresos del mes.',
                    style: small,
                  ),
                ],
                if (!_showKinds)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => setState(() => _showKinds = true),
                      child: const Text('¿No te pagan cada semana?'),
                    ),
                  ),
              ],
              _Kind.monthly => [
                _dayButton('Día de pago', _day, (d) => _day = d),
              ],
              _Kind.twice => [
                _dayButton('Primer pago', _day, (d) => _day = d),
                _dayButton('Segundo pago', _secondDay, (d) => _secondDay = d),
              ],
              _Kind.variable => [
                _dayButton('Día aproximado', _day, (d) => _day = d),
                const SizedBox(height: 6),
                Text(
                  'Cada mes te preguntamos cuánto cobraste y qué día.',
                  style: small,
                ),
              ],
            },
            if (_kind == _Kind.monthly || _kind == _Kind.twice) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<WeekendShift>(
                isExpanded: true,
                initialValue: _shift,
                decoration: const InputDecoration(
                  labelText: 'Si ese día cae sábado o domingo, cobras',
                ),
                items: [
                  for (final e in weekendShiftLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _shift = v ?? _shift),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
