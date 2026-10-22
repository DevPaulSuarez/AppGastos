import 'package:flutter/material.dart';
import 'package:primera_app_curso/config.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:provider/provider.dart';

/// Primera pantalla al abrir la app por primera vez: solo pregunta si la
/// cuenta es individual o de pareja. Lo demás (nombres, sueldos, gastos
/// fijos...) se completa después en Ajustes.
class WelcomePage extends StatefulWidget {
  const WelcomePage({Key? key}) : super(key: key);

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _saving = false;

  Future<void> _choose(bool solo) async {
    setState(() => _saving = true);
    await Provider.of<FinanceRepository>(context, listen: false).setSolo(solo);
  }

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
          // Desplazable por si la pantalla es baja (o el teléfono está
          // acostado); en pantallas normales ocupa justo el alto.
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
                        'Bienvenido',
                        textAlign: TextAlign.center,
                        style: text.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '¿Cómo vas a llevar tus gastos?',
                        textAlign: TextAlign.center,
                        style: text.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      _Option(
                        icon: Icons.person_outline,
                        title: 'Solo yo',
                        subtitle:
                            'Una cuenta individual para tus propios gastos',
                        onTap: _saving ? null : () => _choose(true),
                      ),
                      const SizedBox(height: 16),
                      _Option(
                        icon: Icons.people_outline,
                        title: 'En pareja',
                        subtitle: modoPruebas
                            ? 'Registran juntos y ven quién pagó qué'
                            : 'Tú empiezas y luego invitas a tu pareja',
                        onTap: _saving ? null : () => _choose(false),
                      ),
                      // Con la nube, quien recibió el código se une directo,
                      // sin elegir antes.
                      if (!modoPruebas) ...[
                        const SizedBox(height: 16),
                        _Option(
                          icon: Icons.vpn_key_outlined,
                          title: 'Mi pareja me invitó',
                          subtitle: 'Tengo un código para unirme',
                          onTap: _saving
                              ? null
                              : () => Navigator.of(context).pushNamed('/join'),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'Puedes cambiarlo después en Ajustes.',
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

class _Option extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(24),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Icon(icon, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
