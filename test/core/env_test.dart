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
}
