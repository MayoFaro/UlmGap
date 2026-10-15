import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/cash.dart';
import 'cash_movement.dart';
import 'finance_api.dart' show financeFailureFrom;

/// Caisse (spec §11) : lecture réservée aux instructeurs et aux admins,
/// écritures par les Functions.
abstract class CashApi {
  Stream<Cashbox> watchCashbox();

  /// Toutes les opérations (quelques centaines par an) : filtres et tri
  /// dans l'app (cashPeriod), sans index.
  Stream<List<CashMovement>> watchMovements();

  /// [amount] positif pour une entrée ou une sortie, signé pour un écart.
  /// [liters] : litres achetés (Achat carburant, obligatoires sauf
  /// [outsideTank], « Hors cuve » : achat sans entrée en cuve).
  Future<void> add(
      {required CashKind kind,
      required int amount,
      required DateTime date,
      String? note,
      int? liters,
      bool outsideTank = false});

  /// [amount] : montant juste (positif, signé pour un écart ; 0 annule).
  Future<void> correct(String movementId, {required int amount, String? note});

  Future<void> closeMigration();
}

class FirebaseCashApi implements CashApi {
  FirebaseCashApi({FirebaseFirestore? db, FirebaseFunctions? fn})
      : _db = db ?? FirebaseFirestore.instance,
        _fn = fn ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  Future<Object?> _call(String name, Map<String, dynamic> payload) async {
    try {
      return (await _fn.httpsCallable(name).call(payload)).data;
    } on FirebaseFunctionsException catch (e) {
      throw financeFailureFrom(e.code, e.message ?? e.code, e.details) ?? e;
    }
  }

  @override
  Stream<Cashbox> watchCashbox() =>
      _db.collection('cashbox').doc('main').snapshots().map((s) => Cashbox.fromMap(s.data()));

  @override
  Stream<List<CashMovement>> watchMovements() => _db
      .collection('cashMovements')
      .snapshots()
      .map((q) => q.docs.map((d) => CashMovement.fromMap(d.id, d.data())).toList());

  @override
  Future<void> add(
          {required CashKind kind,
          required int amount,
          required DateTime date,
          String? note,
          int? liters,
          bool outsideTank = false}) =>
      _call('addCashMovement', {
        'kind': kind.code,
        'amount': amount,
        'date': cashDayCode(date),
        if (liters != null) 'liters': liters,
        if (outsideTank) 'outsideTank': true,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  @override
  Future<void> correct(String movementId, {required int amount, String? note}) =>
      _call('correctCashMovement', {
        'movementId': movementId,
        'amount': amount,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  @override
  Future<void> closeMigration() => _call('closeMigration', {});
}
