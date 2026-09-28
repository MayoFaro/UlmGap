import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/flight_api.dart';

void main() {
  test('erreur simple', () {
    final f = flightFailureFrom('Vol introuvable.', null);
    expect(f, isNot(isA<FlightConflict>()));
    expect(f.message, 'Vol introuvable.');
  });

  test('conflit : détails décodés', () {
    final f = flightFailureFrom('Conflit avec un autre vol validé.', {
      'conflict': {
        'start': DateTime(2026, 10, 12, 9).millisecondsSinceEpoch,
        'end': DateTime(2026, 10, 12, 10).millisecondsSinceEpoch,
        'aircraft': 'F-JABC',
        'crew': ['u1'],
        'passengers': ['Paul'],
      }
    });
    expect(f, isA<FlightConflict>());
    final c = (f as FlightConflict).conflict;
    expect(c.start, DateTime(2026, 10, 12, 9));
    expect(c.aircraft, 'F-JABC');
    expect(c.crew, ['u1']);
    expect(c.passengers, ['Paul']);
  });
}
