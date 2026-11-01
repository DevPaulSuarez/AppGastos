import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/couple/space_state.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/category_select_widget.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
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

  /// Notas que se ofrecen con un toque para la categoría elegida: las
  /// sugeridas y las que más se usaron antes.
  List<String> _quickNotes = const [];

  /// Si es una compra para otra persona que la devolverá: su nombre.
  String? owedBy;

  /// Monto tal como se escribe en el teclado, por ejemplo "12,5".
  String input = '';
  int payer = 0;
  late final Stream<List<String>> _people;

  double get value => parseAmount(input) ?? 0;

  /// true: se registra un ingreso (por ejemplo, el pago de un cliente).
  bool isIncome = false;

  /// Compra pagada con la propina de quien pagó (no se cuenta dos veces).
  bool withAllowance = false;

  /// Si alguien tiene propina configurada (si no, no se ofrece la opción).
  bool _hasAllowances = false;

  /// La opción "con propina" tiene sentido solo para gastos normales.
  bool get _allowanceApplies =>
      !isIncome &&
      owedBy == null &&
      category != null &&
      isSpendingCategory(category!) &&
      category != propinaCategory;

  bool get _canSave =>
      value > 0 && (isIncome || category != null || owedBy != null);

  DateTime date = DateTime.now();

  /// Última fecha pasada (no de hoy) con la que se guardó algo. Sirve para
  /// preguntar si el siguiente registro va en esa misma fecha.
  DateTime? _lastDate;

  /// true si ya se eligió la fecha (con el calendario o con la pregunta).
  bool _dateChosen = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _buttonAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _pageAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
    );

    _controller.addListener(() {
      setState(() {});
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        Navigator.of(context).pop();
      }
    });

    _controller.forward();

    _people = Provider.of<FinanceRepository>(
      context,
      listen: false,
    ).watchPeople();
    Provider.of<FinanceRepository>(
      context,
      listen: false,
    ).watchRecurring().first.then((items) {
      final has = items.any((r) => r.type == RecurringType.allowance);
      if (has && mounted) setState(() => _hasAllowances = true);
    });
    // En pareja, quien anota es quien pagó (se puede cambiar). En cuenta
    // individual se recuerda el último.
    final me = Provider.of<SpaceState>(context, listen: false).myPerson;
    if (me != null) payer = me;
    SharedPreferences.getInstance().then((prefs) {
      final lastPayer = prefs.getInt('last_payer');
      if (me == null && lastPayer != null && mounted) {
        setState(() => payer = lastPayer);
      }
      final last = prefs.getString('last_date');
      final parsed = last == null ? null : DateTime.tryParse(last);
      if (parsed != null && !_isToday(parsed) && mounted) {
        setState(() => _lastDate = parsed);
        _askDateWhenOpen();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String get _dateLabel => _labelFor(date);

  String _labelFor(DateTime date) {
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
    if (newDate != null) {
      setState(() {
        date = newDate;
        _dateChosen = true;
      });
    }
  }

  /// Pregunta la fecha apenas termina de abrirse la pantalla.
  void _askDateWhenOpen() {
    if (_controller.isCompleted) {
      _askDate();
      return;
    }
    late void Function(AnimationStatus) listener;
    listener = (status) {
      if (status == AnimationStatus.completed) {
        _controller.removeStatusListener(listener);
        _askDate();
      }
    };
    _controller.addStatusListener(listener);
  }

  /// Si la última vez se guardó con una fecha pasada, pregunta si este
  /// registro es de hoy o de esa fecha. Si se cierra sin elegir, queda hoy.
  Future<void> _askDate() async {
    final last = _lastDate;
    if (_dateChosen || last == null || _isToday(last)) return;
    final lastLabel = _labelFor(last);
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('¿De qué fecha es?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, DateTime.now()),
            child: const ListTile(
              leading: Icon(Icons.today),
              title: Text('Hoy'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, last),
            child: ListTile(
              leading: const Icon(Icons.history),
              title: Text(lastLabel),
              subtitle: const Text('La última fecha que usaste'),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      if (picked != null) date = picked;
      _dateChosen = true;
    });
  }

  /// Recuerda la fecha si fue pasada; si fue hoy, la olvida para no
  /// preguntar más.
  void _rememberDate() {
    final saved = date;
    SharedPreferences.getInstance().then((prefs) {
      if (_isToday(saved)) {
        prefs.remove('last_date');
      } else {
        prefs.setString(
          'last_date',
          DateTime(saved.year, saved.month, saved.day).toIso8601String(),
        );
      }
    });
  }

  Future<void> _editNote() async {
    final values = await showFieldsDialog(
      context,
      title: isIncome ? '¿De dónde vino?' : '¿En qué gastaste?',
      confirm: 'Listo',
      fields: [DialogField('Nota (opcional)', initial: detalle ?? '')],
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
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
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
          children: [
            _noteButton(),
            if (!isIncome) _loanChip(),
            if (_hasAllowances && !isIncome && owedBy == null) _allowanceChip(),
          ],
        ),
        if (isIncome)
          _incomeHint()
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CategorySelectionWidget(
              categories: categories.keys.toList(),
              selected: category,
              onSelected: _selectCategory,
            ),
          ),
        if (!isIncome && _quickNotes.isNotEmpty) _quickNotesRow(),
        _payerSelector(),
        _numpad(),
        SizedBox(height: _buttonHeight + 24 + bottom),
      ],
    );
  }

  void _selectCategory(String newCategory) {
    setState(() {
      category = newCategory;
      _quickNotes = noteSuggestions(newCategory);
    });
    Provider.of<ExpensesRepository>(
      context,
      listen: false,
    ).queryAllByCategory(newCategory).first.then((expenses) {
      if (!mounted || category != newCategory) return;
      setState(() => _quickNotes = _mergeNotes(newCategory, expenses));
    });
  }

  /// Las sugeridas primero y luego las notas más usadas, sin repetir.
  List<String> _mergeNotes(String category, List<Expense> expenses) {
    final counts = <String, int>{};
    for (final e in expenses) {
      final note = e.description.trim();
      // Sin nota se guarda el nombre de la categoría.
      if (note.isEmpty || note == category) continue;
      counts[note] = (counts[note] ?? 0) + 1;
    }
    final used = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final notes = <String>[];
    for (final note in [...noteSuggestions(category), ...used]) {
      if (!notes.any((n) => n.toLowerCase() == note.toLowerCase())) {
        notes.add(note);
      }
    }
    return notes.take(8).toList();
  }

  Widget _quickNotesRow() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final note in _quickNotes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(note),
                selected: detalle == note,
                onSelected: (selected) =>
                    setState(() => detalle = selected ? note : null),
              ),
            ),
        ],
      ),
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
              'Anota solo el dinero que entra de afuera: un cliente, un '
              'trabajo extra, una devolución. No anotes envíos entre ustedes '
              'ni lo que sacas de la caja chica. Los sueldos se anotan solos.',
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
        hasNote ? detalle! : (isIncome ? 'Cliente o trabajo' : 'Agregar nota'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
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

  Widget _allowanceChip() {
    return FilterChip(
      avatar: withAllowance ? null : const Icon(Icons.redeem, size: 18),
      label: const Text('Pagado con propina'),
      selected: withAllowance,
      tooltip:
          'La propina ya se contó al entregarla; este gasto no se suma '
          'otra vez',
      onSelected: (value) => setState(() => withAllowance = value),
    );
  }

  Future<void> _askOwedBy() async {
    final values = await showFieldsDialog(
      context,
      title: '¿Quién te lo devolverá?',
      confirm: 'Listo',
      hint:
          'No se cuenta como gasto suyo: queda "por cobrar" hasta que te '
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
        // En cuenta individual siempre paga la misma persona (aunque antes,
        // en pareja, el último registro lo hubiera pagado la otra).
        if (people.length < 2) {
          payer = 0;
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Text(
                isIncome ? 'Recibió' : 'Pagó',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (var i = 0; i < people.length; i++)
                      ButtonSegment(
                        value: i,
                        label: Text(
                          people[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                ? Icon(
                    Icons.backspace_outlined,
                    color: scheme.onSurfaceVariant,
                    semanticLabel: 'Borrar',
                  )
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
                  children: [for (final key in row) Expanded(child: _num(key))],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Aviso si lo que se va a guardar parece mover dinero de un lado a otro
  /// (envíos entre ustedes, retiros, caja chica), que no se anota así.
  Future<bool> _confirmNotAMove() async {
    String plain(String s) => s
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
    final note = plain(detalle ?? '');
    if (note.isEmpty) return true;
    bool has(List<String> words) =>
        words.any((w) => RegExp('\\b${RegExp.escape(w)}').hasMatch(note));

    String? title;
    String? message;
    if (has(['caja chica', 'caja'])) {
      title = '¿Es de la caja chica?';
      message =
          'Si sacas o devuelves dinero de la caja chica, no lo anotes '
          'como gasto ni ingreso. Usa la tarjeta "Caja chica" en Inicio: '
          '"Sacar" o "Ya devolví".';
    } else if (has(['retiro', 'cajero', 'atm'])) {
      title = '¿Es un retiro del cajero?';
      message =
          'Sacar dinero del banco no es un gasto: sigue siendo de ustedes. '
          'Anota lo que hiciste con ese dinero, por ejemplo en Iglesia lo '
          'que diste.';
    } else {
      final people = await Provider.of<FinanceRepository>(
        context,
        listen: false,
      ).watchPeople().first;
      final names = people.length > 1
          ? people.map(plain).where((n) => n.length > 2).toList()
          : <String>[];
      final looksLikeTransfer =
          has(['envio', 'transferencia', 'transfer']) ||
          ((isIncome || category == 'Otros') && has(names));
      if (looksLikeTransfer) {
        title = '¿Es dinero entre ustedes?';
        message =
            'Pasar dinero de una cuenta a la otra no se anota: el dinero '
            'sigue siendo de los dos. Solo se anota lo que sale o entra de '
            'afuera.';
      }
    }
    if (title == null || !mounted) return true;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title!),
        content: Text(message!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar igual'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No guardar'),
          ),
        ],
      ),
    );
    return save ?? false;
  }

  Future<void> _save() async {
    if (!await _confirmNotAMove() || !mounted) return;
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
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setInt('last_payer', payer),
      );
      _rememberDate();
      _controller.reverse();
      return;
    }
    if (owedBy != null) {
      final what = (detalle == null || detalle!.isEmpty)
          ? (category ?? 'Compra')
          : detalle!;
      db.addLoan(value, date, what, owedBy!, payer);
      _rememberDate();
      _controller.reverse();
      return;
    }
    if (category == ahorroCategory) {
      // No se puede apartar más de lo que tienen disponible, sin lo que
      // falta pagar este mes.
      final finance = Provider.of<FinanceRepository>(context, listen: false);
      final available = await finance.freeForSavings();
      if (!mounted) return;
      if (value > available + 0.001) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              available > 0
                  ? 'Solo hay ${money(available)} disponibles para ahorrar'
                  : 'No hay dinero disponible para ahorrar',
            ),
          ),
        );
        return;
      }
    }
    final note = (detalle == null || detalle!.isEmpty) ? category! : detalle!;
    if (withAllowance && _allowanceApplies) {
      // Solo se descuenta de la propina lo que queda de ella este mes; lo
      // que pase de eso es un gasto normal.
      final messenger = ScaffoldMessenger.of(context);
      // Se pide de nuevo: _people ya lo escucha el selector de quién pagó.
      final people = await Provider.of<FinanceRepository>(
        context,
        listen: false,
      ).watchPeople().first;
      final left = await db.allowanceLeft(payer, date.month, date.year);
      if (!mounted) return;
      final who = personName(people, payer);
      if (left <= 0.001) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              people.length == 1
                  ? 'No te queda propina este mes'
                  : 'A $who no le queda propina este mes',
            ),
          ),
        );
        return;
      }
      final used = min(value, left);
      await db.addWithAllowance(
        category!,
        value,
        date,
        note,
        paidBy: payer,
        fromAllowance: used,
      );
      if (used < value) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${money(used)} salieron de la propina; los '
              '${money(value - used)} restantes cuentan como gasto normal',
            ),
          ),
        );
      }
    } else {
      db.add(category!, value, date, note, paidBy: payer);
    }
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setInt('last_payer', payer),
    );
    _rememberDate();
    _controller.reverse();
  }

  Widget _submit() {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final bottom = MediaQuery.of(context).padding.bottom;
    final finalRect = Rect.fromLTWH(
      16,
      size.height - bottom - 16 - _buttonHeight,
      size.width - 32,
      _buttonHeight,
    );

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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          category == null
                              ? 'Elige una categoría'
                              : 'Escribe el monto',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
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
