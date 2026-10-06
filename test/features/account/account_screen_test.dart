import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/money.dart';
import 'package:ulmgap/core/profiles.dart';
import 'package:ulmgap/data/account_movement.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/account/account_screen.dart';

import '../../support/fakes.dart';

AppUser _user({required int balance}) => AppUser(
      uid: 'u1',
      displayName: 'Jean Dupont',
      shortName: 'JDU',
      email: 'jdu@ulmgap.invalid',
      profile: PilotProfile.eleve,
      category: UserCategory.gap,
      isAdmin: false,
      active: true,
      balance: balance,
    );

Widget host(FakeFinanceApi finance, AppUser me,
        {FakeUserRepository? users, FakeFlightApi? flights}) =>
    AppServices(
      auth: FakeAuthService(),
      users: users ?? FakeUserRepository(),
      flights: flights,
      finance: finance,
      child: MaterialApp(home: AccountScreen(me: me)),
    );

void main() {
  testWidgets('en-tête (nom, badge, appartenance, solde) et mouvements formatés',
      (tester) async {
    final me = _user(balance: -3000);
    final finance = FakeFinanceApi()
      ..movements['u1'] = [
        AccountMovement(
          id: 'm1',
          userUid: 'u1',
          amount: -15000,
          type: 'flight',
          reason: 'Vol',
          flightId: 'f1',
          by: 'u1',
          at: DateTime(2026, 10, 13, 9, 5),
          balanceAfter: -3000,
        ),
        AccountMovement(
          id: 'm2',
          userUid: 'u1',
          amount: 12000,
          type: 'credit',
          reason: 'Versement caisse',
          flightId: null,
          by: 'admin1',
          at: DateTime(2026, 10, 10, 8),
          balanceAfter: 12000,
        ),
      ];
    await tester.pumpWidget(host(finance, me));
    await tester.pump();

    expect(find.text('Jean Dupont'), findsOneWidget);
    expect(find.text(PilotProfile.eleve.label), findsOneWidget); // badge
    expect(find.text('GAP'), findsOneWidget); // appartenance
    final soldeLabel = 'Solde : ${formatFcfa(-3000)}';
    expect(find.text(soldeLabel), findsOneWidget);

    // Le solde est affiché en rouge (négatif).
    final soldeText = tester.widget<Text>(find.text(soldeLabel));
    final errorColor = Theme.of(tester.element(find.byType(AccountScreen))).colorScheme.error;
    expect(soldeText.style?.color, errorColor);

    // Mouvements : type, raison, montant signé, solde après.
    // Sans FlightApi, le vol n'est pas identifié ; la raison « Vol » égale
    // au libellé n'est pas répétée.
    expect(find.text('Vol'), findsOneWidget);
    expect(find.text('Crédit — Versement caisse'), findsOneWidget);
    expect(find.text(formatFcfa(-15000)), findsOneWidget);
    expect(find.text('+${formatFcfa(12000)}'), findsOneWidget);
    expect(find.textContaining('Solde : ${formatFcfa(-3000)}'), findsWidgets);
    expect(find.textContaining('Solde : ${formatFcfa(12000)}'), findsOneWidget);
  });

  testWidgets('solde positif affiché sans la couleur d\'erreur', (tester) async {
    final me = _user(balance: 5000);
    await tester.pumpWidget(host(FakeFinanceApi(), me));
    await tester.pump();
    final soldeLabel = 'Solde : ${formatFcfa(5000)}';
    final soldeText = tester.widget<Text>(find.text(soldeLabel));
    final errorColor = Theme.of(tester.element(find.byType(AccountScreen))).colorScheme.error;
    expect(soldeText.style?.color, isNot(errorColor));
  });

  testWidgets('aucun mouvement : message vide', (tester) async {
    final me = _user(balance: 0);
    await tester.pumpWidget(host(FakeFinanceApi(), me));
    await tester.pump();
    expect(find.text('Aucun mouvement.'), findsOneWidget);
  });

  // Fix round 1 (revue de la Task 11) : le solde de l'en-tête doit suivre le
  // flux utilisateur en direct (watchUser), pas rester figé sur l'AppUser
  // passé à la navigation.
  testWidgets('solde en direct : mis à jour après un événement de watchUser',
      (tester) async {
    final me = _user(balance: 0);
    final users = FakeUserRepository()..live = StreamController<AppUser?>();
    await tester.pumpWidget(host(FakeFinanceApi(), me, users: users));
    await tester.pump();
    expect(find.text('Solde : ${formatFcfa(0)}'), findsOneWidget);

    users.live!.add(_user(balance: 20000));
    await tester.pump();
    expect(find.text('Solde : ${formatFcfa(20000)}'), findsOneWidget);
    expect(find.text('Solde : ${formatFcfa(0)}'), findsNothing);
  });

  testWidgets('mouvements liés à un vol : date du vol, raison égale au libellé omise',
      (tester) async {
    final me = _user(balance: 0);
    AccountMovement move(String id, String type, String reason, int amount) => AccountMovement(
          id: id,
          userUid: 'u1',
          amount: amount,
          type: type,
          reason: reason,
          flightId: 'f1',
          by: 'u1',
          at: DateTime(2026, 10, 14, 9),
          balanceAfter: 0,
        );
    final finance = FakeFinanceApi()
      ..movements['u1'] = [
        move('m1', 'flight', 'Vol', -15000),
        move('m2', 'flight_adjustment', 'Régularisation', -6000),
        move('m3', 'flight_adjustment', 'Annulation du vol', 21000),
        move('m4', 'instruction', 'Crédit instruction', 20000),
        move('m5', 'instruction', 'Régularisation crédit instruction', -20000),
      ];
    final flights = FakeFlightApi()..flights = [testFlight(id: 'f1', start: DateTime(2026, 10, 12, 9))];
    await tester.pumpWidget(host(finance, me, flights: flights));
    await tester.pumpAndSettle();

    expect(find.text('Vol du lundi 12 octobre'), findsOneWidget);
    expect(find.text('Régularisation — vol du lundi 12 octobre'), findsOneWidget);
    expect(find.text('Régularisation — vol du lundi 12 octobre — Annulation du vol'), findsOneWidget);
    expect(find.text('Crédit instruction — vol du lundi 12 octobre'), findsOneWidget);
    expect(find.text('Régularisation crédit instruction — vol du lundi 12 octobre'), findsOneWidget);
  });

  testWidgets('Se déconnecter : revient à la racine puis déconnecte', (tester) async {
    final auth = FakeAuthService();
    final me = _user(balance: 0);
    await tester.pumpWidget(AppServices(
      auth: auth,
      users: FakeUserRepository(),
      finance: FakeFinanceApi(),
      flights: FakeFlightApi(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AccountScreen(me: me)),
            ),
            child: const Text('racine'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('racine'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(auth.calls, contains('signOut'));
    expect(find.byType(AccountScreen), findsNothing);
  });

  testWidgets('plan 10 : « Lâché amphibie » affiché seulement pour un compte lâché amphibie',
      (tester) async {
    await tester.pumpWidget(host(FakeFinanceApi(), testUser(amphibiousCleared: true)));
    await tester.pump();
    expect(find.text('Lâché amphibie'), findsOneWidget);

    await tester.pumpWidget(host(FakeFinanceApi(), testUser()));
    await tester.pump();
    expect(find.text('Lâché amphibie'), findsNothing);
  });
}
