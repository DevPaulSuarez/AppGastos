import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:primera_app_curso/add_page_transicion.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/login_state.dart';
import 'package:primera_app_curso/pages/add_page.dart';
import 'package:primera_app_curso/pages/home_page.dart';
import 'package:primera_app_curso/pages/login_page.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/detail_page_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const Miapp());
}

class Miapp extends StatelessWidget {
  const Miapp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LoginState>(
          create: (BuildContext context) => LoginState(),
        ),
        ProxyProvider<LoginState, ExpensesRepository>(
            update: (_, LoginState value, __) {
          if (value.isLoggedIn()) {
            return ExpensesRepository(value.currentUser().uid);
          }
          throw Exception('User not logged in');
        }),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
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
          }
          return null;
        },
        routes: {
          '/': (BuildContext context) {
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
