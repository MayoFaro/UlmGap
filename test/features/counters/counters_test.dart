import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/features/counters/counters.dart';

import '../../support/fakes.dart';

void main() {
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

  test('pilotMinutes : tout membre de l\'équipage cumule, pas les autres', () {
    final flights = [
      testFlight(id: 'a', crew: ['u1', 'u2'], isClosed: true, actualFlightMinutes: 60),
      testFlight(id: 'b', crew: ['u2'], isClosed: true, actualFlightMinutes: 45),
      testFlight(
          id: 'c', crew: ['u1'], passengers: ['Paul'], isClosed: true, actualFlightMinutes: 90),
      testFlight(id: 'd', crew: ['u1']), // non clôturé
    ];
    expect(pilotMinutes(flights, 'u1'), 150);
    expect(pilotMinutes(flights, 'u2'), 105);
    expect(pilotMinutes(flights, 'u3'), 0);
  });

  test('aircraftMinutes : seuls les vols de l\'appareil', () {
    final flights = [
      testFlight(id: 'a', aircraftId: 'a1', isClosed: true, actualFlightMinutes: 60),
      testFlight(id: 'b', aircraftId: 'a2', isClosed: true, actualFlightMinutes: 45),
      testFlight(id: 'c', aircraftId: 'a1', isClosed: true, actualFlightMinutes: 30),
    ];
    expect(aircraftMinutes(flights, 'a1'), 90);
    expect(aircraftMinutes(flights, 'a2'), 45);
    expect(aircraftMinutes(flights, 'a9'), 0);
  });
}
