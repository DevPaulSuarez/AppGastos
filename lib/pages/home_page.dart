import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:primera_app_curso/alerts.dart';
import 'package:primera_app_curso/cash.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/models.dart';
import 'package:primera_app_curso/month_widge.dart';
import 'package:primera_app_curso/pages/balance_page.dart';
import 'package:primera_app_curso/pages/couple/couple_pages.dart';
import 'package:primera_app_curso/pages/report_page.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
import 'package:primera_app_curso/theme.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' show TZDateTime, UTC;

class Inicio extends StatefulWidget {
  const Inicio({Key? key}) : super(key: key);

  @override
  _InicioState createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  final globalKey = GlobalKey();

  late Rect buttonRect;

  /// Mes mostrado, de 0 (enero) a 11 (diciembre).
  int currentPage = DateTime.now().month - 1;
  int selectedYear = DateTime.now().year;
  StreamSubscription<CategorySettings>? _categories;
  StreamSubscription<CurrencySettings>? _currency;

  /// Primer mes con algo anotado (gasto o ingreso): antes de ese mes no hay
  /// nada que ver, así que la flecha ‹ no deja ir más atrás.
  DateTime? _firstExpense;
  DateTime? _firstIncome;
  StreamSubscription<List<Expense>>? _expensesSub;
  StreamSubscription<List<Income>>? _incomesSub;

  /// Alerta vigente del mes en curso y si su tarjeta está a la vista. La
  /// tarjeta se muestra un rato; después queda el ícono junto al mes.
  SpendingAlert? _alert;
  bool _showAlert = false;
  Timer? _alertTimer;
  static const _alertDuration = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();

    // Mantiene al día las categorías creadas u ocultas por el usuario.
    _categories = Provider.of<FinanceRepository>(context, listen: false)
        .watchCategorySettings()
        .listen((settings) {
          categorySettings = settings;
          if (mounted) setState(() {});
        });

    // Al cambiar la moneda se vuelven a leer los datos, ya convertidos.
    _currency = Provider.of<FinanceRepository>(context, listen: false)
        .watchCurrencySettings()
        .listen((settings) {
          currencySettings = settings;
          if (mounted) setState(() {});
        });

    // Registra los sueldos y gastos fijos del mes si todavía no están (antes,
    // los pagos fijos pasan a esperar el "Ya pagué").
    final finance = Provider.of<FinanceRepository>(context, listen: false);
    finance.fixedPaymentsWaitForPaid().then((_) => finance.applyRecurring());
    // Gastos en categorías que la app ya no trae pasan a las nuevas.
    Provider.of<FinanceRepository>(
      context,
      listen: false,
    ).moveRetiredCategories();

    DateTime? first(Iterable<DateTime> months) =>
        months.isEmpty ? null : months.reduce((a, b) => a.isBefore(b) ? a : b);
    _expensesSub = Provider.of<ExpensesRepository>(context, listen: false)
        .queryAll()
        .listen((all) {
          if (!mounted) return;
          setState(
            () => _firstExpense = first(
              all.map((e) => DateTime(e.year, e.month)),
            ),
          );
        });
    _incomesSub = Provider.of<FinanceRepository>(context, listen: false)
        .watchAllIncomes()
        .listen((all) {
          if (!mounted) return;
          setState(
            () =>
                _firstIncome = first(all.map((i) => DateTime(i.year, i.month))),
          );
        });

