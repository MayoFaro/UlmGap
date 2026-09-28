import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/flight.dart';

import '../support/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 12, 12);

  test('fromMap : champs du contrat et valeurs par défaut', () {
    final f = testFlight(id: 'f1', start: DateTime(2026, 10, 13, 9), status: 'demande');
    expect(f.status, FlightStatus.demande);
    expect(f.end, DateTime(2026, 10, 13, 10));
    expect(f.crew, ['u1']);
    expect(f.deleted, isFalse);
  });

  test('demande dont le départ est passé : refusée (statut calculé)', () {
    final past = testFlight(start: DateTime(2026, 10, 12, 11), status: 'demande');
    final future = testFlight(start: DateTime(2026, 10, 12, 13), status: 'demande');
    expect(past.isExpiredRequest(now), isTrue);
    expect(past.effectiveStatus(now), FlightStatus.refuse);
    expect(future.effectiveStatus(now), FlightStatus.demande);
    expect(testFlight(start: DateTime(2026, 10, 12, 11)).effectiveStatus(now), FlightStatus.valide);
  });

  test('FlightDraft.toPayload : millisecondes, destination nettoyée, mode facultatif', () {
    final d = FlightDraft(
      start: DateTime.utc(2026, 10, 13, 9),
      end: DateTime.utc(2026, 10, 13, 10),
      destination: ' Lomé ',
      aircraftId: 'a1',
      crew: const ['u1'],
      passengers: const [],
    );
    expect(d.toPayload(), {
      'start': DateTime.utc(2026, 10, 13, 9).millisecondsSinceEpoch,
      'end': DateTime.utc(2026, 10, 13, 10).millisecondsSinceEpoch,
      'destination': 'Lomé',
      'aircraftId': 'a1',
      'crew': ['u1'],
      'passengers': <String>[],
    });
  });
}
