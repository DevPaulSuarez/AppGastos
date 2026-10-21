import 'package:flutter/material.dart';
import 'package:primera_app_curso/pages/ui/day_picker.dart';
import 'package:primera_app_curso/utils.dart';

class DialogField {
  final String label;
  final String initial;
  final bool number;

  /// Si se indica, el campo es una lista desplegable con estas opciones.
  final List<String>? options;

  /// Día del mes elegido con un mini calendario (el valor es el número).
  final bool day;

  /// Con [day]: muestra el calendario real de este mes, y [maxDay] desactiva
  /// los días siguientes.
  final DateTime? month;
  final int? maxDay;

  /// Con [options]: se elige con botones de una letra (ej. días de la
  /// semana) en vez de una lista desplegable.
  final bool letters;

  const DialogField(
    this.label, {
    this.initial = '',
    this.number = false,
    this.options,
    this.letters = false,
  }) : day = false,
       month = null,
       maxDay = null;

  /// Día del mes con mini calendario.
  const DialogField.day(
    this.label, {
    required this.initial,
    this.month,
    this.maxDay,
  }) : number = true,
       options = null,
       day = true,
       letters = false;
}

/// Muestra un diálogo con varios campos y devuelve lo escrito en cada uno, o
/// null si se canceló. Los campos numéricos se validan antes de cerrar.
Future<List<String>?> showFieldsDialog(
  BuildContext context, {
  required String title,
  required List<DialogField> fields,
  String confirm = 'Guardar',
  String? hint,
  String? Function(List<String> values)? validate,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _FieldsDialog(
      title: title,
      fields: fields,
      confirm: confirm,
      hint: hint,
      validate: validate,
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context,
  String message, {
  String confirm = 'Aceptar',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancelar'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        TextButton(
          child: Text(confirm),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _FieldsDialog extends StatefulWidget {
  final String title;
  final List<DialogField> fields;
  final String confirm;

  /// Texto de ayuda arriba de los campos.
  final String? hint;

  /// Validación extra; devuelve el mensaje de error, o null si está bien.
  final String? Function(List<String> values)? validate;

  const _FieldsDialog({
    required this.title,
    required this.fields,
    required this.confirm,
    this.hint,
    this.validate,
  });

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final List<TextEditingController> _controllers;
  late final List<String?> _choices;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final field in widget.fields)
        TextEditingController(text: field.initial),
    ];
    _choices = [
      for (final field in widget.fields)
        field.options == null
            ? null
            : (field.options!.contains(field.initial)
                  ? field.initial
                  : field.options!.first),
    ];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(int i) {
    final field = widget.fields[i];
    if (field.day) return _dayField(i);
    if (field.options != null && field.letters) return _lettersField(i);
    if (field.options != null) {
      return DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _choices[i],
        decoration: InputDecoration(labelText: field.label),
        items: [
          for (final option in field.options!)
            DropdownMenuItem(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) => _choices[i] = value,
      );
    }
    return TextField(
      controller: _controllers[i],
      keyboardType: field.number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: field.label),
    );
  }

  Widget _dayField(int i) {
    final field = widget.fields[i];
    final day = parseAmount(_controllers[i].text)?.round() ?? 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showDayPicker(
            context,
            title: field.label,
            initial: day,
            month: field.month,
            maxDay: field.maxDay,
          );
          if (picked != null) {
            setState(() => _controllers[i].text = '$picked');
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: field.label,
            suffixIcon: const Icon(Icons.calendar_month_outlined),
          ),
          child: Text('Día $day', style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }

  Widget _lettersField(int i) {
    final field = widget.fields[i];
    final options = field.options!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final option in options)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: option,
                      child: ChoiceChip(
                        label: Text(option.characters.first),
                        showCheckmark: false,
                        padding: EdgeInsets.zero,
                        labelPadding: EdgeInsets.zero,
                        selected: _choices[i] == option,
                        onSelected: (_) => setState(() => _choices[i] = option),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_choices[i] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _choices[i]!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  void _submit() {
    for (var i = 0; i < widget.fields.length; i++) {
      final field = widget.fields[i];
      if (field.number && parseAmount(_controllers[i].text) == null) {
        setState(() => _error = 'Escribe un número válido en "${field.label}"');
        return;
      }
    }
    final values = [
      for (var i = 0; i < widget.fields.length; i++)
        _choices[i] ?? _controllers[i].text.trim(),
    ];
    final error = widget.validate?.call(values);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(values);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.hint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(widget.hint!),
              ),
            for (var i = 0; i < widget.fields.length; i++) _field(i),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancelar'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(onPressed: _submit, child: Text(widget.confirm)),
      ],
    );
  }
}
