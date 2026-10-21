import 'package:flutter/material.dart';
import 'package:primera_app_curso/login_state.dart';
import 'package:provider/provider.dart';

/// Inicio de sesión con Google. Con la cuenta, los datos se guardan en la
/// nube: no se pierden si se cambia o se pierde el teléfono.
class LoginPage extends StatelessWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.primaryContainer, scheme.surface],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      Icon(
                        Icons.savings_outlined,
                        size: 72,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Control de Gastos',
                        textAlign: TextAlign.center,
                        style: text.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tu dinero, claro y simple',
                        textAlign: TextAlign.center,
                        style: text.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Consumer<LoginState>(
                        builder: (context, state, _) {
                          if (state.isLoading()) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (state.getErrorMessage() != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Text(
                                    state.getErrorMessage()!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: scheme.error),
                                  ),
                                ),
                              FilledButton.icon(
                                icon: const Icon(Icons.login),
                                label: const Text('Continuar con Google'),
                                onPressed: () => Provider.of<LoginState>(
                                  context,
                                  listen: false,
                                ).login(),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Tus datos se guardan en tu cuenta y solo tú puedes '
                        'verlos. Si cambias de teléfono, siguen ahí.',
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
