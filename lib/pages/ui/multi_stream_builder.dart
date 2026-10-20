import 'dart:async';

import 'package:flutter/material.dart';

/// Escucha varios streams a la vez y construye la pantalla cuando todos
/// tienen datos. Se suscribe una sola vez: para cambiar los streams (por
/// ejemplo al cambiar de mes) hay que darle una [Key] distinta.
class MultiStreamBuilder extends StatefulWidget {
  final List<Stream<Object?>> streams;
  final Widget Function(BuildContext context, List<Object?> values) builder;

  /// Lo que se muestra mientras cargan los datos.
  final Widget placeholder;

  const MultiStreamBuilder(
      {super.key,
      required this.streams,
      required this.builder,
      this.placeholder = const Center(child: CircularProgressIndicator())});

  @override
  State<MultiStreamBuilder> createState() => _MultiStreamBuilderState();
}

class _MultiStreamBuilderState extends State<MultiStreamBuilder> {
  late final List<Object?> _values;
  late final List<bool> _received;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _values = List.filled(widget.streams.length, null);
    _received = List.filled(widget.streams.length, false);
    for (var i = 0; i < widget.streams.length; i++) {
      _subscriptions.add(widget.streams[i].listen(
        (value) => setState(() {
          _values[i] = value;
          _received[i] = true;
        }),
        onError: (Object error) {
          debugPrint('Error al leer datos: $error');
          setState(() => _error = error);
        },
      ));
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text('No se pudieron cargar los datos:\n$_error',
              textAlign: TextAlign.center),
        ),
      );
    }
    if (!_received.every((received) => received)) {
      return widget.placeholder;
    }
    return widget.builder(context, _values);
  }
}
