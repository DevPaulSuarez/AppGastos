import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/models.dart';

/// Última vez que compararon la app con su dinero real, por persona.
///
/// [offsets] es lo que hay que sumar a lo calculado por la app para llegar a
/// lo real de cada persona (el "punto de partida"): incluye el dinero que ya
/// tenían antes de usar la app y las diferencias que decidieron ajustar.
class CashCheck {
  final List<double> offsets;
  final List<double> realAmounts;
  final DateTime date;

  const CashCheck({
    required this.offsets,
    required this.realAmounts,
    required this.date,
  });

  factory CashCheck.fromMap(Map<String, dynamic> map) {
    final currency = map['currency'] as String?;
    List<double> amounts(String key) => [
      for (final v in (map[key] as List?) ?? const [])
        currencySettings.convert((v as num).toDouble(), currency),
    ];
    return CashCheck(
      offsets: amounts('offsets'),
      realAmounts: amounts('realAmounts'),
      date: DateTime.parse(map['date'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
    'offsets': offsets,
    'realAmounts': realAmounts,
    'currency': currencySettings.code,
    'date': date.toIso8601String(),
  };

  double get realTotal => realAmounts.fold(0.0, (a, b) => a + b);
}

/// Cuentas de una persona: punto de partida + lo que le entró − lo que pagó.
class PersonCash {
  final double start;
  final double income;
  final double spent;

  const PersonCash({
    required this.start,
    required this.income,
    required this.spent,
  });

  double get total => start + income - spent;
}

class CashSummary {
  final List<PersonCash> people;

  /// Lo apartado como ahorro o en metas (sigue siendo de ustedes).
  final double saved;

  /// Lo que les deben por préstamos; todavía no lo tienen.
  final double receivable;

  const CashSummary({
    required this.people,
    required this.saved,
    required this.receivable,
  });

  double _sum(double Function(PersonCash p) f) =>
      people.fold(0.0, (a, p) => a + f(p));

  double get start => _sum((p) => p.start);
  double get income => _sum((p) => p.income);
  double get spent => _sum((p) => p.spent);

  /// Todo el dinero que deberían tener entre los dos.
  double get total => _sum((p) => p.total);

  /// Parte del total que no está apartada.
  double get free => total - saved;
}

/// Lo que la app calcula para cada persona sin punto de partida: lo que le
/// entró menos lo que pagó (gastos y préstamos). Lo apartado como ahorro
/// sigue siendo dinero de ellos, así que no se resta. Lo que no tiene
/// "quién pagó" se reparte entre todos.
List<({double income, double spent})> _calculated(
  List<Income> incomes,
  List<Expense> expenses,
  int people,
) {
  final outflows = expenses.where((e) => e.category != ahorroCategory);
  final unassigned = outflows
      .where((e) => e.paidBy == null || e.paidBy! < 0 || e.paidBy! >= people)
      .fold(0.0, (a, e) => a + e.value);
  return [
    for (var i = 0; i < people; i++)
      (
        income: incomes
            .where((x) => x.person == i)
            .fold(0.0, (a, x) => a + x.amount),
        spent:
            outflows
                .where((e) => e.paidBy == i)
                .fold(0.0, (a, e) => a + e.value) +
            unassigned / people,
      ),
  ];
}

CashSummary cashSummary(
  List<Income> incomes,
  List<Expense> expenses,
  CashCheck? check,
  int people,
) {
  final calculated = _calculated(incomes, expenses, people);
  return CashSummary(
    people: [
      for (var i = 0; i < people; i++)
        PersonCash(
          start: check != null && i < check.offsets.length
              ? check.offsets[i]
              : 0,
          income: calculated[i].income,
          spent: calculated[i].spent,
        ),
    ],
    saved: expenses
        .where((e) => e.category == ahorroCategory)
        .fold(0.0, (a, e) => a + e.value),
    receivable: expenses.fold(0.0, (a, e) => a + e.pending),
  );
}

/// Nuevo punto de partida para que lo calculado coincida con lo que cada
/// persona tiene de verdad ([realByPerson]).
CashCheck reconcile(
  List<Income> incomes,
  List<Expense> expenses,
  List<double> realByPerson,
) {
  final calculated = _calculated(incomes, expenses, realByPerson.length);
  return CashCheck(
    offsets: [
      for (var i = 0; i < realByPerson.length; i++)
        realByPerson[i] - (calculated[i].income - calculated[i].spent),
    ],
    realAmounts: realByPerson,
    date: DateTime.now(),
  );
}

/// Lo que se puede apartar como ahorro o aportar a metas en un mes: su
/// sobrante (ingresos − gastos − lo ya ahorrado − lo prestado).
double monthLeftover(List<Income> incomes, List<Expense> expenses) =>
    incomes.fold(0.0, (a, i) => a + i.amount) -
    expenses.fold(0.0, (a, e) => a + e.value);

/// Como [cashSummary], pero contando solo lo registrado hasta [until]
/// (incluido). Sirve para saber cuánto tenían al empezar o terminar un mes.
CashSummary cashSummaryUntil(
  List<Income> incomes,
  List<Expense> expenses,
  CashCheck? check,
  int people,
  DateTime until,
) {
  bool upTo(int year, int month, int day) =>
      !DateTime(year, month, day).isAfter(until);
  return cashSummary(
    incomes.where((i) => upTo(i.year, i.month, i.day)).toList(),
    expenses.where((e) => upTo(e.year, e.month, e.day)).toList(),
    check,
    people,
  );
}
