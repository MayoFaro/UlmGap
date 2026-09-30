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

  test('admin : valider, refuser, annuler, corriger, supprimer', () {
    expect(flightActions(request, testUser(uid: 'adm', isAdmin: true, profile: null), now), {
      FlightAction.validate,
      FlightAction.refuse,
      FlightAction.cancel,
      FlightAction.adminEdit,
      FlightAction.adminDelete,
    });
  });

  test('autre utilisateur : rien', () {
    expect(flightActions(request, testUser(uid: 'x'), now), isEmpty);
  });

  test('vol annulé (supprimé) : rien, même après le départ', () {
    final deleted = testFlight(start: DateTime(2026, 10, 13, 9), createdBy: 'u1', deleted: true);
    expect(flightActions(deleted, testUser(uid: 'u1'), now), isEmpty);
  });

  // --- Task 9 (plan 3) : clôture après le départ ---

  test('vol validé, départ passé : clôturer pour un membre de l\'équipage ou un admin', () {
    final started = testFlight(start: DateTime(2026, 10, 12, 7), crew: ['u1'], createdBy: 'u1');
    expect(flightActions(started, testUser(uid: 'u1'), now), {FlightAction.close});
    expect(flightActions(started, testUser(uid: 'adm', isAdmin: true, profile: null), now),
        {FlightAction.close, FlightAction.adminEdit, FlightAction.adminDelete});
  });

  test('vol validé, départ passé : pas de clôture pour un tiers', () {
    final started = testFlight(start: DateTime(2026, 10, 12, 7), crew: ['u1'], createdBy: 'u1');
    expect(flightActions(started, testUser(uid: 'x'), now), isEmpty);
  });

  test('vol validé, départ non passé : pas de clôture même pour l\'équipage', () {
    final future = testFlight(start: DateTime(2026, 10, 13, 9), crew: ['u1'], createdBy: 'u1');
    expect(flightActions(future, testUser(uid: 'u1'), now).contains(FlightAction.close), isFalse);
  });

  test('demande dont le départ est passé (expirée) : pas de clôture', () {
    final pastDemande = testFlight(
        start: DateTime(2026, 10, 12, 7), status: 'demande', crew: ['u1'], createdBy: 'u1');
    expect(flightActions(pastDemande, testUser(uid: 'u1'), now), isEmpty);
  });

  test('vol déjà clôturé : rien', () {
    final closed = testFlight(
        start: DateTime(2026, 10, 12, 7), crew: ['u1'], createdBy: 'u1', isClosed: true);
    expect(flightActions(closed, testUser(uid: 'u1'), now), isEmpty);
  });

  test('vol validé : pas de validation', () {
    final valid = testFlight(
        start: DateTime(2026, 10, 13, 9), crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins');
    expect(flightActions(valid, testUser(uid: 'ins', profile: 'instructeur'), now),
        {FlightAction.cancel});
  });

  // --- Task 10 (plan 3) : correction et suppression admin ---

  test('admin : vol clôturé → seulement corriger et supprimer', () {
    final closed = testFlight(
        start: DateTime(2026, 10, 12, 7), crew: ['u1'], createdBy: 'u1', isClosed: true);
    expect(flightActions(closed, testUser(uid: 'adm', isAdmin: true, profile: null), now),
        {FlightAction.adminEdit, FlightAction.adminDelete});
  });

  test('admin : vol refusé → annuler et supprimer, mais pas corriger', () {
    final refused = testFlight(
        start: DateTime(2026, 10, 13, 9), status: 'refuse', crew: ['u1'], createdBy: 'u1');
    expect(flightActions(refused, testUser(uid: 'adm', isAdmin: true, profile: null), now),
        {FlightAction.cancel, FlightAction.adminDelete});
  });

  test('admin : vol validé futur d\'un autre → annuler, corriger, supprimer', () {
    final other = testFlight(
        start: DateTime(2026, 10, 13, 9), crew: ['x'], createdBy: 'x', status: 'valide');
    expect(flightActions(other, testUser(uid: 'adm', isAdmin: true, profile: null), now),
        {FlightAction.cancel, FlightAction.adminEdit, FlightAction.adminDelete});
  });

  test('admin : vol validé passé, non clôturé → clôturer, corriger, supprimer', () {
    final started = testFlight(start: DateTime(2026, 10, 12, 7), crew: ['x'], createdBy: 'x');
    expect(flightActions(started, testUser(uid: 'adm', isAdmin: true, profile: null), now),
        {FlightAction.close, FlightAction.adminEdit, FlightAction.adminDelete});
  });

  test('non-admin : jamais corriger ni supprimer', () {
    final actions = flightActions(request, testUser(uid: 'u1'), now);
    expect(actions.contains(FlightAction.adminEdit), isFalse);
    expect(actions.contains(FlightAction.adminDelete), isFalse);
  });
}
