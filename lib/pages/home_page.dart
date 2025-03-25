import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/login_state.dart';
import 'package:primera_app_curso/month_widge.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:rect_getter/rect_getter.dart';

class Inicio extends StatefulWidget {
  const Inicio({Key? key}) : super(key: key);

  @override
  _InicioState createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  final globalKey = RectGetter.createGlobalKey();

  late Rect buttonRect;

  late PageController _controller;
  int currentPage = DateTime.now().month - 1;
  late Stream<QuerySnapshot> _query;
  GraphType currentType = GraphType.LINES;
  int selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();

    _controller = PageController(
      initialPage: currentPage,
      viewportFraction: 0.4,
    );

    setupNotificationPlugin();
    tz.initializeTimeZones();
  }

  Widget _botonAction(IconData icon, VoidCallback callback) {
    return InkWell(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon),
      ),
      onTap: callback,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExpensesRepository>(
        builder: (BuildContext context, ExpensesRepository db, Widget? child) {
      _query = db.queryByMonth(currentPage + 1, selectedYear);
      return Scaffold(
        bottomNavigationBar: BottomAppBar(
          notchMargin: 8.0,
          shape: const CircularNotchedRectangle(),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _botonAction(FontAwesomeIcons.chartLine, () {
                setState(() {
                  currentType = GraphType.LINES;
                });
              }),
              _botonAction(FontAwesomeIcons.chartPie, () {
                setState(() {
                  currentType = GraphType.PIE;
                });
              }),
              const SizedBox(width: 32.0),
              _botonAction(FontAwesomeIcons.wallet, () {}),
              _botonAction(Icons.settings, () {
                Provider.of<LoginState>(context, listen: false).logout();
              }),
            ],
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton: RectGetter(
          key: globalKey,
          child: FloatingActionButton(
            backgroundColor: Colors.green,
            child: const Icon(Icons.add),
            onPressed: () {
              final rect = RectGetter.getRectFromKey(globalKey);
              if (rect != null) {
                buttonRect = rect;
                Navigator.of(context).pushNamed('/add', arguments: buttonRect);
              }
            },
          ),
        ),
        body: _body(),
      );
    });
  }

  Widget _body() {
    return SafeArea(
      child: Column(
        children: <Widget>[
          _yearSelector(),
          _selector(),
          StreamBuilder<QuerySnapshot>(
            stream: _query,
            builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> data) {
              if (data.connectionState == ConnectionState.active) {
                final docs = data.data?.docs;
                if (docs != null && docs.isNotEmpty) {
                  return MonthWidget(
                    days: daysInMonth(currentPage + 1),
                    documents: docs,
                    graphType: currentType,
                    month: currentPage,
                    detalle: '',
                  );
                } else {
                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Image(image: AssetImage('assets/no_data.png')),
                        const SizedBox(height: 80),
                        Text(
                          "No hay ningun Registro, Tocar Simbolo '+' ",
                          style: Theme.of(context).textTheme.overline,
                        )
                      ],
                    ),
                  );
                }
              }

              return const Center(
                child: CircularProgressIndicator(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _yearSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                selectedYear--;
                final db = Provider.of<ExpensesRepository>(context, listen: false);
                _query = db.queryByMonth(currentPage + 1, selectedYear);
              });
            },
          ),
          Text(
            selectedYear.toString(),
            style: const TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                selectedYear++;
                final db = Provider.of<ExpensesRepository>(context, listen: false);
                _query = db.queryByMonth(currentPage + 1, selectedYear);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _pageItem(String nombre, int position) {
    Alignment _alignment;
    final selected = const TextStyle(
      fontSize: 20.0,
      fontWeight: FontWeight.bold,
      color: Colors.blueGrey,
    );
    final unselected = TextStyle(
      fontSize: 20.0,
      fontWeight: FontWeight.normal,
      color: Colors.blueGrey.withOpacity(0.4),
    );
    if (position == currentPage) {
      _alignment = Alignment.center;
    } else if (position > currentPage) {
      _alignment = Alignment.centerRight;
    } else {
      _alignment = Alignment.centerLeft;
    }

    return Align(
        alignment: _alignment,
        child: Text(
          nombre,
          style: position == currentPage ? selected : unselected,
        ));
  }

  Widget _selector() {
    return SizedBox.fromSize(
      size: const Size.fromHeight(70.0),
      child: PageView(
        onPageChanged: (newPage) {
          setState(() {
            final db = Provider.of<ExpensesRepository>(context, listen: false);
            currentPage = newPage;
            _query = db.queryByMonth(currentPage + 1, selectedYear);
          });
        },
        controller: _controller,
        children: const <Widget>[
          _PageItem("ENERO", 0),
          _PageItem("FEBRERO", 1),
          _PageItem("MARZO", 2),
          _PageItem("ABRIL", 3),
          _PageItem("MAYO", 4),
          _PageItem("JUNIO", 5),
          _PageItem("JULIO", 6),
          _PageItem("AGOSTO", 7),
          _PageItem("SEPTIEMBRE", 8),
          _PageItem("OCTUBRE", 9),
          _PageItem("NOVIEMBRE", 10),
          _PageItem("DICIEMBRE", 11),
        ],
      ),
    );
  }

  void setupNotificationPlugin() {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    // initialise the plugin. app_icon needs to be a added as a drawable resource to the Android head project
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    final iOS = IOSInitializationSettings(
      onDidReceiveLocalNotification: (int id, String? title, String? body, String? payload) async {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            content: const Text("Don't forget to add your expenses"),
            actions: <Widget>[
              TextButton(
                child: const Text('Ok'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
    final initializationSettings = InitializationSettings(android: android, iOS: iOS);

    flutterLocalNotificationsPlugin
        .initialize(
      initializationSettings,
      onSelectNotification: onSelectNotification,
    )
        .then((_) {
      setupNotification();
    });
  }

  Future<void> onSelectNotification(String? payload) async {
    if (payload != null) {
      debugPrint('notification payload: $payload');
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const Inicio()),
    );
  }

  void setupNotification() async {
    // repetir cada minito
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
            'repeating channel id', 'repeating channel name',
            channelDescription: 'repeating description');
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.periodicallyShow(
        0,
        'Gasto Algo?',
        'Si es ASI, REGISTRALO PORFAVOR ',
        RepeatInterval.hourly,
        platformChannelSpecifics,
        androidAllowWhileIdle: true);
  }
}

class _PageItem extends StatelessWidget {
  final String nombre;
  final int position;

  const _PageItem(this.nombre, this.position);

  @override
  Widget build(BuildContext context) {
    final selected = const TextStyle(
      fontSize: 20.0,
      fontWeight: FontWeight.bold,
      color: Colors.blueGrey,
    );
    final unselected = TextStyle(
      fontSize: 20.0,
      fontWeight: FontWeight.normal,
      color: Colors.blueGrey.withOpacity(0.4),
    );

    return Text(
      nombre,
      style: position == 0 ? selected : unselected,
    );
  }
}
