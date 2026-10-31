import 'dart:math';

import 'package:primera_app_curso/cash.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/petty_cash.dart';
import 'package:primera_app_curso/tithe.dart';
import 'package:primera_app_curso/utils.dart';

/// Primera vez que se abre la app: elegir si la cuenta es individual o de
/// pareja, luego cargar sueldos y gastos fijos, y después ya se usa normal.
enum AccountStep { choose, setup, ready }

/// Un pago fijo del mes en curso: lo que hay que pagar y, si ya se marcó
/// "Ya pagué", el gasto anotado.
class FixedPayment {
  final Recurring item;
  final Expense? paid;

  const FixedPayment(this.item, this.paid);

  /// Los pagos fijos del mes (los que esperan el "Ya pagué"), por día.
  static List<FixedPayment> ofMonth(
    List<Recurring> items,
    List<Expense> expenses,
    int month,
    int year,
  ) => [
    for (final item in items)
      if (item.type == RecurringType.expense && item.confirm)
        FixedPayment(
          item,
          expenses
              .where((e) => e.id == 'rec_${item.id}_$year-$month')
              .firstOrNull,
        ),
  ]..sort((a, b) => a.item.day.compareTo(b.item.day));
}

/// Aviso del teléfono para un día de pago o de cobro.
class Reminder {
  final int id;
  final DateTime when;
  final String title;
  final String body;

  const Reminder(this.id, this.when, this.title, this.body);

  /// Ids que usan estos avisos (para borrarlos antes de volver a armarlos).
  static const firstId = 100;
  static const maxCount = 40;

  /// Avisos de los próximos días, a las [hour]: cada pago fijo que todavía
  /// no tiene "Ya pagué" y cada sueldo, el día que tocan. Un pago fijo que
  /// ya se pasó se recuerda al día siguiente.
  static List<Reminder> upcoming(
    List<Recurring> items,
    Set<String> registeredIds,
    List<String> people,
    DateTime now, {
    int hour = 9,
  }) {
    final until = now.add(const Duration(days: 35));
    final found = <(DateTime, String, String)>[];
    for (final item in items) {
      final fixedPayment = item.type == RecurringType.expense && item.confirm;
      final salary = item.type == RecurringType.income && !item.confirm;
      if (!fixedPayment && !salary) continue;
      for (final month in [
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1),
      ]) {
        if (fixedPayment &&
            registeredIds.contains(
              'rec_${item.id}_${month.year}-${month.month}',
            )) {
          continue;
        }
        for (final day in FinanceRepository.occurrences(
          item,
          month.year,
          month.month,
        )) {
          final when = DateTime(day.year, day.month, day.day, hour);
          // Ya pasó su día y sigue sin pagar: se recuerda mañana.
          if (fixedPayment && !when.isAfter(now) && month.month == now.month) {
            found.add((
              DateTime(now.year, now.month, now.day + 1, hour),
              '¿Ya pagaste ${item.description}?',
              'Tocaba el ${day.day}: ${money(item.amount)}. Si ya lo '
                  'pagaste, toca "Ya pagué" en la app.',
            ));
            continue;
          }
          if (!when.isAfter(now) || when.isAfter(until)) continue;
          found.add(
            fixedPayment
                ? (
                    when,
                    'Hoy toca pagar ${item.description}',
                    '${money(item.amount)}. Cuando lo pagues, toca '
                        '"Ya pagué" en la app.',
                  )
                : (
                    when,
                    people.length > 1
                        ? 'Hoy llega el sueldo de '
                              '${personName(people, item.person)}'
                        : 'Hoy llega tu sueldo',
                    '${item.description}: ${money(item.amount)}',
                  ),
          );
        }
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [
      for (var i = 0; i < found.length && i < maxCount; i++)
        Reminder(firstId + i, found[i].$1, found[i].$2, found[i].$3),
    ];
  }
}

/// Algo que todavía falta este mes: un sueldo por cobrar, un fijo o una
/// propina por pagar, o un pago de fecha variable por confirmar.
class Upcoming {
  final Recurring item;

  /// Día en que toca (aproximado si [needsConfirm]).
  final DateTime date;

  const Upcoming(this.item, this.date);

  bool get isIncome => item.type == RecurringType.income;

  /// Fecha variable: no se registra solo, hay que confirmarlo.
  bool get needsConfirm => item.confirm;

  double get amount => item.amount;
}

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

  // Pareja o cuenta individual

