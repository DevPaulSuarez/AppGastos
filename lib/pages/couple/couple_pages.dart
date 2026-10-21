import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/couple/couple.dart';
import 'package:primera_app_curso/couple/space_state.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/data/store.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/expenses_repository.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/login_state.dart';
import 'package:primera_app_curso/pages/balance_page.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/theme.dart';
import 'package:primera_app_curso/utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cuenta personal de quien inició sesión (aunque esté en pareja).
FinanceRepository _personal(BuildContext context) => FinanceRepository(
  FirestoreStore(Provider.of<SpaceState>(context, listen: false).uid!),
);

/// Nombre de la persona: el de su cuenta personal o, si no lo escribió, el
/// de su cuenta de Google.
Future<String> _myName(BuildContext context) async {
  final google = Provider.of<LoginState>(
    context,
    listen: false,
  ).currentUser().displayName;
  final names = await _personal(context).watchPeople().first;
  if (!FinanceRepository.isDefaultName(names.first)) return names.first;
  final first = google?.split(' ').first;
  return first == null || first.isEmpty ? 'Yo' : first;
}

double? _amount(TextEditingController c) => parseAmount(c.text);

/// Campo de dinero con el símbolo de la moneda.
Widget _moneyField(TextEditingController controller, String label) => TextField(
  controller: controller,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  decoration: InputDecoration(
    labelText: label,
    prefixText: '${currencySettings.currency.symbol} ',
  ),
);

Widget _note(BuildContext context, String text) => Text(
  text,
  style: TextStyle(
    fontSize: 13,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  ),
);

// ---------------------------------------------------------------------------
// Invitar

/// Crea el código para que la pareja se una, y lo muestra para compartirlo.
class InvitePage extends StatefulWidget {
  const InvitePage({super.key});

  @override
  State<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends State<InvitePage> {
  bool _creating = false;

  Future<void> _create() async {
    setState(() => _creating = true);
    final space = Provider.of<SpaceState>(context, listen: false);
    try {
      await space.repo!.createInvitation(await _myName(context));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo crear el código. Revisa tu conexión a internet.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final space = Provider.of<SpaceState>(context);
    final inv = space.myInvitation;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Invitar a mi pareja')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _note(
            context,
            'Tu pareja instala la app en su teléfono, inicia sesión con su '
            'cuenta de Google y escribe este código. Tú confirmas y listo: '
            'los dos verán y anotarán lo mismo.',
          ),
          const SizedBox(height: 24),
          if (inv == null)
            FilledButton.icon(
              icon: const Icon(Icons.mail_outline),
              label: const Text('Crear mi código'),
              onPressed: _creating ? null : _create,
            )
          else if (inv.status == 'requested')
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      '${inv.joinerName} quiere unirse',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    PartnerRequestButtons(invitation: inv),
                  ],
                ),
              ),
            )
          else ...[
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _note(context, 'Tu código'),
                    const SizedBox(height: 8),
                    SelectableText(
                      inv.code,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _note(
                      context,
                      'Vale hasta el ${inv.expiresAt.day}/${inv.expiresAt.month} '
                      'a las ${inv.expiresAt.hour}:'
                      '${inv.expiresAt.minute.toString().padLeft(2, '0')}. '
                      'Sirve una sola vez.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copiar código'),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text:
                        'Únete a mi cuenta en Control de Gastos con este '
                        'código: ${inv.code}',
                  ),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copiado: pégalo en WhatsApp'),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => space.repo!.cancelInvitation(inv.code),
              child: const Text('Anular este código'),
            ),
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            Center(child: _note(context, 'Esperando que tu pareja lo use…')),
          ],
        ],
      ),
    );
  }
}

/// Aceptar o rechazar a quien pidió unirse.
class PartnerRequestButtons extends StatelessWidget {
  final Invitation invitation;

  const PartnerRequestButtons({super.key, required this.invitation});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _reject(context),
            child: const Text('Rechazar'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => acceptPartner(context, invitation),
            child: const Text('Aceptar'),
          ),
        ),
      ],
    );
  }

  Future<void> _reject(BuildContext context) async {
    if (await confirmDialog(
      context,
      '¿Rechazar a ${invitation.joinerName}?',
      confirm: 'Rechazar',
    )) {
      if (!context.mounted) return;
      await Provider.of<SpaceState>(
        context,
        listen: false,
      ).repo!.rejectRequest(invitation);
    }
  }
}

