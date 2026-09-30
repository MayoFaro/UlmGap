import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/features/performed/performed.dart';

import '../../support/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 15, 12);

  group('needsClosing', () {
    test('validé, non clôturé, départ passé : à clôturer', () {
      expect(needsClosing(testFlight(start: DateTime(2026, 10, 15, 9)), now), isTrue);
    });
    test('vol du jour pas encore parti : à clôturer (décision 6)', () {
      expect(needsClosing(testFlight(start: DateTime(2026, 10, 15, 23, 30)), now), isTrue);
    });
    test('vol de demain : non', () {
      expect(needsClosing(testFlight(start: DateTime(2026, 10, 16, 0, 0)), now), isFalse);
    });
    test('clôturé, supprimé, demande ou refusé : non', () {
      final past = DateTime(2026, 10, 10, 9);
      expect(needsClosing(testFlight(start: past, isClosed: true), now), isFalse);
      expect(needsClosing(testFlight(start: past, deleted: true), now), isFalse);
      expect(needsClosing(testFlight(start: past, status: 'demande'), now), isFalse);
      expect(needsClosing(testFlight(start: past, status: 'refuse'), now), isFalse);
    });
  });

  group('isPerformed', () {
    test('validé, départ aujourd\'hui ou avant : oui, même pas encore parti', () {
      expect(isPerformed(testFlight(start: DateTime(2026, 10, 1, 9)), now), isTrue);
      expect(isPerformed(testFlight(start: DateTime(2026, 10, 15, 23, 30)), now), isTrue);
    });
    test('départ demain : non', () {
      expect(isPerformed(testFlight(start: DateTime(2026, 10, 16, 0, 0)), now), isFalse);
    });
    test('supprimé, demande (expirée) ou refusé : non', () {
      final past = DateTime(2026, 10, 10, 9);
      expect(isPerformed(testFlight(start: past, deleted: true), now), isFalse);
      expect(isPerformed(testFlight(start: past, status: 'demande'), now), isFalse);
      expect(isPerformed(testFlight(start: past, status: 'refuse'), now), isFalse);
    });
  });

  group('visibleTo', () {
    final f = testFlight(crew: ['u2', 'u3']);
    test('pilote : seulement s\'il est dans l\'équipage', () {
      expect(visibleTo(f, testUser(uid: 'u1', profile: 'lache_solo')), isFalse);
      expect(visibleTo(f, testUser(uid: 'u3', profile: 'eleve')), isTrue);
    });
    test('instructeur ou admin : tout', () {
      expect(visibleTo(f, testUser(uid: 'u1', profile: 'instructeur')), isTrue);
      expect(visibleTo(f, testUser(uid: 'u1', profile: null, isAdmin: true)), isTrue);
    });
  });

  test('performedList : filtre, appareil, tri du plus récent au plus ancien', () {
    final me = testUser(uid: 'u1', profile: 'lache_solo');
    final flights = [
      testFlight(id: 'old', start: DateTime(2026, 10, 2, 9), crew: ['u1']),
      testFlight(id: 'recent', start: DateTime(2026, 10, 12, 9), crew: ['u1']),
      testFlight(id: 'other-ac', start: DateTime(2026, 10, 8, 9), crew: ['u1'], aircraftId: 'a2'),
      testFlight(id: 'not-mine', start: DateTime(2026, 10, 9, 9), crew: ['u2']),
      testFlight(id: 'future', start: DateTime(2026, 10, 20, 9), crew: ['u1']),
    ];
    expect(performedList(flights, me: me, now: now).map((f) => f.id),
        ['recent', 'other-ac', 'old']);
    expect(performedList(flights, me: me, now: now, aircraftId: 'a1').map((f) => f.id),
        ['recent', 'old']);
  });

  test('performedLabel', () {
    expect(
        performedLabel(
            testFlight(start: DateTime(2026, 10, 10, 9), isClosed: true, actualFlightMinutes: 75),
            now),
        'Clôturé · 1 h 15');
    expect(performedLabel(testFlight(start: DateTime(2026, 10, 10, 9)), now), 'À clôturer');
    expect(performedLabel(testFlight(start: DateTime(2026, 10, 15, 14)), now), 'À clôturer');
  });

  test('toCloseCountText : singulier et pluriel', () {
    expect(toCloseCountText(1), '1 vol à clôturer');
    expect(toCloseCountText(3), '3 vols à clôturer');
  });
}
