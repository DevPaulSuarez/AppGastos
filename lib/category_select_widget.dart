import 'package:flutter/material.dart';

class CategorySelectionWidget extends StatefulWidget {
  final Map<String, IconData> categories;
  final Function(String) onValueChange;
  final Function(String) descripcion;

  const CategorySelectionWidget(
      {Key? key, required this.categories, required this.onValueChange, required this.descripcion})
      : super(key: key);

  @override
  _CategorySelectionWidgetState createState() => _CategorySelectionWidgetState();
}

class CategoryWidget extends StatelessWidget {
  final String name;
  final IconData icon;
  final bool selected;
  final String? descripcion;

  const CategoryWidget(
      {Key? key, required this.name, required this.icon, required this.selected, this.descripcion})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 23.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15.0),
                border: Border.all(
                  color: selected ? Colors.green : Colors.black,
                  width: selected ? 7.0 : 5.0,
                )),
            child: Icon(icon),
          ),
          Text(name),
        ],
      ),
    );
  }
}

class _CategorySelectionWidgetState extends State<CategorySelectionWidget> {
  Future<String?> createAlertDialog(BuildContext context) {
    final customController = TextEditingController();

    return showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('¿En Que Gastaste?'),
            content: TextField(
              controller: customController,
            ),
            actions: <Widget>[
              MaterialButton(
                elevation: 5.0,
                child: const Text('Aceptar'),
                onPressed: () {
                  Navigator.of(context).pop(customController.text);
                },
              )
            ],
          );
        });
  }

  String currentItem = "";
  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];

    widget.categories.forEach((name, icon) {
      widgets.add(GestureDetector(
        onTap: () {
          setState(() {
            currentItem = name;
          });
          createAlertDialog(context).then((descripcionValue) {
            if (descripcionValue != null) {
              widget.onValueChange(name);
              widget.descripcion(descripcionValue);
            }
          });
        },
        child: CategoryWidget(
          name: name,
          icon: icon,
          selected: name == currentItem,
        ),
      ));
    });

    return ListView(
      scrollDirection: Axis.horizontal,
      children: widgets,
    );
  }
}
