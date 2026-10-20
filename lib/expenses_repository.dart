import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/expense.dart';

class ExpensesRepository {
  static const _collection = 'expenses';

  final Store store;

  ExpensesRepository(this.store);

  Stream<List<Expense>> _query(Map<String, Object?> where) {
    return store.watch(_collection, where: where).map((docs) =>
        docs.map((doc) => Expense.fromMap(doc.id, doc.data)).toList());
  }

  Stream<List<Expense>> queryByCategory(
      int month, String categoryName, int year) {
    return _query({"month": month, "year": year, "category": categoryName});
  }

  Stream<List<Expense>> queryByMonth(int month, int year) {
    return _query({"month": month, "year": year});
  }

  Stream<List<Expense>> queryByYear(int year) => _query({"year": year});

  Stream<List<Expense>> queryAll() => _query({});

  Stream<List<Expense>> querySavings() => _query({"category": ahorroCategory});

  /// Préstamos y sus devoluciones.
  Stream<List<Expense>> queryLoans() => _query({"category": prestamoCategory});

  Future<void> addLoan(double value, DateTime date, String description,
      String owedBy, int? paidBy) async {
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
        ).toMap());
  }

  /// Registra que devolvieron [amount] de un préstamo, en la fecha [date].
  /// El dinero vuelve en ese mes (como un monto negativo de "Préstamos").
  Future<void> registerRepayment(
      Expense loan, double amount, DateTime date) async {
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
        ).toMap());
    await update(loan.copyWith(repaid: loan.repaid + amount));
  }

  Future<void> delete(String documentId) async {
    await store.delete(_collection, documentId);
  }

  Future<void> deleteMany(Iterable<String> ids) =>
      store.deleteMany(_collection, ids);

  /// Deja un aporte como ahorro general, sin meta.
  Future<void> detachFromGoal(Expense expense) =>
      store.set(_collection, expense.id, expense.toMap()..remove('goalId'));

  Future<void> update(Expense expense) async {
    await store.set(_collection, expense.id, expense.toMap());
  }

  Future<void> add(String categoryName, double value, DateTime date,
      String detalleDescripcion,
      {int? paidBy, String? goalId}) async {
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
        ).toMap());
  }
}
