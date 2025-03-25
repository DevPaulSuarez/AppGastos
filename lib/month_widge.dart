import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:primera_app_curso/graph_widget.dart';
import 'package:primera_app_curso/pages/detail_page_container.dart';

enum GraphType {
  LINES,
  PIE,
}

class MonthWidget extends StatefulWidget {
  final List<DocumentSnapshot> documents;
  final double total;
  final List<double> perDay;
  final Map<String, double> categories;
  final GraphType graphType;
  final int month;
  final String detalle;

  MonthWidget(
      {Key? key,
      required this.month,
      required this.graphType,
      required this.documents,
      required int days,
      required this.detalle})
      : total = documents.map((doc) => (doc['value'] as num).toDouble()).fold(0.0, (a, b) => a + b),
        perDay = List.generate(days, (int index) {
          return documents
              .where((doc) => (doc['day'] as num).toInt() == (index + 1))
              .map((doc) => (doc['value'] as num).toDouble())
              .fold(0.0, (a, b) => a + b);
        }),
        categories = documents.fold({}, (Map<String, double> map, document) {
          final category = document['category'] as String;
          final value = (document['value'] as num).toDouble();
          if (!map.containsKey(category)) {
            map[category] = 0.0;
          }
          map[category] = (map[category] ?? 0.0) + value;
          return map;
        }),
        super(key: key);

  @override
  _MonthWidgetState createState() => _MonthWidgetState();
}

class _MonthWidgetState extends State<MonthWidget> {
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          _gastos(),
          _grafico(),
          Container(
            color: Colors.greenAccent.withOpacity(0.15),
            height: 25.0,
          ),
          _list(),
        ],
      ),
    );
  }

  Widget _grafico() {
    if (widget.graphType == GraphType.LINES) {
      return SizedBox(
        height: 250.0,
        child: LinesGraphWidget(data: widget.perDay),
      );
    } else {
      var perCategory = widget.categories.keys
          .map((name) => (widget.categories[name] ?? 0.0) / widget.total)
          .toList();
      return SizedBox(
        height: 250.0,
        child: PieGraphwidget(data: perCategory),
      );
    }
  }

  Widget _item(IconData icon, String nombre, int percent, double value) {
    return ListTile(
      onTap: () {
        Navigator.of(context).pushNamed('/details',
            arguments: DetailsParams(
              nombre,
              widget.month,
              widget.detalle,
              DateTime.now().year
            ));
      },
      leading: Icon(
        icon,
        size: 32.0,
      ),
      title: Text(
        nombre,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20.0),
      ),
      subtitle: Text("$percent% de Gastos"),
      trailing: Container(
          decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.5),
              borderRadius: BorderRadius.circular(4.0)),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              "\S/.$value",
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontSize: 20.0,
              ),
            ),
          )),
    );
  }

  Widget _list() {
    return Expanded(
      child: ListView.separated(
        itemCount: widget.categories.keys.length,
        itemBuilder: (BuildContext context, int index) {
          var key = widget.categories.keys.elementAt(index);
          var data = widget.categories[key] ?? 0.0;
          return _item(FontAwesomeIcons.notesMedical, key,
              (100 * data / widget.total).round(), data);
        },
        separatorBuilder: (BuildContext context, int index) {
          return Container(
            color: Colors.greenAccent.withOpacity(0.15),
            height: 8.0,
          );
        },
      ),
    );
  }

  Widget _gastos() {
    return Column(
      children: <Widget>[
        Text(
          "\S/.${widget.total.toStringAsFixed(2)}",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 45.0,
            color: Colors.blueGrey,
          ),
        ),
        const Text(
          "Gasto Total",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16.0,
            color: Colors.blueGrey,
          ),
        ),
      ],
    );
  }
}
