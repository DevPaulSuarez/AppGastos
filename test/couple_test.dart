import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:primera_app_curso/couple/couple.dart';
import 'package:primera_app_curso/finance_repository.dart';

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
      'day': 5,
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

  test(
    'lo ya cobrado este mes se ve en la pareja sin contarlo dos veces',
    () async {
      final today = DateTime(2026, 10, 21);
      final mine = MemoryStore();
      await mine.set('recurring', 'r1', {
        'type': 'income',
        'person': 0,
        'description': 'Sueldo',
        'amount': 500,
        'day': 5,
        'frequency': 'weekly',
        'lastApplied': '2026-10-16',
      });
      for (final day in [9, 16]) {
        await mine.set('incomes', 'rec_r1_2026-10-$day', {
          'person': 0,
          'description': 'Sueldo',
          'amount': 500,
          'day': day,
          'month': 10,
          'year': 2026,
        });
      }
      final ours = MemoryStore();
      final couple = FinanceRepository(ours);
      await ours.set('settings', 'people', {
        'names': ['Ana', 'Paul'],
        'solo': false,
      });
      await couple.setStartingMoney([1500, 2000], today: today);

      // Paul se unió (persona 1) y trae su sueldo.
      expect(await couple.copyRecurringFrom(mine, 1, today: today), (
        items: 1,
        payments: 2,
      ));
      final incomes = ours.data['incomes']!.values.toList();
      expect(incomes.map((i) => i['day']), unorderedEquals([9, 16]));
      expect(incomes.every((i) => i['person'] == 1), isTrue);
      // Los 1000 ya estaban en los 2000 que dijo tener.
      expect(await couple.freeMoneyToday(today: today), 3500);

      // Con el botón de Ajustes no se repite.
      expect(
        await couple.copyRecurringFrom(
          mine,
          1,
          skipExisting: true,
          today: today,
        ),
        (items: 0, payments: 0),
      );
      expect(ours.data['incomes']!.length, 2);
      expect(await couple.freeMoneyToday(today: today), 3500);
    },
  );

  test('el botón trae los pagos que faltan de un sueldo ya copiado', () async {
    // Lo que pasó de verdad: al crear la pareja se copió el sueldo pero no
    // los viernes ya cobrados.
    final today = DateTime(2026, 10, 21);
    final mine = MemoryStore();
    final salary = {
      'type': 'income',
      'person': 0,
      'description': 'Sueldo',
      'amount': 500,
      'day': 5,
      'frequency': 'weekly',
      'lastApplied': '2026-10-16',
    };
    await mine.set('recurring', 'r1', salary);
    await mine.set('incomes', 'rec_r1_2026-10-9', {
      'person': 0,
      'description': 'Sueldo',
      'amount': 500,
      'day': 9,
      'month': 10,
      'year': 2026,
    });
    final ours = MemoryStore();
    final couple = FinanceRepository(ours);
    await ours.set('settings', 'people', {
      'names': ['Paul', 'Marisol'],
      'solo': false,
    });
    await ours.set('recurring', 'c1', salary);
    await couple.setStartingMoney([2000, 0], today: today);

    expect(
      await couple.copyRecurringFrom(mine, 0, skipExisting: true, today: today),
      (items: 0, payments: 1),
    );
    expect(ours.data['incomes']!.keys, ['rec_c1_2026-10-9']);
    expect(ours.data['recurring']!.length, 1);
    expect(await couple.freeMoneyToday(today: today), 2000);
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
