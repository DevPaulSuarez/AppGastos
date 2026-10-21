import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:primera_app_curso/data/store.dart';

/// Invitación para formar pareja: el código que una persona comparte y la
/// solicitud de quien lo escribe. Se guarda en invitations/{código}.
class Invitation {
  final String code;
  final String from;
  final String fromName;

  /// pending: nadie la usó · requested: alguien pidió unirse · accepted ·
  /// rejected · cancelled.
  final String status;
  final String? joinerUid;
  final String? joinerName;

  /// Con cuánto dinero entra quien se une.
  final double joinerMoney;

  /// Si quien se une quiere traer sus sueldos, pagos fijos y categorías.
  final bool joinerCopies;
  final bool joinerCopied;
  final String? coupleId;
  final DateTime expiresAt;

  const Invitation({
    required this.code,
    required this.from,
    required this.fromName,
    required this.status,
    required this.expiresAt,
    this.joinerUid,
    this.joinerName,
    this.joinerMoney = 0,
    this.joinerCopies = false,
    this.joinerCopied = false,
    this.coupleId,
  });

  bool get expired => DateTime.now().isAfter(expiresAt);

  factory Invitation.fromMap(String code, Map<String, dynamic> map) =>
      Invitation(
        code: code,
        from: map['from'] as String,
        fromName: (map['fromName'] as String?) ?? '',
        status: (map['status'] as String?) ?? 'pending',
        expiresAt: (map['expiresAt'] as Timestamp).toDate(),
        joinerUid: map['joinerUid'] as String?,
        joinerName: map['joinerName'] as String?,
        joinerMoney: ((map['joinerMoney'] as num?) ?? 0).toDouble(),
        joinerCopies: (map['joinerCopies'] as bool?) ?? false,
        joinerCopied: (map['joinerCopied'] as bool?) ?? false,
        coupleId: map['coupleId'] as String?,
      );
}

/// Pareja: los dos miembros (el 0 es quien invitó) y, si se separaron,
/// cuándo y con cuánto dinero se quedó cada uno. Se guarda en
/// couples/{id}; sus gastos, ingresos, etc. van debajo, como en una cuenta
/// personal.
class Couple {
  final String id;
  final List<String> members;
  final List<String> names;
  final DateTime createdAt;
  final DateTime? endedAt;
  final String? endedBy;

  /// Con cuánto se quedó cada uno al separarse (por id de la persona).
  final Map<String, double> keep;

  const Couple({
    required this.id,
    required this.members,
    required this.names,
    required this.createdAt,
    this.endedAt,
    this.endedBy,
    this.keep = const {},
  });

  bool get active => endedAt == null;

  /// Nombre de la otra persona.
  String partnerName(String uid) {
    final i = members.indexOf(uid);
    return names.length == 2 && i >= 0 ? names[1 - i] : 'tu pareja';
  }

