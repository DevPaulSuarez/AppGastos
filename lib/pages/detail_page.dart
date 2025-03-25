import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:primera_app_curso/pages/ui/day_expense_list_tile.dart';

class DetailsPage extends StatelessWidget {
  final String categoryName;
  final List<DocumentSnapshot> documents;
  final Function(String) onDelete;

  const DetailsPage({Key? key, required this.categoryName, required this.documents, required this.onDelete})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(categoryName),
          backgroundColor: Colors.green,
        ),
        body: ListView.builder(
          itemCount: documents.length,
          itemBuilder: (BuildContext context, int index) {
            var document = documents[index];

            return Dismissible(
              key: Key(document.id),
              onDismissed: (direction) {
                onDelete(document.id);
                // db.delete(document.id);
              },
              child: DayExpenseListTile(document: document),
            );
          },
        ));
  }
}
