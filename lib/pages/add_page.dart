import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:primera_app_curso/cash.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/category_select_widget.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddPage extends StatefulWidget {
  final Rect buttonRect;

  const AddPage({Key? key, required this.buttonRect}) : super(key: key);

  @override
  _AddPageState createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> with SingleTickerProviderStateMixin {
  static const _buttonHeight = 56.0;

  late AnimationController _controller;
  late Animation<double> _buttonAnimation;
  late Animation<double> _pageAnimation;

  String? category;
  String? detalle;

  /// Si es una compra para otra persona que la devolverá: su nombre.
  String? owedBy;

  /// Monto tal como se escribe en el teclado, por ejemplo "12,5".
  String input = '';
  int payer = 0;
  late final Stream<List<String>> _people;

  double get value => parseAmount(input) ?? 0;
  /// true: se registra un ingreso (por ejemplo, el pago de un cliente).
  bool isIncome = false;

  bool get _canSave =>
      value > 0 && (isIncome || category != null || owedBy != null);

  DateTime date = DateTime.now();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _buttonAnimation = CurvedAnimation(
        parent: _controller, curve: Curves.easeOutCubic);

    _pageAnimation = CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic));

    _controller.addListener(() {
      setState(() {});
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        Navigator.of(context).pop();
      }
    });

    _controller.forward();

    _people =
        Provider.of<FinanceRepository>(context, listen: false).watchPeople();
    SharedPreferences.getInstance().then((prefs) {
      final lastPayer = prefs.getInt('last_payer');
      if (lastPayer != null && mounted) setState(() => payer = lastPayer);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _dateLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    final month = monthNames[date.month - 1].substring(0, 3).toLowerCase();
    return '${date.day} $month${date.year != now.year ? ' ${date.year}' : ''}';
  }

  Future<void> _pickDate() async {
    final newDate = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (newDate != null) setState(() => date = newDate);
  }

  Future<void> _editNote() async {
    final values = await showFieldsDialog(
      context,
      title: isIncome ? '¿De dónde vino?' : '¿En qué gastaste?',
      confirm: 'Listo',
      fields: [
        DialogField('Nota (opcional)', initial: detalle ?? ''),
      ],
    );
    if (values != null) setState(() => detalle = values[0]);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Stack(
      children: [
        Transform.translate(
          offset: Offset(0, h * (1 - _pageAnimation.value)),
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              leading: IconButton(
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close),
                onPressed: () => _controller.reverse(),
              ),
              title: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(value: false, label: Text('Gasto')),
                  ButtonSegment(value: true, label: Text('Ingreso')),
                ],
                selected: {isIncome},
                onSelectionChanged: (value) =>
                    setState(() => isIncome = value.first),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ActionChip(
                    avatar: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_dateLabel),
                    onPressed: _pickDate,
                  ),
                ),
              ],
            ),
            body: _body(),
          ),
        ),
        _submit(),
      ],
    );
  }

  Widget _body() {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Column(
      children: <Widget>[
        _currentValue(),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [_noteButton(), if (!isIncome) _loanChip()],
        ),
        if (isIncome)
          _incomeHint()
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CategorySelectionWidget(
              categories: categories.keys.toList(),
              selected: category,
              onSelected: (newCategory) =>
                  setState(() => category = newCategory),
            ),
          ),
        _payerSelector(),
        _numpad(),
        SizedBox(height: _buttonHeight + 24 + bottom),
      ],
    );
  }

  Widget _incomeHint() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.payments_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Para pagos que varían: un cliente, un proyecto, un trabajo '
              'extra. Los que se repiten igual se configuran en Ajustes.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteButton() {
    final hasNote = detalle != null && detalle!.isNotEmpty;
    return TextButton.icon(
      icon: Icon(hasNote ? Icons.edit_note : Icons.note_add_outlined),
      label: Text(
          hasNote
              ? detalle!
              : (isIncome ? 'Cliente o trabajo' : 'Agregar nota'),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      onPressed: _editNote,
    );
  }

  Widget _loanChip() {
    if (owedBy == null) {
      return ActionChip(
        avatar: const Icon(Icons.handshake_outlined, size: 18),
        label: const Text('Me lo devolverá'),
        onPressed: _askOwedBy,
      );
    }
    return InputChip(
      avatar: const Icon(Icons.handshake, size: 18),
      label: Text('Me lo devuelve $owedBy'),
      selected: true,
      onPressed: _askOwedBy,
      onDeleted: () => setState(() => owedBy = null),
    );
  }

  Future<void> _askOwedBy() async {
    final values = await showFieldsDialog(
      context,
      title: '¿Quién te lo devolverá?',
      confirm: 'Listo',
      hint: 'No se cuenta como gasto suyo: queda "por cobrar" hasta que te '
          'lo pague.',
      fields: [DialogField('Nombre (ej. Mi hermana)', initial: owedBy ?? '')],
      validate: (values) =>
          values[0].isEmpty ? 'Escribe a quién se lo compraste' : null,
    );
    if (values != null) setState(() => owedBy = values[0]);
  }

  Widget _payerSelector() {
    return StreamBuilder<List<String>>(
      stream: _people,
      builder: (context, snapshot) {
        final people = snapshot.data ?? FinanceRepository.defaultPeople;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Text(isIncome ? 'Recibió' : 'Pagó',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (var i = 0; i < people.length; i++)
                      ButtonSegment(
                        value: i,
                        label: Text(people[i],
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  selected: {payer},
                  onSelectionChanged: (value) =>
                      setState(() => payer = value.first),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _currentValue() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          "${currencySettings.currency.symbol} ${input.isEmpty ? '0' : input}",
          style: TextStyle(
            fontSize: 48.0,
            color: input.isEmpty ? scheme.outline : scheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  void _press(String text) {
    HapticFeedback.selectionClick();
    setState(() {
      if (text == ",") {
        if (!input.contains(',')) input = input.isEmpty ? '0,' : '$input,';
      } else if (text == "<") {
        if (input.isNotEmpty) input = input.substring(0, input.length - 1);
      } else {
        final decimals = input.contains(',') ? input.split(',')[1].length : 0;
        // Máximo 2 decimales y un monto razonable.
        if (decimals < 2 && input.length < 9) {
          input = input == '0' ? text : input + text;
        }
      }
    });
  }

  Widget _num(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _press(text),
          onLongPress: text == "<" ? () => setState(() => input = '') : null,
          child: Center(
            child: text == "<"
                ? Icon(Icons.backspace_outlined,
                    color: scheme.onSurfaceVariant, semanticLabel: 'Borrar')
                : Text(
                    text,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _numpad() {
    const rows = [
      ["1", "2", "3"],
      ["4", "5", "6"],
      ["7", "8", "9"],
      [",", "0", "<"],
    ];
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            for (final row in rows)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final key in row) Expanded(child: _num(key)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final db = Provider.of<ExpensesRepository>(context, listen: false);
    if (isIncome) {
      final finance = Provider.of<FinanceRepository>(context, listen: false);
      finance.addIncome(
        payer,
        (detalle == null || detalle!.isEmpty) ? 'Ingreso' : detalle!,
        value,
        date.month,
        date.year,
        day: date.day,
      );
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setInt('last_payer', payer));
      _controller.reverse();
      return;
    }
    if (owedBy != null) {
      final what = (detalle == null || detalle!.isEmpty)
          ? (category ?? 'Compra')
          : detalle!;
      db.addLoan(value, date, what, owedBy!, payer);
      _controller.reverse();
      return;
    }
    if (category == ahorroCategory) {
      // No se puede separar como ahorro más que el sobrante de ese mes.
      final finance = Provider.of<FinanceRepository>(context, listen: false);
      final available = monthLeftover(
          await finance.watchIncomes(date.month, date.year).first,
          await db.queryByMonth(date.month, date.year).first);
      if (!mounted) return;
      if (value > available + 0.001) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(available > 0
              ? 'Solo les sobran ${money(available)} este mes para ahorrar'
              : 'No tienen dinero disponible para ahorrar'),
        ));
        return;
      }
    }
    final note = (detalle == null || detalle!.isEmpty) ? category! : detalle!;
    db.add(category!, value, date, note, paidBy: payer);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt('last_payer', payer));
    _controller.reverse();
  }

  Widget _submit() {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final bottom = MediaQuery.of(context).padding.bottom;
    final finalRect = Rect.fromLTWH(16, size.height - bottom - 16 - _buttonHeight,
        size.width - 32, _buttonHeight);

    // El botón + se estira hasta convertirse en el botón "Aceptar".
    final t = _buttonAnimation.value;
    final rect = Rect.lerp(widget.buttonRect, finalRect, t)!;
    final radius = (widget.buttonRect.width / 2) * (1 - t) + 16 * t;
    final enabled = _canSave && t == 1;

    return Positioned.fromRect(
      rect: rect,
      child: Material(
        color: enabled || t < 1
            ? scheme.primary
            : scheme.onSurface.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: t < 1
              ? null
              : () {
                  if (_canSave) {
                    _save();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(category == null
                          ? 'Elige una categoría'
                          : 'Escribe el monto'),
                      duration: const Duration(seconds: 2),
                    ));
                  }
                },
          child: Center(
            child: Opacity(
              opacity: t,
              child: Text(
                isIncome
                    ? 'Guardar ingreso ${input.isEmpty ? '' : '${currencySettings.currency.symbol} $input'}'
                    : owedBy != null
                    ? 'Guardar ${input.isEmpty ? '' : '${currencySettings.currency.symbol} $input '}· por cobrar'
                    : category == null
                        ? 'Aceptar'
                        : 'Guardar ${input.isEmpty ? '' : '${currencySettings.currency.symbol} $input '}en $category',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled
                      ? scheme.onPrimary
                      : scheme.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w700,
                  fontSize: 17.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
