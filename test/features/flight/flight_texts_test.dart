import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/data/flight_api.dart';
import 'package:ulmgap/features/flight/flight_texts.dart';

import '../../support/fakes.dart';

void main() {
  final dir = {for (final m in [member('ral', 'RAL', 'eleve'), member('hil', 'HIL', 'lache_toute_mission')]) m.uid: m};
  ConflictInfo info(String kind, List<String> members) => ConflictInfo(
      start: DateTime(2026, 9, 30, 15), end: DateTime(2026, 9, 30, 16),
      aircraft: 'TR-KJP', crew: const ['hil', 'ral'], passengers: const [],
      kind: kind, members: members);

  test('conflit d\'appareil', () {
    expect(describeConflict(info('aircraft', const []), dir),
        'Conflit : TR-KJP est déjà réservé sur le vol du mercredi 30 septembre, 15:00–16:00 (HIL/RAL).');
  });
  test('conflit de personne', () {
    expect(describeConflict(info('crew', const ['ral']), dir),
        'Conflit : RAL est déjà sur le vol du mercredi 30 septembre, 15:00–16:00 (TR-KJP, HIL/RAL).');
  });

  test('plan 8 : pricingModeLabel baptême', () {
    expect(pricingModeLabel('baptism'), 'Baptême de l\'air');
  });

  test('plan 4b : landingsText', () {
    expect(landingsText(null, null), '');
    expect(landingsText(2, 0), '2 att.');
    expect(landingsText(2, null), '2 att.');
    expect(landingsText(1, 3), '1 att. · 3 am.');
  });

  test('plan 4b : closedSummary avec atterrissages et amerrissages', () {
    expect(
        closedSummary(actualMinutes: 75, billedAmount: 15000, billedTo: 'account',
            debitedShortName: 'DPS', landings: 2, waterLandings: 1),
        endsWith(', 2 att., 1 am.'));
    expect(
        closedSummary(actualMinutes: 75, billedAmount: 15000, billedTo: 'account',
            debitedShortName: 'DPS', landings: 2, waterLandings: 0),
        endsWith('DPS, 2 att.'));
    expect(
        closedSummary(actualMinutes: 75, billedAmount: 15000, billedTo: 'account',
            debitedShortName: 'DPS'),
        endsWith('le compte de DPS'));
  });

  test('savedMessage : confirmation selon le résultat du serveur', () {
    expect(savedMessage(FlightStatus.valide, 'INS', created: true), 'Vol enregistré.');
    expect(savedMessage(FlightStatus.demande, 'INS', created: true), 'Demande envoyée à INS.');
    expect(savedMessage(FlightStatus.demande, null, created: true),
        'Demande envoyée à l\'instructeur.');
    expect(savedMessage(FlightStatus.valide, null, created: false), 'Modifications enregistrées.');
    expect(savedMessage(FlightStatus.demande, 'INS', created: false),
        'Demande modifiée, envoyée à INS.');
  });

  test('fuelSummary : sans écart, avec écart, prévu inconnu', () {
    Flight f(int? exp, int start) => testFlight(isClosed: true, actualFlightMinutes: 60,
        fuelStartExpected: exp, fuelStart: start, fuelAdded: 20, fuelEnd: 35);
    expect(fuelSummary(f(40, 40)), 'Carburant : départ 40 L · ajouté 20 L · rangé 35 L');
    expect(fuelSummary(f(30, 40)), 'Carburant : départ 40 L · ajouté 20 L · rangé 35 L (prévu 30 L)');
    expect(fuelSummary(f(null, 40)), 'Carburant : départ 40 L · ajouté 20 L · rangé 35 L (prévu inconnu)');
  });
}