/// Acepta a la pareja: pregunta con cuánto dinero entra quien invitó y si
/// trae sus sueldos y pagos fijos, y crea la cuenta de pareja.
Future<void> acceptPartner(BuildContext context, Invitation inv) async {
  final personal = _personal(context);
  final space = Provider.of<SpaceState>(context, listen: false);
  final myMoney = TextEditingController(
    text: (await personal.freeMoneyToday()).toStringAsFixed(2),
  );
  final hasSetup = (await personal.watchRecurring().first).isNotEmpty;
  var copy = hasSetup;
  if (!context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Unirte con ${inv.joinerName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _note(
                context,
                'Se crea una cuenta de pareja nueva. Tu cuenta personal queda '
                'guardada: la puedes ver, pero desde ahora anotarán todo en '
                'la de pareja.',
              ),
              const SizedBox(height: 16),
              _moneyField(myMoney, '¿Con cuánto dinero entras tú?'),
              const SizedBox(height: 4),
              _note(
                context,
                '${inv.joinerName} entra con ${money(inv.joinerMoney)}.',
              ),
              if (hasSetup)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: copy,
                  onChanged: (v) => setState(() => copy = v ?? false),
                  title: const Text('Traer mis sueldos y pagos fijos'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unirnos'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final name = await _myName(context);
  try {
    final currency = await personal.watchCurrencySettings().first;
    await space.repo!.acceptRequest(
      inv,
      inviterName: name,
      inviterMoney: _amount(myMoney) ?? 0,
      currency: currency.toMap(),
      copyMine: copy,
      personal: personal.store,
      setStartingMoney: (couple, amounts) =>
          FinanceRepository(couple).setStartingMoney(amounts),
    );
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  } catch (e) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'No se pudo crear la cuenta de pareja. Inténtalo de nuevo.',
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Unirse

/// Escribir el código que mandó la pareja y pedir unirse.
class JoinPage extends StatefulWidget {
  const JoinPage({super.key});

  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _money = TextEditingController();
  bool _hasSetup = false;
  bool _copy = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final personal = _personal(context);
      final name = await _myName(context);
      final free = await personal.freeMoneyToday();
      final setup = (await personal.watchRecurring().first).isNotEmpty;
      if (!mounted) return;
      setState(() {
        _name.text = name;
        _money.text = free > 0 ? free.toStringAsFixed(2) : '';
        _hasSetup = _copy = setup;
      });
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _money.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Escribe el código que te enviaron');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    String? error;
    try {
      error = await Provider.of<SpaceState>(context, listen: false).repo!
          .requestJoin(
            _code.text,
            joinerName: _name.text.trim().isEmpty
                ? 'Pareja'
                : _name.text.trim(),
            money: _amount(_money) ?? 0,
            copySetup: _copy,
          );
    } catch (e) {
      error = 'No se pudo enviar. Revisa tu conexión a internet.';
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
    });
    if (error == null) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unirme a mi pareja')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _note(
            context,
            'Escribe el código que te envió tu pareja. Cuando lo acepte, '
            'verán y anotarán lo mismo. Tu cuenta personal queda guardada y '
            'la puedes ver cuando quieras.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Código (ej. GASTO-7K3P)',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Tu nombre'),
          ),
          const SizedBox(height: 12),
          _moneyField(_money, '¿Con cuánto dinero entras?'),
          const SizedBox(height: 4),
          _note(context, 'Lo que tienes hoy en el banco y en efectivo.'),
          if (_hasSetup)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _copy,
              onChanged: (v) => setState(() => _copy = v ?? false),
              title: const Text('Traer mis sueldos y pagos fijos'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: const Text('Pedir unirme'),
          ),
        ],
      ),
    );
  }
}

/// Mientras la pareja no acepta la solicitud.
class WaitingPage extends StatelessWidget {
  final Invitation request;

