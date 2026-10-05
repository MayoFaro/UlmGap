import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/flight_rules.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/flight_rules.json').readAsStringSync())
      as Map<String, dynamic>;

  List<RulePerson> crew(List<dynamic> l) => [
        for (final p in l.cast<Map<String, dynamic>>())
          RulePerson(p['uid'] as String, p['profile'] as String?)
      ];

  for (final c in (fx['matrix'] as List).cast<Map<String, dynamic>>()) {
    test('matrice : ${c['name']}', () {
      final creator = c['creator'] as Map<String, dynamic>;
      final d = decideStatus(
        creatorUid: creator['uid'] as String,
        creatorProfile: creator['profile'] as String?,
        creatorIsAdmin: creator['isAdmin'] as bool,
        crew: crew(c['crew'] as List),
        passengers: c['passengers'] as int,
      );
      if (c['expected'] == 'refus') {
        expect(d.ok, isFalse);
        expect(d.reason, isNotEmpty);
      } else {
        expect(d.status, c['expected']);
        expect(d.instructorUid, c['instructorUid']);
      }
    });
  }

  for (final c in (fx['pricing'] as List).cast<Map<String, dynamic>>()) {
    test('mode : ${c['name']}', () {
      expect(
        resolvePricingMode(
          allGap: c['allGap'] as bool,
          hasPassenger: c['hasPassenger'] as bool,
          mayChoose: c['mayChoose'] as bool,
          requested: c['requested'] as String?,
          previous: c['previous'] as String?,
        ),
        c['expected'],
      );
    });
  }

  for (final c in (fx['instruction'] as List).cast<Map<String, dynamic>>()) {
    test('instruction : ${c['name']}', () {
      expect(isInstructionEligible(crew(c['crew'] as List)), c['expected']);
    });
  }

  RuleFlight rf(Map<String, dynamic> m) => RuleFlight(
        id: m['id'] as String?,
        start: m['start'] as int,
        end: m['end'] as int,
        aircraftId: m['aircraftId'] as String,
        crew: (m['crew'] as List).cast<String>(),
        status: (m['status'] as String?) ?? 'valide',
        deleted: (m['deleted'] as bool?) ?? false,
        closed: (m['closed'] as bool?) ?? false,
      );

  for (final c in (fx['conflicts'] as List).cast<Map<String, dynamic>>()) {
    test('conflit : ${c['name']}', () {
      final candidate = rf(c['candidate'] as Map<String, dynamic>);
      final hit = findConflict(
        candidate,
        (c['others'] as List).cast<Map<String, dynamic>>().map(rf),
      );
      expect(hit?.id, c['expected']);
      final expectedCause = c['expectedCause'] as Map<String, dynamic>?;
      if (expectedCause != null) {
        final cause = conflictCause(candidate, hit!);
        expect(cause.kind, expectedCause['kind']);
        expect(cause.members, (expectedCause['members'] as List).cast<String>());
      }
    });
  }

  for (final c in (fx['payer'] as List).cast<Map<String, dynamic>>()) {
    test('payeur : ${c['name']}', () {
      final creator = c['creator'] as Map<String, dynamic>;
      final result = checkPayer(
        creatorUid: creator['uid'] as String,
        creatorProfile: creator['profile'] as String?,
        creatorIsAdmin: creator['isAdmin'] as bool,
        crew: (c['crew'] as List).cast<String>(),
      );
      if (c['ok'] as bool) {
        expect(result, isNull);
      } else {
        expect(result, 'Le compte débité doit être le vôtre : placez-vous en premier.');
      }
    });
  }

  test('isPlanning : contrôle des conflits pour un vol à venir non clôturé seulement', () {
    expect(isPlanning(start: 1000, now: 999, closed: false), isTrue);
    expect(isPlanning(start: 1000, now: 1000, closed: false), isFalse); // départ atteint
    expect(isPlanning(start: 1000, now: 2000, closed: false), isFalse); // conduite
    expect(isPlanning(start: 1000, now: 999, closed: true), isFalse); // clôturé
  });
}
