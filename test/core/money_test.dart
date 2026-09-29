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

  test('parseAmount : entrée invalide ou décimale → null', () {
    expect(parseAmount('abc'), isNull);
    expect(parseAmount('12,5'), isNull);
    expect(parseAmount('12.5'), isNull);
    expect(parseAmount(''), isNull);
  });
}
