import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/auth/login_screen.dart';

import '../../support/fakes.dart';

Widget host(FakeAuthService auth) => AppServices(
      auth: auth,
      users: FakeUserRepository(),
      child: const MaterialApp(home: LoginScreen()),
    );

void main() {
  testWidgets('connexion : appelle signIn avec l\'e-mail nettoyé', (tester) async {
    final auth = FakeAuthService();
    await tester.pumpWidget(host(auth));
    await tester.enterText(find.byKey(const Key('email')), ' jean@club.fr ');
    await tester.enterText(find.byKey(const Key('password')), 'secret');
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    expect(auth.calls, ['signIn:jean@club.fr']);
  });

  testWidgets('échec : message affiché', (tester) async {
    final auth = FakeAuthService()..failWith = 'E-mail ou mot de passe incorrect.';
    await tester.pumpWidget(host(auth));
    await tester.enterText(find.byKey(const Key('email')), 'jean@club.fr');
    await tester.enterText(find.byKey(const Key('password')), 'x');
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    expect(find.text('E-mail ou mot de passe incorrect.'), findsOneWidget);
  });

  testWidgets('mot de passe oublié sans e-mail : invite à le saisir', (tester) async {
    final auth = FakeAuthService();
    await tester.pumpWidget(host(auth));
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pump();
    expect(find.text('Saisissez d\'abord votre e-mail.'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('mot de passe oublié : envoie le lien', (tester) async {
    final auth = FakeAuthService();
    await tester.pumpWidget(host(auth));
    await tester.enterText(find.byKey(const Key('email')), 'jean@club.fr');
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pump();
    expect(auth.calls, ['reset:jean@club.fr']);
    expect(find.textContaining('Lien envoyé'), findsOneWidget);
  });
}
