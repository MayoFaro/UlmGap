import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/fuel.dart';
import 'package:ulmgap/data/flight.dart';

import '../support/fakes.dart';

void main() {
  test('fuelError : bornes 0 à 100, messages du serveur', () {
    expect(fuelError(start: 40, added: 0, end: 30), isNull);
    expect(fuelError(start: null, added: 0, end: 30), 'Carburant au départ invalide (0 à 100 L).');
    expect(fuelError(start: 40, added: 101, end: 30), 'Carburant ajouté invalide (0 à 100 L).');
    expect(fuelError(start: 40, added: 0, end: -1), 'Carburant rangé invalide (0 à 100 L).');
    expect(fuelError(start: 100, added: 100, end: 0), isNull);
  });

  test('fuelText', () {
    expect(fuelText(40), '40 L');
    expect(fuelText(null), 'inconnu');
  });

  test('fuelGap : départ différent du prévu, ou prévu inconnu', () {
    Flight f(int? expected, int start) => testFlight(
        isClosed: true, actualFlightMinutes: 60,
        fuelStartExpected: expected, fuelStart: start, fuelAdded: 0, fuelEnd: 10);
    expect(fuelGap(f(40, 40)), isFalse);
    expect(fuelGap(f(40, 30)), isTrue);
    expect(fuelGap(f(null, 30)), isTrue);
  });

  test('fuelStats : Σ (départ + ajouté − rangé) / Σ minutes', () {
    final flights = [
      testFlight(id: 'a', isClosed: true, actualFlightMinutes: 60,
          fuelStartExpected: 40, fuelStart: 40, fuelAdded: 20, fuelEnd: 45), // 15 L
      testFlight(id: 'b', isClosed: true, actualFlightMinutes: 120,
          fuelStartExpected: 45, fuelStart: 45, fuelAdded: 0, fuelEnd: 20), // 25 L
    ];
    final s = fuelStats(flights)!;
    expect(s.flights, 2);
    expect(s.minutes, 180);
    expect(s.litersPerHour, closeTo(40 / 3, 1e-9));
    expect(formatLitersPerHour(s.litersPerHour), '13,3 L/h');
  });

  test('fuelStats : vols sans carburant, non clôturés ou supprimés exclus ; null sans vol utile', () {
    expect(fuelStats([]), isNull);
    expect(fuelStats([testFlight(isClosed: true, actualFlightMinutes: 60)]), isNull);
    final counted = testFlight(id: 'ok', isClosed: true, actualFlightMinutes: 60,
        fuelStart: 30, fuelAdded: 0, fuelEnd: 18);
    final deleted = testFlight(id: 'del', isClosed: true, deleted: true, actualFlightMinutes: 60,
        fuelStart: 30, fuelAdded: 0, fuelEnd: 0);
    final open = testFlight(id: 'open', actualFlightMinutes: null,
        fuelStart: 30, fuelAdded: 0, fuelEnd: 0);
    final s = fuelStats([counted, deleted, open])!;
    expect(s.flights, 1);
    expect(s.litersPerHour, 12);
  });

  test('flightLitersPerHour : (départ + ajouté − rangé) / durée réelle', () {
    expect(flightLitersPerHour(start: 40, added: 20, end: 45, minutes: 60), 15);
    expect(flightLitersPerHour(start: 30, added: 0, end: 20, minutes: 30), 20);
    expect(flightLitersPerHour(start: 10, added: 0, end: 20, minutes: 60), -10);
  });

  test('isUnusualConsumption : alerte sous 8 L/h et au-dessus de 30 L/h, bornes acceptées', () {
    expect(isUnusualConsumption(8), isFalse);
    expect(isUnusualConsumption(30), isFalse);
    expect(isUnusualConsumption(15), isFalse);
    expect(isUnusualConsumption(7.9), isTrue);
    expect(isUnusualConsumption(30.1), isTrue);
    expect(isUnusualConsumption(-10), isTrue);
  });
}
