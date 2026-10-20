/// Moneda en que se muestran los montos.
class Currency {
  final String code;
  final String name;
  final String symbol;

  /// Símbolo para el PDF, que solo admite caracteres latinos básicos.
  final String pdfSymbol;

  /// Unidades de esta moneda por 1 dólar, aproximado. Solo se usa para
  /// proponer el tipo de cambio; el usuario lo puede corregir.
  final double perDollar;

  const Currency(this.code, this.name, this.symbol, this.perDollar,
      {String? pdfSymbol})
      : pdfSymbol = pdfSymbol ?? symbol;
}

const currencies = [
  Currency('PEN', 'Sol peruano', 'S/.', 3.75),
  Currency('USD', 'Dólar estadounidense', 'US\$', 1),
  Currency('EUR', 'Euro', '€', 0.92, pdfSymbol: 'EUR'),
  Currency('MXN', 'Peso mexicano', 'MX\$', 18),
  Currency('COP', 'Peso colombiano', 'COL\$', 4000),
  Currency('CLP', 'Peso chileno', 'CLP\$', 950),
  Currency('ARS', 'Peso argentino', 'AR\$', 1000),
  Currency('BOB', 'Boliviano', 'Bs.', 6.9),
];

/// Moneda de los datos guardados antes de poder elegirla.
const legacyCurrency = 'PEN';

Currency currencyOf(String code) =>
    currencies.firstWhere((c) => c.code == code, orElse: () => currencies.first);

/// Moneda actual y cuánto vale 1 unidad de cada moneda usada antes, en la
/// moneda actual (el tipo de cambio que indicó el usuario).
class CurrencySettings {
  final String code;
  final Map<String, double> rates;

  const CurrencySettings({this.code = legacyCurrency, this.rates = const {}});

  factory CurrencySettings.fromMap(Map<String, dynamic>? map) =>
      CurrencySettings(
        code: (map?['code'] as String?) ?? legacyCurrency,
        rates: {
          for (final e in ((map?['rates'] as Map?) ?? const {}).entries)
            e.key as String: (e.value as num).toDouble(),
        },
      );

  Map<String, dynamic> toMap() => {'code': code, 'rates': rates};

  Currency get currency => currencyOf(code);

  /// Ajustes al cambiar a [newCode], sabiendo que 1 unidad de la moneda
  /// actual equivale a [rate] unidades de la nueva.
  CurrencySettings switchTo(String newCode, double rate) {
    if (newCode == code) return this;
    return CurrencySettings(code: newCode, rates: {
      for (final e in rates.entries)
        if (e.key != newCode) e.key: e.value * rate,
      code: rate,
    });
  }

  /// Convierte un monto guardado en [from] a la moneda actual.
  double convert(double amount, String? from) {
    final source = from ?? legacyCurrency;
    if (source == code) return amount;
    return amount * (rates[source] ?? 1);
  }
}

/// Ajustes vigentes; los actualiza la pantalla principal cuando cambian.
CurrencySettings currencySettings = const CurrencySettings();

/// Monto con el símbolo de la moneda actual, por ejemplo "US$ 12.50".
String money(double value) =>
    "${currencySettings.currency.symbol} ${value.toStringAsFixed(2)}";

/// Igual que [money], para el PDF.
String pdfMoney(double value) =>
    "${currencySettings.currency.pdfSymbol} ${value.toStringAsFixed(2)}";
