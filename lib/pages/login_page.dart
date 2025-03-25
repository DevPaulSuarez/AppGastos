import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:primera_app_curso/login_state.dart';
import 'package:provider/provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TapGestureRecognizer _recognizer1;
  late final TapGestureRecognizer _recognizer2;

  @override
  void initState() {
    super.initState();

    _recognizer1 = TapGestureRecognizer()
      ..onTap = () {
        showHelp(
            "Este servicio se proporciona TAL CUAL y no tiene garantía actual sobre cómo"
            " se gestionan los datos y el tiempo de actividad. Los términos finales se publicarán cuando la versión final de la aplicación"
            " será realizado.");
      };
    _recognizer2 = TapGestureRecognizer()
      ..onTap = () {
        showHelp(
            "Todos sus datos se guardan de forma anónima en la base de datos de Firebase y permanecerán así."
            " Ningún otro usuario tendrá acceso a él.");
      };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const Expanded(
              flex: 1,
              child: SizedBox(),
            ),
            Text(
              "Control De Gastos",
              style: Theme.of(context).textTheme.headline4,
            ),
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Image(image: AssetImage('assets/login_background.png')),
            ),
            Text(
              "Tu asesor de finanzas personal",
              style: Theme.of(context).textTheme.overline,
            ),
            const Expanded(
              flex: 1,
              child: SizedBox(),
            ),
            Consumer<LoginState>(
              builder: (BuildContext context, LoginState value, Widget? child) {
                if (value.isLoading()) {
                  return const CircularProgressIndicator();
                } else {
                  return Column(
                    children: [
                      if (value.getErrorMessage() != null)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            value.getErrorMessage()!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(primary: Colors.green),
                        child: const Text("Iniciar Sesion con Google"),
                        onPressed: () {
                          Provider.of<LoginState>(context, listen: false).login();
                        },
                      ),
                    ],
                  );
                }
              },
            ),
            const Expanded(
              child: SizedBox(),
            ),
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                    style: Theme.of(context).textTheme.bodyText1,
                    text: "Para utilizar esta aplicación, debe aceptar nuestra",
                    children: [
                      TextSpan(
                        text: "Terms of Service",
                        recognizer: _recognizer1,
                        style: Theme.of(context)
                            .textTheme
                            .bodyText1
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: " y "),
                      TextSpan(
                        text: "Privacy Policy",
                        recognizer: _recognizer2,
                        style: Theme.of(context)
                            .textTheme
                            .bodyText1
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ]),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recognizer1.dispose();
    _recognizer2.dispose();
    super.dispose();
  }

  void showHelp(String s) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              content: Text(s),
              actions: <Widget>[
                TextButton(
                  child: const Text('Ok'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ));
  }
}

/* eliminar una vez que este lito ya 
class LoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Consumer<LoginState>(
          builder: (BuildContext context, LoginState value, Widget child) {
            if (value.isLoading()) {
              return CircularProgressIndicator();
            } else {
              return child;
            }
          },
          child: RaisedButton(
            child: Text("Sing In"),
            onPressed: () {
              Provider.of<LoginState>(context, listen: false).login();
            },
          ),
        ),
      ),
    );
  }
}*/
