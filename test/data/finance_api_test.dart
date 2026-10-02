import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/pricing.dart';
import 'package:ulmgap/core/profiles.dart';
import 'package:ulmgap/data/account_movement.dart';
import 'package:ulmgap/data/finance_api.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/data/flight_api.dart';

void main() {
  test('AccountMovement.fromMap : champs du contrat', () {
    final at = DateTime(2026, 10, 13, 9);
    final m = AccountMovement.fromMap('m1', {
      'userUid': 'u1',
      'amount': -15000,
      'type': 'flight',
      'reason': 'Vol',
      'flightId': 'f1',
      'by': 'u1',
      'at': at,
      'balanceAfter': 35000,
    });
    expect(m.id, 'm1');
    expect(m.userUid, 'u1');
    expect(m.amount, -15000);
    expect(m.type, 'flight');
    expect(m.reason, 'Vol');
    expect(m.flightId, 'f1');
    expect(m.by, 'u1');
    expect(m.at, at);
    expect(m.balanceAfter, 35000);
  });

  test('AccountMovement.fromMap : reason et flightId absents (crédit)', () {
    final m = AccountMovement.fromMap('m2', {
      'userUid': 'u1',
      'amount': 500000,
      'type': 'credit',
      'by': 'system',
      'at': DateTime(2026, 9, 1),
      'balanceAfter': 500000,
    });
    expect(m.reason, isNull);
    expect(m.flightId, isNull);
  });

  Map<String, dynamic> baseFlight() => {
        'start': DateTime(2026, 10, 13, 9),
        'end': DateTime(2026, 10, 13, 10),
        'destination': 'Lomé',
        'aircraftId': 'a1',
        'aircraft': 'F-JABC',
        'crew': ['u1'],
        'passengers': <String>[],
        'status': 'valide',
        'createdBy': 'u1',
        'pricingMode': 'standard',
        'isClosed': false,
        'deleted': false,
      };

  test('Flight.fromMap : champs financiers absents → null', () {
    final f = Flight.fromMap('f1', baseFlight());
    expect(f.payerUidField, isNull);
    expect(f.pricingSnapshot, isNull);
    expect(f.actualFlightMinutes, isNull);
    expect(f.billedAmount, isNull);
    expect(f.billedTo, isNull);
    expect(f.customAmount, isNull);
    expect(f.shortFlightAmount, isNull);
    expect(f.closedBy, isNull);
    expect(f.closedAt, isNull);
  });

  test('Flight.fromMap : vol clôturé, champs financiers décodés', () {
    final closedAt = DateTime(2026, 10, 13, 11);
    final f = Flight.fromMap('f1', {
      ...baseFlight(),
      'isClosed': true,
      'payerUid': 'u1',
      'pricingSnapshot': defaultPricing.toMap(),
      'actualFlightMinutes': 90,
      'billedAmount': 15000,
      'billedTo': 'account',
      'customAmount': null,
      'shortFlightAmount': null,
      'closedBy': 'u1',
      'closedAt': closedAt,
    });
    expect(f.payerUidField, 'u1');
    expect(f.pricingSnapshot, isNotNull);
    expect(f.pricingSnapshot!.flatFee[UserCategory.gap], 12000);
    expect(f.actualFlightMinutes, 90);
    expect(f.billedAmount, 15000);
    expect(f.billedTo, 'account');
    expect(f.customAmount, isNull);
    expect(f.shortFlightAmount, isNull);
    expect(f.closedBy, 'u1');
    expect(f.closedAt, closedAt);
  });

  test('Flight.fromMap : vol facturé hors app avec montant différent', () {
    final f = Flight.fromMap('f1', {
      ...baseFlight(),
      'isClosed': true,
      'billedAmount': 50000,
      'billedTo': 'off_app',
      'customAmount': 50000,
      'pricingMode': 'custom',
    });
    expect(f.billedTo, 'off_app');
    expect(f.customAmount, 50000);
    expect(f.pricingMode, 'custom');
  });

  test('financeFailureFrom : refus du serveur → FlightFailure avec son message', () {
    for (final code in ['invalid-argument', 'failed-precondition', 'permission-denied', 'not-found']) {
      final f = financeFailureFrom(code, 'Compte introuvable.', null);
      expect(f, isA<FlightFailure>(), reason: code);
      expect(f!.message, 'Compte introuvable.');
    }
  });

  test('financeFailureFrom : issue incertaine (réseau, délai, interne) → null', () {
    for (final code in ['unavailable', 'deadline-exceeded', 'internal', 'unknown', 'cancelled']) {
      expect(financeFailureFrom(code, 'x', null), isNull, reason: code);
    }
  });
}
