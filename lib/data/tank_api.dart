import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/cash.dart' show cashDayCode;
import 'finance_api.dart' show financeFailureFrom;
import 'tank_movement.dart';

/// Cuve de carburant (spec §13) : lecture réservée aux instructeurs et aux
/// admins, écritures par les Functions.
abstract class TankApi {
  /// Niveau courant en litres (peut être négatif).
  Stream<int> watchTank();

  /// Toutes les lignes ; filtres et tri dans l'app, sans index.
  Stream<List<TankMovement>> watchMovements();

  /// Plein d'un appareil hors vol : sort [liters] de la cuve.
  Future<void> aircraftFill(
      {required String aircraftId, required int liters, required DateTime date, String? note});

  /// Relevé de jauge : [measuredLiters] est le niveau mesuré.
  Future<void> gaugeReading({required int measuredLiters, required DateTime date, String? note});
}

class FirebaseTankApi implements TankApi {
  FirebaseTankApi({FirebaseFirestore? db, FirebaseFunctions? fn})
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
  Stream<int> watchTank() => _db
      .collection('tank')
      .doc('main')
      .snapshots()
      .map((s) => (s.data()?['liters'] as num?)?.toInt() ?? 0);

  @override
  Stream<List<TankMovement>> watchMovements() => _db
      .collection('tankMovements')
      .snapshots()
      .map((q) => q.docs.map((d) => TankMovement.fromMap(d.id, d.data())).toList());

  @override
  Future<void> aircraftFill(
          {required String aircraftId, required int liters, required DateTime date, String? note}) =>
      _call('addAircraftFill', {
        'aircraftId': aircraftId,
        'liters': liters,
        'date': cashDayCode(date),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  @override
  Future<void> gaugeReading({required int measuredLiters, required DateTime date, String? note}) =>
      _call('addGaugeReading', {
        'measuredLiters': measuredLiters,
        'date': cashDayCode(date),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });
}
