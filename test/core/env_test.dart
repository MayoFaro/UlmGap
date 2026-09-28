import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/env.dart';

void main() {
  test('prod seulement si ENV=prod (casse et espaces ignorés)', () {
    expect(parseEnv('prod'), AppEnv.prod);
    expect(parseEnv(' PROD '), AppEnv.prod);
  });
  test('tout le reste → dev (défaut sûr)', () {
    expect(parseEnv('dev'), AppEnv.dev);
    expect(parseEnv(''), AppEnv.dev);
    expect(parseEnv('production'), AppEnv.dev);
  });
  test('M9 : flavor et ENV concordants ou flavor absent → aucun blocage', () {
    expect(flavorMismatch(AppEnv.dev, 'dev'), isNull);
    expect(flavorMismatch(AppEnv.prod, 'prod'), isNull);
    expect(flavorMismatch(AppEnv.dev, null), isNull); // web
  });
  test('M9 : flavor et ENV discordants → message', () {
    expect(flavorMismatch(AppEnv.dev, 'prod'),
        'Build incohérent : flavor « prod » mais ENV=dev. '
        'Recompiler avec --flavor prod --dart-define=ENV=prod.');
    expect(flavorMismatch(AppEnv.prod, 'dev'), isNotNull);
  });
}
