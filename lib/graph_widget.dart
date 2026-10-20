import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:primera_app_curso/currency.dart';
import 'package:primera_app_curso/categories.dart';

/// Dona con el gasto por categoría. El total va en el centro y cada porción
/// muestra su porcentaje; las categorías pequeñas se agrupan en "Otros".
class PieGraphwidget extends StatefulWidget {
  final Map<String, double> data;
  const PieGraphwidget({super.key, required this.data});

  @override
  State<PieGraphwidget> createState() => _PieGraphwidgetState();
}

class _PieGraphwidgetState extends State<PieGraphwidget> {
  int? _touched;

  /// Máximo 5 porciones; el resto se junta en una sola.
  List<MapEntry<String, double>> get _slices {
    final sorted = widget.data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.length <= 5) return sorted;
    final rest = sorted.skip(4).fold(0.0, (a, e) => a + e.value);
    return [...sorted.take(4), MapEntry('Resto', rest)];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slices = _slices;
    final total = slices.fold(0.0, (a, e) => a + e.value);
    // Al tocar fuera de una porción (por ejemplo el centro) llega -1.
    final index = _touched;
    final touched = index != null && index >= 0 && index < slices.length
        ? slices[index]
        : null;

    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sectionsSpace: 3,
            centerSpaceRadius: 62,
            startDegreeOffset: -90,
            pieTouchData: PieTouchData(
              touchCallback: (event, response) {
                setState(() {
                  _touched = event.isInterestedForInteractions
                      ? response?.touchedSection?.touchedSectionIndex
                      : null;
                });
              },
            ),
            sections: [
              for (var i = 0; i < slices.length; i++)
                PieChartSectionData(
                  value: slices[i].value,
                  color: categoryColor(slices[i].key),
                  radius: _touched == i ? 40 : 32,
                  title: slices[i].value / total >= 0.06
                      ? '${(slices[i].value / total * 100).round()}%'
                      : '',
                  titleStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              touched?.key ?? 'Total',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            Text(
              money(touched?.value ?? total),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}

/// Barras con el gasto de cada día del mes. Al tocar una barra se ve el monto.
class LinesGraphWidget extends StatelessWidget {
  final List<double> data;

  /// Lo separado como ahorro cada día; se dibuja encima del gasto, en azul.
  final List<double>? saved;

  /// Índice del día a resaltar (hoy), o null.
  final int? highlight;

  /// Se llama con el índice del día (0 = día 1) al tocar su columna.
  final ValueChanged<int>? onDayTap;

  const LinesGraphWidget(
      {super.key,
      required this.data,
      this.saved,
      this.highlight,
      this.onDayTap});

  double _savedAt(int i) => saved == null ? 0 : saved![i];

  static String _compact(double value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k';
    }
    return value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totals = [for (var i = 0; i < data.length; i++) data[i] + _savedAt(i)];
    final maxValue = totals.fold(0.0, (a, b) => a > b ? a : b);
    final maxY = maxValue == 0 ? 10.0 : maxValue * 1.15;

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceBetween,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                if (value == meta.max) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(_compact(value),
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final day = value.toInt() + 1;
                if (day != 1 && day % 5 != 0) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text('$day',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          // Se puede tocar toda la columna del día, no solo la barra.
          allowTouchBarBackDraw: true,
          touchCallback: (event, response) {
            final spot = response?.spot;
            if (event is FlTapUpEvent && spot != null) {
              onDayTap?.call(spot.touchedBarGroupIndex);
            }
          },
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              'Día ${group.x + 1}\n'
              '${_savedAt(group.x) > 0 ? 'Gasto ${money(data[group.x])}\nAhorro ${money(_savedAt(group.x))}' : money(rod.toY)}',
              TextStyle(
                  color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: totals[i],
                  width: 6,
                  borderRadius: BorderRadius.circular(3),
                  rodStackItems: _savedAt(i) > 0
                      ? [
                          BarChartRodStackItem(0, data[i],
                              i == highlight ? scheme.primary : scheme.primary.withValues(alpha: 0.55)),
                          BarChartRodStackItem(
                              data[i], totals[i], const Color(0xFF2563EB)),
                        ]
                      : const [],
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: Colors.transparent,
                  ),
                  color: i == highlight
                      ? scheme.primary
                      : scheme.primary.withValues(alpha: 0.55),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class TrendMonth {
  final String label;
  final double incomes;
  final double expenses;

  const TrendMonth(this.label, this.incomes, this.expenses);
}

/// Ingresos frente a gastos de varios meses, en barras lado a lado.
class TrendChart extends StatelessWidget {
  final List<TrendMonth> months;

  const TrendChart({super.key, required this.months});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxValue = months.fold(
        0.0,
        (a, m) => [a, m.incomes, m.expenses]
            .reduce((x, y) => x > y ? x : y));

    return BarChart(
      BarChartData(
        maxY: maxValue == 0 ? 10 : maxValue * 1.15,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                if (value == meta.max) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(LinesGraphWidget._compact(value),
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(months[value.toInt()].label,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ),
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
              '${rodIndex == 0 ? 'Ingresos' : 'Gastos'}\n${money(rod.toY)}',
              TextStyle(
                  color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < months.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 3,
              barRods: [
                BarChartRodData(
                  toY: months[i].incomes,
                  width: 10,
                  borderRadius: BorderRadius.circular(3),
                  color: const Color(0xFF16A34A),
                ),
                BarChartRodData(
                  toY: months[i].expenses,
                  width: 10,
                  borderRadius: BorderRadius.circular(3),
                  color: const Color(0xFFDC2626),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
