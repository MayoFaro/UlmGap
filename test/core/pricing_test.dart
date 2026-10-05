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
            baptismTier: c['baptismTier'] as String?,
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

  for (final c in (fx['adjustments'] as List).cast<Map<String, dynamic>>()) {
    test('régularisation : ${c['name']}', () {
      BillLeg leg(Map<String, dynamic> m) => (
            billedTo: m['billedTo'] as String?,
            payerUid: m['payerUid'] as String?,
            amount: m['amount'] as int,
          );
      final result = adjustments(
        leg(c['before'] as Map<String, dynamic>),
        leg(c['after'] as Map<String, dynamic>),
      );
      final expected = (c['expected'] as List).cast<Map<String, dynamic>>();
      expect(
        result.map((r) => {'uid': r.uid, 'amount': r.amount}).toList(),
        expected,
      );
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

  test('plan 9 : tolérance, défauts et ancien snapshot', () {
    expect(defaultPricing.includedMinutes, 60);
    expect(defaultPricing.toleranceMinutes, 75);
    expect(defaultPricing.toMap()['toleranceMinutes'], 75);
    // Ancien snapshot : includedMinutes 75, sans toleranceMinutes → ancien calcul.
    final old = Pricing.fromMap({...defaultPricing.toMap()..remove('toleranceMinutes'), 'includedMinutes': 75});
    expect(old.toleranceMinutes, 75);
    expect(computedCost('standard', 60, UserCategory.gap, old), 12000);
    // 12 000 + 12 000 × 15 / 60
    expect(computedCost('standard', 90, UserCategory.gap, old), 15000);
    // Snapshot incohérent (tolérance 75 < couvert 80) : jamais négatif.
    final odd = Pricing.fromMap({...defaultPricing.toMap()..remove('toleranceMinutes'), 'includedMinutes': 80});
    expect(computedCost('standard', 78, UserCategory.gap, odd), 12000);
  });

  test('plan 8 : crédit instruction et baptême, défauts et toMap', () {
    final p = Pricing.fromMap({});
    expect(p.instructionCredit, 20000);
    expect(p.baptismFees, {'local': 70000, 'nyonye': 90000, 'awagne': 110000});
    expect(p.toMap()['instructionCredit'], 20000);
    expect(p.toMap()['baptismFees'], {'local': 70000, 'nyonye': 90000, 'awagne': 110000});
    expect(p.toMap().containsKey('baptismFee'), isFalse);
    final q = Pricing.fromMap({
      'instructionCredit': 15000,
      'baptismFees': {'nyonye': 95000},
    });
    expect(q.instructionCredit, 15000);
    expect(q.baptismFees, {'local': 70000, 'nyonye': 95000, 'awagne': 110000});
  });

  test('Pricing.fromMap : cartes imbriquées typées Map<Object?, Object?> (Task 9)', () {
    // Reproduit une carte Firestore imbriquée non typée Map<String, dynamic>
    // (observé selon la plateforme) : le décodage ne doit pas planter.
    final nested = <Object?, Object?>{'GAP': 99000, 'GR': 30000, 'MIL': 50000, 'EXT': 70000};
    final p = Pricing.fromMap({'flatFee': nested});
    expect(p.flatFee[UserCategory.gap], 99000);
    expect(p.flatFee[UserCategory.ext], 70000);
    expect(p.overtimeHourly, defaultPricing.overtimeHourly);
  });

  test('Pricing.toMap / fromMap : aller-retour', () {
    final round = Pricing.fromMap(defaultPricing.toMap());
    expect(round.toMap(), defaultPricing.toMap());
  });
}
