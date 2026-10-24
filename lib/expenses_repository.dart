import 'dart:math';

import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/expense.dart';

class ExpensesRepository {
  static const _collection = 'expenses';

  final Store store;

  ExpensesRepository(this.store);

  Stream<List<Expense>> _query(Map<String, Object?> where) {
    return store
        .watch(_collection, where: where)
        .map(
          (docs) =>
              docs.map((doc) => Expense.fromMap(doc.id, doc.data)).toList(),
        );
  }

  Stream<List<Expense>> queryByCategory(
    int month,
    String categoryName,
    int year,
  ) {
    return _query({"month": month, "year": year, "category": categoryName});
  }

  /// Todos los gastos de una categoría, de cualquier mes.
  Stream<List<Expense>> queryAllByCategory(String categoryName) =>
      _query({"category": categoryName});

  Stream<List<Expense>> queryByMonth(int month, int year) {
    return _query({"month": month, "year": year});
  }

  Stream<List<Expense>> queryByYear(int year) => _query({"year": year});

  Stream<List<Expense>> queryAll() => _query({});

  Stream<List<Expense>> querySavings() => _query({"category": ahorroCategory});

  /// Préstamos y sus devoluciones.
  Stream<List<Expense>> queryLoans() => _query({"category": prestamoCategory});

  Future<void> addLoan(
    double value,
    DateTime date,
    String description,
    String owedBy,
    int? paidBy,
  ) async {
    await store.add(
      _collection,
      Expense(
        id: '',
        category: prestamoCategory,
        value: value,
        day: date.day,
        month: date.month,
        year: date.year,
        description: description,
        paidBy: paidBy,
        owedBy: owedBy,
      ).toMap(),
    );
  }

  /// Registra que devolvieron [amount] de un préstamo, en la fecha [date].
  /// El dinero vuelve en ese mes (como un monto negativo de "Préstamos").
  Future<void> registerRepayment(
    Expense loan,
    double amount,
    DateTime date,
  ) async {
    await store.add(
      _collection,
      Expense(
        id: '',
        category: prestamoCategory,
        value: -amount,
        day: date.day,
        month: date.month,
        year: date.year,
        description: 'Devolución de ${loan.owedBy}',
        paidBy: loan.paidBy,
        owedBy: loan.owedBy,
        loanId: loan.id,
      ).toMap(),
    );
    await update(loan.copyWith(repaid: loan.repaid + amount));
  }

  Future<void> delete(String documentId) async {
    final doc = await store.get(_collection, documentId);
    await store.delete(_collection, documentId);
    if (doc == null) return;
    final expense = Expense.fromMap(doc.id, doc.data);
    // Una compra con propina se lleva su descuento; si se borra el descuento,
    // la compra pasa a contar como gasto normal.
    if (expense.withAllowance) {
      await store.deleteMany(
        _collection,
        (await _allowanceOffsets(documentId)).map((e) => e.id),
      );
    }
    final purchaseId = expense.allowanceFor;
    if (purchaseId != null) {
      final purchase = await store.get(_collection, purchaseId);
      if (purchase != null) {
        await store.set(
          _collection,
          purchaseId,
          Map.of(purchase.data)..remove('withAllowance'),
        );
      }
    }
    // Un gasto pagado con el dinero de una meta: ese dinero vuelve a la meta
    // (si se borra la salida, el gasto queda como gasto normal).
    await store.deleteMany(
      _collection,
      (await _query({"goalUseFor": documentId}).first).map((e) => e.id),
    );
  }

  Future<List<Expense>> _allowanceOffsets(String purchaseId) =>
      _query({"allowanceFor": purchaseId}).first;

  /// Propina que le queda a [person] en el mes: lo recibido menos lo que ya
  /// usó en compras marcadas "con propina".
  Future<double> allowanceLeft(int person, int month, int year) async {
    final tips = await _query({
      "month": month,
      "year": year,
      "category": propinaCategory,
    }).first;
    return tips
        .where((e) => e.paidBy == person)
        .fold<double>(0.0, (a, e) => a + e.value);
  }

  /// Registra una compra pagada con propina: la compra en su categoría y,
  /// para no contarla dos veces, un descuento de [fromAllowance] en
  /// "Propinas" (como las devoluciones de préstamos).
  Future<void> addWithAllowance(
    String categoryName,
    double value,
    DateTime date,
    String description, {
    required int paidBy,
    required double fromAllowance,
  }) async {
    final id = await store.add(
      _collection,
      Expense(
        id: '',
        category: categoryName,
        value: value,
        day: date.day,
        month: date.month,
        year: date.year,
        description: description,
        paidBy: paidBy,
        withAllowance: true,
      ).toMap(),
    );
    await store.add(
      _collection,
      Expense(
        id: '',
        category: propinaCategory,
        value: -fromAllowance,
        day: date.day,
        month: date.month,
        year: date.year,
        description: 'Usado en: $description',
        paidBy: paidBy,
        allowanceFor: id,
      ).toMap(),
    );
  }

  Future<void> deleteMany(Iterable<String> ids) =>
      store.deleteMany(_collection, ids);

  /// Gasto pagado con el dinero apartado en una meta (ej. los pasajes del
  /// viaje). Se anota el gasto en su categoría y, para no restarlo dos
  /// veces, el mismo monto sale del ahorro de la meta: lo disponible no
  /// cambia, porque ese dinero ya estaba apartado.
  Future<void> useGoalMoney(
    String goalId,
    double amount,
    String category,
    String description,
    DateTime date, {
    int? paidBy,
  }) async {
    final id = await store.add(
      _collection,
      Expense(
        id: '',
        category: category,
        value: amount,
        day: date.day,
        month: date.month,
        year: date.year,
        description: description,
        paidBy: paidBy,
      ).toMap(),
    );
    await store.add(
      _collection,
      Expense(
        id: '',
        category: ahorroCategory,
        value: -amount,
        day: date.day,
        month: date.month,
        year: date.year,
        description: 'Usado en: $description',
        paidBy: paidBy,
        goalId: goalId,
        goalUseFor: id,
      ).toMap(),
    );
  }

  /// Deshace un uso del dinero de una meta: el dinero vuelve a la meta y se
  /// borra el gasto que se pagó con él.
  Future<void> undoGoalUse(Expense use) async {
    await store.delete(_collection, use.id);
    final purchase = use.goalUseFor;
    if (purchase != null) await store.delete(_collection, purchase);
  }

  /// Deja un aporte como ahorro general, sin meta.
  Future<void> detachFromGoal(Expense expense) =>
      store.set(_collection, expense.id, expense.toMap()..remove('goalId'));

  Future<void> update(Expense expense) async {
    await store.set(_collection, expense.id, expense.toMap());
    // Si bajan el monto de una compra con propina, el descuento baja igual;
    // si lo suben, lo extra cuenta como gasto normal.
    if (!expense.withAllowance) return;
    for (final offset in await _allowanceOffsets(expense.id)) {
      final value = -min(expense.value, -offset.value);
      if (value != offset.value) {
        await store.set(
          _collection,
          offset.id,
          offset.copyWith(value: value).toMap(),
        );
      }
    }
  }

  Future<void> add(
    String categoryName,
    double value,
    DateTime date,
    String detalleDescripcion, {
    int? paidBy,
    String? goalId,
  }) async {
    await store.add(
      _collection,
      Expense(
        id: '',
        category: categoryName,
        value: value,
        day: date.day,
        month: date.month,
        year: date.year,
        description: detalleDescripcion,
        paidBy: paidBy,
        goalId: goalId,
      ).toMap(),
    );
  }
}
