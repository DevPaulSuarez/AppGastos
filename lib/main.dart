import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:primera_app_curso/add_page_transicion.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/login_state.dart';
import 'package:primera_app_curso/pages/add_page.dart';
import 'package:primera_app_curso/pages/balance_page.dart';
import 'package:primera_app_curso/pages/categories_page.dart';
import 'package:primera_app_curso/pages/goals_page.dart';
import 'package:primera_app_curso/pages/home_page.dart';
import 'package:primera_app_curso/pages/loans_page.dart';
import 'package:primera_app_curso/pages/login_page.dart';
import 'package:primera_app_curso/pages/report_page.dart';
import 'package:primera_app_curso/pages/settings_page.dart';
import 'package:primera_app_curso/pages/year_page.dart';
import 'package:primera_app_curso/theme.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config.dart';
import 'pages/detail_page_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // En modo pruebas no se usa Firebase (así también corre en iPhone, que aún
  // no tiene su archivo de configuración de Firebase).
  if (!modoPruebas) {
    await Firebase.initializeApp();
  }
  runApp(const Miapp());
}

class Miapp extends StatelessWidget {
  const Miapp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        if (!modoPruebas)
          ChangeNotifierProvider<LoginState>(
            create: (BuildContext context) => LoginState(),
          ),
        if (modoPruebas)
          Provider<Store>(create: (_) => LocalStore())
        else
          ProxyProvider<LoginState, Store>(
              update: (_, LoginState value, Store? previous) {
            if (value.isLoggedIn()) {
              final uid = value.currentUser().uid;
              if (previous is FirestoreStore && previous.userId == uid) {
                return previous;
              }
              return FirestoreStore(uid);
            }
            throw Exception('User not logged in');
          }),
        ProxyProvider<Store, ExpensesRepository>(
          update: (_, store, previous) => previous?.store == store
              ? previous!
              : ExpensesRepository(store),
        ),
        ProxyProvider<Store, FinanceRepository>(
          update: (_, store, previous) => previous?.store == store
              ? previous!
              : FinanceRepository(store),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('es', 'ES'),
        ],
        title: 'Control de Gastos',
        onGenerateRoute: (settings) {
          if (settings.name == '/details') {
            final params = settings.arguments as DetailsParams;
            return MaterialPageRoute(builder: (BuildContext context) {
              return DetailsPageContainer(
                params: params,
              );
            });
          } else if (settings.name == '/add') {
            final buttonRect = settings.arguments as Rect;
            return AddPageTransition(
                page: AddPage(
              buttonRect: buttonRect,
            ));
          } else if (settings.name == '/balance') {
            final params = settings.arguments as BalanceParams;
            return MaterialPageRoute(
                builder: (BuildContext context) => BalancePage(params: params));
          } else if (settings.name == '/report') {
            final params = settings.arguments as ReportParams;
            return MaterialPageRoute(
                builder: (BuildContext context) => ReportPage(params: params));
          } else if (settings.name == '/goals') {
            return MaterialPageRoute(
                builder: (BuildContext context) => const GoalsPage());
          } else if (settings.name == '/year') {
            final year = settings.arguments as int;
            return MaterialPageRoute(
                builder: (BuildContext context) => YearPage(year: year));
          } else if (settings.name == '/loans') {
            return MaterialPageRoute(
                builder: (BuildContext context) => const LoansPage());
          } else if (settings.name == '/categories') {
            return MaterialPageRoute(
                builder: (BuildContext context) => const CategoriesPage());
          } else if (settings.name == '/settings') {
            return MaterialPageRoute(
                builder: (BuildContext context) => const SettingsPage());
          }
          return null;
        },
        routes: {
          '/': (BuildContext context) {
            if (modoPruebas) {
              return const Inicio();
            }
            var state = Provider.of<LoginState>(context);
            if (state.isLoggedIn()) {
              return const Inicio();
            } else {
              return const LoginPage();
            }
          },
        },
      ),
    );
  }
}