  factory Couple.fromMap(String id, Map<String, dynamic> map) => Couple(
    id: id,
    members: (map['members'] as List).cast<String>(),
    names: ((map['names'] as List?) ?? const []).cast<String>(),
    createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    endedAt: (map['endedAt'] as Timestamp?)?.toDate(),
    endedBy: map['endedBy'] as String?,
    keep: {
      for (final e in ((map['keep'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
  );
}

/// Letras y números que no se confunden al leerlos o dictarlos (sin 0/O,
/// 1/I/L).
const _codeChars = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

/// Código nuevo, por ejemplo "GASTO-7K3P".
String newInvitationCode([Random? random]) {
  final r = random ?? Random.secure();
  final part = List.generate(
    4,
    (_) => _codeChars[r.nextInt(_codeChars.length)],
  );
  return 'GASTO-${part.join()}';
}

/// Normaliza lo que escribe la persona: "gasto 7k3p" → "GASTO-7K3P".
String normalizeInvitationCode(String text) {
  final clean = text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final body = clean.startsWith('GASTO') ? clean.substring(5) : clean;
  return 'GASTO-$body';
}

/// Copia a la cuenta de pareja los sueldos, pagos fijos y propinas de una
/// cuenta personal, a nombre de [person] (0 o 1), y suma sus categorías
/// propias y ocultas. Lo ya cobrado o pagado este mes no se vuelve a anotar:
/// ese dinero ya está en lo que cada uno dijo que traía.
Future<void> copyPersonalSetup(Store personal, Store couple, int person) async {
  for (final doc in await personal.watch('recurring').first) {
    await couple.add('recurring', {...doc.data, 'person': person});
  }
  final mine = await personal.get('settings', 'categories');
  if (mine == null) return;
  final ours = await couple.get('settings', 'categories');
  List<dynamic> list(Map<String, dynamic>? map, String key) =>
      (map?[key] as List?) ?? const [];
  final custom = [...list(ours?.data, 'custom')];
  final names = custom.map((c) => (c as Map)['name']).toSet();
  for (final c in list(mine.data, 'custom')) {
    if (!names.contains((c as Map)['name'])) custom.add(c);
  }
  final hidden = {...list(ours?.data, 'hidden'), ...list(mine.data, 'hidden')};
  await couple.set('settings', 'categories', {
    'custom': custom,
    'hidden': hidden.toList(),
  });
}

/// Invitaciones y parejas en la nube, vistas por la persona [uid].
class CoupleRepository {
  final FirebaseFirestore db;
  final String uid;

  CoupleRepository(this.uid, {FirebaseFirestore? db})
    : db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _invitations =>
      db.collection('invitations');
  CollectionReference<Map<String, dynamic>> get _couples =>
      db.collection('couples');

  /// Todas las parejas en las que estuvo o está (la activa y las anteriores).
  Stream<List<Couple>> watchMyCouples() => _couples
      .where('members', arrayContains: uid)
      .snapshots()
      .map((s) => [for (final d in s.docs) Couple.fromMap(d.id, d.data())]);

  /// Mi invitación abierta (esperando o con alguien que pidió unirse).
  Stream<Invitation?> watchMyInvitation() =>
      _invitations.where('from', isEqualTo: uid).snapshots().map((s) {
        final open =
            [for (final d in s.docs) Invitation.fromMap(d.id, d.data())].where(
              (i) =>
                  (i.status == 'pending' && !i.expired) ||
                  i.status == 'requested',
            );
        return open.isEmpty ? null : open.first;
      });

  /// Mi solicitud para unirme a alguien (la última).
  Stream<Invitation?> watchMyJoinRequest() =>
      _invitations.where('joinerUid', isEqualTo: uid).snapshots().map((s) {
        final all = [for (final d in s.docs) Invitation.fromMap(d.id, d.data())]
          ..sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
        return all.isEmpty ? null : all.first;
      });

  /// Crea un código nuevo (vale 24 horas) y anula los anteriores.
  Future<Invitation> createInvitation(String fromName) async {
    for (final d
        in (await _invitations.where('from', isEqualTo: uid).get()).docs) {
      if (d.data()['status'] == 'pending') {
        await d.reference.update({'status': 'cancelled'});
      }
    }
    while (true) {
      final code = newInvitationCode();
      final ref = _invitations.doc(code);
      final expiresAt = DateTime.now().add(const Duration(hours: 24));
      try {
        // Solo se crea si el código no existe (las reglas no dejan
        // sobrescribir uno ajeno).
        await db.runTransaction((tx) async {
          if ((await tx.get(ref)).exists) throw StateError('repetido');
          tx.set(ref, {
            'from': uid,
            'fromName': fromName,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt': Timestamp.fromDate(expiresAt),
          });
        });
        return Invitation(
          code: code,
          from: uid,
          fromName: fromName,
          status: 'pending',
          expiresAt: expiresAt,
        );
      } on StateError {
        continue; // Código repetido: se prueba otro.
      }
    }
  }

  Future<void> cancelInvitation(String code) =>
      _invitations.doc(code).update({'status': 'cancelled'});

  /// Pide unirse con un código. Devuelve un mensaje si no se puede, o null.
  Future<String?> requestJoin(
    String code, {
    required String joinerName,
    required double money,
    required bool copySetup,
  }) async {
    final ref = _invitations.doc(normalizeInvitationCode(code));
    final snap = await ref.get();
    final data = snap.data();
    if (data == null)
      return 'Ese código no existe. Revisa que esté bien escrito.';
    final inv = Invitation.fromMap(snap.id, data);
    if (inv.from == uid) return 'Ese código es tuyo: envíaselo a tu pareja.';
    if (inv.status != 'pending') return 'Ese código ya se usó o se anuló.';
    if (inv.expired) return 'Ese código venció. Pide uno nuevo.';
    await ref.update({
      'status': 'requested',
      'joinerUid': uid,
      'joinerName': joinerName,
      'joinerMoney': money,
      'joinerCopies': copySetup,
    });
    return null;
  }

  Future<void> rejectRequest(Invitation inv) =>
      _invitations.doc(inv.code).update({'status': 'rejected'});

  /// Acepta la solicitud: crea la cuenta de pareja con los nombres y el
  /// dinero de cada uno. [inviterMoney] es con cuánto entra quien invitó.
  /// Si [copyMine], trae los sueldos, pagos fijos y categorías de
  /// [personal]. Devuelve el id de la pareja.
  Future<String> acceptRequest(
    Invitation inv, {
    required String inviterName,
    required double inviterMoney,
    required Map<String, dynamic>? currency,
    required bool copyMine,
    required Store personal,
    required Future<void> Function(Store couple, List<double> money)
    setStartingMoney,
  }) async {
    final ref = _couples.doc();
    await ref.set({
      'members': [uid, inv.joinerUid],
      'names': [inviterName, inv.joinerName ?? 'Pareja'],
      'createdAt': FieldValue.serverTimestamp(),
      'keep': <String, double>{},
    });
    final couple = FirestoreStore.couple(ref.id);
    await couple.set('settings', 'people', {
      'names': [inviterName, inv.joinerName ?? 'Pareja'],
      'solo': false,
      'setupPending': false,
    });
    if (currency != null) await couple.set('settings', 'currency', currency);
    await setStartingMoney(couple, [inviterMoney, inv.joinerMoney]);
    if (copyMine) await copyPersonalSetup(personal, couple, 0);
    await _invitations.doc(inv.code).update({
      'status': 'accepted',
      'coupleId': ref.id,
    });
    return ref.id;
  }

  /// Quien se unió trae sus sueldos, pagos fijos y categorías, si lo pidió.
  Future<void> copyJoinerSetup(Invitation inv, Store personal) async {
    final id = inv.coupleId;
    if (id == null || !inv.joinerCopies || inv.joinerCopied) return;
    await _invitations.doc(inv.code).update({'joinerCopied': true});
    await copyPersonalSetup(personal, FirestoreStore.couple(id), 1);
  }

  /// Sale de la pareja quedándose con [amount]. La cuenta de pareja queda
  /// guardada solo para ver.
  Future<void> leave(Couple couple, double amount) =>
      _couples.doc(couple.id).update({
        // Hora del teléfono: con la del servidor, la pantalla tardaría en
        // enterarse de que la pareja terminó.
        'endedAt': Timestamp.now(),
        'endedBy': uid,
        'keep.$uid': amount,
      });

  /// La otra persona ya salió: anota con cuánto se queda esta.
  Future<void> setKeep(Couple couple, double amount) =>
      _couples.doc(couple.id).update({'keep.$uid': amount});
}
