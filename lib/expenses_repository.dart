import 'package:cloud_firestore/cloud_firestore.dart';

class ExpensesRepository {
  final String userId;

  ExpensesRepository(this.userId);

  Stream<QuerySnapshot> queryByCategory(
      int month, String categoryName, String detalle, int year) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('expenses')
        .where("month", isEqualTo: month)
        .where("year", isEqualTo: year)
        .where("category", isEqualTo: categoryName)
        .where("Description", isEqualTo: detalle)
        .snapshots();
  }

  Stream<QuerySnapshot> queryByMonth(int month, int year) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('expenses')
        .where("month", isEqualTo: month)
        .where("year", isEqualTo: year)
        .snapshots();
  }

  Future<void> delete(String documentId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('expenses')
        .doc(documentId)
        .delete();
  }

  Future<void> add(String categoryName, double value, DateTime date,
      String detalleDescripcion) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('expenses')
        .doc()
        .set({
      "category": categoryName,
      "value": value,
      "month": date.month,
      "day": date.day,
      "year": date.year,
      "Description": detalleDescripcion,
    });
  }
}
