import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/login_state.dart';
import 'package:primera_app_curso/pages/detail_page.dart';
import 'package:provider/provider.dart';

class DetailsParams {
  final String categoryName;
  final int month;
  final String detalle;
  final int year;

  const DetailsParams(this.categoryName, this.month, this.detalle, this.year);
}

class DetailsPageContainer extends StatefulWidget {
  final DetailsParams params;

  const DetailsPageContainer({Key? key, required this.params}) : super(key: key);

  @override
  _DetailsPageContainerState createState() => _DetailsPageContainerState();
}

class _DetailsPageContainerState extends State<DetailsPageContainer> {
  @override
  Widget build(BuildContext context) {
    var user = Provider.of<LoginState>(context, listen: false).currentUser();

    // Depuración: Verificar si user es null
    print("Usuario actual: $user");

    if (user == null) {
      WidgetsBinding.instance?.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed('/login');
      });
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Consumer<ExpensesRepository>(
      builder: (BuildContext context, ExpensesRepository db, Widget? child) {
        var _query = db.queryByCategory(
          widget.params.month + 1,
          widget.params.categoryName,
          widget.params.detalle,
          widget.params.year,
        );

        return StreamBuilder<QuerySnapshot>(
          stream: _query,
          builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> data) {
            if (data.hasData && data.data != null) {
              return DetailsPage(
                categoryName: widget.params.categoryName,
                documents: data.data!.docs,
                onDelete: (documentid) {
                  db.delete(documentid);
                },
              );
            }
            return const Center(child: CircularProgressIndicator());
          },
        );
      },
    );
  }
}
