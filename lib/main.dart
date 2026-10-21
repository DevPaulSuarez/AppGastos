import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:primera_app_curso/add_page_transicion.dart';
import 'package:primera_app_curso/couple/space_state.dart';
import 'package:primera_app_curso/data/migration.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/login_state.dart';
import 'package:primera_app_curso/pages/add_page.dart';
import 'package:primera_app_curso/pages/balance_page.dart';
import 'package:primera_app_curso/pages/categories_page.dart';
import 'package:primera_app_curso/pages/couple/couple_pages.dart';
import 'package:primera_app_curso/pages/goals_page.dart';
import 'package:primera_app_curso/pages/home_page.dart';
import 'package:primera_app_curso/pages/loans_page.dart';
import 'package:primera_app_curso/pages/login_page.dart';
import 'package:primera_app_curso/pages/report_page.dart';
import 'package:primera_app_curso/pages/settings_page.dart';
import 'package:primera_app_curso/pages/setup_page.dart';
import 'package:primera_app_curso/pages/welcome_page.dart';
import 'package:primera_app_curso/pages/year_page.dart';
import 'package:primera_app_curso/theme.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config.dart';
import 'firebase_options.dart';
import 'pages/detail_page_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // En modo pruebas no se usa Firebase (así también corre en iPhone, que aún
  // no tiene su archivo de configuración de Firebase).
  if (!modoPruebas) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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
        // Qué cuenta está activa: la personal o la de pareja.
        if (modoPruebas)
          ChangeNotifierProvider<SpaceState>(create: (_) => SpaceState())
        else
          ChangeNotifierProxyProvider<LoginState, SpaceState>(
            create: (_) => SpaceState(),
            update: (_, login, space) => space!
              ..setUser(login.isLoggedIn() ? login.currentUser().uid : null),
          ),
        if (modoPruebas)
          Provider<Store>(create: (_) => LocalStore())
        else
          ProxyProvider2<LoginState, SpaceState, Store>(
              update: (_, LoginState value, SpaceState space, Store? previous) {
            if (value.isLoggedIn() && space.uid != null) {
              final couple = space.activeCouple;
              final owner = couple == null ? space.uid! : 'couple:${couple.id}';
              if (previous is FirestoreStore && previous.userId == owner) {
                return previous;
              }
              return space.activeStore();
            }
            // Sin sesión no se muestra ningún dato; mientras se cierra la
            // sesión se mantiene el anterior para no romper la pantalla.
            return previous ?? LocalStore();
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
          } else if (settings.name == '/invite') {
            return MaterialPageRoute(
                builder: (BuildContext context) => const InvitePage());
          } else if (settings.name == '/join') {
            return MaterialPageRoute(
                builder: (BuildContext context) => const JoinPage());
          } else if (settings.name == '/leave') {
            return MaterialPageRoute(
                builder: (BuildContext context) => const LeaveCouplePage());
          } else if (settings.name == '/settings') {
            return MaterialPageRoute(
                builder: (BuildContext context) => const SettingsPage());
          }
          return null;
        },
        routes: {
          '/': (BuildContext context) {
            if (modoPruebas) {
              return const _AccountGate();
            }
            var state = Provider.of<LoginState>(context);
            if (state.isLoggedIn()) {
              final space = Provider.of<SpaceState>(context);
              if (!space.loaded) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              // La otra persona salió de la pareja: antes de seguir, con
              // cuánto dinero se queda esta.
              final keep = space.pendingKeep;
              if (keep != null) return KeepMoneyPage(couple: keep);
              // Pidió unirse a alguien y todavía no lo aceptan.
              final request = space.myJoinRequest;
              if (request != null &&
                  request.status == 'requested' &&
                  space.activeCouple == null) {
                return WaitingPage(request: request);
              }
              // La clave cambia al formar o terminar la pareja: así toda la
              // app se vuelve a armar con la cuenta correcta.
              return _CloudReady(
                key: ValueKey('${state.currentUser().uid}-${space.spaceKey}'),
                userId: state.currentUser().uid,
              );
            } else {
              return const LoginPage();
            }
          },
        },
      ),
    );
  }
}

/// Al iniciar sesión por primera vez en este teléfono, sube a la nube lo que
/// se tenía guardado en el teléfono; después sigue como siempre.
class _CloudReady extends StatefulWidget {
  final String userId;

  const _CloudReady({super.key, required this.userId});

  @override
  State<_CloudReady> createState() => _CloudReadyState();
}

class _CloudReadyState extends State<_CloudReady> {
  late final Future<int> _moving;

  @override
  void initState() {
    super.initState();
    // Lo del teléfono va siempre a la cuenta personal.
    final cloud = FirestoreStore(widget.userId);
    _moving = moveLocalDataToCloud(
      LocalStore(),
      cloud,
      widget.userId,
      setMany: cloud.setMany,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _moving,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Subiendo tus datos a la nube…'),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          debugPrint('No se pudieron subir los datos: ${snapshot.error}');
        }
        return const _AccountGate();
      },
    );
  }
}

/// La primera vez pregunta si la cuenta es individual o de pareja y luego
/// pide sueldos y gastos fijos; después entra directo al inicio.
class _AccountGate extends StatelessWidget {
  const _AccountGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AccountStep>(
      stream: Provider.of<FinanceRepository>(context).watchAccountStep(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return switch (snapshot.data!) {
          AccountStep.choose => const WelcomePage(),
          AccountStep.setup => const SetupPage(),
          AccountStep.ready => const Inicio(),
        };
      },
    );
  }
}
