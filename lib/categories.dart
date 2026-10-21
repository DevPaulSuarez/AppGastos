import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Categoría usada para separar dinero como ahorro. No cuenta como gasto.
const ahorroCategory = "Ahorro Neto";

/// Dinero libre que recibe cada persona para usarlo en lo que quiera.
const propinaCategory = "Propinas";

/// Compras hechas para otra persona que la devolverá. No es gasto propio:
/// solo baja el sobrante hasta que la devuelvan.
const prestamoCategory = "Préstamos";

/// Si los movimientos de esta categoría son gasto real (no ahorro ni
/// préstamo).
bool isSpendingCategory(String category) =>
    category != ahorroCategory && category != prestamoCategory;

/// Categorías que trae la app. Se pueden ocultar, pero no borrar.
final Map<String, IconData> _builtInIcons = {
  "Vivienda": Icons.home_rounded,
  "Comida": Icons.dinner_dining,
  "Servicios": Icons.bolt,
  "Transporte": FontAwesomeIcons.busSimple.data,
  "Salud": Icons.medical_services_outlined,
  "Hogar": Icons.chair_outlined,
  "Suscripciones": Icons.subscriptions_outlined,
  "Ocio": Icons.local_activity_outlined,
  "Hijos": Icons.child_care,
  "Mascotas": Icons.pets,
  "Compras": Icons.shopping_bag,
  "Antojitos": FontAwesomeIcons.moneyBillWave.data,
  "Alcohol": FontAwesomeIcons.wineBottle.data,
  propinaCategory: Icons.redeem,
  ahorroCategory: FontAwesomeIcons.piggyBank.data,
  "Otros": FontAwesomeIcons.infinity.data,
  prestamoCategory: Icons.handshake_outlined,
};

/// Un color fijo por categoría, el mismo en el gráfico y en las listas.
const Map<String, Color> _builtInColors = {
  "Vivienda": Color(0xFF0D9488),
  "Comida": Color(0xFFF59E0B),
  "Servicios": Color(0xFF0891B2),
  // Naranja: el azul es del ahorro y en el gráfico se confundían.
  "Transporte": Color(0xFFF97316),
  "Salud": Color(0xFFE11D48),
  "Hogar": Color(0xFF92400E),
  "Suscripciones": Color(0xFF7C3AED),
  "Ocio": Color(0xFFEC4899),
  "Hijos": Color(0xFF65A30D),
  "Mascotas": Color(0xFFB45309),
  "Compras": Color(0xFF8B5CF6),
  "Antojitos": Color(0xFFEF4444),
  "Alcohol": Color(0xFFDB2777),
  propinaCategory: Color(0xFFCA8A04),
  ahorroCategory: Color(0xFF2563EB),
  "Otros": Color(0xFF64748B),
  prestamoCategory: Color(0xFF0E7490),
};

/// Categorías que usa la app por dentro y no se pueden ocultar.
const protectedCategories = {ahorroCategory, propinaCategory, "Otros"};

List<String> get builtInCategories =>
    _builtInIcons.keys.where((name) => name != prestamoCategory).toList();

/// Íconos para elegir al crear una categoría. Se guarda la clave, no el ícono.
final Map<String, IconData> categoryIconChoices = {
  'mascotas': Icons.pets,
  'estudios': Icons.school,
  'hijos': Icons.child_care,
  'bebe': Icons.baby_changing_station,
  'gimnasio': Icons.fitness_center,
  'viajes': Icons.flight,
  'regalos': Icons.card_giftcard,
  'auto': Icons.directions_car,
  'celular': Icons.phone_android,
  'libros': Icons.menu_book,
  'juegos': Icons.sports_esports,
  'belleza': Icons.spa,
  'cafe': Icons.local_cafe,
  'arreglos': Icons.build,
  'musica': Icons.music_note,
  'donaciones': Icons.volunteer_activism,
  'banco': Icons.account_balance,
  'deporte': Icons.sports_soccer,
  'ropa': Icons.checkroom,
  'otros': Icons.sell,
};

const categoryColorChoices = [
  Color(0xFF0D9488),
  Color(0xFF059669),
  Color(0xFF65A30D),
  Color(0xFFCA8A04),
  Color(0xFFEA580C),
  Color(0xFFDC2626),
  Color(0xFFDB2777),
  Color(0xFF9333EA),
  Color(0xFF4F46E5),
  Color(0xFF2563EB),
  Color(0xFF0891B2),
  Color(0xFF475569),
];

/// Categoría creada por el usuario.
class CustomCategory {
  final String name;
  final String icon;
  final Color color;

  const CustomCategory(
      {required this.name, required this.icon, required this.color});

  factory CustomCategory.fromMap(Map<String, dynamic> map) => CustomCategory(
        name: map['name'] as String,
        icon: map['icon'] as String,
        color: Color((map['color'] as num).toInt()),
      );

  Map<String, dynamic> toMap() =>
      {'name': name, 'icon': icon, 'color': color.toARGB32()};

  IconData get iconData => categoryIconChoices[icon] ?? Icons.sell;
}

/// Ajustes de categorías: las creadas por el usuario y las ocultas.
class CategorySettings {
  final List<CustomCategory> custom;
  final Set<String> hidden;

  const CategorySettings({this.custom = const [], this.hidden = const {}});

  factory CategorySettings.fromMap(Map<String, dynamic>? map) =>
      CategorySettings(
        custom: [
          for (final c in (map?['custom'] as List?) ?? const [])
            CustomCategory.fromMap(Map<String, dynamic>.from(c as Map)),
        ],
        hidden: {...((map?['hidden'] as List?) ?? const []).cast<String>()},
      );

  Map<String, dynamic> toMap() => {
        'custom': [for (final c in custom) c.toMap()],
        'hidden': hidden.toList(),
      };
}

/// Ajustes vigentes; los actualiza la pantalla principal cuando cambian.
CategorySettings categorySettings = const CategorySettings();

/// Categorías visibles para registrar gastos, con su ícono. Las creadas por
/// el usuario van antes de "Otros", "Propinas" y "Ahorro Neto".
Map<String, IconData> get categories {
  const last = ["Otros", propinaCategory, ahorroCategory];
  return {
    for (final e in _builtInIcons.entries)
      if (!last.contains(e.key) &&
          e.key != prestamoCategory &&
          !categorySettings.hidden.contains(e.key))
        e.key: e.value,
    for (final c in categorySettings.custom)
      if (!categorySettings.hidden.contains(c.name)) c.name: c.iconData,
    for (final name in last) name: _builtInIcons[name]!,
  };
}

/// Categorías de gasto real (sin el ahorro).
List<String> get expenseCategories =>
    categories.keys.where((name) => name != ahorroCategory).toList();

CustomCategory? _custom(String name) =>
    categorySettings.custom.where((c) => c.name == name).firstOrNull;

IconData categoryIcon(String name) =>
    _builtInIcons[name] ??
    _custom(name)?.iconData ??
    FontAwesomeIcons.notesMedical.data;

Color categoryColor(String name) =>
    _builtInColors[name] ?? _custom(name)?.color ?? const Color(0xFF64748B);

/// Ícono de la categoría dentro de un círculo de su color.
class CategoryAvatar extends StatelessWidget {
  final String category;
  final double size;

  const CategoryAvatar(this.category, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(categoryIcon(category), color: color, size: size * 0.48),
    );
  }
}
