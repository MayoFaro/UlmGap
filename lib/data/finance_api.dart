import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/pricing.dart';
import 'account_movement.dart';
import 'app_user.dart';
import 'flight.dart';
import 'flight_api.dart' show FlightFailure, flightFailureFrom;
import 'pricing_settings.dart';

/// Codes d'erreur des callables qui signifient un refus certain : l'opération
/// n'a pas eu lieu, le message du serveur peut être affiché tel quel.
const _refusalCodes = {
  'invalid-argument', 'failed-precondition', 'permission-denied', 'not-found',
  'unauthenticated', 'already-exists', 'out-of-range',
};

/// FlightFailure pour un refus certain du serveur ; null si l'issue est
/// incertaine (réseau, délai, erreur interne) : l'opération a pu aboutir, et
/// l'appelant laisse alors passer l'erreur d'origine (pas de double
/// versement sur un « Réessayez »).
FlightFailure? financeFailureFrom(String code, String message, Object? details) =>
    _refusalCodes.contains(code) ? flightFailureFrom(message, details) : null;

abstract class FinanceApi {
  /// Tarifs courants ; document absent → valeurs par défaut (spec §2.4).
  Stream<Pricing> watchPricing();

  /// Admin seulement (côté serveur) : remplace intégralement settings/pricing.
  Future<void> updatePricing(Pricing pricing);

  /// Historique d'un compte, trié par date décroissante (côté client : la
  /// requête ne filtre que sur `userUid ==`, sans index composite).
  Stream<List<AccountMovement>> watchMovements(String uid);

  /// Tous les comptes, triés par nom (écran « Instructeurs »).
  Stream<List<AppUser>> watchAccounts();

  /// Rend le nouveau solde.
  Future<int> credit(String uid, int amount, String? reason);

  /// Rend le nouveau solde.
  Future<int> correct(String uid, int amount, String reason);

  Future<void> closeFlight(
    String flightId, {
    required int actualMinutes,
    int? shortFlightAmount,
    int? customAmount,
  });

  Future<void> adminUpdateFlight(String flightId, Map<String, dynamic> payload);
  Future<void> adminDeleteFlight(String flightId);

  /// Vols dont le départ tombe dans [from, to[, pour le calcul du crédit
  /// disponible et les écrans admin.
  Stream<List<Flight>> watchFlightsBetween(DateTime from, DateTime to);

  /// Vols non clôturés dont [payerUid] est le compte débité, passés compris
  /// (crédit disponible, spec §4.4 : même requête que le serveur, égalités
  /// seules, sans index composite).
  Stream<List<Flight>> watchUnclosedFlightsPaidBy(String payerUid);

  /// Vols validés non clôturés, passés comme à venir : les vols à clôturer
  /// de toute période (panneau « Vols effectués »). Égalités seules, sans
  /// index composite.
  Stream<List<Flight>> watchValidUnclosedFlights();
}

class FirebaseFinanceApi implements FinanceApi {
  FirebaseFinanceApi({FirebaseFirestore? db, FirebaseFunctions? fn})
      : _db = db ?? FirebaseFirestore.instance,
        _fn = fn ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  CollectionReference<Map<String, dynamic>> get _flights => _db.collection('flights');
  CollectionReference<Map<String, dynamic>> get _transactions => _db.collection('transactions');
  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  @override
  Stream<Pricing> watchPricing() => watchPricingSettings(_db);

  Future<Object?> _call(String name, Map<String, dynamic> payload) async {
    try {
      return (await _fn.httpsCallable(name).call(payload)).data;
    } on FirebaseFunctionsException catch (e) {
      throw financeFailureFrom(e.code, e.message ?? e.code, e.details) ?? e;
    }
  }

  @override
  Future<void> updatePricing(Pricing pricing) => _call('adminUpdatePricing', pricing.toMap());

  @override
  Stream<List<AccountMovement>> watchMovements(String uid) => _transactions
      .where('userUid', isEqualTo: uid)
      .snapshots()
      .map((q) => q.docs.map((d) => AccountMovement.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.at.compareTo(a.at)));

  @override
  Stream<List<AppUser>> watchAccounts() => _users
      .orderBy('displayName')
      .snapshots()
      .map((q) => q.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList());

  @override
  Future<int> credit(String uid, int amount, String? reason) async {
    final data = (await _call('creditAccount', {
      'userUid': uid,
      'amount': amount,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    })) as Map;
    return (data['balance'] as num).toInt();
  }

  @override
  Future<int> correct(String uid, int amount, String reason) async {
    final data = (await _call('correctAccount', {
      'userUid': uid,
      'amount': amount,
      'reason': reason,
    })) as Map;
    return (data['balance'] as num).toInt();
  }

  @override
  Future<void> closeFlight(
    String flightId, {
    required int actualMinutes,
    int? shortFlightAmount,
    int? customAmount,
  }) =>
      _call('closeFlight', {
        'flightId': flightId,
        'actualMinutes': actualMinutes,
        if (shortFlightAmount != null) 'shortFlightAmount': shortFlightAmount,
        if (customAmount != null) 'customAmount': customAmount,
      });

  @override
  Future<void> adminUpdateFlight(String flightId, Map<String, dynamic> payload) =>
      _call('adminUpdateFlight', {'flightId': flightId, ...payload});

  @override
  Future<void> adminDeleteFlight(String flightId) =>
      _call('adminDeleteFlight', {'flightId': flightId});

  @override
  Stream<List<Flight>> watchFlightsBetween(DateTime from, DateTime to) => _flights
      .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .where('start', isLessThan: Timestamp.fromDate(to))
      .orderBy('start')
      .snapshots()
      .map((q) => q.docs.map((d) => Flight.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<Flight>> watchUnclosedFlightsPaidBy(String payerUid) => _flights
      .where('payerUid', isEqualTo: payerUid)
      .where('isClosed', isEqualTo: false)
      .snapshots()
      .map((q) => q.docs.map((d) => Flight.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<Flight>> watchValidUnclosedFlights() => _flights
      .where('status', isEqualTo: 'valide')
      .where('isClosed', isEqualTo: false)
      .snapshots()
      .map((q) => q.docs.map((d) => Flight.fromMap(d.id, d.data())).toList());
}
