import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:primera_app_curso/couple/couple.dart';

import 'memory_store.dart';

void main() {
  test('códigos fáciles de leer y de escribir', () {
    final code = newInvitationCode(Random(1));
    expect(code, matches(RegExp(r'^GASTO-[2-9A-HJKMNP-Z]{4}$')));
    // Lo que escriba la persona se entiende igual.
    expect(normalizeInvitationCode(' gasto 7k3p '), 'GASTO-7K3P');
    expect(normalizeInvitationCode('7K3P'), 'GASTO-7K3P');
    expect(normalizeInvitationCode('GASTO-7K3P'), 'GASTO-7K3P');
  });

  test('traer sueldos y pagos fijos a la cuenta de pareja', () async {
    final mine = MemoryStore();
    await mine.set('recurring', 'r1', {
      'type': 'income',
      'person': 0,
      'description': 'Sueldo',
      'amount': 500,
    });
    await mine.set('settings', 'categories', {
      'custom': [
        {'name': 'Gimnasio', 'icon': 'otros', 'color': 1},
      ],
      'hidden': ['Alcohol'],
    });
    final ours = MemoryStore();
    await ours.set('settings', 'categories', {
      'custom': [
        {'name': 'Mascota', 'icon': 'mascotas', 'color': 2},
      ],
      'hidden': [],
    });

    // Quien se unió es la persona 1 de la pareja.
    await copyPersonalSetup(mine, ours, 1);
    final copied = ours.data['recurring']!.values.single;
    expect(copied['description'], 'Sueldo');
    expect(copied['person'], 1);
    final categories = ours.data['settings']!['categories']!;
    expect(
      (categories['custom'] as List).map((c) => (c as Map)['name']),
      unorderedEquals(['Mascota', 'Gimnasio']),
    );
    expect(categories['hidden'], ['Alcohol']);
  });

  test('nombre de la pareja', () {
    final couple = Couple(
      id: 'c',
      members: const ['paul', 'ana'],
      names: const ['Paul', 'Ana'],
      createdAt: DateTime(2026, 10, 21),
    );
    expect(couple.active, isTrue);
    expect(couple.partnerName('paul'), 'Ana');
    expect(couple.partnerName('ana'), 'Paul');
  });
}
