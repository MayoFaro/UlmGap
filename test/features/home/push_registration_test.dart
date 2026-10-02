import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/account/account_screen.dart';
import 'package:ulmgap/features/home/push_registration.dart';

import '../../support/fakes.dart';

Widget host(FakeUserRepository users, FakePushService? push, {String uid = 'u1', FakeAuthService? auth}) =>
    AppServices(
      auth: auth ?? FakeAuthService(),
      users: users,
      push: push,
      child: MaterialApp(
        home: PushRegistration(uid: uid, child: const Scaffold(body: Text('accueil'))),
      ),
    );

void main() {
  testWidgets('compte prêt : jeton enregistré une seule fois, même après reconstruction',
      (tester) async {
    final users = FakeUserRepository();
    final push = FakePushService();
    await tester.pumpWidget(host(users, push));
    await tester.pump();
    await tester.pumpWidget(host(users, push)); // reconstruction (même uid)
    await tester.pump();
    expect(users.savedTokens, [(uid: 'u1', token: 'tok-1')]);
    expect(push.tokenCalls, 1);
  });

  testWidgets('nouveau jeton : enregistré', (tester) async {
    final users = FakeUserRepository();
    final push = FakePushService();
    await tester.pumpWidget(host(users, push));
    await tester.pump();
    push.refreshCtrl.add('tok-2');
    await tester.pump();
    expect(users.savedTokens.last, (uid: 'u1', token: 'tok-2'));
  });

  testWidgets('permission refusée ou web sans clé (jeton null) : rien n\'est écrit', (tester) async {
    final users = FakeUserRepository();
    final push = FakePushService()..nextToken = null;
    await tester.pumpWidget(host(users, push));
    await tester.pump();
    expect(users.savedTokens, isEmpty);
    expect(find.text('accueil'), findsOneWidget);
  });

  testWidgets('erreur à l\'obtention du jeton : rien n\'est écrit, l\'accueil s\'affiche',
      (tester) async {
    final users = FakeUserRepository();
    final push = FakePushService()..tokenError = Exception('messaging/unsupported');
    await tester.pumpWidget(host(users, push));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(users.savedTokens, isEmpty);
    expect(find.text('accueil'), findsOneWidget);
  });

  testWidgets('message reçu app ouverte : SnackBar « titre : corps »', (tester) async {
    final push = FakePushService();
    await tester.pumpWidget(host(FakeUserRepository(), push));
    await tester.pump();
    push.messagesCtrl.add((title: 'Vol validé', body: 'LDX, lundi 12 octobre'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // animation de la SnackBar
    expect(find.text('Vol validé : LDX, lundi 12 octobre'), findsOneWidget);
  });

  testWidgets('sans service de notifications (tests existants) : rien ne change', (tester) async {
    final users = FakeUserRepository();
    await tester.pumpWidget(host(users, null));
    await tester.pump();
    expect(users.savedTokens, isEmpty);
    expect(find.text('accueil'), findsOneWidget);
  });

  testWidgets('déconnexion depuis Mon compte : jeton effacé avant signOut', (tester) async {
    final users = FakeUserRepository();
    final push = FakePushService();
    final auth = FakeAuthService();
    await tester.pumpWidget(AppServices(
      auth: auth,
      users: users,
      push: push,
      finance: FakeFinanceApi(),
      flights: FakeFlightApi(),
      child: MaterialApp(home: AccountScreen(me: testUser(uid: 'u1'))),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(users.savedTokens, [(uid: 'u1', token: null)]);
    expect(push.deleteCalls, 1);
    expect(auth.calls, contains('signOut'));
  });
}
