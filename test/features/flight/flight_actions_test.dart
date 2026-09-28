import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/features/flight/flight_actions.dart';

import '../../support/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 12, 8);
  final request = testFlight(
      start: DateTime(2026, 10, 13, 9), status: 'demande',
      crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins');

  test('instructeur désigné : valider, refuser, annuler', () {
    expect(flightActions(request, testUser(uid: 'ins', profile: 'instructeur'), now),
        {FlightAction.validate, FlightAction.refuse, FlightAction.cancel});
  });

  test('créateur : modifier, annuler (pas valider)', () {
    expect(flightActions(request, testUser(uid: 'u1'), now),
        {FlightAction.edit, FlightAction.cancel});
  });

  test('admin : valider, refuser, annuler', () {
    expect(flightActions(request, testUser(uid: 'adm', isAdmin: true, profile: null), now),
        {FlightAction.validate, FlightAction.refuse, FlightAction.cancel});
  });

  test('autre utilisateur : rien', () {
    expect(flightActions(request, testUser(uid: 'x'), now), isEmpty);
  });

  test('après le départ, ou vol annulé : rien', () {
    final started = testFlight(start: DateTime(2026, 10, 12, 7), createdBy: 'u1');
    expect(flightActions(started, testUser(uid: 'u1'), now), isEmpty);
    final deleted = testFlight(start: DateTime(2026, 10, 13, 9), createdBy: 'u1', deleted: true);
    expect(flightActions(deleted, testUser(uid: 'u1'), now), isEmpty);
  });

  test('vol validé : pas de validation', () {
    final valid = testFlight(
        start: DateTime(2026, 10, 13, 9), crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins');
    expect(flightActions(valid, testUser(uid: 'ins', profile: 'instructeur'), now),
        {FlightAction.cancel});
  });
}
