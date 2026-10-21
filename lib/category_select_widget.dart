import 'package:flutter/material.dart';
import 'package:primera_app_curso/categories.dart';

/// Cuadrícula de categorías; la elegida se marca con un borde de su color.
class CategorySelectionWidget extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String> onSelected;

  const CategorySelectionWidget(
      {super.key,
      required this.categories,
      required this.selected,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    // Dos filas que se desplazan de lado; se ve un pedazo de la siguiente
    // columna para que se note que hay más.
    final itemWidth = MediaQuery.of(context).size.width / 4.4;
    const itemHeight = 84.0;
    return SizedBox(
      height: itemHeight * 2,
      child: GridView.count(
        scrollDirection: Axis.horizontal,
        crossAxisCount: 2,
        childAspectRatio: itemHeight / itemWidth,
        children: [
          for (final name in categories)
            _CategoryWidget(
              name: name,
              selected: name == selected,
              onTap: () => onSelected(name),
            ),
        ],
      ),
    );
  }
}

class _CategoryWidget extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryWidget(
      {required this.name, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(name);
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? color : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: CategoryAvatar(name, size: 44),
          ),
          const SizedBox(height: 4),
          Text(
            name == ahorroCategory ? 'Ahorro' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