    setupNotificationPlugin();
    tz.initializeTimeZones();
  }

  @override
  void dispose() {
    _categories?.cancel();
    _currency?.cancel();
    _expensesSub?.cancel();
    _incomesSub?.cancel();
    _alertTimer?.cancel();
    super.dispose();
  }

  void _changeMonth(int delta) {
    setState(() {
      final date = DateTime(selectedYear, currentPage + 1 + delta);
      currentPage = date.month - 1;
      selectedYear = date.year;
    });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return now.month - 1 == currentPage && now.year == selectedYear;
  }

  /// No se puede ir más atrás del primer mes con algo anotado (ni del mes en
  /// curso si todavía no hay nada), ni de enero de hace [yearsToBrowse] años.
  bool get _isFirstMonth {
    final now = DateTime.now();
    final shown = DateTime(selectedYear, currentPage + 1);
    final starts = [
      DateTime(now.year, now.month),
      ?_firstExpense,
      ?_firstIncome,
    ];
    final firstData = starts.reduce((a, b) => a.isBefore(b) ? a : b);
    return !shown.isAfter(firstData) ||
        (currentPage == 0 && selectedYear <= now.year - yearsToBrowse);
  }

  Widget _botonAction(
    IconData icon,
    String label,
    VoidCallback callback, {
    bool selected = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkResponse(
        onTap: callback,
        radius: 32,
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: BottomAppBar(
        notchMargin: 8.0,
        height: 72,
        padding: EdgeInsets.zero,
        shape: const CircularNotchedRectangle(),
        child: Row(
          children: <Widget>[
            _botonAction(Icons.home_rounded, 'Inicio', () {
              final now = DateTime.now();
              setState(() {
                currentPage = now.month - 1;
                selectedYear = now.year;
              });
            }, selected: true),
            _botonAction(Icons.bar_chart_rounded, 'Resumen', () {
              Navigator.of(context).pushNamed(
                '/balance',
                arguments: BalanceParams(currentPage + 1, selectedYear),
              );
            }),
            const SizedBox(width: 64.0),
            _botonAction(Icons.savings_outlined, 'Metas', () {
              Navigator.of(context).pushNamed('/goals');
            }),
            _botonAction(Icons.settings_outlined, 'Ajustes', () {
              Navigator.of(context).pushNamed('/settings');
            }),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        key: globalKey,
        tooltip: 'Agregar gasto',
        child: const Icon(Icons.add, size: 30),
        onPressed: () {
          final box =
              globalKey.currentContext?.findRenderObject() as RenderBox?;
          if (box != null) {
            buttonRect = box.localToGlobal(Offset.zero) & box.size;
            Navigator.of(context).pushNamed('/add', arguments: buttonRect);
          }
        },
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final db = Provider.of<ExpensesRepository>(context);
    final finance = Provider.of<FinanceRepository>(context);
    final month = currentPage + 1;

    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          _selector(),
          const CoupleNotices(),
          Expanded(
            child: MultiStreamBuilder(
              key: ValueKey(
                '$selectedYear-$month-${db.hashCode}-'
                '${currencySettings.code}-${currencySettings.rates}',
              ),
              streams: [
                db.queryByMonth(month, selectedYear),
                finance.watchIncomes(month, selectedYear),
                finance.watchBudgets(),
                finance.watchPeople(),
                db.queryLoans(),
                finance.watchRecurring(),
                finance.watchAllIncomes(),
                db.queryAll(),
                finance.watchCashCheck(),
              ],
              builder: (BuildContext context, List<Object?> values) {
                final docs = values[0] as List<Expense>;
                final incomes = values[1] as List<Income>;
                final budgets = values[2] as Map<String, double>;
                final people = values[3] as List<String>;
                // Lo que traían libre (sin lo apartado como ahorro) al
                // empezar el mes: con eso se paga, por ejemplo, el alquiler
                // del 5 mientras llega el sueldo del 15.
                final carriedOver = cashSummaryUntil(
                  values[6] as List<Income>,
                  values[7] as List<Expense>,
                  values[8] as CashCheck?,
                  people.length,
                  DateTime(selectedYear, month, 0),
                ).free;

                // Lo que todavía falta este mes: sueldos por cobrar, fijos y
                // propinas por pagar, pagos de fecha variable por confirmar.
                final upcoming = _isCurrentMonth
                    ? FinanceRepository.upcoming(values[5] as List<Recurring>, {
                        ...docs.map((e) => e.id),
                        ...incomes.map((i) => i.id),
                      }, DateTime.now())
                    : <Upcoming>[];
                // Sin movimientos, pendientes ni dinero de antes no hay nada
                // que mostrar.
                if (docs.isEmpty &&
                    incomes.isEmpty &&
                    upcoming.isEmpty &&
                    carriedOver.abs() < 0.005) {
                  return _empty();
                }
                final alert = monthAlert(
                  docs,
                  incomes.fold(0.0, (sum, i) => sum + i.amount),
                  month,
                  selectedYear,
                  pendingPayments: upcoming
                      .where((u) => !u.isIncome)
                      .fold(0.0, (a, u) => a + u.amount),
                  // Lo de fecha variable es un estimado: no se cuenta como
                  // ingreso seguro.
                  pendingIncome: upcoming
                      .where((u) => u.isIncome && !u.needsConfirm)
                      .fold(0.0, (a, u) => a + u.amount),
                  carriedOver: carriedOver,
                );
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _updateAlert(alert),
                );
                return MonthWidget(
                  alert: _showAlert ? _alert : null,
                  upcoming: upcoming,
                  fixedPayments: _isCurrentMonth
                      ? FixedPayment.ofMonth(
                          values[5] as List<Recurring>,
                          docs,
                          month,
                          selectedYear,
                        )
                      : const [],
                  onDismissAlert: _hideAlert,
                  days: daysInMonth(month, selectedYear),
                  documents: docs,
                  incomes: incomes.fold(0.0, (sum, i) => sum + i.amount),
                  incomeItems: incomes,
                  budgets: budgets,
                  people: people,
                  carriedOver: carriedOver,
                  pendingLoans: (values[4] as List<Expense>)
                      .where((e) => e.pending > 0.001)
                      .toList(),
                  month: currentPage,
                  year: selectedYear,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 100),
        child: Column(
          children: <Widget>[
            const Image(image: AssetImage('assets/no_data.png'), height: 180),
            const SizedBox(height: 24),
            Text(
              'Aún no hay movimientos',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _isCurrentMonth
                  ? 'Toca + para anotar un gasto o un ingreso.'
                  : 'No hay registros en este mes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertIcon() {
    final danger = _alert!.level == AlertLevel.danger;
    return IconButton(
      tooltip: danger ? 'Están en rojo' : 'Van gastando muy rápido',
      visualDensity: VisualDensity.compact,
      icon: Icon(
        danger ? Icons.error : Icons.speed,
        color: danger ? context.money.expense : context.money.warning,
      ),
      onPressed: _showAlert ? _hideAlert : _revealAlert,
    );
  }

  Widget _selector() {
    final name = monthNames[currentPage];
    final label = '${name[0]}${name.substring(1).toLowerCase()} $selectedYear';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Mes anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: _isFirstMonth ? null : () => _changeMonth(-1),
          ),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_alert != null && _isCurrentMonth) _alertIcon(),
                  ],
                ),
                if (_isFirstMonth)
                  GestureDetector(
                    onTap: () => openYearReport(context),
                    child: Text(
                      '¿Años anteriores? Ver informe anual',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else if (!_isCurrentMonth)
                  GestureDetector(
                    onTap: () {
                      final now = DateTime.now();
                      setState(() {
                        currentPage = now.month - 1;
                        selectedYear = now.year;
                      });
                    },
                    child: Text(
                      'Volver a este mes',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Mes siguiente',
            icon: const Icon(Icons.chevron_right),
            onPressed: _isCurrentMonth ? null : () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  void setupNotificationPlugin() {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    // initialise the plugin. app_icon needs to be a added as a drawable resource to the Android head project
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    const iOS = DarwinInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: android,
      iOS: iOS,
    );

    flutterLocalNotificationsPlugin
        .initialize(
          settings: initializationSettings,
          onDidReceiveNotificationResponse: onSelectNotification,
        )
        .then((_) async {
          await flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission();
          setupNotification();
        });
  }

  /// Guarda la alerta del mes; si es nueva o cambió de nivel, muestra la
  /// tarjeta y manda la notificación.
  void _updateAlert(SpendingAlert? alert) {
    if (!mounted) return;
    final levelChanged = alert?.level != _alert?.level;
    if (!levelChanged && alert?.message == _alert?.message) return;
    setState(() => _alert = alert);
    if (alert == null) {
      _hideAlert();
    } else if (levelChanged) {
      _revealAlert();
      _notifyAlert(alert);
    }
  }

  void _revealAlert() {
    _alertTimer?.cancel();
    setState(() => _showAlert = true);
    _alertTimer = Timer(_alertDuration, _hideAlert);
  }

  void _hideAlert() {
    _alertTimer?.cancel();
    if (mounted && _showAlert) setState(() => _showAlert = false);
  }

  /// Manda la alerta como notificación, una sola vez por mes y por nivel
  /// (primero "muy rápido", después "en rojo").
  Future<void> _notifyAlert(SpendingAlert alert) async {
    final now = DateTime.now();
    final key = 'alerta_${now.year}_${now.month}';
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getInt(key) ?? -1) >= alert.level.index) return;
    await prefs.setInt(key, alert.level.index);
    try {
      await flutterLocalNotificationsPlugin.show(
        id: 1,
        title: alert.title,
        body: alert.message,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'alertas_gasto',
            'Alertas de gasto',
            channelDescription: 'Avisos cuando están gastando de más',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(alert.message),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('No se pudo mostrar la alerta: $e');
    }
  }

  Future<void> onSelectNotification(NotificationResponse response) async {
    final payload = response.payload;
    if (payload != null) {
      debugPrint('notification payload: $payload');
    }
  }

  void setupNotification() async {
    // recordatorio una vez al día
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'recordatorio_diario',
          'Recordatorio diario',
          channelDescription: 'Recordatorio para registrar los gastos del día',
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await flutterLocalNotificationsPlugin.periodicallyShow(
      id: 0,
      title: '¿Gastaste algo hoy?',
      body: 'Regístralo para llevar el control de tus gastos',
      repeatInterval: RepeatInterval.daily,
      notificationDetails: platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );

    // Cada viernes a las 7 p. m. (día de pago): comparar con el banco. Se
    // programa a la hora exacta del teléfono pasada a UTC, así repite cada
    // semana a la misma hora sin depender de la zona horaria configurada.
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: 2,
      title: '¿Comparamos con tu banco?',
      body:
          'Revisa que lo que dice la app sea lo que tienes de verdad: toca la '
          'tarjeta verde → Comparar con mi banco.',
      scheduledDate: TZDateTime.from(
        nextWeekdayAt(DateTime.now(), DateTime.friday, 19),
        UTC,
      ),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'recordatorio_banco',
          'Comparar con el banco',
          channelDescription:
              'Recordatorio semanal para revisar que la app coincida con el '
              'dinero real',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }
}