  const WaitingPage({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.hourglass_top, size: 56),
              const SizedBox(height: 24),
              Text(
                'Esperando que ${request.fromName} acepte',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Pídele que abra la app: le aparecerá tu solicitud en Inicio.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Salir de la pareja

/// Cuánto tienen en la cuenta de pareja y cuánto aportó cada uno a cada
/// meta, para repartir el dinero.
class _CoupleMoney extends StatelessWidget {
  final Store coupleStore;
  final List<String> names;

  const _CoupleMoney({required this.coupleStore, required this.names});

  @override
  Widget build(BuildContext context) {
    final finance = FinanceRepository(coupleStore);
    return FutureBuilder(
      future: () async {
        final free = await finance.freeMoneyToday();
        final expenses = (await coupleStore.watch('expenses').first)
            .map((d) => Expense.fromMap(d.id, d.data))
            .where((e) => e.category == ahorroCategory)
            .toList();
        final goals = await finance.watchGoals().first;
        return (free: free, savings: expenses, goals: goals);
      }(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final saved = data.savings.fold(0.0, (a, e) => a + e.value);
        Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                value,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        );
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row('Disponible en la cuenta de pareja', money(data.free)),
                if (saved > 0.004) row('Ahorrado', money(saved)),
                const Divider(),
                row('Total', money(data.free + saved), bold: true),
                for (final goal in data.goals) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Meta "${goal.name}"',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (var i = 0; i < names.length; i++)
                    row(
                      '  ${names[i]} aportó',
                      money(
                        data.savings
                            .where((e) => e.goalId == goal.id && e.paidBy == i)
                            .fold(0.0, (a, e) => a + e.value),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Salir de la pareja: cualquiera de los dos puede hacerlo. Cada uno dice
/// con cuánto dinero se queda y vuelve a su cuenta personal.
class LeaveCouplePage extends StatefulWidget {
  const LeaveCouplePage({super.key});

  @override
  State<LeaveCouplePage> createState() => _LeaveCouplePageState();
}

class _LeaveCouplePageState extends State<LeaveCouplePage> {
  final _keep = TextEditingController();
  bool _leaving = false;

  @override
  void dispose() {
    _keep.dispose();
    super.dispose();
  }

  Future<void> _leave(Couple couple) async {
    final amount = _amount(_keep);
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe con cuánto dinero te quedas')),
      );
      return;
    }
    final space = Provider.of<SpaceState>(context, listen: false);
    if (!await confirmDialog(
      context,
      '¿Seguro que quieres salir de la pareja con '
      '${couple.partnerName(space.uid!)}? La cuenta de pareja quedará '
      'guardada solo para ver y cada uno volverá a su cuenta personal.',
      confirm: 'Sí, salir',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _leaving = true);
    final personal = _personal(context);
    final people = await personal.watchPeople().first;
    await personal.setStartingMoney([
      amount,
      for (var i = 1; i < people.length; i++) 0,
    ]);
    await space.repo!.leave(couple, amount);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final space = Provider.of<SpaceState>(context);
    final couple = space.activeCouple;
    if (couple == null) {
      return const Scaffold(body: Center(child: Text('No estás en pareja.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Salir de la pareja')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _note(
            context,
            'Así quedó el dinero de la cuenta de pareja. Pónganse de acuerdo '
            'en cómo repartirlo.',
          ),
          const SizedBox(height: 12),
          _CoupleMoney(
            coupleStore: FirestoreStore.couple(couple.id),
            names: couple.names,
          ),
          const SizedBox(height: 20),
          _moneyField(_keep, '¿Con cuánto dinero te quedas tú?'),
          const SizedBox(height: 4),
          _note(
            context,
            'Tu cuenta personal vuelve a estar activa y empieza con este '
            'monto.',
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: expenseColor),
            onPressed: _leaving ? null : () => _leave(couple),
            child: const Text('Salir de la pareja'),
          ),
        ],
      ),
    );
  }
}

/// La otra persona salió de la pareja: se pregunta con cuánto dinero se
/// queda esta para reactivar su cuenta personal.
class KeepMoneyPage extends StatefulWidget {
  final Couple couple;

  const KeepMoneyPage({super.key, required this.couple});

  @override
  State<KeepMoneyPage> createState() => _KeepMoneyPageState();
}

class _KeepMoneyPageState extends State<KeepMoneyPage> {
  final _keep = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _keep.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = _amount(_keep);
    if (amount == null) return;
    setState(() => _saving = true);
    final space = Provider.of<SpaceState>(context, listen: false);
    final personal = _personal(context);
    final people = await personal.watchPeople().first;
    await personal.setStartingMoney([
      amount,
      for (var i = 1; i < people.length; i++) 0,
    ]);
    await space.repo!.setKeep(widget.couple, amount);
  }

  @override
  Widget build(BuildContext context) {
    final space = Provider.of<SpaceState>(context);
    final partner = widget.couple.partnerName(space.uid!);
    final theirs = widget.couple.keep[widget.couple.endedBy];
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Text(
              '$partner salió de la pareja',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _note(
              context,
              'La cuenta de pareja quedó guardada solo para ver. Tu cuenta '
              'personal vuelve a estar activa.'
              '${theirs == null ? '' : ' $partner se quedó con ${money(theirs)}.'}',
            ),
            const SizedBox(height: 16),
            _CoupleMoney(
              coupleStore: FirestoreStore.couple(widget.couple.id),
              names: widget.couple.names,
            ),
            const SizedBox(height: 20),
            _moneyField(_keep, '¿Con cuánto dinero te quedas tú?'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Insignia de la pareja

/// "Paul ❤ Ana" dentro de un recuadro con título en el borde.
class CoupleBadge extends StatelessWidget {
  final List<String> names;

  const CoupleBadge({super.key, required this.names});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Pareja',
        filled: false,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              names.isNotEmpty ? names.first : '',
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.favorite, color: Color(0xFFE11D48)),
          ),
          Flexible(
            child: Text(
              names.length > 1 ? names[1] : '',
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Historial (solo ver)

/// Una cuenta que no está activa (la personal mientras están en pareja, o
/// una pareja anterior), mes a mes y sin poder cambiar nada.
class HistoryPage extends StatefulWidget {
  final Store store;
  final String title;

  const HistoryPage({super.key, required this.store, required this.title});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<Store>.value(value: widget.store),
        Provider(create: (_) => ExpensesRepository(widget.store)),
        Provider(create: (_) => FinanceRepository(widget.store)),
      ],
      child: BalancePage(
        key: ValueKey(_month),
        params: BalanceParams(_month.month, _month.year),
        readOnly: true,
        title: widget.title,
        onChangeMonth: (delta) => setState(
          () => _month = DateTime(_month.year, _month.month + delta),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avisos en Inicio

/// Arriba de Inicio: alguien pidió unirse (con Aceptar / Rechazar), o la
/// pareja no aceptó la solicitud de esta persona.
class CoupleNotices extends StatefulWidget {
  const CoupleNotices({super.key});

  @override
  State<CoupleNotices> createState() => _CoupleNoticesState();
}

class _CoupleNoticesState extends State<CoupleNotices> {
  Set<String> _seen = {};

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(
          () => _seen = (prefs.getStringList('rejected_seen') ?? []).toSet(),
        );
      }
    });
  }

  Future<void> _dismiss(String code) async {
    setState(() => _seen = {..._seen, code});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('rejected_seen', _seen.toList());
  }

  @override
  Widget build(BuildContext context) {
    final space = Provider.of<SpaceState>(context);
    final invitation = space.myInvitation;
    final request = space.myJoinRequest;
    final scheme = Theme.of(context).colorScheme;

    Widget card(Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        color: scheme.secondaryContainer,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );

    if (invitation != null && invitation.status == 'requested') {
      return card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.favorite, color: Color(0xFFE11D48)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${invitation.joinerName} quiere unirse como tu pareja',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PartnerRequestButtons(invitation: invitation),
          ],
        ),
      );
    }
    if (request != null &&
        request.status == 'rejected' &&
        !_seen.contains(request.code)) {
      return card(
        Row(
          children: [
            Expanded(
              child: Text('${request.fromName} no aceptó tu solicitud.'),
            ),
            TextButton(
              onPressed: () => _dismiss(request.code),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
