import 'package:flutter/material.dart';
import 'package:primera_app_curso/utils.dart';

const _weekdayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// Mini calendario para elegir un día.
///
/// Sin [month]: días del 1 al 31, para pagos que se repiten cada mes (el
/// día de la semana cambia de un mes a otro, así que no se muestra).
/// Con [month]: el calendario real de ese mes, con los días de la semana;
/// [maxDay] desactiva los días posteriores (ej. un pago no puede ser futuro).
Future<int?> showDayPicker(
  BuildContext context, {
  required String title,
  required int initial,
  DateTime? month,
  int? maxDay,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 320,
        child: DayGrid(
          selected: initial,
          month: month,
          maxDay: maxDay,
          onSelected: (day) => Navigator.of(context).pop(day),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );
}

class DayGrid extends StatelessWidget {
  final int selected;
  final DateTime? month;
  final int? maxDay;
  final ValueChanged<int> onSelected;

  const DayGrid({
    Key? key,
    required this.selected,
    required this.onSelected,
    this.month,
    this.maxDay,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final month = this.month;
    final days = month == null ? 31 : daysInMonth(month.month, month.year);
    // Casillas vacías antes del día 1 para que caiga en su día de la semana.
    final offset = month == null
        ? 0
        : DateTime(month.year, month.month, 1).weekday - 1;
    final now = DateTime.now();
    final isToday = (int day) =>
        month != null &&
        month.year == now.year &&
        month.month == now.month &&
        day == now.day;

    Widget cell(int day) {
      final enabled = maxDay == null || day <= maxDay!;
      final isSelected = day == selected;
      final weekend =
          month != null &&
          DateTime(month.year, month.month, day).weekday >= DateTime.saturday;
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: isSelected ? scheme.primary : Colors.transparent,
          shape: CircleBorder(
            side: isToday(day) && !isSelected
                ? BorderSide(color: scheme.primary)
                : BorderSide.none,
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? () => onSelected(day) : null,
            child: Center(
              child: Text(
                '$day',
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  color: isSelected
                      ? scheme.onPrimary
                      : !enabled
                      ? scheme.onSurface.withValues(alpha: 0.3)
                      : weekend
                      ? scheme.error
                      : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (month != null) ...[
          Text(
            '${monthNames[month.month - 1][0]}'
            '${monthNames[month.month - 1].substring(1).toLowerCase()} '
            '${month.year}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final letter in _weekdayLetters)
                Expanded(
                  child: Center(
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < offset; i++) const SizedBox(),
            for (var day = 1; day <= days; day++) cell(day),
          ],
        ),
        if (month == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Se repite cada mes. Si un mes tiene menos días, se usa el '
              'último.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
