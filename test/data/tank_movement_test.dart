import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/tank_movement.dart';

void main() {
  test('TankMovement.fromMap : champs du contrat', () {
    final at = DateTime(2026, 10, 14, 9);
    final m = TankMovement.fromMap('t1', {
      'kind': 'flight',
      'liters': -25,
      'date': '2026-10-14',
      'flightId': 'f1',
      'aircraftId': 'a1',
      'cashMovementId': 'c1',
      'measuredLiters': 180,
      'technical': true,
      'note': 'x',
      'by': 'u1',
      'at': at,
      'litersAfter': 155,
    });
    expect(m.id, 't1');
    expect(m.kind, TankKind.flight);
    expect(m.liters, -25);
    expect(m.date, '2026-10-14');
    expect(m.day, DateTime(2026, 10, 14));
    expect([m.flightId, m.aircraftId, m.cashMovementId], ['f1', 'a1', 'c1']);
    expect(m.measuredLiters, 180);
    expect(m.technical, isTrue);
    expect(m.note, 'x');
    expect(m.by, 'u1');
    expect(m.at, at);
    expect(m.litersAfter, 155);
  });

  test('TankMovement.fromMap : champs optionnels absents', () {
    final m = TankMovement.fromMap('t2', {'kind': 'refill', 'liters': 200, 'date': '2026-10-01'});
    expect(m.technical, isFalse);
    expect([m.flightId, m.aircraftId, m.cashMovementId, m.measuredLiters, m.note], [null, null, null, null, null]);
  });

  test('libellés de cuve', () {
    expect(TankKind.refill.label, 'Remplissage');
    expect(TankKind.flight.label, 'Vol');
    expect(TankKind.aircraftFill.label, 'Plein hors vol');
    expect(TankKind.gauge.label, 'Relevé de jauge');
    expect(TankKind.flightAdjustment.label, 'Régularisation');
    expect(TankKind.fromCode('aircraft_fill'), TankKind.aircraftFill);
    expect(TankKind.fromCode('zzz'), isNull);
    expect(TankMovement.fromMap('t', {'kind': 'gauge'}).kind, TankKind.gauge);
  });
}
