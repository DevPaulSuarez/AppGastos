import 'package:flutter/material.dart';

/// Colores con significado (ingreso, gasto, ahorro, aviso). Siempre van con
/// un texto o ícono, para no depender solo del color. Hay una versión para
/// modo claro y otra para modo oscuro, más suave para que no encandile.
@immutable
class MoneyColors extends ThemeExtension<MoneyColors> {
  final Color income;
  final Color expense;
  final Color savings;
  final Color warning;

  const MoneyColors({
    required this.income,
    required this.expense,
    required this.savings,
    required this.warning,
  });

  static const light = MoneyColors(
    income: Color(0xFF2E8B57),
    expense: Color(0xFFC94A4A),
    savings: Color(0xFF3B6FD8),
    warning: Color(0xFFC96A12),
  );

  static const dark = MoneyColors(
    income: Color(0xFF8FD3A8),
    expense: Color(0xFFF0A29B),
    savings: Color(0xFFA3C0F5),
    warning: Color(0xFFF2BB80),
  );

  @override
  MoneyColors copyWith({
    Color? income,
    Color? expense,
    Color? savings,
    Color? warning,
  }) => MoneyColors(
    income: income ?? this.income,
    expense: expense ?? this.expense,
    savings: savings ?? this.savings,
    warning: warning ?? this.warning,
  );

  @override
  MoneyColors lerp(MoneyColors? other, double t) {
    if (other == null) return this;
    return MoneyColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      savings: Color.lerp(savings, other.savings, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

extension MoneyColorsOf on BuildContext {
  /// Colores de ingreso, gasto, ahorro y aviso del tema actual.
  MoneyColors get money =>
      Theme.of(this).extension<MoneyColors>() ?? MoneyColors.light;
}

const _seed = Color(0xFF059669);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

  return ThemeData(
    useMaterial3: true,
    extensions: [
      brightness == Brightness.dark ? MoneyColors.dark : MoneyColors.light,
    ],
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: const CircleBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