  /// null si todavía no eligieron (primera vez que abren la app); si no,
  /// true para cuenta individual y false para pareja. Las cuentas creadas
  /// antes de existir esta opción son de pareja.
  Stream<bool?> watchSolo() {
    return store.watch(_settings).map((docs) {
      final doc = docs.where((d) => d.id == _peopleId).firstOrNull;
      if (doc == null) return null;
      return doc.data['solo'] as bool? ?? false;
    });
  }

  Future<void> setSolo(bool solo) async {
    final doc = await store.get(_settings, _peopleId);
    final names = _names(doc);
    if (solo && names[0] == defaultPeople[0]) names[0] = 'Yo';
    await store.set(_settings, _peopleId, {
      ...?doc?.data,
      "names": names,
      "solo": solo,
      // La primera vez sigue la configuración inicial (sueldos y fijos).
      if (doc == null) "setupPending": true,
    });
  }

  // Diezmo

  static const _titheId = 'tithe';

  /// Quién aparta su diezmo y los montos cambiados. Apagado al empezar.
  Stream<TitheSettings> watchTithe() => store
      .watch(_settings)
      .map(
        (docs) => TitheSettings.fromMap(
          docs.where((d) => d.id == _titheId).firstOrNull?.data,
        ),
      );

  /// Prende o apaga el diezmo de una persona.
  Future<void> setTitheOn(int person, bool on) async {
    final s = await watchTithe().first;
    await store.set(
      _settings,
      _titheId,
      TitheSettings(
        people: on ? {...s.people, person} : ({...s.people}..remove(person)),
        amounts: s.amounts,
      ).toMap(),
    );
  }

  /// Cambia el diezmo de una persona en un mes; null vuelve al 10%.
  Future<void> setTitheAmount(
    int person,
    int month,
    int year,
    double? amount,
  ) async {
    final s = await watchTithe().first;
    final key = TitheSettings.key(year, month, person);
    await store.set(
      _settings,
      _titheId,
      TitheSettings(
        people: s.people,
        amounts: amount == null
            ? ({...s.amounts}..remove(key))
            : {...s.amounts, key: amount},
      ).toMap(),
    );
  }

  /// Lo que falta dar de diezmo este mes, de todos (0 si no lo apartan).
  Future<double> pendingTithe({DateTime? today}) async {
    final settings = await watchTithe().first;
    if (!settings.on) return 0;
    final now = today ?? DateTime.now();
    final expenses = (await store.watch('expenses').first)
        .map((d) => Expense.fromMap(d.id, d.data))
        .toList();
    return Tithes.of(
      settings,
      await watchIncomes(now.month, now.year).first,
      expenses,
      now.month,
      now.year,
      count: (await watchPeople().first).length,
    ).pending;
  }

  // Caja chica

  static const _pettyCash = 'pettyCash';
  static const _pettyCashId = 'pettyCash';

  /// Si usan caja chica: lo que sobra cada mes se guarda ahí y el mes
  /// empieza de cero. Apagado al empezar.
  Stream<bool> watchPettyCashOn() => store
      .watch(_settings)
      .map(
        (docs) =>
            docs.where((d) => d.id == _pettyCashId).firstOrNull?.data['on'] ==
            true,
      );

  Future<void> setPettyCashOn(bool on) =>
      store.set(_settings, _pettyCashId, {'on': on});

  /// Lo que sacaron o devolvieron a la caja chica, de todos los meses.
  Stream<List<PettyCashMove>> watchPettyCash() => store
      .watch(_pettyCash)
      .map(
        (docs) => [for (final d in docs) PettyCashMove.fromMap(d.id, d.data)],
      );

  Future<void> addPettyCashMove(PettyCashMove move) =>
      store.add(_pettyCash, move.toMap());

  Future<void> deletePettyCashMove(String id) => store.delete(_pettyCash, id);

  /// Cuánto hay de verdad hoy en la caja chica ([real]). Corrige el punto de
  /// partida para que la caja de la app ([calculated]) dé lo mismo.
  Future<void> setPettyCashAmount(double real, double calculated) async {
    final delta = real - calculated;
    if (delta.abs() < 0.005) return;
    final check = await watchCashCheck().first;
    if (check == null || check.offsets.isEmpty) {
      final people = (await watchPeople().first).length;
      await saveCashCheck(
        CashCheck(
          offsets: [delta, for (var i = 1; i < people; i++) 0],
          realAmounts: const [],
          date: DateTime.now(),
        ),
      );
    } else {
      await _shiftStartingMoney(0, delta);
    }
  }

