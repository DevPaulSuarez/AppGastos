import 'dart:math';

import 'package:primera_app_curso/cash.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/utils.dart';

/// Ingresos, gastos fijos, presupuestos, metas de ahorro y nombres de la
/// pareja.
class FinanceRepository {
  static const _incomes = 'incomes';
  static const _recurring = 'recurring';
  static const _budgets = 'budgets';
  static const _goals = 'goals';
  static const _settings = 'settings';
  static const _peopleId = 'people';

  static const defaultPeople = ['Persona 1', 'Persona 2'];

  final Store store;
  Future<void>? _applying;

  FinanceRepository(this.store);

  // Pareja

  Stream<List<String>> watchPeople() {
    return store.watch(_settings).map((docs) {
      final doc = docs.where((d) => d.id == _peopleId).firstOrNull;
      final names = (doc?.data['names'] as List?)?.cast<String>();
      return names != null && names.length == 2 ? names : defaultPeople;
    });
  }

  Future<void> setPeople(List<String> names) {
    return store.set(_settings, _peopleId, {"names": names});
  }

  // Moneda

  static const _currencyId = 'currency';

  Stream<CurrencySettings> watchCurrencySettings() {
    return store.watch(_settings).map((docs) => CurrencySettings.fromMap(
        docs.where((d) => d.id == _currencyId).firstOrNull?.data));
  }

  Future<void> saveCurrencySettings(CurrencySettings settings) {
    return store.set(_settings, _currencyId, settings.toMap());
  }

  // Comparación con el dinero real

  static const _cashId = 'cash';

  Stream<CashCheck?> watchCashCheck() {
    return store.watch(_settings).map((docs) {
      final data = docs.where((d) => d.id == _cashId).firstOrNull?.data;
      return data == null ? null : CashCheck.fromMap(data);
    });
  }

  Future<void> saveCashCheck(CashCheck check) =>
      store.set(_settings, _cashId, check.toMap());

  // Categorías

  static const _categoriesId = 'categories';

  Stream<CategorySettings> watchCategorySettings() {
    return store.watch(_settings).map((docs) => CategorySettings.fromMap(
        docs.where((d) => d.id == _categoriesId).firstOrNull?.data));
  }

  Future<void> saveCategorySettings(CategorySettings settings) {
    return store.set(_settings, _categoriesId, settings.toMap());
  }

  /// Cambia el nombre de una categoría en todo lo ya registrado: gastos,
  /// gastos fijos y presupuesto.
  Future<void> renameCategory(String from, String to) async {
    for (final doc
        in await store.watch('expenses', where: {"category": from}).first) {
      await store.set('expenses', doc.id, {...doc.data, "category": to});
    }
    for (final doc in await store.watch(_recurring).first) {
      if (doc.data['category'] == from) {
        await store.set(_recurring, doc.id, {...doc.data, "category": to});
      }
    }
    final budget = await store.get(_budgets, from);
    if (budget != null) {
      await store.set(_budgets, to, budget.data);
      await store.delete(_budgets, from);
    }
  }

  // Ingresos

  Stream<List<Income>> _incomesWhere(Map<String, Object?> where) {
    return store.watch(_incomes, where: where).map((docs) =>
        docs.map((doc) => Income.fromMap(doc.id, doc.data)).toList());
  }

  Stream<List<Income>> watchIncomes(int month, int year) =>
      _incomesWhere({"month": month, "year": year});

  Stream<List<Income>> watchIncomesByYear(int year) =>
      _incomesWhere({"year": year});

  Stream<List<Income>> watchAllIncomes() => _incomesWhere({});

  Future<void> addIncome(int person, String description, double amount,
      int month, int year,
      {int day = 1}) {
    return store.add(
        _incomes,
        Income(
          id: '',
          person: person,
          description: description,
          amount: amount,
          day: day,
          month: month,
          year: year,
        ).toMap());
  }

  Future<void> deleteIncome(String id) => store.delete(_incomes, id);

  // Ingresos y gastos fijos

  Stream<List<Recurring>> watchRecurring() {
    return store.watch(_recurring).map((docs) =>
        docs.map((doc) => Recurring.fromMap(doc.id, doc.data)).toList());
  }

