import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
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
      'instruction': false,
      'baptism': false,
      'baptismTier': null,
    });
  });

  test('plan 8 : instruction, crédit instruction et baptême', () {
    final f = testFlight();
    expect(f.instruction, isFalse);
    expect(f.instructionCreditUid, isNull);
    expect(f.instructionCreditAmount, isNull);
    expect(f.isBaptism, isFalse);
    final g = testFlight(
        instruction: true,
        instructionCreditUid: 'i1',
        instructionCreditAmount: 20000,
        pricingMode: 'baptism');
    expect(g.instruction, isTrue);
    expect(g.instructionCreditUid, 'i1');
    expect(g.instructionCreditAmount, 20000);
    expect(g.isBaptism, isTrue);
    final d = FlightDraft(
      start: DateTime.utc(2026, 10, 13, 9),
      end: DateTime.utc(2026, 10, 13, 10),
      destination: 'x',
      aircraftId: 'a1',
      crew: const ['u1'],
      passengers: const [],
    );
    expect(d.toPayload()['instruction'], false);
    expect(d.toPayload()['baptism'], false);
  });

  test('plan 9 : forfait de baptême lu et envoyé', () {
    expect(testFlight().baptismTier, isNull);
    expect(testFlight(pricingMode: 'baptism', baptismTier: 'awagne').baptismTier, 'awagne');
    final d = FlightDraft(
      start: DateTime.utc(2026, 10, 13, 9),
      end: DateTime.utc(2026, 10, 13, 10),
      destination: 'x',
      aircraftId: 'a1',
      crew: const ['u1'],
      passengers: const ['Paul'],
      baptism: true,
      baptismTier: 'nyonye',
    );
    expect(d.toPayload()['baptismTier'], 'nyonye');
  });

  test('plan 4b : landings et waterLandings lus, null si absents', () {
    final f = testFlight(isClosed: true);
    expect(f.landings, isNull);
    expect(f.waterLandings, isNull);
    final g = Flight.fromMap('g', {
      'start': DateTime(2026, 10, 1, 9), 'end': DateTime(2026, 10, 1, 10),
      'crew': ['u1'], 'landings': 2, 'waterLandings': 1,
    });
    expect(g.landings, 2);
    expect(g.waterLandings, 1);
  });

  test('plan 4b : Aircraft.amphibious, faux par défaut', () {
    expect(Aircraft.fromMap('a', {'registration': 'F-JA', 'label': 'x', 'active': true}).amphibious,
        isFalse);
    expect(Aircraft.fromMap('a', {'amphibious': true}).amphibious, isTrue);
  });

  test('carburant lu depuis Firestore ; hasFuel', () {
    final f = testFlight(fuelStartExpected: null, fuelStart: 35, fuelAdded: 20, fuelEnd: 41);
    expect(f.fuelStartExpectedLiters, isNull);
    expect([f.fuelStartLiters, f.fuelAddedLiters, f.fuelEndLiters], [35, 20, 41]);
    expect(f.hasFuel, isTrue);
    expect(testFlight().hasFuel, isFalse);
  });

  test('appareil : carburant actuel', () {
    final a = Aircraft.fromMap('a1', {'registration': 'F-X', 'label': 'ULM', 'active': true,
        'fuelLiters': 41, 'fuelFlightId': 'f1'});
    expect(a.fuelLiters, 41);
    expect(a.fuelFlightId, 'f1');
    expect(Aircraft.fromMap('a2', {}).fuelLiters, isNull);
  });
}
