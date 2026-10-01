import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/features/logbook/logbook.dart';

import '../../support/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 15, 12);

  group('countedMinutes', () {
    test('vol clôturé non supprimé : ses minutes réelles', () {
      expect(countedMinutes(testFlight(isClosed: true, actualFlightMinutes: 75)), 75);
    });
    test('vol non clôturé : 0', () {
      expect(countedMinutes(testFlight(actualFlightMinutes: 75)), 0);
    });
    test('vol clôturé puis supprimé : 0', () {
      expect(
          countedMinutes(testFlight(isClosed: true, deleted: true, actualFlightMinutes: 75)), 0);
    });
    test('vol clôturé sans minutes réelles (données anciennes) : 0', () {
      expect(countedMinutes(testFlight(isClosed: true)), 0);
    });
  });

  test('totalMinutes : somme des vols clôturés, chaque vol une fois', () {
    expect(
        totalMinutes([
          testFlight(id: 'a', crew: ['u1', 'u2'], isClosed: true, actualFlightMinutes: 60),
          testFlight(id: 'b', isClosed: true, actualFlightMinutes: 45),
          testFlight(id: 'c', actualFlightMinutes: 90), // non clôturé
        ]),
        105);
  });

  group('needsClosing', () {
    test('validé, non clôturé, départ passé : à clôturer', () {
      expect(needsClosing(testFlight(start: DateTime(2026, 10, 15, 9)), now), isTrue);
    });
    test('vol du jour pas encore parti : à clôturer', () {
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

  group('logbookList', () {
    final flights = [
      testFlight(id: 'old', start: DateTime(2026, 10, 2, 9), crew: ['u1']),
      testFlight(id: 'recent', start: DateTime(2026, 10, 12, 9), crew: ['u1', 'u2']),
      testFlight(id: 'other-ac', start: DateTime(2026, 10, 8, 9), crew: ['u1'], aircraftId: 'a2'),
      testFlight(id: 'u2-only', start: DateTime(2026, 10, 9, 9), crew: ['u2']),
      testFlight(id: 'future', start: DateTime(2026, 10, 20, 9), crew: ['u1']),
      testFlight(id: 'refused', start: DateTime(2026, 10, 3, 9), crew: ['u1'], status: 'refuse'),
    ];
    test('pilote : ses vols effectués, tous appareils, du plus récent au plus ancien', () {
      final me = testUser(uid: 'u1', profile: 'lache_solo');
      expect(logbookList(flights, me: me, now: now, pilotUid: 'u1').map((f) => f.id),
          ['recent', 'other-ac', 'old']);
    });
    test('pilote : ne voit jamais les vols des autres, même avec pilotUid null', () {
      final me = testUser(uid: 'u1', profile: 'lache_solo');
      expect(logbookList(flights, me: me, now: now, pilotUid: null).map((f) => f.id),
          ['recent', 'other-ac', 'old']);
    });
    test('instructeur, tous les pilotes : tous les vols effectués', () {
      final me = testUser(uid: 'u9', profile: 'instructeur');
      expect(logbookList(flights, me: me, now: now, pilotUid: null).map((f) => f.id),
          ['recent', 'u2-only', 'other-ac', 'old']);
    });
    test('instructeur, un pilote choisi : ses vols', () {
      final me = testUser(uid: 'u9', profile: 'instructeur');
      expect(logbookList(flights, me: me, now: now, pilotUid: 'u2').map((f) => f.id),
          ['recent', 'u2-only']);
    });
  });

  group('monthPeriod', () {
    test('un mois : du 1er au 1er du mois suivant', () {
      final p = monthPeriod(2026, 9);
      expect(p.from, DateTime(2026, 9, 1));
      expect(p.to, DateTime(2026, 10, 1));
    });
    test('décembre : jusqu\'au 1er janvier suivant', () {
      final p = monthPeriod(2026, 12);
      expect(p.to, DateTime(2027, 1, 1));
    });
    test('année entière (mois 0)', () {
      final p = monthPeriod(2026, 0);
      expect(p.from, DateTime(2026, 1, 1));
      expect(p.to, DateTime(2027, 1, 1));
    });
  });

  test('logbookYears : de 2026 à l\'année en cours, la plus récente en premier', () {
    expect(logbookYears(DateTime(2026, 10, 15)), [2026]);
    expect(logbookYears(DateTime(2028, 3, 1)), [2028, 2027, 2026]);
  });

  test('performedLabel', () {
    expect(
        performedLabel(
            testFlight(start: DateTime(2026, 10, 10, 9), isClosed: true, actualFlightMinutes: 75),
            now),
        'Clôturé · 1 h 15');
    expect(performedLabel(testFlight(start: DateTime(2026, 10, 15, 14)), now), 'À clôturer');
  });

  test('toCloseCountText : singulier et pluriel', () {
    expect(toCloseCountText(1), '1 vol à clôturer');
    expect(toCloseCountText(3), '3 vols à clôturer');
  });

  Flight counted(String id, {int? landings, int? water, bool closed = true, bool deleted = false}) =>
      Flight.fromMap(id, {
        'start': DateTime(2026, 10, 10, 9), 'end': DateTime(2026, 10, 10, 10), 'crew': ['u1'],
        'status': 'valide', 'isClosed': closed, 'deleted': deleted, 'actualFlightMinutes': 60,
        'landings': landings, 'waterLandings': water,
      });

  test('plan 4b : totalLandings, vols clôturés non supprimés, null = 0', () {
    final t = totalLandings([
      counted('a', landings: 2, water: 1),
      counted('b', landings: 1),
      counted('old'), // clôturé avant le plan 4b
      counted('open', landings: 5, closed: false),
      counted('del', landings: 5, water: 5, deleted: true),
    ]);
    expect(t.landings, 3);
    expect(t.waterLandings, 1);
  });

  test('plan 4b : performedLabel avec les nombres', () {
    expect(performedLabel(counted('a', landings: 2), now), 'Clôturé · 1 h 00 · 2 att.');
    expect(performedLabel(counted('b', landings: 1, water: 2), now), 'Clôturé · 1 h 00 · 1 att. · 2 am.');
    expect(performedLabel(counted('old'), now), 'Clôturé · 1 h 00');
  });

  test('logbookList : filtre appareil, combiné au pilote', () {
    final me = testUser(uid: 'u9', profile: 'instructeur');
    final flights = [
      testFlight(id: 'a1-u1', start: DateTime(2026, 10, 2, 9), crew: ['u1'], aircraftId: 'a1'),
      testFlight(id: 'a2-u1', start: DateTime(2026, 10, 3, 9), crew: ['u1'], aircraftId: 'a2'),
      testFlight(id: 'a1-u2', start: DateTime(2026, 10, 4, 9), crew: ['u2'], aircraftId: 'a1'),
    ];
    expect(logbookList(flights, me: me, now: now, pilotUid: null, aircraftId: 'a1').map((f) => f.id),
        ['a1-u2', 'a1-u1']);
    expect(logbookList(flights, me: me, now: now, pilotUid: 'u1', aircraftId: 'a1').map((f) => f.id),
        ['a1-u1']);
  });
}
