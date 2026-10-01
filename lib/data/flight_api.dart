import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/profiles.dart';
import 'aircraft.dart';
import 'crew_member.dart';
import 'finance_api.dart' show financeFailureFrom;
import 'flight.dart';

/// Refus d'une action de vol par le serveur (message prêt à afficher).
class FlightFailure implements Exception {
  const FlightFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class ConflictInfo {
  const ConflictInfo({
    required this.start,
    required this.end,
    required this.aircraft,
    required this.crew,
    required this.passengers,
    this.kind = 'aircraft',
    this.members = const [],
  });
  final DateTime start;
  final DateTime end;
  final String aircraft;
  final List<String> crew; // uids
  final List<String> passengers;
  final String kind; // 'aircraft' | 'crew'
  final List<String> members; // uids en commun, quand kind == 'crew'
}

class FlightConflict extends FlightFailure {
  const FlightConflict(super.message, this.conflict);
  final ConflictInfo conflict;
}

FlightFailure flightFailureFrom(String message, Object? details) {
  final c = details is Map ? details['conflict'] : null;
  if (c is! Map) return FlightFailure(message);
  DateTime ms(Object? v) => DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
  return FlightConflict(
    message,
    ConflictInfo(
      start: ms(c['start']),
      end: ms(c['end']),
      aircraft: (c['aircraft'] as String?) ?? '',
      crew: (c['crew'] as List?)?.cast<String>() ?? const [],
      passengers: (c['passengers'] as List?)?.cast<String>() ?? const [],
      kind: (c['kind'] as String?) ?? 'aircraft',
      members: (c['members'] as List?)?.cast<String>() ?? const [],
    ),
  );
}

FlightStatus _statusOf(Object? v) =>
    FlightStatus.values.firstWhere((s) => s.name == v, orElse: () => FlightStatus.valide);

abstract class FlightApi {
  /// Vols dont le départ est à partir de [from], triés par départ.
  Stream<List<Flight>> watchFrom(DateTime from);
  Stream<Flight?> watchFlight(String id);
  Stream<List<CrewMember>> watchDirectory();

  /// Appartenances de tous les comptes : réservé aux instructeurs et admins (règles).
  Stream<Map<String, UserCategory>> watchCategories();
  Stream<List<Aircraft>> watchAircraft();
  Future<List<String>> recentDestinations();

  // Actions : lèvent FlightFailure (ou FlightConflict).
  /// Rendent le statut décidé par le serveur (vol enregistré ou demande).
  Future<({String id, FlightStatus status})> create(FlightDraft draft);
  Future<FlightStatus> update(String id, FlightDraft draft);
  Future<void> validate(String id, {Map<String, dynamic> changes = const {}});
  Future<void> refuse(String id, String? reason);
  Future<void> cancel(String id);
}

class FirebaseFlightApi implements FlightApi {
  FirebaseFlightApi({FirebaseFirestore? db, FirebaseFunctions? fn})
      : _db = db ?? FirebaseFirestore.instance,
        _fn = fn ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  CollectionReference<Map<String, dynamic>> get _flights => _db.collection('flights');

  @override
  Stream<List<Flight>> watchFrom(DateTime from) => _flights
      .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .orderBy('start')
      .snapshots()
      .map((q) => q.docs.map((d) => Flight.fromMap(d.id, d.data())).toList());

  @override
  Stream<Flight?> watchFlight(String id) => _flights
      .doc(id)
      .snapshots()
      .map((s) => s.exists ? Flight.fromMap(s.id, s.data()!) : null);

  @override
  Stream<List<CrewMember>> watchDirectory() => _db
      .collection('profiles')
      .orderBy('displayName')
      .snapshots()
      .map((q) => q.docs.map((d) => CrewMember.fromMap(d.id, d.data())).toList());

  @override
  Stream<Map<String, UserCategory>> watchCategories() =>
      _db.collection('users').snapshots().map((q) => {
            for (final d in q.docs)
              d.id: UserCategory.fromCode(d.data()['category'] as String?),
          });

  @override
  Stream<List<Aircraft>> watchAircraft() => _db
      .collection('aircraft')
      .orderBy('label')
      .snapshots()
      .map((q) => q.docs.map((d) => Aircraft.fromMap(d.id, d.data())).toList());

  @override
  Future<List<String>> recentDestinations() async {
    final q = await _flights.orderBy('start', descending: true).limit(200).get();
    final seen = <String>{};
    for (final d in q.docs) {
      final s = (d.data()['destination'] as String?)?.trim() ?? '';
      if (s.isNotEmpty) seen.add(s);
    }
    return seen.toList();
  }

  Future<Object?> _call(String name, Map<String, dynamic> payload) async {
    try {
      return (await _fn.httpsCallable(name).call(payload)).data;
    } on FirebaseFunctionsException catch (e) {
      // Refus certain du serveur : son message. Sinon (réseau, délai,
      // erreur interne) l'issue est incertaine : erreur d'origine, que
      // l'écran traduit en « vérifiez le planning » (pas de doublon).
      throw financeFailureFrom(e.code, e.message ?? e.code, e.details) ?? e;
    }
  }

  @override
  Future<({String id, FlightStatus status})> create(FlightDraft draft) async {
    final r = (await _call('createFlight', draft.toPayload())) as Map;
    return (id: r['id'] as String, status: _statusOf(r['status']));
  }

  @override
  Future<FlightStatus> update(String id, FlightDraft draft) async {
    final r = (await _call('updateFlight', {'flightId': id, ...draft.toPayload()})) as Map;
    return _statusOf(r['status']);
  }

  @override
  Future<void> validate(String id, {Map<String, dynamic> changes = const {}}) =>
      _call('validateFlight', {'flightId': id, 'changes': changes});

  @override
  Future<void> refuse(String id, String? reason) => _call('refuseFlight', {
        'flightId': id,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

  @override
  Future<void> cancel(String id) => _call('cancelFlight', {'flightId': id});
}
