import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/cash.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/cash_movement.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/cash/cash_screen.dart';

import '../../support/fakes.dart';

final now = DateTime(2026, 10, 14, 10);
final instr = testUser(uid: 'ins', profile: 'instructeur', shortName: 'INS');
final adm = testUser(uid: 'adm', profile: null, isAdmin: true, shortName: 'ADM');

CashMovement line(String id, String kind, int amount, String date,
        {String? userUid, String? correctsId, String? note}) =>
    CashMovement.fromMap(id, {
      'kind': kind, 'amount': amount, 'date': date, 'userUid': userUid,
      'correctsId': correctsId, 'note': note, 'by': 'ins', 'at': DateTime(2026, 10, 14),
    });

Widget host(AppUser me, FakeCashApi cash, FakeFinanceApi finance, {FakeTankApi? tank}) =>
    AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      finance: finance,
      cash: cash,
      tank: tank,
      flights: FakeFlightApi(),
      child: MaterialApp(home: CashScreen(me: me, now: () => now)),
    );

FakeFinanceApi accounts() => FakeFinanceApi()
  ..accounts = [
    testUser(uid: 'lcm', shortName: 'LCM', balance: 70000),
    testUser(uid: 'cnl', shortName: 'CNL', balance: -20000),
  ];

void main() {
  testWidgets('en-tête : caisse, avoirs adhérents, disponible', (tester) async {
    final cash = FakeCashApi()..cashbox = const Cashbox(balance: 3638000, migrationClosedAt: null);
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    expect(find.text('Caisse : 3 638 000 FCFA'), findsOneWidget);
    expect(find.text('Avoirs adhérents : 50 000 FCFA'), findsOneWidget);
    expect(find.text('Disponible : 3 588 000 FCFA'), findsOneWidget);
  });

  testWidgets('liste du mois, titres, mention Correction, totaux ; filtre par puce', (tester) async {
    final cash = FakeCashApi()
      ..movements = [
        line('a', 'fuel_credit', 50000, '2026-10-12', userUid: 'lcm'),
        line('c', 'fuel_credit', -20000, '2026-10-12', userUid: 'lcm', correctsId: 'a', note: 'Correction'),
        line('b', 'fuel_purchase', -220000, '2026-10-12', note: 'ESSENCE'),
        line('old', 'maintenance', -1000, '2026-09-30'),
      ];
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    expect(find.text('Crédit carburant LCM'), findsNWidgets(2));
    expect(find.text('Achat carburant'), findsWidgets); // puce + ligne
    expect(find.textContaining('Correction'), findsOneWidget);
    expect(find.text('Entrées : +30 000 FCFA · Sorties : −220 000 FCFA'), findsOneWidget);
    expect(find.text('Maintenance'), findsOneWidget); // puce seulement : hors période

    await tester.tap(find.widgetWithText(FilterChip, 'Achat carburant'));
    await tester.pump();
    expect(find.text('Crédit carburant LCM'), findsNothing);
    expect(find.text('Entrées : +0 FCFA · Sorties : −220 000 FCFA'), findsOneWidget);
  });

  testWidgets('période vide : message', (tester) async {
    await tester.pumpWidget(host(instr, FakeCashApi(), accounts()));
    await tester.pump();
    expect(find.text('Aucune opération sur cette période.'), findsOneWidget);
  });

  testWidgets('+ Opération : dépense de maintenance envoyée ; écart absent pour un instructeur',
      (tester) async {
    final cash = FakeCashApi();
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    await tester.tap(find.text('Opération'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Écart de caisse'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Maintenance'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('cash-amount')), '10000');
    await tester.tap(find.text('Valider'));
    await tester.pump();
    expect(find.text('Objet obligatoire.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('cash-note')), 'Nettoyage ULM');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(cash.added.single['kind'], CashKind.maintenance);
    expect(cash.added.single['amount'], 10000);
    expect(cash.added.single['note'], 'Nettoyage ULM');
    expect(find.text('Opération enregistrée.'), findsOneWidget);
  });

  testWidgets('+ Opération : Crédit carburant passe par finance.credit avec la date', (tester) async {
    final finance = accounts();
    await tester.pumpWidget(host(instr, FakeCashApi(), finance));
    await tester.pump();
    await tester.tap(find.text('Opération'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cash-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('LCM').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cash-amount')), '20000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(finance.credited.single['uid'], 'lcm');
    expect(finance.credited.single['amount'], 20000);
    expect(finance.credited.single['date'], DateTime(2026, 10, 14));
  });

  testWidgets('appui sur une ligne : détail et correction au montant juste', (tester) async {
    final cash = FakeCashApi()
      ..movements = [line('b', 'maintenance', -86000, '2026-10-12', note: 'Roue')];
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    await tester.tap(find.textContaining('Roue').first);
    await tester.pumpAndSettle();
    expect(find.text('Montant juste : 86 000 FCFA'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('cash-correct-amount')), '68000');
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(cash.corrected.single, {'id': 'b', 'amount': 68000, 'note': null});
  });

  testWidgets('écart de caisse (admin) : montant juste gardant le signe', (tester) async {
    final cash = FakeCashApi()..movements = [line('g', 'cash_gap', -2000, '2026-10-12', note: 'Comptage')];
    await tester.pumpWidget(host(adm, cash, accounts()));
    await tester.pump();
    await tester.tap(find.textContaining('Comptage').first);
    await tester.pumpAndSettle();
    expect(find.text('Montant juste : \u22122\u00A0000\u00A0FCFA'), findsOneWidget);
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(find.text('Le montant est déjà de \u22122\u00A0000\u00A0FCFA.'), findsOneWidget);
  });

  testWidgets('écart de caisse : pas de correction pour un instructeur', (tester) async {
    final cash = FakeCashApi()..movements = [line('g', 'cash_gap', -2000, '2026-10-12', note: 'Comptage')];
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    await tester.tap(find.textContaining('Comptage').first);
    await tester.pumpAndSettle();
    expect(find.text('Corriger'), findsNothing);
  });

  testWidgets('admin : Reprise terminée avec confirmation, puis date affichée', (tester) async {
    final cash = FakeCashApi();
    await tester.pumpWidget(host(adm, cash, accounts()));
    await tester.pump();
    await tester.tap(find.text('Reprise terminée'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(cash.migrationClosings, 1);

    cash.cashbox = Cashbox(balance: 0, migrationClosedAt: DateTime(2026, 10, 20));
    await tester.pumpWidget(host(adm, cash, accounts()));
    await tester.pump();
    expect(find.text('Reprise terminée le 20/10/2026'), findsOneWidget);
  });

  testWidgets('instructeur : pas de bouton Reprise terminée', (tester) async {
    await tester.pumpWidget(host(instr, FakeCashApi(), accounts()));
    await tester.pump();
    expect(find.text('Reprise terminée'), findsNothing);
  });

  Future<void> openFuelPurchase(WidgetTester tester, FakeCashApi cash) async {
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    await tester.tap(find.text('Opération'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Achat carburant'));
    await tester.pump();
  }

  String litersText(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const Key('cash-liters'))).controller!.text;

  testWidgets('Achat carburant : « Litres » obligatoire visible pour ce type seul, envoyé',
      (tester) async {
    final cash = FakeCashApi();
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    await tester.tap(find.text('Opération'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cash-liters')), findsNothing); // Crédit carburant par défaut
    expect(find.byKey(const Key('cash-outside-tank')), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Achat carburant'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Litres'), findsOneWidget);
    expect(find.byKey(const Key('cash-outside-tank')), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('cash-outside-tank'))).value, false);
    await tester.enterText(find.byKey(const Key('cash-amount')), '220000');
    await tester.enterText(find.byKey(const Key('cash-liters')), '370');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(cash.added.single['kind'], CashKind.fuelPurchase);
    expect(cash.added.single['liters'], 370);
    expect(cash.added.single['outsideTank'], false);
  });

  testWidgets('Achat carburant : litres invalides ou vides refusés, rien envoyé', (tester) async {
    final cash = FakeCashApi();
    await openFuelPurchase(tester, cash);
    await tester.enterText(find.byKey(const Key('cash-amount')), '220000');
    await tester.enterText(find.byKey(const Key('cash-liters')), '0');
    await tester.tap(find.text('Valider'));
    await tester.pump();
    expect(find.text('Litres invalides (1 à 100 000).'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('cash-liters')), '');
    await tester.tap(find.text('Valider'));
    await tester.pump();
    expect(find.text('Litres obligatoires pour un achat de carburant (ou cochez « Hors cuve »).'),
        findsOneWidget);
    expect(cash.added, isEmpty);
  });

  testWidgets('montant 595 000 : litres calculés 1000 et prix au litre affiché', (tester) async {
    await openFuelPurchase(tester, FakeCashApi());
    await tester.enterText(find.byKey(const Key('cash-amount')), '595000');
    await tester.pump();
    expect(litersText(tester), '1000');
    expect(find.text('Prix au litre : 595 FCFA/L'), findsOneWidget);
  });

  testWidgets('litres modifiés par l\'utilisateur : le calcul automatique s\'arrête', (tester) async {
    await openFuelPurchase(tester, FakeCashApi());
    await tester.enterText(find.byKey(const Key('cash-amount')), '595000');
    await tester.enterText(find.byKey(const Key('cash-liters')), '900');
    await tester.enterText(find.byKey(const Key('cash-amount')), '600000');
    await tester.pump();
    expect(litersText(tester), '900');
  });

  testWidgets('1000 L pour 595 000 : aucune fenêtre, envoyé', (tester) async {
    final cash = FakeCashApi();
    await openFuelPurchase(tester, cash);
    await tester.enterText(find.byKey(const Key('cash-amount')), '595000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Prix au litre inhabituel'), findsNothing);
    expect(cash.added.single['liters'], 1000);
  });

  testWidgets('700 L pour 595 000 : fenêtre ; Corriger n\'envoie rien, Confirmer envoie', (tester) async {
    final cash = FakeCashApi();
    await openFuelPurchase(tester, cash);
    await tester.enterText(find.byKey(const Key('cash-amount')), '595000');
    await tester.enterText(find.byKey(const Key('cash-liters')), '700');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Prix au litre inhabituel'), findsOneWidget);
    expect(find.text('Prix au litre : 850 FCFA/L (référence : 595 FCFA/L). Confirmer l\'opération ?'),
        findsOneWidget);
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(cash.added, isEmpty);
    expect(find.text('Nouvelle opération'), findsOneWidget);
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(cash.added.single['liters'], 700);
  });

  testWidgets('bornes : 5 % pile sans fenêtre, au-delà avec fenêtre', (tester) async {
    final cash = FakeCashApi();
    await openFuelPurchase(tester, cash);
    await tester.enterText(find.byKey(const Key('cash-amount')), '624750'); // 595 × 1,05
    await tester.enterText(find.byKey(const Key('cash-liters')), '1000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Prix au litre inhabituel'), findsNothing);
    expect(cash.added.single['liters'], 1000);

    final cash2 = FakeCashApi();
    await openFuelPurchase(tester, cash2);
    await tester.enterText(find.byKey(const Key('cash-amount')), '624751');
    await tester.enterText(find.byKey(const Key('cash-liters')), '1000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Prix au litre inhabituel'), findsOneWidget);
    expect(cash2.added, isEmpty);
  });

  testWidgets('« Hors cuve » : pas de champ litres, envoi sans litres ni contrôle', (tester) async {
    final cash = FakeCashApi();
    await openFuelPurchase(tester, cash);
    await tester.tap(find.byKey(const Key('cash-outside-tank')));
    await tester.pump();
    expect(find.byKey(const Key('cash-liters')), findsNothing);
    await tester.enterText(find.byKey(const Key('cash-amount')), '12345');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Prix au litre inhabituel'), findsNothing);
    expect(cash.added.single['liters'], isNull);
    expect(cash.added.single['outsideTank'], true);
  });

  testWidgets('litres saisis puis type changé : non envoyés', (tester) async {
    final cash = FakeCashApi();
    await tester.pumpWidget(host(instr, cash, accounts()));
    await tester.pump();
    await tester.tap(find.text('Opération'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Achat carburant'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('cash-liters')), '200');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Maintenance'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('cash-amount')), '10000');
    await tester.enterText(find.byKey(const Key('cash-note')), 'Roue');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(cash.added.single['liters'], isNull);
  });

  testWidgets('ligne « Cuve : 180 L » ; appui → Suivi cuve', (tester) async {
    await tester.pumpWidget(host(instr, FakeCashApi(), accounts(), tank: FakeTankApi()..level = 180));
    await tester.pump();
    expect(find.text('Cuve : 180 L'), findsOneWidget);
    await tester.tap(find.text('Cuve : 180 L'));
    await tester.pumpAndSettle();
    expect(find.text('Suivi cuve'), findsOneWidget);
  });

  testWidgets('niveau de cuve négatif : affiché en orange', (tester) async {
    await tester.pumpWidget(host(instr, FakeCashApi(), accounts(), tank: FakeTankApi()..level = -12));
    await tester.pump();
    final t = tester.widget<Text>(find.text('Cuve : \u221212 L'));
    expect(t.style?.color, Colors.orange.shade800);
  });
}