  /// En qué parte de la primera configuración está la cuenta.
  Stream<AccountStep> watchAccountStep() {
    return store.watch(_settings).map((docs) {
      final doc = docs.where((d) => d.id == _peopleId).firstOrNull;
      if (doc == null) return AccountStep.choose;
      return doc.data['setupPending'] == true
          ? AccountStep.setup
          : AccountStep.ready;
    });
  }

  Future<void> finishSetup() async {
    final doc = await store.get(_settings, _peopleId);
    await store.set(_settings, _peopleId, {
      ...?doc?.data,
      "names": _names(doc),
      "setupPending": false,
    });
  }

  /// Nombres de quienes llevan la cuenta: uno si es individual, dos si es de
  /// pareja.
  Stream<List<String>> watchPeople() {
    return store.watch(_settings).map((docs) {
      final doc = docs.where((d) => d.id == _peopleId).firstOrNull;
      final names = _names(doc);
      return doc?.data['solo'] == true ? names.sublist(0, 1) : names;
    });
  }

  /// Cambia los primeros nombres; en cuenta individual se guarda el de la
  /// pareja por si luego la cuenta pasa a ser de dos.
  Future<void> setPeople(List<String> names) async {
    final doc = await store.get(_settings, _peopleId);
    final all = _names(doc)..setRange(0, names.length, names);
    await store.set(_settings, _peopleId, {...?doc?.data, "names": all});
  }

  /// Si es uno de los nombres que pone la app mientras no escriban el suyo.
  static bool isDefaultName(String name) =>
      name == 'Yo' || defaultPeople.contains(name);

  static List<String> _names(Doc? doc) {
    final names = (doc?.data['names'] as List?)?.cast<String>();
    return [...(names != null && names.length == 2 ? names : defaultPeople)];
  }

  // Moneda

  static const _currencyId = 'currency';

