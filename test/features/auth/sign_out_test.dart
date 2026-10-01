import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/account/account_screen.dart';
import 'package:ulmgap/features/auth/no_access_screen.dart';
import 'package:ulmgap/features/auth/verify_email_screen.dart';

import '../../support/fakes.dart';

Widget host(Widget home, FakeAuthService auth, FakeUserRepository users, FakePushService push) =>
    AppServices(
      auth: auth,
      users: users,
      push: push,
      finance: FakeFinanceApi(),
      flights: FakeFlightApi(),
      child: MaterialApp(home: home),
    );

void main() {
  testWidgets('hors ligne (écriture sans réponse) : la déconnexion aboutit quand même',
      (tester) async {
    final auth = FakeAuthService();
    final users = FakeUserRepository()..saveHangs = true;
    final push = FakePushService();
    await tester.pumpWidget(host(AccountScreen(me: testUser(uid: 'u1')), auth, users, push));
    await tester.pump();
    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pump(const Duration(seconds: 5));
    expect(users.savedTokens, [(uid: 'u1', token: null)]);
    expect(push.deleteCalls, 1);
    expect(auth.calls, contains('signOut'));
  });

  testWidgets('écran sans accès : jeton de l\'appareil supprimé avant signOut', (tester) async {
    final auth = FakeAuthService();
    final push = FakePushService();
    await tester.pumpWidget(host(const NoAccessScreen(), auth, FakeUserRepository(), push));
    await tester.tap(find.text('Se déconnecter'));
    await tester.pump(const Duration(seconds: 1));
    expect(push.deleteCalls, 1);
    expect(auth.calls, contains('signOut'));
  });

  testWidgets('vérification d\'e-mail : jeton de l\'appareil supprimé avant signOut',
      (tester) async {
    final auth = FakeAuthService();
    final push = FakePushService();
    await tester.pumpWidget(
        host(const VerifyEmailScreen(email: 'a@b.fr'), auth, FakeUserRepository(), push));
    await tester.tap(find.text('Se déconnecter'));
    await tester.pump(const Duration(seconds: 1));
    expect(push.deleteCalls, 1);
    expect(auth.calls, contains('signOut'));
  });
}
