import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:primera_app_curso/couple/couple.dart';
import 'package:primera_app_curso/data/store.dart';

/// Qué cuenta está activa para la persona que inició sesión: su cuenta
/// personal, o la de pareja mientras están juntos (la personal queda
/// congelada y solo se puede ver). También sigue sus invitaciones.
class SpaceState extends ChangeNotifier {
  String? _uid;
  CoupleRepository? _repo;
  final _subs = <StreamSubscription>[];

  List<Couple> _couples = const [];
  Invitation? _myInvitation;
  Invitation? _myJoinRequest;
  bool _loaded = false;
  bool _copying = false;

  String? get uid => _uid;
  CoupleRepository? get repo => _repo;

  /// Ya se sabe si hay pareja (para no mostrar la cuenta equivocada un
  /// instante al abrir la app).
  bool get loaded => _loaded;

  Couple? get activeCouple => _couples.where((c) => c.active).firstOrNull;

  /// Parejas anteriores, de la más reciente a la más antigua.
  List<Couple> get pastCouples =>
      _couples.where((c) => !c.active).toList()
        ..sort((a, b) => b.endedAt!.compareTo(a.endedAt!));

  /// La otra persona salió de la pareja y esta todavía no dijo con cuánto
  /// dinero se queda.
  Couple? get pendingKeep => _couples
      .where(
        (c) => !c.active && c.endedBy != _uid && !c.keep.containsKey(_uid),
      )
      .firstOrNull;

  /// Mi código para invitar (esperando, o con alguien que pidió unirse).
  Invitation? get myInvitation => _myInvitation;

  /// Mi pedido para unirme a otra persona.
  Invitation? get myJoinRequest => _myJoinRequest;

  /// Identifica la cuenta activa: cambia cuando se forma o termina la
  /// pareja, y así la app se vuelve a armar con los datos correctos.
  String get spaceKey => activeCouple?.id ?? 'personal';

  /// Datos de la cuenta activa.
  Store activeStore() {
    final couple = activeCouple;
    return couple != null
        ? FirestoreStore.couple(couple.id)
        : FirestoreStore(_uid!);
  }

  void setUser(String? uid) {
    if (uid == _uid) return;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _uid = uid;
    _couples = const [];
    _myInvitation = null;
    _myJoinRequest = null;
    _loaded = uid == null;
    _repo = uid == null ? null : CoupleRepository(uid);
    if (uid != null) {
      final repo = _repo!;
      _subs.add(
        repo.watchMyCouples().listen((couples) {
          _couples = couples;
          _loaded = true;
          _copyJoinerSetupIfNeeded();
          notifyListeners();
        }, onError: (Object e) => _failed(e)),
      );
      _subs.add(
        repo.watchMyInvitation().listen((inv) {
          _myInvitation = inv;
          notifyListeners();
        }, onError: (Object e) => debugPrint('Invitaciones: $e')),
      );
      _subs.add(
        repo.watchMyJoinRequest().listen((inv) {
          _myJoinRequest = inv;
          _copyJoinerSetupIfNeeded();
          notifyListeners();
        }, onError: (Object e) => debugPrint('Solicitud: $e')),
      );
    }
    // Se llama mientras se arma la pantalla: el aviso va después.
    scheduleMicrotask(notifyListeners);
  }

  void _failed(Object e) {
    // Sin conexión o sin permiso: se sigue con la cuenta personal.
    debugPrint('Parejas: $e');
    _loaded = true;
    notifyListeners();
  }

  /// Quien se unió y pidió traer sus sueldos y pagos fijos: se copian una
  /// sola vez, cuando ya existe la cuenta de pareja.
  Future<void> _copyJoinerSetupIfNeeded() async {
    final inv = _myJoinRequest;
    final couple = activeCouple;
    if (_copying ||
        inv == null ||
        couple == null ||
        inv.coupleId != couple.id ||
        !inv.joinerCopies ||
        inv.joinerCopied) {
      return;
    }
    _copying = true;
    try {
      await _repo!.copyJoinerSetup(inv, FirestoreStore(_uid!));
    } catch (e) {
      debugPrint('No se pudo copiar la configuración: $e');
    } finally {
      _copying = false;
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
