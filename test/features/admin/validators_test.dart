import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/features/admin/validators.dart';

void main() {
  test('validateEmail', () {
    expect(validateEmail('jean@club.fr'), isNull);
    expect(validateEmail(' jean@club.fr '), isNull);
    expect(validateEmail('jean'), 'E-mail invalide.');
  });
  test('validateShortName : 2 à 4 lettres ou chiffres', () {
    expect(validateShortName('jdu'), isNull);
    expect(validateShortName('J'), isNotNull);
    expect(validateShortName('JDUPO'), isNotNull);
    expect(validateShortName('J-D'), isNotNull);
  });
  test('validateRequired', () {
    expect(validateRequired(' ', 'Nom'), 'Nom obligatoire.');
    expect(validateRequired('x', 'Nom'), isNull);
  });
}
