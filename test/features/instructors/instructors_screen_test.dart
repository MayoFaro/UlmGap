import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/money.dart';
import 'package:ulmgap/core/profiles.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/instructors/instructors_screen.dart';

import '../../support/fakes.dart';

AppUser _account(String uid, String name, {required int balance}) => AppUser(
      uid: uid,
      displayName: name,
      shortName: name.substring(0, 3).toUpperCase(),
      email: '$uid@ulmgap.invalid',
      profile: PilotProfile.eleve,
      category: UserCategory.gap,
      isAdmin: false,
      active: true,
      balance: balance,
    );

Widget host(FakeFinanceApi finance) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      finance: finance,
      child: const MaterialApp(home: InstructorsScreen()),
    );

void main() {
  testWidgets('liste des comptes avec solde', (tester) async {
    final finance = FakeFinanceApi()
      ..accounts = [
        _account('u1', 'Jean Dupont', balance: -3000),
        _account('u2', 'Alice Martin', balance: 5000),
      ];
    await tester.pumpWidget(host(finance));
    await tester.pump();
    expect(find.text('Jean Dupont'), findsOneWidget);
    expect(find.text('Alice Martin'), findsOneWidget);
    expect(find.text(formatFcfa(-3000)), findsOneWidget);
    expect(find.text(formatFcfa(5000)), findsOneWidget);
  });

  testWidgets('aucun compte : message vide', (tester) async {
    await tester.pumpWidget(host(FakeFinanceApi()));
    await tester.pump();
    expect(find.text('Aucun compte.'), findsOneWidget);
  });

  testWidgets('appui sur un compte : historique et bouton Créditer / corriger',
      (tester) async {
    final finance = FakeFinanceApi()..accounts = [_account('u1', 'Jean Dupont', balance: 0)];
    await tester.pumpWidget(host(finance));
    await tester.pump();
    await tester.tap(find.text('Jean Dupont'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun mouvement.'), findsOneWidget); // MovementsList vide
    expect(find.text('Créditer / corriger'), findsOneWidget);
  });

  testWidgets('crédit : appel avec le bon montant et SnackBar', (tester) async {
    final finance = FakeFinanceApi()
      ..accounts = [_account('u1', 'Jean Dupont', balance: 0)]
      ..balance = 12000;
    await tester.pumpWidget(host(finance));
    await tester.pump();
    await tester.tap(find.text('Jean Dupont'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créditer / corriger'));
    await tester.pumpAndSettle();

    // Mode « Créditer » est le mode par défaut.
    await tester.enterText(find.byKey(const Key('credit-amount')), '12000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    expect(finance.credited.single, {'uid': 'u1', 'amount': 12000, 'reason': null});
    expect(find.text('Nouveau solde : ${formatFcfa(12000)}'), findsOneWidget);
  });

  testWidgets('correction sans motif : bloquée', (tester) async {
    final finance = FakeFinanceApi()..accounts = [_account('u1', 'Jean Dupont', balance: 0)];
    await tester.pumpWidget(host(finance));
    await tester.pump();
    await tester.tap(find.text('Jean Dupont'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créditer / corriger'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Corriger'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('credit-amount')), '-5000');
    await tester.tap(find.text('Valider'));
    await tester.pump();

    expect(finance.corrected, isEmpty);
    expect(find.text('Motif obligatoire pour une correction.'), findsOneWidget);
    // Le dialogue reste ouvert.
    expect(find.byKey(const Key('credit-amount')), findsOneWidget);
  });

  testWidgets('1 000 000 accepté (aucun plafond)', (tester) async {
    final finance = FakeFinanceApi()
      ..accounts = [_account('u1', 'Jean Dupont', balance: 0)]
      ..balance = 1000000;
    await tester.pumpWidget(host(finance));
    await tester.pump();
    await tester.tap(find.text('Jean Dupont'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créditer / corriger'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('credit-amount')), '1000000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    expect(finance.credited.single['amount'], 1000000);
    expect(find.text('Nouveau solde : ${formatFcfa(1000000)}'), findsOneWidget);
  });

  testWidgets('correction avec motif : appel avec le montant signé', (tester) async {
    final finance = FakeFinanceApi()
      ..accounts = [_account('u1', 'Jean Dupont', balance: 10000)]
      ..balance = 0;
    await tester.pumpWidget(host(finance));
    await tester.pump();
    await tester.tap(find.text('Jean Dupont'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créditer / corriger'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Corriger'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('credit-amount')), '-10000');
    await tester.enterText(find.byKey(const Key('credit-reason')), 'Erreur de saisie');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    expect(finance.corrected.single,
        {'uid': 'u1', 'amount': -10000, 'reason': 'Erreur de saisie'});
    expect(find.text('Nouveau solde : ${formatFcfa(0)}'), findsOneWidget);
  });
}
