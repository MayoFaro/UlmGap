import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/user_repository.dart';

void main() {
  test('C1 : une erreur de lecture devient null (pas d\'accès), pas un silence', () async {
    final src = StreamController<String?>();
    final out = <String?>[];
    final sub = nullOnError(src.stream).listen(out.add);
    src.add('actif');
    src.addError(Exception('permission-denied'));
    await Future<void>.delayed(Duration.zero);
    expect(out, ['actif', null]);
    await sub.cancel();
  });
}