  Stream<CurrencySettings> watchCurrencySettings() {
    return store
        .watch(_settings)
        .map(
          (docs) => CurrencySettings.fromMap(
            docs.where((d) => d.id == _currencyId).firstOrNull?.data,
          ),
        );
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

  /// Punto de partida: cuánto dinero tiene de verdad cada persona hoy. Se
  /// ajusta contra lo ya registrado hasta hoy (sueldos y fijos de días que
  /// ya pasaron), para no contar dos veces lo que ya está en ese dinero.
  Future<void> setStartingMoney(List<double> real, {DateTime? today}) async {
    final now = today ?? DateTime.now();
    final until = DateTime(now.year, now.month, now.day);
    bool upTo(int y, int m, int d) => !DateTime(y, m, d).isAfter(until);
    final incomes = (await store.watch(_incomes).first)
        .map((d) => Income.fromMap(d.id, d.data))
        .where((i) => upTo(i.year, i.month, i.day))
        .toList();
    final expenses = (await store.watch('expenses').first)
        .map((d) => Expense.fromMap(d.id, d.data))
        .where((e) => upTo(e.year, e.month, e.day))
        .toList();
    await saveCashCheck(reconcile(incomes, expenses, real));
  }

  /// Lo que tienen libre hoy para gastar o apartar (lo mismo que "Tienes
  /// disponible" en Inicio): todo lo anotado hasta hoy más el punto de
  /// partida, sin lo que ya está apartado como ahorro.
  Future<double> freeMoneyToday({DateTime? today}) async {
    final now = today ?? DateTime.now();
    final incomes = (await store.watch(_incomes).first)
        .map((d) => Income.fromMap(d.id, d.data))
        .toList();
    final expenses = (await store.watch('expenses').first)
        .map((d) => Expense.fromMap(d.id, d.data))
        .toList();
    final people = await watchPeople().first;
    return cashSummaryUntil(
      incomes,
      expenses,
      await watchCashCheck().first,
      people.length,
      DateTime(now.year, now.month, now.day),
    ).free;
  }

  // Categorías

  static const _categoryRequests = 'categoryRequests';

  /// Categorías que alguien de la pareja propuso y esperan respuesta (o que
  /// la otra persona rechazó).
  Stream<List<CategoryRequest>> watchCategoryRequests() => store
      .watch(_categoryRequests)
      .map(
        (docs) => [for (final d in docs) CategoryRequest.fromMap(d.id, d.data)],
      );

  /// Propone una categoría nueva; se crea cuando la otra persona acepta.
  Future<void> requestCategory(CustomCategory category, int by) => store.add(
    _categoryRequests,
    {...category.toMap(), 'by': by, 'status': 'pending'},
  );

  /// Acepta (la crea para los dos) o rechaza una categoría propuesta.
  Future<void> answerCategoryRequest(
    CategoryRequest request,
    bool accept,
  ) async {
    if (!accept) {
      await store.set(_categoryRequests, request.id, {
        ...request.category.toMap(),
        'by': request.by,
        'status': 'rejected',
      });
      return;
    }
    final settings = await watchCategorySettings().first;
    final name = request.category.name.toLowerCase();
    if (!settings.custom.any((c) => c.name.toLowerCase() == name)) {
      await saveCategorySettings(
        CategorySettings(
          custom: [...settings.custom, request.category],
          hidden: settings.hidden,
        ),
      );
    }
    await store.delete(_categoryRequests, request.id);
  }

  /// Quita una propuesta (la cancela quien la hizo, o ya vio el rechazo).
  Future<void> deleteCategoryRequest(String id) =>
      store.delete(_categoryRequests, id);

  static const _categoriesId = 'categories';

  Stream<CategorySettings> watchCategorySettings() {
    return store
        .watch(_settings)
        .map(
          (docs) => CategorySettings.fromMap(
            docs.where((d) => d.id == _categoriesId).firstOrNull?.data,
          ),
        );
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

  /// Pasa los gastos, fijos y presupuestos de las categorías que la app ya
  /// no trae a su reemplazo (ej. "Alcohol" → "Ocio"). Una sola vez por
  /// cuenta; no toca una categoría que la persona creó con ese nombre.
  Future<void> moveRetiredCategories() async {
    const id = 'migrations';
    final done = await store.get(_settings, id);
    if (((done?.data['categories'] as num?) ?? 0) >= 2) return;
    final custom = (await watchCategorySettings().first).custom
        .map((c) => c.name)
        .toSet();
    for (final e in retiredCategories.entries) {
      if (!custom.contains(e.key)) await renameCategory(e.key, e.value);
    }
    await store.set(_settings, id, {...?done?.data, 'categories': 2});
  }

  /// Los pagos fijos mensuales ya no se dan por pagados solos: esperan a que
  /// la persona revise su banco y toque "Ya pagué". Lo que la app anotó
  /// sola este mes se quita (ej. el alquiler del 1 que aún no pagan) y vuelve
  /// a quedar con el botón. Una sola vez por cuenta.
  Future<void> fixedPaymentsWaitForPaid({DateTime? today}) async {
    const id = 'migrations';
    final done = await store.get(_settings, id);
    if (done?.data['fixedPaid'] == true) return;
    for (final item in await watchRecurring().first) {
      if (item.type == RecurringType.expense &&
          item.frequency == Frequency.monthly &&
          !item.confirm) {
        await store.set(_recurring, item.id, {
          ...item.toMap(),
          'confirm': true,
          'weekendShift': WeekendShift.none.name,
        });
        await unconfirmRecurring(item, today: today);
      }
    }
    await store.set(_settings, id, {...?done?.data, 'fixedPaid': true});
  }

  // Ingresos

  Stream<List<Income>> _incomesWhere(Map<String, Object?> where) {
    return store
        .watch(_incomes, where: where)
        .map(
          (docs) =>
              docs.map((doc) => Income.fromMap(doc.id, doc.data)).toList(),
        );
  }

  Stream<List<Income>> watchIncomes(int month, int year) =>
      _incomesWhere({"month": month, "year": year});

  Stream<List<Income>> watchIncomesByYear(int year) =>
      _incomesWhere({"year": year});

  Stream<List<Income>> watchAllIncomes() => _incomesWhere({});

  Future<void> addIncome(
    int person,
    String description,
    double amount,
    int month,
    int year, {
    int day = 1,
  }) {
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
      ).toMap(),
    );
  }

  Future<void> deleteIncome(String id) => store.delete(_incomes, id);

  /// Cambia lo que llegó de un sueldo (ej. faltó un día y llegó menos). Se
  /// guarda lo que debía llegar para mostrar que vino incompleto; si se pone
  /// de nuevo el monto completo, vuelve a quedar como completo.
  Future<void> setIncomeAmount(Income income, double amount) {
    final full = income.expected ?? income.amount;
    return store.set(
      _incomes,
      income.id,
      Income(
        id: income.id,
        person: income.person,
        description: income.description,
        amount: amount,
        day: income.day,
        month: income.month,
        year: income.year,
        expected: amount == full ? null : full,
      ).toMap(),
    );
  }

  // Ingresos y gastos fijos

  Stream<List<Recurring>> watchRecurring() {
    return store
        .watch(_recurring)
        .map(
          (docs) =>
              docs.map((doc) => Recurring.fromMap(doc.id, doc.data)).toList(),
        );
  }

