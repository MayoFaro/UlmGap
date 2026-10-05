import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/pricing.dart';
import 'package:ulmgap/core/profiles.dart';
import 'package:ulmgap/features/flight/closing_dialog.dart';

/// Ouvre le dialogue depuis un bouton et rend le résultat dans [out].
Future<void> open(WidgetTester tester, List<ClosingResult?> out,
    {bool amphibious = false,
    int? fuelExpected = 40,
    String mode = 'standard',
    int plannedMinutes = 60,
    UserCategory? category = UserCategory.gap,
    bool hasPassenger = false}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => out.add(await showDialog<ClosingResult>(
          context: context,
          builder: (_) => ClosingDialog(
            plannedMinutes: plannedMinutes,
            mode: mode,
            category: category,
            pricing: defaultPricing,
            hasPassenger: hasPassenger,
            amphibious: amphibious,
            fuelExpected: fuelExpected,
          ),
        )),
        child: const Text('ouvrir'),
      ),
    ),
  ));
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

/// Remplit les champs carburant obligatoires (et le départ s'il est affiché).
Future<void> fillFuel(WidgetTester tester, {String added = '0', String end = '30'}) async {
  final start = find.byKey(const Key('closing-fuel-start'));
  if (start.evaluate().isNotEmpty) await tester.enterText(start, '40');
  await tester.enterText(find.byKey(const Key('closing-fuel-added')), added);
  await tester.enterText(find.byKey(const Key('closing-fuel-end')), end);
}

