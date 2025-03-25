//import 'dart:math';
import 'package:flutter/material.dart';
import 'package:charts_flutter/flutter.dart';

class PieGraphwidget extends StatefulWidget {
  final List<double> data;
  const PieGraphwidget({Key? key, required this.data}) : super(key: key);

  @override
  _PieGraphwidgetState createState() => _PieGraphwidgetState();
}

class _PieGraphwidgetState extends State<PieGraphwidget> {
  @override
  Widget build(BuildContext context) {
    final series = [
      Series<double, num>(
        id: 'Gasto',
        colorFn: (_, __) => MaterialPalette.green.shadeDefault.lighter,
        domainFn: (value, index) => index ?? 0,
        measureFn: (value, _) => value,
        data: widget.data,
        strokeWidthPxFn: (_, __) => 4,
      )
    ];

    return PieChart(series);
  }
}

class LinesGraphWidget extends StatefulWidget {
  final List<double> data;

  const LinesGraphWidget({Key? key, required this.data}) : super(key: key);

  @override
  _LinesGraphWidgetState createState() => _LinesGraphWidgetState();
}

class _LinesGraphWidgetState extends State<LinesGraphWidget> {
  void _onSelectionChanged(SelectionModel model) {
    final selectedDatum = model.selectedDatum;

    var time;
    final measures = <String, double>{};

    // We get the model that updated with a list of [SeriesDatum] which is
    // simply a pair of series & datum.
    //
    // Walk the selection updating the measures map, storing off the sales and
    // series name for each selection point.
    if (selectedDatum.isNotEmpty) {
      time = selectedDatum.first.datum;
      for (var datumPair in selectedDatum) {
        measures[datumPair.series.displayName ?? ''] = datumPair.datum;
      }
    }

    print(time);
    print(measures);
  }

  @override
  Widget build(BuildContext context) {
    final series = [
      Series<double, int>(
        id: 'Gasto',
        colorFn: (_, __) => MaterialPalette.green.shadeDefault,
        domainFn: (value, index) => index ?? 0,
        measureFn: (value, _) => value,
        data: widget.data,
        strokeWidthPxFn: (_, __) => 4,
      )
    ];

    return LineChart(
      series,
      animate: false,
      selectionModels: [
        SelectionModelConfig(
          type: SelectionModelType.info,
          changedListener: _onSelectionChanged,
        )
      ],
      domainAxis: NumericAxisSpec(
          tickProviderSpec: StaticNumericTickProviderSpec([
        const TickSpec(0, label: '01'),
        const TickSpec(4, label: '05'),
        const TickSpec(9, label: '10'),
        const TickSpec(14, label: '15'),
        const TickSpec(19, label: '20'),
        const TickSpec(24, label: '25'),
        const TickSpec(29, label: '30'),
      ])),
      primaryMeasureAxis: const NumericAxisSpec(
        tickProviderSpec: BasicNumericTickProviderSpec(
          desiredTickCount: 4,
        ),
      ),
    );
  }
}