  Future<void> saveRecurring(Recurring recurring, {DateTime? today}) async {
    var item = recurring;
    // Una propina nueva no cobra periodos pasados: empieza con el periodo en
    // curso, que se registra en el momento.
    if (item.id.isEmpty &&
        item.type == RecurringType.allowance &&
        item.lastApplied == null) {
      item = item.copyWith(lastApplied: _dateKey(today ?? DateTime.now()));
    }
    // Un pago semanal o quincenal nuevo cuenta desde hoy (incluido).
    if (item.id.isEmpty && item.isDated && item.lastApplied == null) {
      final now = today ?? DateTime.now();
      item = item.copyWith(
          lastApplied:
              _dateKey(DateTime(now.year, now.month, now.day - 1)));
    }
    if (item.id.isEmpty) {
      await store.add(_recurring, item.toMap());
    } else {
      await store.set(_recurring, item.id, item.toMap());
    }
    await applyRecurring(today: today);
  }

  Future<void> deleteRecurring(String id) => store.delete(_recurring, id);

  /// Guarda los cambios de un fijo o propina ya existente. También corrige
  /// lo que ya se registró en el periodo en curso con los datos nuevos.
  Future<void> updateRecurring(Recurring previous, Recurring updated) async {
    var lastApplied = previous.lastApplied;
    // Si una propina cambia de frecuencia, se toma como último pago el día
    // de pago anterior según la nueva frecuencia.
    if (updated.type == RecurringType.allowance &&
        lastApplied != null &&
        previous.biweekly != updated.biweekly) {
      final last = _parseKey(lastApplied);
      final candidates = [
        ...payoutDates(last.year, last.month - 1, updated.biweekly),
        ...payoutDates(last.year, last.month, updated.biweekly),
      ].where((d) => !d.isAfter(last));
      lastApplied = _dateKey(candidates.last);
    }
    // Si un sueldo o gasto fijo cambia de frecuencia, sigue desde hoy con
    // la nueva (lo ya registrado se mantiene).
    if (updated.type != RecurringType.allowance &&
        lastApplied != null &&
        previous.frequency != updated.frequency) {
      final now = DateTime.now();
      lastApplied = updated.isDated
          ? _dateKey(DateTime(now.year, now.month, now.day))
          : '${now.year}-${now.month}';
    }
    final item = updated.copyWith(id: previous.id, lastApplied: lastApplied);
    await store.set(_recurring, item.id, item.toMap());

    if (previous.lastApplied == null) return;
    final recordId = 'rec_${item.id}_${previous.lastApplied}';
    if (item.type == RecurringType.income) {
      final doc = await store.get(_incomes, recordId);
      if (doc == null) return;
      final income = Income.fromMap(doc.id, doc.data);
      await store.set(
          _incomes,
          recordId,
          Income(
            id: recordId,
            person: item.person,
            description: item.description,
            amount: item.amount,
            day: item.isDated
                ? income.day
                : min(item.day, daysInMonth(income.month, income.year)),
            month: income.month,
            year: income.year,
          ).toMap());
    } else {
      final doc = await store.get('expenses', recordId);
      if (doc == null) return;
      final expense = Expense.fromMap(doc.id, doc.data);
      await store.set(
          'expenses',
          recordId,
          Expense(
            id: recordId,
            category: item.type == RecurringType.allowance
                ? propinaCategory
                : item.category,
            value: item.amount,
            day: item.type == RecurringType.allowance || item.isDated
                ? expense.day
                : min(item.day, daysInMonth(expense.month, expense.year)),
            month: expense.month,
            year: expense.year,
            description: item.description,
            paidBy: item.person,
          ).toMap());
    }
  }

  /// Registra los sueldos, gastos fijos y propinas que ya tocaban y aún no se
  /// registraron, incluidos los meses en que no se abrió la app.
  Future<void> applyRecurring({DateTime? today}) {
    return _applying = (_applying ?? Future.value())
        .then((_) => _apply(today ?? DateTime.now()));
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static DateTime _parseKey(String key) {
    final parts = key.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts.length > 2 ? parts[2] : 1);
  }

  Future<void> _apply(DateTime today) async {
    final items = await watchRecurring().first;
    for (final item in items) {
      if (item.type == RecurringType.allowance) {
        await _applyAllowance(item, today);
      } else if (item.confirm) {
        // Fecha variable: queda pendiente hasta que confirmen el pago.
        continue;
      } else if (item.isDated) {
        await _applyDated(item, today);
      } else {
        await _applyMonthly(item, today);
      }
    }
  }