Future<void> submit(WidgetTester tester) async {
  await tester.tap(find.text('Clôturer'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('appareil classique : 1 atterrissage pré-rempli, pas d\'amerrissages',
      (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    expect(tester.widget<TextField>(find.byKey(const Key('closing-landings'))).controller!.text, '1');
    expect(find.byKey(const Key('closing-water-landings')), findsNothing);
    await fillFuel(tester);
    await submit(tester);
    expect(out.single!.landings, 1);
    expect(out.single!.waterLandings, 0);
  });

  testWidgets('appareil amphibie : amerrissages pré-remplis à 0 et transmis', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, amphibious: true);
    expect(tester.widget<TextField>(find.byKey(const Key('closing-water-landings'))).controller!.text,
        '0');
    await tester.enterText(find.byKey(const Key('closing-landings')), '0');
    await tester.enterText(find.byKey(const Key('closing-water-landings')), '3');
    await fillFuel(tester);
    await submit(tester);
    expect(out.single!.landings, 0);
    expect(out.single!.waterLandings, 3);
  });

  testWidgets('total nul : refusé', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, amphibious: true);
    await tester.enterText(find.byKey(const Key('closing-landings')), '0');
    await submit(tester);
    expect(find.text('Au moins un atterrissage ou amerrissage.'), findsOneWidget);
    expect(out, isEmpty);
  });

  testWidgets('hors plage : refusé', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, amphibious: true);
    await tester.enterText(find.byKey(const Key('closing-landings')), '100');
    await submit(tester);
    expect(find.text('Nombre d\'atterrissages invalide (0 à 99).'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('closing-landings')), '1');
    await tester.enterText(find.byKey(const Key('closing-water-landings')), '');
    await submit(tester);
    expect(find.text('Nombre d\'amerrissages invalide (0 à 99).'), findsOneWidget);
    expect(out, isEmpty);
  });

  testWidgets('carburant connu : prévu affiché, départ = prévu si la case n\'est pas cochée',
      (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, fuelExpected: 40);
    expect(find.text('Carburant prévu au départ : 40 L'), findsOneWidget);
    expect(find.byKey(const Key('closing-fuel-start')), findsNothing);
    await fillFuel(tester, added: '20', end: '45');
    await submit(tester);
    final r = out.single!;
    expect([r.fuelStartExpected, r.fuelStart, r.fuelAdded, r.fuelEnd], [40, 40, 20, 45]);
  });

  testWidgets('non conforme : départ corrigé transmis', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, fuelExpected: 40);
    await tester.tap(find.byKey(const Key('closing-fuel-gap')));
    await tester.pumpAndSettle();
    await fillFuel(tester);
    // après fillFuel, qui met 40 dans le départ affiché ; 45 − 30 = 15 L/h,
    // consommation habituelle (pas d'alerte)
    await tester.enterText(find.byKey(const Key('closing-fuel-start')), '45');
    await submit(tester);
    expect(out.single!.fuelStart, 45);
    expect(out.single!.fuelStartExpected, 40);
  });

  testWidgets('non conforme cochée puis décochée : départ = prévu', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, fuelExpected: 40);
    await tester.tap(find.byKey(const Key('closing-fuel-gap')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('closing-fuel-start')), '25');
    await tester.tap(find.byKey(const Key('closing-fuel-gap')));
    await tester.pumpAndSettle();
    await fillFuel(tester);
    await submit(tester);
    expect(out.single!.fuelStart, 40);
  });

  testWidgets('carburant inconnu : pas de case, départ obligatoire', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, fuelExpected: null);
    expect(find.text('Carburant prévu au départ : inconnu'), findsOneWidget);
    expect(find.byKey(const Key('closing-fuel-gap')), findsNothing);
    await tester.enterText(find.byKey(const Key('closing-fuel-added')), '0');
    await tester.enterText(find.byKey(const Key('closing-fuel-end')), '30');
    await submit(tester);
    expect(find.text('Carburant au départ invalide (0 à 100 L).'), findsOneWidget);
    expect(out, isEmpty);
    await tester.enterText(find.byKey(const Key('closing-fuel-start')), '42');
    await submit(tester);
    expect(out.single!.fuelStartExpected, isNull);
    expect(out.single!.fuelStart, 42);
  });

  testWidgets('ajouté et rangé vides : refusés ; plus de 100 L : refusé', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    await submit(tester);
    expect(find.text('Carburant ajouté invalide (0 à 100 L).'), findsOneWidget);
    await fillFuel(tester, end: '101');
    await submit(tester);
    expect(find.text('Carburant rangé invalide (0 à 100 L).'), findsOneWidget);
    expect(out, isEmpty);
  });

  // 60 min prévues (durée réelle pré-remplie), 40 L prévus au départ.
  testWidgets('consommation habituelle (10 L/h) : pas d\'alerte, clôture directe', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    await fillFuel(tester, added: '0', end: '30');
    await submit(tester);
    expect(find.text('Consommation inhabituelle'), findsNothing);
    expect(out.single!.fuelEnd, 30);
  });

  testWidgets('consommation inhabituelle (40 L/h) : alerte, « Corriger » garde le dialogue',
      (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    await fillFuel(tester, added: '0', end: '0');
    await submit(tester);
    expect(find.text('Consommation inhabituelle'), findsOneWidget);
    expect(find.text('Consommation calculée : 40,0 L/h. Vérifiez les valeurs saisies.'),
        findsOneWidget);
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(find.text('Consommation inhabituelle'), findsNothing);
    expect(find.text('Clôturer le vol'), findsOneWidget);
    expect(out, isEmpty);
    await tester.enterText(find.byKey(const Key('closing-fuel-end')), '28');
    await submit(tester);
    expect(out.single!.fuelEnd, 28);
  });

  testWidgets('consommation inhabituelle (négative) : « Confirmer » clôture quand même',
      (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    await fillFuel(tester, added: '0', end: '50');
    await submit(tester);
    expect(find.text('Consommation calculée : -10,0 L/h. Vérifiez les valeurs saisies.'),
        findsOneWidget);
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(out.single!.fuelEnd, 50);
    expect(find.text('Clôturer le vol'), findsNothing);
  });

  testWidgets('baptême de 20 min : montant fixe hors app, aucun champ de montant', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out,
        mode: 'baptism', plannedMinutes: 20, hasPassenger: true, category: null);
    expect(find.byKey(const Key('closing-short-amount')), findsNothing);
    expect(find.byKey(const Key('closing-custom-check')), findsNothing);
    expect(find.text('Montant : 70\u00a0000\u00a0FCFA facturé hors app'), findsOneWidget);
    await fillFuel(tester);
    await submit(tester);
    expect(out.single, isNotNull);
    expect(out.single!.actualMinutes, 20);
    expect(out.single!.shortFlightAmount, isNull);
    expect(out.single!.customAmount, isNull);
  });

  testWidgets('clôture d\'un vol d\'instruction : aucune mention de l\'instruction', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    expect(find.textContaining('nstruction'), findsNothing);
  });
}
