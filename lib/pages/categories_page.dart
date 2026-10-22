import 'package:flutter/material.dart';
import 'package:primera_app_curso/categories.dart';
import 'package:primera_app_curso/couple/space_state.dart';
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
    // En pareja, una categoría nueva la acepta la otra persona.
    final space = Provider.of<SpaceState>(context);
    final couple = space.activeCouple;
    final me = couple == null
        ? 0
        : couple.members.indexOf(space.uid!).clamp(0, 1);
    final partner = couple?.partnerName(space.uid!) ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      body: MultiStreamBuilder(
        streams: [
          finance.watchCategorySettings(),
          if (couple != null) finance.watchCategoryRequests(),
        ],
        builder: (context, values) {
          final settings = values[0] as CategorySettings;
          final requests = couple == null
              ? const <CategoryRequest>[]
              : [
                  for (final r in values[1] as List<CategoryRequest>)
                    // Un rechazo solo lo ve quien la propuso.
                    if (r.pending || r.by == me) r,
                ];
          // Se aplican aquí también para que los avatares se vean al momento.
          categorySettings = settings;

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (requests.isNotEmpty) ...[
                _header(
                  context,
                  'Esperando respuesta',
                  'Una categoría nueva se crea cuando los dos están de acuerdo.',
                ),
                for (final r in requests)
                  _requestTile(context, finance, r, me, partner),
              ],
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
                  subtitle: Text([
                    if (categoryExamples[name] != null) categoryExamples[name]!,
                    if (protectedCategories.contains(name)) 'siempre visible',
                  ].join(' · ')),
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
          await _edit(
            context,
            finance,
            settings,
            null,
            couple: couple == null ? null : (me, partner),
          );
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

  /// Una propuesta de categoría: la mía (esperando o rechazada) o la de mi
  /// pareja (para aceptar o rechazar).
  Widget _requestTile(BuildContext context, FinanceRepository finance,
      CategoryRequest r, int me, String partner) {
    final mine = r.by == me;
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: r.category.color.withValues(alpha: 0.18),
        foregroundColor: r.category.color,
        child: Icon(r.category.iconData, size: 22),
      ),
      title: Text(r.category.name),
      subtitle: Text(!mine
          ? '$partner quiere crearla'
          : r.pending
              ? 'Esperando que $partner acepte'
              : '$partner no la aceptó'),
      trailing: !mine
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => finance.answerCategoryRequest(r, false),
                  child: const Text('Rechazar'),
                ),
                TextButton(
                  onPressed: () => finance.answerCategoryRequest(r, true),
                  child: const Text('Aceptar'),
                ),
              ],
            )
          : TextButton(
              onPressed: () => finance.deleteCategoryRequest(r.id),
              child: Text(r.pending ? 'Cancelar' : 'Entendido'),
            ),
    );
  }

  /// [couple]: en pareja, (quién soy, nombre de mi pareja). Ahí una
  /// categoría nueva se propone y la crea la otra persona al aceptar.
  Future<void> _edit(BuildContext context, FinanceRepository finance,
      CategorySettings settings, CustomCategory? existing,
      {(int, String)? couple}) async {
    final pending = couple == null
        ? const <CategoryRequest>[]
        : await finance.watchCategoryRequests().first;
    if (!context.mounted) return;
    final taken = {
      ...builtInCategories,
      ...settings.custom.map((c) => c.name),
      for (final r in pending)
        if (r.pending) r.category.name,
    }.map((n) => n.toLowerCase()).toSet()
      ..remove(existing?.name.toLowerCase());

    final result = await showDialog<CustomCategory>(
      context: context,
      builder: (_) => _CategoryDialog(existing: existing, taken: taken),
    );
    if (result == null) return;

    if (existing == null && couple != null) {
      final messenger = ScaffoldMessenger.of(context);
      await finance.requestCategory(result, couple.$1);
      messenger.showSnackBar(SnackBar(
        content: Text('Le preguntamos a ${couple.$2}. Cuando acepte, '
            '"${result.name}" aparece para los dos.'),
      ));
      return;
    }

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
