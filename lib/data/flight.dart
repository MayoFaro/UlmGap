import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/flight_rules.dart';
import '../core/pricing.dart';

enum FlightStatus { demande, valide, refuse }

FlightStatus _status(Object? v) => FlightStatus.values
    .firstWhere((s) => s.name == v, orElse: () => FlightStatus.demande);

DateTime _date(Object? v) => v is Timestamp
    ? v.toDate()
    : v is DateTime
        ? v
        : DateTime.fromMillisecondsSinceEpoch(0);

DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);

List<String> _strings(Object? v) => (v as List?)?.cast<String>() ?? const [];

class Flight {
  const Flight({
    required this.id,
    required this.start,
    required this.end,
    required this.destination,
    required this.aircraftId,
    required this.aircraft,
    required this.crew,
    required this.passengers,
    required this.instructorUid,
    required this.status,
    required this.refusalReason,
    required this.createdBy,
    required this.pricingMode,
    required this.isClosed,
    required this.deleted,
    this.payerUidField,
    this.pricingSnapshot,
    this.actualFlightMinutes,
    this.billedAmount,
    this.billedTo,
    this.customAmount,
    this.shortFlightAmount,
    this.closedBy,
    this.closedAt,
    this.landings,
    this.waterLandings,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final String destination;
  final String aircraftId;
  final String aircraft; // immatriculation
  final List<String> crew;
  final List<String> passengers;
  final String? instructorUid;
  final FlightStatus status;
  final String? refusalReason;
  final String createdBy;
  final String pricingMode;
  final bool isClosed;
  final bool deleted;

  /// Compte débité stocké sur le vol (`payerUid`, plan 3), absent des vols
  /// créés avant ce plan : distinct du repli [payerUid] (crew.first).
  final String? payerUidField;

  /// Tarifs figés au passage à `valide` (spec, décision du contrôleur) ;
  /// `null` pour un vol validé avant le plan 3 (repli sur les tarifs courants).
  final Pricing? pricingSnapshot;
  final int? actualFlightMinutes;
  final int? billedAmount;
  final String? billedTo; // 'account' | 'off_app'
  final int? customAmount;
  final int? shortFlightAmount;
  final String? closedBy;
  final DateTime? closedAt;

  /// Plan 4b : saisis à la clôture ; null pour un vol clôturé avant.
  final int? landings;
  final int? waterLandings;

  String get payerUid => crew.first;

  factory Flight.fromMap(String id, Map<String, dynamic> m) => Flight(
        id: id,
        start: _date(m['start']),
        end: _date(m['end']),
        destination: (m['destination'] as String?) ?? '',
        aircraftId: (m['aircraftId'] as String?) ?? '',
        aircraft: (m['aircraft'] as String?) ?? '',
        crew: _strings(m['crew']),
        passengers: _strings(m['passengers']),
        instructorUid: m['instructorUid'] as String?,
        status: _status(m['status']),
        refusalReason: m['refusalReason'] as String?,
        createdBy: (m['createdBy'] as String?) ?? '',
        pricingMode: (m['pricingMode'] as String?) ?? 'standard',
        isClosed: m['isClosed'] == true,
        deleted: m['deleted'] == true,
        payerUidField: m['payerUid'] as String?,
        pricingSnapshot: m['pricingSnapshot'] == null
            ? null
            : Pricing.fromMap((m['pricingSnapshot'] as Map).cast<String, dynamic>()),
        actualFlightMinutes: (m['actualFlightMinutes'] as num?)?.toInt(),
        billedAmount: (m['billedAmount'] as num?)?.toInt(),
        billedTo: m['billedTo'] as String?,
        customAmount: (m['customAmount'] as num?)?.toInt(),
        shortFlightAmount: (m['shortFlightAmount'] as num?)?.toInt(),
        closedBy: m['closedBy'] as String?,
        closedAt: _dateOrNull(m['closedAt']),
        landings: (m['landings'] as num?)?.toInt(),
        waterLandings: (m['waterLandings'] as num?)?.toInt(),
      );

  /// Demande non validée à l'heure du départ : considérée comme refusée.
  bool isExpiredRequest(DateTime now) =>
      status == FlightStatus.demande && !start.isAfter(now);

  FlightStatus effectiveStatus(DateTime now) =>
      isExpiredRequest(now) ? FlightStatus.refuse : status;

  RuleFlight toRule() => RuleFlight(
        id: id,
        start: start.millisecondsSinceEpoch,
        end: end.millisecondsSinceEpoch,
        aircraftId: aircraftId,
        crew: crew,
        status: status.name,
        deleted: deleted,
        closed: isClosed,
      );
}

/// Saisie du formulaire, envoyée à createFlight / updateFlight.
class FlightDraft {
  const FlightDraft({
    required this.start,
    required this.end,
    required this.destination,
    required this.aircraftId,
    required this.crew,
    required this.passengers,
    this.pricingMode,
  });

  final DateTime start;
  final DateTime end;
  final String destination;
  final String aircraftId;
  final List<String> crew;
  final List<String> passengers;
  final String? pricingMode; // 'standard' | 'fuel_only', seulement si choisi

  Map<String, dynamic> toPayload() => {
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'destination': destination.trim(),
        'aircraftId': aircraftId,
        'crew': crew,
        'passengers': passengers,
        if (pricingMode != null) 'pricingMode': pricingMode,
      };
}
