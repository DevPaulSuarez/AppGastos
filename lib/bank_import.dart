import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/expense.dart';
import 'package:primera_app_curso/models.dart';

/// Un movimiento del CSV del banco. [amount] es positivo si entró dinero y
/// negativo si salió.
class BankRow {
  final DateTime date;
  final String description;
  final double amount;

  const BankRow(this.date, this.description, this.amount);

  /// Nombre corto del comercio: lo que viene entre paréntesis al final o la
  /// descripción sin números largos.
  String get merchant {
    final m = RegExp(r'\(([^()]*)\)\s*$').firstMatch(description);
    final text = m != null ? m.group(1)! : description;
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Clave para recordar cómo llaman a este comercio: las dos primeras
  /// palabras sin números ni símbolos.
  String get key {
    final words = merchant
        .toUpperCase()
        .replaceAll(RegExp(r"[^A-Z' ]"), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .take(2);
    return words.join(' ');
  }
}

enum BankKind { expense, income, transfer, deposit }

/// Lo que la app cree que es un movimiento del banco.
class BankGuess {
  final BankKind kind;
  final String name;
  final String category;

  const BankGuess(this.kind, this.name, [this.category = '']);
}

/// Nombre y categoría que el usuario usa para un comercio (se aprende de los
/// movimientos que ya coinciden).
class LearnedName {
  final String name;
  final String category;

  const LearnedName(this.name, this.category);

  Map<String, dynamic> toMap() => {'name': name, 'category': category};

  factory LearnedName.fromMap(Map<String, dynamic> map) =>
      LearnedName(map['name'] as String, map['category'] as String);
}

/// Lee el CSV que se baja del banco. Busca la fila de títulos (Date,
/// Description y Credit/Debit o Amount) y devuelve los movimientos. Lanza
/// [FormatException] si no reconoce el archivo.
List<BankRow> parseBankCsv(String text) {
  final rows = _csvRows(text);
  final headerIndex = rows.indexWhere((r) {
    final lower = r.map((c) => c.toLowerCase().trim()).toList();
    return lower.contains('date') &&
        lower.contains('description') &&
        (lower.contains('amount') ||
            (lower.contains('credit') && lower.contains('debit')));
  });
  if (headerIndex < 0) {
    throw const FormatException(
      'No se reconoce el archivo: debe tener las columnas Date, Description '
      'y Credit/Debit o Amount.',
    );
  }
  final header = rows[headerIndex].map((c) => c.toLowerCase().trim()).toList();
  final date = header.indexOf('date');
  final desc = header.indexOf('description');
  final credit = header.indexOf('credit');
  final debit = header.indexOf('debit');
  final amount = header.indexOf('amount');

  double? number(List<String> r, int i) {
    if (i < 0 || i >= r.length) return null;
    final t = r[i].replaceAll(RegExp(r'[\$,\s]'), '');
    return t.isEmpty ? null : double.tryParse(t);
  }

  final out = <BankRow>[];
  for (final r in rows.skip(headerIndex + 1)) {
    if (r.length <= desc || date >= r.length) continue;
    final d = _parseDate(r[date]);
    if (d == null) continue;
    double? value;
    if (amount >= 0) {
      value = number(r, amount);
    } else {
      final c = number(r, credit);
      final dbt = number(r, debit);
      if (c != null && c != 0) {
        value = c.abs();
      } else if (dbt != null && dbt != 0) {
        value = -dbt.abs();
      }
    }
    if (value == null || value == 0) continue;
    out.add(BankRow(d, r[desc].trim(), value));
  }
  return out;
}

/// Fechas MM/DD/YYYY (como las del banco) o YYYY-MM-DD.
DateTime? _parseDate(String text) {
  final t = text.trim();
  final us = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(t);
  if (us != null) {
    return DateTime(
      int.parse(us.group(3)!),
      int.parse(us.group(1)!),
      int.parse(us.group(2)!),
    );
  }
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
  if (iso != null) {
    return DateTime(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }
  return null;
}

/// Separa un CSV en filas y columnas, con comillas.
List<List<String>> _csvRows(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  row.add(cell.toString());
  if (row.any((c) => c.isNotEmpty)) rows.add(row);
  return rows;
}

// (texto a buscar, nombre, categoría)
const _expenseRules = [
  ('SENDWAVE', 'Sendwave', 'Familia'),
  ('APPLE.COM/BILL', 'Apple TV', 'Suscripciones'),
  ('AMAZON PRIME', 'Amazon Prime', 'Suscripciones'),
  ('STATE FARM', 'Seguro carro', 'Transporte'),
  ('COSTCO GAS', 'Gasolina Costco', 'Transporte'),
  ('MAVERIK', 'Gasolina Maverik', 'Transporte'),
  ('COSTCO', 'Costco', 'Comida'),
  ('SMITHS', "Smith's", 'Comida'),
  ('WM SUPERCENTER', 'Walmart', 'Comida'),
  ('WAL-MART', 'Walmart', 'Comida'),
  ('WAL MART', 'Walmart', 'Comida'),
  ('RANCHO MARKET', 'Rancho Market', 'Comida'),
  ('WINCO', 'Winco', 'Comida'),
  ('PEQUENITA', 'La Super Pequeñita', 'Comida'),
  ('CHINATOWN', 'Chinatown Supermarket', 'Comida'),
  ('BODEGUITA', 'La Bodeguita Latina', 'Comida'),
  ('FAMILY DOLLAR', 'Family Dollar', 'Comida'),
  ('TARGET', 'Target', 'Comida'),
  ('CRICKET', 'Celular', 'Servicios'),
  ('SLCC PARKING', 'Estacionamiento SLCC', 'Educación'),
  ('SALT LAKE COMMUNITY', 'SLCC', 'Educación'),
  ('SL COMM COLL', 'SLCC', 'Educación'),
  ('DENTAL', 'Dentista', 'Salud'),
  ('DENTIST', 'Dentista', 'Salud'),
  ('EYE CARE', 'Oculista', 'Salud'),
  ('J M TIRES', 'J&M Tires', 'Transporte'),
  ('AUTOZONE', 'AutoZone', 'Transporte'),
  ("O'REILLY", "O'Reilly", 'Transporte'),
  ('AIR/TIRE', 'Aire para llantas', 'Transporte'),
  ('AIR TIRE', 'Aire para llantas', 'Transporte'),
  ('LYFT', 'Lyft', 'Transporte'),
  ('ROSS STORES', 'Ross', 'Ropa y cuidado'),
  ('DILLARD', "Dillard's", 'Ropa y cuidado'),
  ("MACY'S", "Macy's", 'Ropa y cuidado'),
  ('SHOE DEPT', 'Shoe Dept', 'Ropa y cuidado'),
  ('T J MAXX', 'TJ Maxx', 'Ropa y cuidado'),
  ('OVHCLOUD', 'OVHcloud', 'Suscripciones'),
  ('GOOGLE', 'Google Play', 'Suscripciones'),
  ('MCDONALD', "McDonald's", 'Restaurantes'),
  ('WILD PERU', 'Wild Peru', 'Restaurantes'),
  ('BAKERY', 'Bakery 85°', 'Restaurantes'),
  ('DUTCH BROS', 'Dutch Bros', 'Restaurantes'),
  ('SANGUCHO', 'El Rico Sanguchón', 'Restaurantes'),
  ('PIZZ', 'Pizzería', 'Restaurantes'),
  ("DOMINO", "Domino's", 'Restaurantes'),
  ('KFC', 'KFC', 'Restaurantes'),
  ('FOREIGN TRANS', 'Comisión del banco', 'Otros'),
  ('STATEMENT FEE', 'Comisión del banco', 'Otros'),
  ('DELIVERY FEE', 'Comisión del banco', 'Otros'),
  ('MONTHLY SERVICE FEE', 'Comisión del banco', 'Otros'),
  ('LIBRA', 'Biblioteca (impresión)', 'Otros'),
];

/// Adivina qué es un movimiento del banco. [people]: nombres de la pareja
/// (para reconocer envíos entre ellos). [learned]: nombres y categorías que
/// ya usaron para ese comercio; tienen prioridad.
BankGuess guessBankRow(
  BankRow row, {
  List<String> people = const [],
  Map<String, LearnedName> learned = const {},
}) {
  final up = row.description.toUpperCase();
  // Envíos entre las cuentas de la pareja.
  if (up.contains('XFER FROM DDA') || up.contains('XFER TO DDA')) {
    return const BankGuess(BankKind.transfer, 'Envío entre ustedes');
  }
  if (up.contains('ZELLE') &&
      people.any((p) => p.length > 2 && up.contains(p.toUpperCase()))) {
    return const BankGuess(BankKind.transfer, 'Envío entre ustedes');
  }
  if (row.amount > 0) {
    if (up.contains('PAYROLL') || up.contains('PAPERLESS')) {
      return const BankGuess(BankKind.income, 'Sueldo');
    }
    if (up.contains('DEPOSIT') && !up.contains('IRS')) {
      return const BankGuess(BankKind.deposit, 'Depósito');
    }
    final known = learned[row.key];
    if (known != null) return BankGuess(BankKind.income, known.name);
    if (up.contains('IRS')) {
      return const BankGuess(BankKind.income, 'Devolución de impuestos');
    }
    return BankGuess(BankKind.income, 'Devolución ${_title(row.merchant)}');
  }
  if (up.contains('WITHDRAWAL')) {
    return const BankGuess(BankKind.expense, 'Retiro de banco', 'Otros');
  }
  final known = learned[row.key];
  if (known != null) {
    return BankGuess(BankKind.expense, known.name, known.category);
  }
  for (final (key, name, category) in _expenseRules) {
    if (up.contains(key)) {
      if (key == 'STATE FARM' && row.amount.abs() < 20) {
        return const BankGuess(BankKind.expense, 'Seguro vida', 'Servicios');
      }
      return BankGuess(BankKind.expense, name, category);
    }
  }
  return BankGuess(BankKind.expense, _title(row.merchant), 'Otros');
}

String _title(String text) {
  final words = text
      .replaceAll(RegExp(r'\b[A-Z]{2}\b\s*(US)?\s*$'), '')
      .split(' ')
      .where((w) => w.isNotEmpty && !RegExp(r'\d').hasMatch(w))
      .take(3);
  return words
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

/// Un movimiento de la app (gasto o ingreso) para comparar.
class AppMove {
  final Expense? expense;
  final Income? income;

  const AppMove.expense(Expense this.expense) : income = null;
  const AppMove.income(Income this.income) : expense = null;

  bool get isIncome => income != null;
  double get amount => expense?.value ?? income!.amount;
  String get name => expense?.description ?? income!.description;
  String get category => expense?.category ?? '';
  int? get person => expense != null ? expense!.paidBy : income!.person;
  DateTime get date => expense != null
      ? DateTime(expense!.year, expense!.month, expense!.day)
      : DateTime(income!.year, income!.month, income!.day);
}

class BankMatch {
  final BankRow row;
  final BankGuess guess;
  final AppMove move;

  const BankMatch(this.row, this.guess, this.move);
}

class BankMissing {
  final BankRow row;
  final BankGuess guess;

  const BankMissing(this.row, this.guess);
}

/// Resultado de comparar el banco con la app.
class BankCheck {
  /// Mismo monto y fecha cercana.
  final List<BankMatch> matched;

  /// Parecen el mismo movimiento (mismo comercio y fecha cercana) pero con
  /// otro monto.
  final List<BankMatch> amountDiffers;

  /// Coinciden, pero la categoría en la app no es la que se esperaba.
  final List<BankMatch> categoryDiffers;

  /// Están en el banco y no en la app.
  final List<BankMissing> missing;

  /// Están en la app (a nombre de esta persona) y no en el banco: pueden
  /// ser en efectivo o de otra cuenta.
  final List<AppMove> onlyInApp;

  /// No se cuentan: envíos entre ustedes y depósitos.
  final List<BankMissing> ignored;

  const BankCheck({
    required this.matched,
    required this.amountDiffers,
    required this.categoryDiffers,
    required this.missing,
    required this.onlyInApp,
    required this.ignored,
  });
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áà]'), 'a')
    .replaceAll(RegExp('[éè]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ñ', 'n');

bool _similar(String a, String b) {
  final wa = _norm(a).split(RegExp(r"[^a-z']+")).where((w) => w.length > 3);
  final wb = _norm(b).split(RegExp(r"[^a-z']+")).where((w) => w.length > 3);
  return wa.any((w) => wb.any((x) => x.startsWith(w) || w.startsWith(x)));
}

/// Compara los movimientos del banco de la persona [person] con lo que hay
/// en la app entre [from] y [to] (inclusive).
BankCheck compareBank({
  required List<BankRow> rows,
  required List<Expense> expenses,
  required List<Income> incomes,
  required int person,
  required DateTime from,
  required DateTime to,
  List<String> people = const [],
  Map<String, LearnedName> learned = const {},
}) {
  bool inRange(DateTime d) => !d.isBefore(from) && !d.isAfter(to);
  final pool = <AppMove>[
    for (final e in expenses)
      if (inRange(DateTime(e.year, e.month, e.day)) &&
          isSpendingCategory(e.category))
        AppMove.expense(e),
    for (final i in incomes)
      if (inRange(DateTime(i.year, i.month, i.day))) AppMove.income(i),
  ];
  final matched = <BankMatch>[];
  final missing = <BankMissing>[];
  final ignored = <BankMissing>[];
  final pending = <(BankRow, BankGuess)>[];

  final inFile = rows.where((r) => inRange(r.date)).toList();
  final guesses = {
    for (final r in inFile)
      r: guessBankRow(r, people: people, learned: learned),
  };

  // Compras devueltas: un cobro y su devolución por el mismo monto en el
  // mismo comercio no son gasto ni ingreso.
  final returned = <BankRow>{};
  for (final back in inFile) {
    if (back.amount <= 0 || guesses[back]!.kind != BankKind.income) continue;
    if (guesses[back]!.name == 'Sueldo') continue;
    for (final buy in inFile) {
      if (buy.amount >= 0 || returned.contains(buy)) continue;
      if (buy.key != back.key || (buy.amount + back.amount).abs() > 0.005) {
        continue;
      }
      if (back.date.difference(buy.date).inDays.abs() > 31) continue;
      returned
        ..add(buy)
        ..add(back);
      break;
    }
  }

  for (final row in inFile) {
    final guess = guesses[row]!;
    if (returned.contains(row)) {
      ignored.add(BankMissing(row, BankGuess(guess.kind, 'Compra devuelta')));
      continue;
    }
    if (guess.kind == BankKind.transfer || guess.kind == BankKind.deposit) {
      ignored.add(BankMissing(row, guess));
      continue;
    }
    final income = guess.kind == BankKind.income;
    // Mismo monto; gana el de la misma persona y la fecha más cercana. Con
    // el mismo nombre se acepta más distancia (ej. "Ya pagué" días después).
    AppMove? best;
    var bestScore = 1 << 30;
    for (final m in pool) {
      if (m.isIncome != income) continue;
      if ((m.amount - row.amount.abs()).abs() > 0.005) continue;
      final days = m.date.difference(row.date).inDays.abs();
      final sameName =
          _similar(m.name, guess.name) || _similar(m.name, row.merchant);
      if (days > (sameName ? 31 : 5)) continue;
      final score = days + (m.person == person ? 0 : 100) + (sameName ? 0 : 10);
      if (score < bestScore) {
        best = m;
        bestScore = score;
      }
    }
    if (best != null) {
      pool.remove(best);
      matched.add(BankMatch(row, guess, best));
    } else {
      pending.add((row, guess));
    }
  }

  // Mismo comercio y fecha cercana, pero otro monto.
  final amountDiffers = <BankMatch>[];
  for (final (row, guess) in pending) {
    final income = guess.kind == BankKind.income;
    AppMove? near;
    for (final m in pool) {
      if (m.isIncome != income) continue;
      if (m.date.difference(row.date).inDays.abs() > 3) continue;
      if (_similar(m.name, guess.name) || _similar(m.name, row.merchant)) {
        near = m;
        break;
      }
    }
    if (near != null) {
      pool.remove(near);
      amountDiffers.add(BankMatch(row, guess, near));
    } else {
      missing.add(BankMissing(row, guess));
    }
  }

  final categoryDiffers = [
    for (final m in matched)
      if (!m.move.isIncome &&
          m.guess.category.isNotEmpty &&
          m.guess.category != 'Otros' &&
          learned[m.row.key] == null &&
          m.move.category != m.guess.category)
        m,
  ];

  final onlyInApp = [
    for (final m in pool)
      if (m.person == person) m,
  ]..sort((a, b) => a.date.compareTo(b.date));

  return BankCheck(
    matched: matched,
    amountDiffers: amountDiffers,
    categoryDiffers: categoryDiffers,
    missing: missing,
    onlyInApp: onlyInApp,
    ignored: ignored,
  );
}

/// Lo que se aprende de los movimientos que coinciden: cómo llaman y en qué
/// categoría ponen cada comercio.
Map<String, LearnedName> learnFrom(List<BankMatch> matched) => {
  for (final m in matched)
    if (!m.move.isIncome && m.row.key.isNotEmpty)
      m.row.key: LearnedName(m.move.name, m.move.category),
};
