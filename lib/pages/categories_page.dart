import 'package:flutter/material.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/finance_repository.dart';
import 'package:primera_app_curso/pages/ui/dialogs.dart';
import 'package:primera_app_curso/pages/ui/multi_stream_builder.dart';
import 'package:provider/provider.dart';

/// Crear, editar y ocultar categorías.
class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final finance = Provider.of<FinanceRepository>(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      body: MultiStreamBuilder(
        streams: [finance.watchCategorySettings()],
        builder: (context, values) {
          final settings = values[0] as CategorySettings;
          // Se aplican aquí también para que los avatares se vean al momento.
          categorySettings = settings;

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _header(context, 'Creadas por ustedes',
                  'Toca una para cambiar su nombre, ícono o color.'),
              if (settings.custom.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Aún no crearon categorías.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              for (final custom in settings.custom)
                ListTile(
                  leading: CategoryAvatar(custom.name, size: 40),
                  title: Text(custom.name),
                  subtitle: settings.hidden.contains(custom.name)
                      ? const Text('Oculta')
                      : null,
                  onTap: () => _edit(context, finance, settings, custom),
                  trailing: IconButton(
                    tooltip: 'Eliminar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(context, finance, settings, custom),
                  ),
                ),
              _header(context, 'De la app',
                  'Apaga las que no usen para que no salgan al registrar.'),
              for (final name in builtInCategories)
                SwitchListTile(
                  secondary: CategoryAvatar(name, size: 40),
                  title: Text(name),
                  subtitle: protectedCategories.contains(name)
                      ? const Text('Siempre visible')
                      : null,
                  value: !settings.hidden.contains(name),
                  onChanged: protectedCategories.contains(name)
                      ? null
                      : (visible) => finance.saveCategorySettings(
                            CategorySettings(
                              custom: settings.custom,
                              hidden: visible
                                  ? ({...settings.hidden}..remove(name))
                                  : {...settings.hidden, name},
                            ),
                          ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        shape: const StadiumBorder(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva categoría'),
        onPressed: () async {
          final settings = await finance.watchCategorySettings().first;
          if (!context.mounted) return;
          await _edit(context, finance, settings, null);
        },
      ),
    );
  }

  Widget _header(BuildContext context, String title, String hint) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: scheme.primary)),
          Text(hint,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, FinanceRepository finance,
      CategorySettings settings, CustomCategory? existing) async {
    final taken = {
      ...builtInCategories,
      ...settings.custom.map((c) => c.name),
    }.map((n) => n.toLowerCase()).toSet()
      ..remove(existing?.name.toLowerCase());

    final result = await showDialog<CustomCategory>(
      context: context,
      builder: (_) => _CategoryDialog(existing: existing, taken: taken),
    );
    if (result == null) return;

    final custom = [
      for (final c in settings.custom)
        if (c.name == existing?.name) result else c,
      if (existing == null) result,
    ];
    final hidden = {...settings.hidden};
    if (existing != null && existing.name != result.name) {
      if (hidden.remove(existing.name)) hidden.add(result.name);
      await finance.renameCategory(existing.name, result.name);
    }
    await finance.saveCategorySettings(
        CategorySettings(custom: custom, hidden: hidden));
  }

  Future<void> _delete(BuildContext context, FinanceRepository finance,
      CategorySettings settings, CustomCategory category) async {
    if (!await confirmDialog(
        context,
        '¿Eliminar "${category.name}"? Los gastos ya registrados con esta '
        'categoría se mantienen.',
        confirm: 'Eliminar')) {
      return;
    }
    await finance.saveCategorySettings(CategorySettings(
      custom: settings.custom.where((c) => c.name != category.name).toList(),
      hidden: {...settings.hidden}..remove(category.name),
    ));
  }
}

class _CategoryDialog extends StatefulWidget {
  final CustomCategory? existing;

  /// Nombres ya usados (en minúsculas), para no repetir.
  final Set<String> taken;

  const _CategoryDialog({required this.existing, required this.taken});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name;
  late String _icon;
  late Color _color;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _icon = widget.existing?.icon ?? categoryIconChoices.keys.first;
    _color = widget.existing?.color ?? categoryColorChoices.first;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe un nombre');
    } else if (widget.taken.contains(name.toLowerCase())) {
      setState(() => _error = 'Ya existe una categoría con ese nombre');
    } else {
      Navigator.of(context)
          .pop(CustomCategory(name: name, icon: _icon, color: _color));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nueva categoría' : 'Editar categoría'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: _color.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child: Icon(categoryIconChoices[_icon], color: _color, size: 28),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Nombre', errorText: _error),
            ),
            const SizedBox(height: 16),
            Text('Ícono', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in categoryIconChoices.entries)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _icon = entry.key),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: entry.key == _icon
                            ? _color.withValues(alpha: 0.2)
                            : scheme.surfaceContainerHigh,
                        border: entry.key == _icon
                            ? Border.all(color: _color, width: 2)
                            : null,
                      ),
                      child: Icon(entry.value,
                          size: 20,
                          color: entry.key == _icon
                              ? _color
                              : scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Color', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in categoryColorChoices)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = color),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: color == _color
                            ? Border.all(color: scheme.onSurface, width: 3)
                            : null,
                      ),
                      child: color == _color
                          ? const Icon(Icons.check, size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Cancelar'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
