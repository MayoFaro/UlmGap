import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _date(Object? v) => v is Timestamp
    ? v.toDate()
    : v is DateTime
        ? v
        : DateTime.fromMillisecondsSinceEpoch(0);

/// Nature d'une ligne de `tankMovements` (spec §13.1).
enum TankKind {
  refill('refill', 'Remplissage'),
  flight('flight', 'Vol'),
  aircraftFill('aircraft_fill', 'Plein hors vol'),
  gauge('gauge', 'Relevé de jauge'),
  flightAdjustment('flight_adjustment', 'Régularisation');

  const TankKind(this.code, this.label);
  final String code;
  final String label;

  static TankKind? fromCode(String code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// Ligne de `tankMovements` (spec §13.1), jamais modifiée.
class TankMovement {
  const TankMovement({
    required this.id,
    required this.kindCode,
    required this.liters,
    required this.date,
    required this.flightId,
    required this.aircraftId,
    required this.cashMovementId,
    required this.measuredLiters,
    required this.technical,
    required this.note,
    required this.by,
    required this.at,
    required this.litersAfter,
  });

  final String id;
  final String kindCode;
  final int liters; // signé : positif = entrée dans la cuve
  final String date; // « AAAA-MM-JJ » (jour du vol pour un vol)
  final String? flightId;
  final String? aircraftId;
  final String? cashMovementId;
  final int? measuredLiters;
  final bool technical;
  final String? note;
  final String by;
  final DateTime at;
  final int litersAfter;

  TankKind? get kind => TankKind.fromCode(kindCode);

  /// Minuit (heure locale) du jour de l'opération.
  DateTime get day => DateTime.parse(date);

  factory TankMovement.fromMap(String id, Map<String, dynamic> m) => TankMovement(
        id: id,
        kindCode: (m['kind'] as String?) ?? '',
        liters: (m['liters'] as num?)?.toInt() ?? 0,
        date: (m['date'] as String?) ?? '1970-01-01',
        flightId: m['flightId'] as String?,
        aircraftId: m['aircraftId'] as String?,
        cashMovementId: m['cashMovementId'] as String?,
        measuredLiters: (m['measuredLiters'] as num?)?.toInt(),
        technical: m['technical'] == true,
        note: m['note'] as String?,
        by: (m['by'] as String?) ?? '',
        at: _date(m['at']),
        litersAfter: (m['litersAfter'] as num?)?.toInt() ?? 0,
      );
}
