import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/money.dart';

void main() {
  test('formatFcfa : groupes de 3 chiffres, espace insécable, signe négatif', () {
    expect(formatFcfa(0), '0 FCFA');
    expect(formatFcfa(500), '500 FCFA');
    expect(formatFcfa(12000), '12 000 FCFA');
    expect(formatFcfa(1234567), '1 234 567 FCFA');
    expect(formatFcfa(-3000), '−' '3 000 FCFA');
  });

  test('parseAmount : espaces (normales et insécables) acceptées', () {
    expect(parseAmount('12 000'), 12000);
    expect(parseAmount('12 000'), 12000);
    expect(parseAmount('12000'), 12000);
  });

  test('parseAmount : signe négatif accepté (montant signé d’une correction)', () {
    expect(parseAmount('-5000'), -5000);
    expect(parseAmount('-5 000'), -5000);
  });

  test('parseAmount : entrée invalide ou décimale → null', () {
    expect(parseAmount('abc'), isNull);
    expect(parseAmount('12,5'), isNull);
    expect(parseAmount('12.5'), isNull);
    expect(parseAmount(''), isNull);
  });

  test('formatAmountInput : groupes de 3 chiffres, sans unité', () {
    expect(formatAmountInput(40000), '40\u00a0000');
    expect(formatAmountInput(1250000), '1\u00a0250\u00a0000');
    expect(formatAmountInput(-5000), '-5\u00a0000');
    expect(formatAmountInput(0), '0');
  });

  test('AmountInputFormatter : regroupe à la saisie, garde le signe', () {
    String fmt(String typed) => const AmountInputFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: typed))
        .text;
    expect(fmt('40000'), '40\u00a0000');
    expect(fmt('350 0000'), '3\u00a0500\u00a0000');
    expect(fmt('-5000'), '-5\u00a0000');
    expect(fmt('12a3'), '123');
    expect(fmt(''), '');
    expect(fmt('-'), '-');
    expect(parseAmount(fmt('40000')), 40000);
  });
}