  Future<void> _applyMonthly(Recurring item, DateTime today) async {
    final current = DateTime(today.year, today.month);
    final last = item.lastApplied == null ? null : _parseKey(item.lastApplied!);
    var month = last == null ? current : DateTime(last.year, last.month + 1);
    if (month.isAfter(current)) return;

    var key = '';
    for (; !month.isAfter(current); month = DateTime(month.year, month.month + 1)) {
      key = '${month.year}-${month.month}';
      // El id depende del mes, así no se duplica aunque se aplique dos veces.
      final id = 'rec_${item.id}_$key';
      final date = occurrences(item, month.year, month.month).single;
      if (item.type == RecurringType.income) {
        await store.set(
            _incomes,
            id,
            Income(
              id: id,
              person: item.person,
              description: item.description,
              amount: item.amount,
              day: date.day,
              month: date.month,
              year: date.year,
            ).toMap());
      } else {
        await store.set(
            'expenses',
            id,
            Expense(
              id: id,
              category: item.category,
              value: item.amount,
              day: date.day,
              month: date.month,
              year: date.year,
              description: item.description,
              paidBy: item.person,
            ).toMap());
      }
    }
    await store.set(
        _recurring, item.id, item.copyWith(lastApplied: key).toMap());
  }

  /// Días en que toca un sueldo o gasto fijo dentro de un mes, ya movidos
  /// si caen fin de semana y así se indicó.
  static List<DateTime> occurrences(Recurring item, int year, int month) {
    final last = daysInMonth(month, year);
    final dates = switch (item.frequency) {
      Frequency.monthly => [DateTime(year, month, min(item.day, last))],
      Frequency.biweekly => payoutDates(year, month, true),
      Frequency.weekly => [
          for (var d = 1; d <= last; d++)
            if (DateTime(year, month, d).weekday == item.day)
              DateTime(year, month, d),
        ],
    };
    return [for (final d in dates) shiftWeekend(d, item.weekendShift)];
  }

  /// Pagos de fecha variable (sueldos o gastos) que todavía no confirmaron
  /// en el mes indicado.
  static List<Recurring> pendingConfirmations(
    List<Recurring> items,
    Set<String> registeredIds,
    int month,
    int year,
  ) =>
      items
          .where((r) =>
              r.confirm &&
              r.type != RecurringType.allowance &&
              !registeredIds.contains('rec_${r.id}_$year-$month'))
          .toList()
        ..sort((a, b) => a.day.compareTo(b.day));

  /// Registra un pago de fecha variable del mes [month]/[year], con el monto
  /// y el día en que realmente se pagó o cobró.
  Future<void> confirmRecurring(Recurring item, double amount, DateTime date,
      int month, int year) async {
    final id = 'rec_${item.id}_$year-$month';
    if (item.type == RecurringType.income) {
      await store.set(
          _incomes,
          id,
          Income(
            id: id,
            person: item.person,
            description: item.description,
            amount: amount,
            day: date.day,
            month: date.month,
            year: date.year,
          ).toMap());
    } else {
      await store.set(
          'expenses',
          id,
          Expense(
            id: id,
            category: item.category,
            value: amount,
            day: date.day,
            month: date.month,
            year: date.year,
            description: item.description,
            paidBy: item.person,
          ).toMap());
    }
  }

  /// Sueldos y gastos semanales o quincenales: se registra cada pago el día
  /// que toca, incluidos los que pasaron sin abrir la app.
  Future<void> _applyDated(Recurring item, DateTime today) async {
    final todayDate = DateTime(today.year, today.month, today.day);
    final last =
        item.lastApplied == null ? todayDate : _parseKey(item.lastApplied!);
    final due = <DateTime>[];
    for (var m = DateTime(last.year, last.month);
        !m.isAfter(todayDate);
        m = DateTime(m.year, m.month + 1)) {
      for (final date in occurrences(item, m.year, m.month)) {
        if (date.isAfter(last) && !date.isAfter(todayDate)) due.add(date);
      }
    }
    for (final date in due) {
      final id = 'rec_${item.id}_${_dateKey(date)}';
      if (item.type == RecurringType.income) {
        await store.set(
            _incomes,
            id,
            Income(
              id: id,
              person: item.person,
              description: item.description,
              amount: item.amount,
              day: date.day,
              month: date.month,
              year: date.year,
            ).toMap());
      } else {
        await store.set(
            'expenses',
            id,
            Expense(
              id: id,
              category: item.category,
              value: item.amount,
              day: date.day,
              month: date.month,
              year: date.year,
              description: item.description,
              paidBy: item.person,
            ).toMap());
      }
    }
    if (due.isNotEmpty) {
      await store.set(_recurring, item.id,
          item.copyWith(lastApplied: _dateKey(due.last)).toMap());
    }
  }