  /// [firstPayment]: para un sueldo semanal o quincenal nuevo, el primer
  /// pago que hay que anotar (puede ser de días que ya pasaron este mes). Si
  /// no se indica, cuenta desde hoy.
  Future<void> saveRecurring(
    Recurring recurring, {
    DateTime? today,
    DateTime? firstPayment,
  }) async {
    var item = recurring;
    if (item.id.isEmpty && item.isDated && firstPayment != null) {
      item = item.copyWith(
        lastApplied: _dateKey(
          DateTime(firstPayment.year, firstPayment.month, firstPayment.day - 1),
        ),
      );
    }
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
        lastApplied: _dateKey(DateTime(now.year, now.month, now.day - 1)),
      );
    }
    if (item.id.isEmpty) {
      final id = await store.add(_recurring, item.toMap());
      await applyRecurring(today: today);
      if (item.type != RecurringType.allowance) {
        await _keepCashAfterBackfill(id, item);
      }
    } else {
      await store.set(_recurring, item.id, item.toMap());
      await applyRecurring(today: today);
    }
  }

  /// Si ya indicaron cuánto dinero tenían y un fijo nuevo anota pagos de días
  /// anteriores (ej. los viernes que ya cobraron), ese dinero ya estaba en lo
  /// que dijeron tener: se ajusta el punto de partida para no contarlo dos
  /// veces. Las propinas no, porque se entregan en el momento.
  Future<void> _keepCashAfterBackfill(String id, Recurring item) async {
    final check = await watchCashCheck().first;
    if (check == null || check.offsets.isEmpty) return;
    final checkDay = DateTime(
      check.date.year,
      check.date.month,
      check.date.day,
    );
    bool before(int y, int m, int d) => !DateTime(y, m, d).isAfter(checkDay);
    final prefix = 'rec_${id}_';
    final isIncome = item.type == RecurringType.income;
    var amount = 0.0;
    if (isIncome) {
      for (final doc in await store.watch(_incomes).first) {
        final income = Income.fromMap(doc.id, doc.data);
        if (doc.id.startsWith(prefix) &&
            before(income.year, income.month, income.day)) {
          amount += income.amount;
        }
      }
    } else {
      for (final doc in await store.watch('expenses').first) {
        final expense = Expense.fromMap(doc.id, doc.data);
        if (doc.id.startsWith(prefix) &&
            before(expense.year, expense.month, expense.day)) {
          amount += expense.value;
        }
      }
    }
    await _shiftStartingMoney(item.person, isIncome ? -amount : amount);
  }

  /// Corrige el punto de partida de [person] en [delta].
  Future<void> _shiftStartingMoney(int person, double delta) async {
    final check = await watchCashCheck().first;
    if (check == null || check.offsets.isEmpty || delta == 0) return;
    // Todo el dinero va junto en la primera persona (ver setStartingMoney).
    final offsets = [...check.offsets];
    final who = person < offsets.length ? person : 0;
    offsets[who] += delta;
    await saveCashCheck(
      CashCheck(
        offsets: offsets,
        realAmounts: check.realAmounts,
        date: check.date,
      ),
    );
  }

  /// Trae a esta cuenta (la de pareja) los sueldos, pagos fijos y propinas
  /// de la cuenta [personal], a nombre de [person], junto con lo que ya se
  /// cobró o pagó de ellos este mes (para que se vea en "Lo que entró este
  /// mes"). Ese dinero ya está en lo que cada uno dijo que traía, así que no
  /// se cuenta dos veces. Con [skipExisting] no repite los que ya están
  /// (mismo nombre, monto y persona), pero sí trae sus pagos de este mes que
  /// falten. Devuelve cuántos fijos y cuántos pagos trajo.
  Future<({int items, int payments})> copyRecurringFrom(
    Store personal,
    int person, {
    bool skipExisting = false,
    DateTime? today,
  }) async {
    final now = today ?? DateTime.now();
    final until = DateTime(now.year, now.month, now.day);
    final existing = skipExisting ? await watchRecurring().first : const [];
    final personalIncomes = await personal.watch(_incomes).first;
    final personalExpenses = await personal.watch('expenses').first;
    final ours = {
      for (final c in [_incomes, 'expenses'])
        for (final d in await store.watch(c).first) d.id,
    };
    final check = await watchCashCheck().first;
    bool beforeCheck(DateTime d) =>
        check != null &&
        !d.isAfter(DateTime(check.date.year, check.date.month, check.date.day));

    var items = 0;
    var payments = 0;
    var delta = 0.0;
    for (final doc in await personal.watch(_recurring).first) {
      final item = Recurring.fromMap(doc.id, doc.data);
      final same = existing.where(
        (r) =>
            r.type == item.type &&
            r.person == person &&
            r.description == item.description &&
            r.amount == item.amount,
      );
      final String id;
      if (same.isNotEmpty) {
        id = same.first.id;
      } else {
        id = await store.add(_recurring, {...doc.data, 'person': person});
        items++;
      }
      if (item.type == RecurringType.allowance) continue;

      final prefix = 'rec_${doc.id}_';
      String? target(Doc record, int year, int month, DateTime date) {
        if (!record.id.startsWith(prefix) ||
            year != now.year ||
            month != now.month ||
            date.isAfter(until)) {
          return null;
        }
        final newId = 'rec_${id}_${record.id.substring(prefix.length)}';
        return ours.contains(newId) ? null : newId;
      }

      for (final record in personalIncomes) {
        final income = Income.fromMap(record.id, record.data);
        final date = DateTime(income.year, income.month, income.day);
        final newId = target(record, income.year, income.month, date);
        if (newId == null) continue;
        await store.set(_incomes, newId, {...record.data, 'person': person});
        payments++;
        if (beforeCheck(date)) delta -= income.amount;
      }
      for (final record in personalExpenses) {
        final expense = Expense.fromMap(record.id, record.data);
        final date = DateTime(expense.year, expense.month, expense.day);
        final newId = target(record, expense.year, expense.month, date);
        if (newId == null) continue;
        await store.set('expenses', newId, {...record.data, 'paidBy': person});
        payments++;
        if (beforeCheck(date)) delta += expense.value;
      }
    }
    await _shiftStartingMoney(person, delta);
    return (items: items, payments: payments);
  }

  Future<void> deleteRecurring(String id) => store.delete(_recurring, id);

  /// Quita un fijo y también todo lo que ya se registró a partir de él (para
  /// corregir uno recién cargado por error).
  Future<void> deleteRecurringWithRecords(String id) async {
    for (final collection in [_incomes, 'expenses']) {
      final docs = await store.watch(collection).first;
      await store.deleteMany(
        collection,
        docs.map((d) => d.id).where((d) => d.startsWith('rec_${id}_')),
      );
    }
    await deleteRecurring(id);
  }

  /// Guarda los cambios de un fijo o propina ya existente. También corrige
  /// lo que ya se registró en el periodo en curso con los datos nuevos.
  Future<void> updateRecurring(
    Recurring previous,
    Recurring updated, {
    DateTime? today,
  }) async {
    final now = today ?? DateTime.now();
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
      lastApplied = updated.isDated
          ? _dateKey(DateTime(now.year, now.month, now.day))
          : '${now.year}-${now.month}';
    }
    final item = updated.copyWith(id: previous.id, lastApplied: lastApplied);
    await store.set(_recurring, item.id, item.toMap());

    if (previous.lastApplied == null) return;
    final recordId = 'rec_${item.id}_${previous.lastApplied}';

    // Pasa a fecha variable: lo que se anotó solo este mes se quita y queda
    // esperando el "Ya pagué".
    if (item.type != RecurringType.allowance &&
        !previous.confirm &&
        item.confirm &&
        previous.lastApplied == '${now.year}-${now.month}') {
      await _removeRecord(item, recordId);
      final prev = DateTime(now.year, now.month - 1);
      await store.set(
        _recurring,
        item.id,
        item.copyWith(lastApplied: '${prev.year}-${prev.month}').toMap(),
      );
      return;
    }

    // Fijo mensual que pasa a un día que todavía no llegó: lo de este mes se
    // quita y vuelve a quedar "por venir" hasta ese día.
    if (item.type != RecurringType.allowance &&
        !item.isDated &&
        !item.confirm &&
        previous.lastApplied == '${now.year}-${now.month}' &&
        occurrences(
          item,
          now.year,
          now.month,
        ).single.isAfter(DateTime(now.year, now.month, now.day))) {
      await store.delete(
        item.type == RecurringType.income ? _incomes : 'expenses',
        recordId,
      );
      await store.set(
        _recurring,
        item.id,
        item
            .copyWith(
              lastApplied:
                  '${DateTime(now.year, now.month - 1).year}-'
                  '${DateTime(now.year, now.month - 1).month}',
            )
            .toMap(),
      );
      return;
    }
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
          // Si ese sueldo llegó incompleto, se mantiene lo que llegó.
          amount: income.expected == null || income.amount >= item.amount
              ? item.amount
              : income.amount,
          day: item.isDated
              ? income.day
              : min(item.day, daysInMonth(income.month, income.year)),
          month: income.month,
          year: income.year,
          expected: income.expected == null || income.amount >= item.amount
              ? null
              : item.amount,
        ).toMap(),
      );
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
        ).toMap(),
      );
    }
  }

  /// Registra los sueldos, gastos fijos y propinas que ya tocaban y aún no se
  /// registraron, incluidos los meses en que no se abrió la app.
  Future<void> applyRecurring({DateTime? today}) {
    return _applying = (_applying ?? Future.value()).then(
      (_) => _apply(today ?? DateTime.now()),
    );
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

    final todayDate = DateTime(today.year, today.month, today.day);
    String? key;
    for (
      ;
      !month.isAfter(current);
      month = DateTime(month.year, month.month + 1)
    ) {
      final date = occurrences(item, month.year, month.month).single;
      // Se registra recién el día que toca, como en la vida real (el sueldo
      // del 30 no se cuenta el 5). Mientras tanto aparece como "por venir".
      if (date.isAfter(todayDate)) break;
      key = '${month.year}-${month.month}';
      // El id depende del mes, así no se duplica aunque se aplique dos veces.
      final id = 'rec_${item.id}_$key';
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
          ).toMap(),
        );
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
          ).toMap(),
        );
      }
    }
    if (key == null) return;
    await store.set(
      _recurring,
      item.id,
      item.copyWith(lastApplied: key).toMap(),
    );
  }

  /// Días en que toca un sueldo o gasto fijo dentro de un mes, ya movidos
  /// si caen fin de semana y así se indicó.
  static List<DateTime> occurrences(Recurring item, int year, int month) {
    final last = daysInMonth(month, year);
    final dates = switch (item.frequency) {
      Frequency.monthly => [DateTime(year, month, min(item.day, last))],
      Frequency.biweekly => {
        DateTime(year, month, min(item.day, last)),
        DateTime(year, month, min(item.secondDay, last)),
      }.toList()..sort(),
      Frequency.weekly => [
        for (var d = 1; d <= last; d++)
          if (DateTime(year, month, d).weekday == item.day)
            DateTime(year, month, d),
      ],
    };
    return [for (final d in dates) shiftWeekend(d, item.weekendShift)];
  }

  /// Lo que todavía falta este mes, ordenado por fecha: sueldos que aún no
  /// llegan, gastos fijos y propinas que aún no tocan, y los de fecha
  /// variable sin confirmar. [registeredIds] son los ids de lo ya registrado
  /// en el mes (gastos e ingresos).
  static List<Upcoming> upcoming(
    List<Recurring> items,
    Set<String> registeredIds,
    DateTime today,
  ) {
    final todayDate = DateTime(today.year, today.month, today.day);
    final y = today.year, m = today.month;
    final result = <Upcoming>[];
    for (final item in items) {
      if (item.type == RecurringType.allowance) {
        for (final date in payoutDates(y, m, item.biweekly)) {
          if (date.isAfter(todayDate) &&
              !registeredIds.contains('rec_${item.id}_${_dateKey(date)}')) {
            result.add(Upcoming(item, date));
          }
        }
      } else if (item.confirm) {
        if (!registeredIds.contains('rec_${item.id}_$y-$m')) {
          result.add(
            Upcoming(item, DateTime(y, m, min(item.day, daysInMonth(m, y)))),
          );
        }
      } else {
        for (final date in occurrences(item, y, m)) {
          if (date.isAfter(todayDate)) result.add(Upcoming(item, date));
        }
      }
    }
    return result..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Lo que todavía falta pagar este mes (pagos fijos sin "Ya pagué",
  /// propinas por dar...). [registeredIds]: ids de los gastos ya anotados.
  static double toPayThisMonth(
    List<Recurring> items,
    Set<String> registeredIds,
    DateTime today,
  ) => upcoming(
    items,
    registeredIds,
    today,
  ).where((u) => !u.isIncome).fold(0.0, (a, u) => a + u.amount);

  /// Lo que se puede apartar para ahorro o metas: lo disponible hoy sin lo
  /// que falta pagar este mes (ej. el alquiler) ni el diezmo por dar, para
  /// no ahorrar esa plata.
  Future<double> freeForSavings({DateTime? today}) async {
    final now = today ?? DateTime.now();
    final ids = {for (final d in await store.watch('expenses').first) d.id};
    return await freeMoneyToday(today: now) -
        toPayThisMonth(await watchRecurring().first, ids, now) -
        await pendingTithe(today: now);
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
          .where(
            (r) =>
                r.confirm &&
                r.type != RecurringType.allowance &&
                !registeredIds.contains('rec_${r.id}_$year-$month'),
          )
          .toList()
        ..sort((a, b) => a.day.compareTo(b.day));

  /// "Todavía no lo pagué": quita el pago de este mes de un fijo que se
  /// confirma a mano, y vuelve a quedar en "Lo que falta este mes".
  Future<void> unconfirmRecurring(Recurring item, {DateTime? today}) {
    final now = today ?? DateTime.now();
    return _removeRecord(item, 'rec_${item.id}_${now.year}-${now.month}');
  }

  /// Borra un pago anotado de un fijo: el dinero vuelve a contar como que
  /// todavía lo tienen (no se pagó).
  Future<void> _removeRecord(Recurring item, String recordId) => store.delete(
    item.type == RecurringType.income ? _incomes : 'expenses',
    recordId,
  );

  /// Registra un pago de fecha variable del mes [month]/[year], con el monto
  /// y el día en que realmente se pagó o cobró.
  Future<void> confirmRecurring(
    Recurring item,
    double amount,
    DateTime date,
    int month,
    int year,
  ) async {
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
        ).toMap(),
      );
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
        ).toMap(),
      );
      // Un pago que cambia cada mes (ej. el alquiler): lo pagado queda como
      // el monto aproximado del mes que viene.
      if (amount != item.amount) {
        final updated = item.copyWith(amount: amount);
        await store.set(_recurring, item.id, updated.toMap());
      }
    }
  }

  /// Sueldos y gastos semanales o quincenales: se registra cada pago el día
  /// que toca, incluidos los que pasaron sin abrir la app.
  Future<void> _applyDated(Recurring item, DateTime today) async {
    final todayDate = DateTime(today.year, today.month, today.day);
    final last = item.lastApplied == null
        ? todayDate
        : _parseKey(item.lastApplied!);
    final due = <DateTime>[];
    for (
      var m = DateTime(last.year, last.month);
      !m.isAfter(todayDate);
      m = DateTime(m.year, m.month + 1)
    ) {
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
          ).toMap(),
        );
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
          ).toMap(),
        );
      }
    }
    if (due.isNotEmpty) {
      await store.set(
        _recurring,
        item.id,
        item.copyWith(lastApplied: _dateKey(due.last)).toMap(),
      );
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
    Recurring item,
    DateTime period,
    DateTime date,
  ) {
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
      ).toMap(),
    );
  }

  Future<void> _applyAllowance(Recurring item, DateTime today) async {
    final todayDate = DateTime(today.year, today.month, today.day);
    var last = item.lastApplied == null
        ? todayDate
        : _parseKey(item.lastApplied!);

    // Propina recién creada (aún no se pagó ningún periodo): la del periodo
    // en curso se entrega en el momento, para que se vea desde ya.
    if (!_isPayoutDate(last, item.biweekly)) {
      final period = _nextPayout(last, item.biweekly);
      await _registerAllowance(
        item,
        period,
        period.isAfter(todayDate) ? todayDate : period,
      );
      last = period;
    }

    // Días de pago pendientes desde el último registro.
    final due = <DateTime>[];
    for (
      var m = DateTime(last.year, last.month);
      !m.isAfter(todayDate);
      m = DateTime(m.year, m.month + 1)
    ) {
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
        _recurring,
        item.id,
        item.copyWith(lastApplied: newKey).toMap(),
      );
    }
  }

  // Presupuestos (monto mensual por categoría)

  Stream<Map<String, double>> watchBudgets() {
    return store
        .watch(_budgets)
        .map(
          (docs) => {
            for (final doc in docs)
              doc.id: currencySettings.convert(
                (doc.data['amount'] as num).toDouble(),
                doc.data['currency'] as String?,
              ),
          },
        );
  }

  Future<void> setBudget(String category, double amount) {
    if (amount <= 0) return store.delete(_budgets, category);
    return store.set(_budgets, category, {
      "amount": amount,
      "currency": currencySettings.code,
    });
  }

  // Metas de ahorro

  Stream<List<Goal>> watchGoals() {
    return store
        .watch(_goals)
        .map(
          (docs) => docs.map((doc) => Goal.fromMap(doc.id, doc.data)).toList(),
        );
  }

  Future<void> addGoal(String name, double target) {
    return store.add(_goals, Goal(id: '', name: name, target: target).toMap());
  }

  Future<void> deleteGoal(String id) => store.delete(_goals, id);
}
