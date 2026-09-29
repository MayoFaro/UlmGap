import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/pricing.dart';
import 'package:ulmgap/core/profiles.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/pricing_cases.json').readAsStringSync())
      as Map<String, dynamic>;

  for (final c in (fx['cost'] as List).cast<Map<String, dynamic>>()) {
    test('coût : ${c['name']}', () {
      final result = computedCost(
        c['mode'] as String,
        c['minutes'] as int,
        UserCategory.fromCode(c['category'] as String),
        defaultPricing,
      );
      expect(result, c['expected']);
    });
  }

  for (final c in (fx['closing'] as List).cast<Map<String, dynamic>>()) {
    test('clôture : ${c['name']}', () {
      ClosingBill call() => closingBill(
            mode: c['mode'] as String,
            actualMinutes: c['actualMinutes'] as int,
            category: UserCategory.fromCode(c['category'] as String),
            pricing: defaultPricing,
            shortFlightAmount: c['shortFlightAmount'] as int?,
            customAmount: c['customAmount'] as int?,
            hasPassenger: c['hasPassenger'] as bool,
          );
      final expectedError = c['expectedError'] as String?;
      if (expectedError != null) {
        expect(
          call,
          throwsA(isA<ArgumentError>()
              .having((e) => e.message, 'message', expectedError)),
        );
      } else {
        final expected = c['expected'] as Map<String, dynamic>;
        final r = call();
        expect(r.billedAmount, expected['billedAmount']);
        expect(r.billedTo, expected['billedTo']);
        expect(r.pricingMode, expected['pricingMode']);
      }
    });
  }

  test('estimatedCost : jamais null pour une durée prévue suffisante', () {
    expect(estimatedCost('standard', 60, UserCategory.gap, defaultPricing), 12000);
    expect(estimatedCost('fuel_only', 60, UserCategory.gap, defaultPricing), 12000);
  });

  test('availableCredit : solde moins le coût estimé des autres vols', () {
    expect(availableCredit(100000, [30000, 20000]), 50000);
    expect(availableCredit(100000, []), 100000);
  });

  test('Pricing.fromMap : document absent ou champs absents → défauts', () {
    expect(Pricing.fromMap(null).toMap(), defaultPricing.toMap());
    final p = Pricing.fromMap({'includedMinutes': 90});
    expect(p.includedMinutes, 90);
    expect(p.minPlannedMinutes, defaultPricing.minPlannedMinutes);
    expect(p.flatFee[UserCategory.gap], defaultPricing.flatFee[UserCategory.gap]);
  });

  test('Pricing.toMap / fromMap : aller-retour', () {
    final round = Pricing.fromMap(defaultPricing.toMap());
    expect(round.toMap(), defaultPricing.toMap());
  });
}