  /// Días de pago de una propina en un mes: el 15 (si es quincenal) y el
  /// 30. En febrero el fin de mes es el 28, o el 29 en años bisiestos.
  static List<DateTime> payoutDates(int year, int month, bool biweekly) => [
        if (biweekly) DateTime(year, month, 15),
        DateTime(year, month, min(30, daysInMonth(month, year))),
      ];

  static bool _isPayoutDate(DateTime date, bool biweekly) =>
      payoutDates(date.year, date.month, biweekly).contains(date) ||
      // Versiones anteriores pagaban el último día (31).
      date.day == daysInMonth(date.month, date.year);

  /// Primer día de pago desde [from] (incluido).
  static DateTime _nextPayout(DateTime from, bool biweekly) => [
        ...payoutDates(from.year, from.month, biweekly),
        ...payoutDates(from.year, from.month + 1, biweekly),
      ].firstWhere((d) => !d.isBefore(from));

  Future<void> _registerAllowance(
      Recurring item, DateTime period, DateTime date) {
    // El id depende del periodo, así cada propina se registra una sola vez.
    final id = 'rec_${item.id}_${_dateKey(period)}';
    return store.set(
        'expenses',
        id,
        Expense(
          id: id,
          category: propinaCategory,
          value: item.amount,
          day: date.day,
          month: date.month,
          year: date.year,
          description: item.description,
          paidBy: item.person,
        ).toMap());
  }

  Future<void> _applyAllowance(Recurring item, DateTime today) async {
    final todayDate = DateTime(today.year, today.month, today.day);
    var last =
        item.lastApplied == null ? todayDate : _parseKey(item.lastApplied!);

    // Propina recién creada (aún no se pagó ningún periodo): la del periodo
    // en curso se entrega en el momento, para que se vea desde ya.
    if (!_isPayoutDate(last, item.biweekly)) {
      final period = _nextPayout(last, item.biweekly);
      await _registerAllowance(
          item, period, period.isAfter(todayDate) ? todayDate : period);
      last = period;
    }

    // Días de pago pendientes desde el último registro.
    final due = <DateTime>[];
    for (var m = DateTime(last.year, last.month);
        !m.isAfter(todayDate);
        m = DateTime(m.year, m.month + 1)) {
      for (final date in payoutDates(m.year, m.month, item.biweekly)) {
        if (date.isAfter(last) && !date.isAfter(todayDate)) due.add(date);
      }
    }
    for (final date in due) {
      await _registerAllowance(item, date, date);
    }

    final newKey = _dateKey(due.isEmpty ? last : due.last);
    if (newKey != item.lastApplied) {
      await store.set(
          _recurring, item.id, item.copyWith(lastApplied: newKey).toMap());
    }
  }

  // Presupuestos (monto mensual por categoría)

  Stream<Map<String, double>> watchBudgets() {
    return store.watch(_budgets).map((docs) => {
          for (final doc in docs)
            doc.id: currencySettings.convert(
                (doc.data['amount'] as num).toDouble(),
                doc.data['currency'] as String?),
        });
  }

  Future<void> setBudget(String category, double amount) {
    if (amount <= 0) return store.delete(_budgets, category);
    return store.set(_budgets, category,
        {"amount": amount, "currency": currencySettings.code});
  }

  // Metas de ahorro

  Stream<List<Goal>> watchGoals() {
    return store.watch(_goals).map((docs) =>
        docs.map((doc) => Goal.fromMap(doc.id, doc.data)).toList());
  }

  Future<void> addGoal(String name, double target) {
    return store.add(_goals, Goal(id: '', name: name, target: target).toMap());
  }

  Future<void> deleteGoal(String id) => store.delete(_goals, id);
}
