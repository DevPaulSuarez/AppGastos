import 'package:primera_app_curso/currency.dart';

/// Gasto. El monto se lee ya convertido a la moneda actual y se guarda junto
/// con su moneda.
class Expense {
  final String id;
  final String category;
  final double value;
  final int day;
  final int month;
  final int year;
  final String description;

  /// Índice de la persona que pagó (0 o 1), o null si no se indicó.
  final int? paidBy;

  /// Meta de ahorro a la que corresponde este aporte, si la hay.
  final String? goalId;

  /// Préstamos: quién lo devolverá y cuánto devolvió ya.
  final String? owedBy;
  final double repaid;

  /// Devoluciones: el préstamo que se está pagando. Se guardan como montos
  /// negativos de la categoría "Préstamos".
  final String? loanId;

  /// Compra pagada con la propina de [paidBy]. Se cuenta en su categoría
  /// (ej. Comida) y se descuenta de "Propinas", para no contarla dos veces:
  /// la propina ya se contó como gasto al entregarla.
  final bool withAllowance;

  /// Descuento en "Propinas" (monto negativo) de la compra con este id.
  final String? allowanceFor;

  /// Salida del ahorro de una meta (monto negativo de "Ahorro Neto") para
  /// pagar el gasto con este id: el dinero apartado se usó.
  final String? goalUseFor;

  const Expense({
    required this.id,
    required this.category,
    required this.value,
    required this.day,
    required this.month,
    required this.year,
    required this.description,
    this.paidBy,
    this.goalId,
    this.owedBy,
    this.repaid = 0,
    this.loanId,
    this.withAllowance = false,
    this.allowanceFor,
    this.goalUseFor,
  });

  bool get isLoan => owedBy != null && loanId == null;

  /// Lo que falta que devuelvan de un préstamo.
  double get pending => isLoan ? value - repaid : 0;

  factory Expense.fromMap(String id, Map<String, dynamic> map) {
    return Expense(
      id: id,
      category: map['category'] as String,
      value: currencySettings.convert(
        (map['value'] as num).toDouble(),
        map['currency'] as String?,
      ),
      day: (map['day'] as num).toInt(),
      month: (map['month'] as num).toInt(),
      year: (map['year'] as num).toInt(),
      description: (map['Description'] as String?) ?? '',
      paidBy: (map['paidBy'] as num?)?.toInt(),
      goalId: map['goalId'] as String?,
      owedBy: map['owedBy'] as String?,
      repaid: currencySettings.convert(
        ((map['repaid'] as num?) ?? 0).toDouble(),
        map['currency'] as String?,
      ),
      loanId: map['loanId'] as String?,
      withAllowance: (map['withAllowance'] as bool?) ?? false,
      allowanceFor: map['allowanceFor'] as String?,
      goalUseFor: map['goalUseFor'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    "category": category,
    "value": value,
    "currency": currencySettings.code,
    "month": month,
    "day": day,
    "year": year,
    "Description": description,
    if (paidBy != null) "paidBy": paidBy,
    if (goalId != null) "goalId": goalId,
    if (owedBy != null) "owedBy": owedBy,
    if (repaid != 0) "repaid": repaid,
    if (loanId != null) "loanId": loanId,
    if (withAllowance) "withAllowance": true,
    if (allowanceFor != null) "allowanceFor": allowanceFor,
    if (goalUseFor != null) "goalUseFor": goalUseFor,
  };

  Expense copyWith({
    double? value,
    String? description,
    int? paidBy,
    double? repaid,
    bool? withAllowance,
  }) {
    return Expense(
      id: id,
      category: category,
      value: value ?? this.value,
      day: day,
      month: month,
      year: year,
      description: description ?? this.description,
      paidBy: paidBy ?? this.paidBy,
      goalId: goalId,
      owedBy: owedBy,
      repaid: repaid ?? this.repaid,
      loanId: loanId,
      withAllowance: withAllowance ?? this.withAllowance,
      allowanceFor: allowanceFor,
      goalUseFor: goalUseFor,
    );
  }
}
