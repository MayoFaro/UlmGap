import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/features/home/closing_reminder.dart';

import '../../support/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 12, 14);

  test('vol terminé, non clôturé, dont je suis membre : rappelé', () {
    final f = testFlight(id: 'a', crew: ['me', 'u2'],
        start: DateTime(2026, 10, 12, 10), end: DateTime(2026, 10, 12, 11));
    expect(firstFlightToClose([f], 'me', now)?.id, 'a');
  });

  test('heure de fin pas encore passée : pas de rappel ; fin exactement maintenant : rappel', () {
    final running = testFlight(crew: ['me'], start: DateTime(2026, 10, 12, 13),
        end: DateTime(2026, 10, 12, 15));
    expect(firstFlightToClose([running], 'me', now), isNull);
    final justEnded = testFlight(crew: ['me'], start: DateTime(2026, 10, 12, 13), end: now);
    expect(firstFlightToClose([justEnded], 'me', now), isNotNull);
  });

  test('pas membre, déjà clôturé, supprimé ou non validé : pas de rappel', () {
    final s = DateTime(2026, 10, 12, 9);
    final e = DateTime(2026, 10, 12, 10);
    expect(firstFlightToClose([testFlight(crew: ['u2'], start: s, end: e)], 'me', now), isNull);
    expect(firstFlightToClose(
        [testFlight(crew: ['me'], start: s, end: e, isClosed: true)], 'me', now), isNull);
    expect(firstFlightToClose(
        [testFlight(crew: ['me'], start: s, end: e, deleted: true)], 'me', now), isNull);
    expect(firstFlightToClose(
        [testFlight(crew: ['me'], start: s, end: e, status: 'demande')], 'me', now), isNull);
  });

  test('plusieurs vols à clôturer : le plus ancien', () {
    final older = testFlight(id: 'old', crew: ['me'],
        start: DateTime(2026, 10, 10, 9), end: DateTime(2026, 10, 10, 10));
    final newer = testFlight(id: 'new', crew: ['me'],
        start: DateTime(2026, 10, 11, 9), end: DateTime(2026, 10, 11, 10));
    expect(firstFlightToClose([newer, older], 'me', now)?.id, 'old');
  });
}
