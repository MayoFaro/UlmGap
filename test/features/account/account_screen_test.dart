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

Widget host(FakeFinanceApi finance, AppUser me) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
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
    expect(find.text('Vol — Vol'), findsOneWidget);
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
}
