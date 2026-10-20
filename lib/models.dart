import 'package:primera_app_curso/currency.dart';

// Los montos se leen ya convertidos a la moneda actual y se guardan junto con
// su moneda.

/// Ingreso de dinero de un mes (sueldo, extra, etc.).
class Income {
  final String id;
  final int person;
  final String description;
  final double amount;
  final int day;
  final int month;
  final int year;

  const Income({
    required this.id,
    required this.person,
    required this.description,
    required this.amount,
    this.day = 1,
    required this.month,
    required this.year,
  });

  factory Income.fromMap(String id, Map<String, dynamic> map) {
    return Income(
      id: id,
      person: (map['person'] as num).toInt(),
      description: (map['description'] as String?) ?? '',
      amount: currencySettings.convert(
          (map['amount'] as num).toDouble(), map['currency'] as String?),
      day: (map['day'] as num?)?.toInt() ?? 1,
      month: (map['month'] as num).toInt(),
      year: (map['year'] as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
        "person": person,
        "description": description,
        "amount": amount,
        "currency": currencySettings.code,
        "day": day,
        "month": month,
        "year": year,
      };
}

enum RecurringType { income, expense, allowance }

/// Cada cuánto se repite un sueldo o gasto fijo.
enum Frequency { monthly, biweekly, weekly }

/// Qué pasa si el día de pago cae sábado o domingo.
enum WeekendShift { none, next, previous }

/// Mueve [date] según [shift] si cae fin de semana.
DateTime shiftWeekend(DateTime date, WeekendShift shift) {
  final weekend = date.weekday >= DateTime.saturday;
  if (!weekend || shift == WeekendShift.none) return date;
  if (shift == WeekendShift.next) {
    return date.add(Duration(days: 8 - date.weekday)); // al lunes
  }
  return date.subtract(Duration(days: date.weekday - DateTime.friday));
}

const weekdayNames = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

/// Movimiento que se repite: un sueldo fijo, un gasto fijo (alquiler, luz,
/// internet...) o la propina de una persona. Los sueldos y gastos fijos se
/// registran al empezar cada mes; las propinas, el día que tocan (el 15 y/o
/// el último día del mes).
class Recurring {
  final String id;
  final RecurringType type;
  final int person;
  final String category;
  final String description;
  final double amount;

  /// Mensual: día del mes. Semanal: día de la semana (1 = lunes, 7 = domingo).
  final int day;

  /// Sueldos y gastos fijos: cada cuánto se repiten.
  final Frequency frequency;

  /// Mensual con fecha variable (ej. el alquiler que cobran el 7, el 12 o el
  /// 20): no se registra solo; queda pendiente hasta que confirmen el pago.
  final bool confirm;

  /// Si cae fin de semana: se queda, pasa al lunes o se adelanta al viernes.
  final WeekendShift weekendShift;

  /// Solo propinas: true = cada quincena (15 y fin de mes), false = fin de mes.
  final bool biweekly;

  /// Último periodo ya registrado: "año-mes" para sueldos y gastos fijos,
  /// "año-mes-día" para propinas.
  final String? lastApplied;

  const Recurring({
    this.id = '',
    required this.type,
    required this.person,
    this.category = '',
    required this.description,
    required this.amount,
    required this.day,
    this.frequency = Frequency.monthly,
    this.confirm = false,
    this.weekendShift = WeekendShift.none,
    this.biweekly = false,
    this.lastApplied,
  });

  /// Sueldos y gastos fijos que no son mensuales se registran el día exacto
  /// de cada pago.
  bool get isDated =>
      type != RecurringType.allowance &&
      !confirm &&
      frequency != Frequency.monthly;

  /// Texto corto con cuándo se paga, por ejemplo "cada semana (viernes)".
  String get schedule => switch (type) {
        RecurringType.allowance =>
          biweekly ? 'cada quincena (15 y 30)' : 'a fin de mes (30)',
        _ when confirm => 'una vez al mes, fecha variable (~día $day)',
        _ => switch (frequency) {
            Frequency.monthly => 'cada mes, día $day',
            Frequency.biweekly => 'cada quincena (15 y 30)',
            Frequency.weekly =>
              'cada semana (${weekdayNames[(day - 1).clamp(0, 6)].toLowerCase()})',
          } +
          switch (weekendShift) {
            WeekendShift.none => '',
            WeekendShift.next => ', fin de semana → lunes',
            WeekendShift.previous => ', fin de semana → viernes',
          },
      };

  factory Recurring.fromMap(String id, Map<String, dynamic> map) {
    return Recurring(
      id: id,
      type: RecurringType.values.firstWhere((t) => t.name == map['type'],
          orElse: () => RecurringType.expense),
      person: (map['person'] as num).toInt(),
      category: (map['category'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      amount: currencySettings.convert(
          (map['amount'] as num).toDouble(), map['currency'] as String?),
      day: (map['day'] as num).toInt(),
      frequency: Frequency.values.firstWhere(
          (f) => f.name == map['frequency'],
          orElse: () => Frequency.monthly),
      confirm: (map['confirm'] as bool?) ?? false,
      weekendShift: WeekendShift.values.firstWhere(
          (w) => w.name == map['weekendShift'],
          orElse: () => WeekendShift.none),
      biweekly: (map['biweekly'] as bool?) ?? false,
      lastApplied: map['lastApplied'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        "type": type.name,
        "person": person,
        "category": category,
        "description": description,
        "amount": amount,
        "currency": currencySettings.code,
        "day": day,
        "frequency": frequency.name,
        "confirm": confirm,
        "weekendShift": weekendShift.name,
        "biweekly": biweekly,
        if (lastApplied != null) "lastApplied": lastApplied,
      };

  Recurring copyWith({String? id, String? lastApplied}) {
    return Recurring(
      id: id ?? this.id,
      type: type,
      person: person,
      category: category,
      description: description,
      amount: amount,
      day: day,
      frequency: frequency,
      confirm: confirm,
      weekendShift: weekendShift,
      biweekly: biweekly,
      lastApplied: lastApplied ?? this.lastApplied,
    );
  }
}

/// Meta de ahorro. Lo ahorrado se calcula a partir de los aportes, que son
/// gastos de la categoría "Ahorro Neto" con el id de la meta.
class Goal {
  final String id;
  final String name;
  final double target;

  const Goal({required this.id, required this.name, required this.target});

  factory Goal.fromMap(String id, Map<String, dynamic> map) {
    return Goal(
      id: id,
      name: map['name'] as String,
      target: currencySettings.convert(
          (map['target'] as num).toDouble(), map['currency'] as String?),
    );
  }

  Map<String, dynamic> toMap() =>
      {"name": name, "target": target, "currency": currencySettings.code};
}
