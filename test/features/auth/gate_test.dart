import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/auth_service.dart';
import 'package:ulmgap/features/auth/gate.dart';

import '../../support/fakes.dart';

void main() {
  const verified = AuthSnapshot(uid: 'u1', email: 'a@b.fr', emailVerified: true);
  const unverified = AuthSnapshot(uid: 'u1', email: 'a@b.fr', emailVerified: false);

  test('non connecté', () => expect(gateFor(null, null), GateState.signedOut));
  test('e-mail non vérifié, même avec un compte actif', () {
    expect(gateFor(unverified, testUser()), GateState.emailUnverified);
  });
  test('pas de document users', () => expect(gateFor(verified, null), GateState.noAccess));
  test('compte désactivé', () {
    expect(gateFor(verified, testUser(active: false)), GateState.noAccess);
  });
  test('compte actif et vérifié', () => expect(gateFor(verified, testUser()), GateState.ready));
  test('authErrorMessage : codes connus et inconnus', () {
    expect(authErrorMessage('wrong-password'), 'E-mail ou mot de passe incorrect.');
    expect(authErrorMessage('invalid-credential'), 'E-mail ou mot de passe incorrect.');
    expect(authErrorMessage('user-disabled'), 'Ce compte est désactivé.');
    expect(authErrorMessage('xyz'), 'Connexion impossible (xyz).');
  });
}
