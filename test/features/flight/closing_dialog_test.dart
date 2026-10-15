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
    String? baptismTier,
    bool hasPassenger = false,
    Map<String, String> crewNames = const {'u1': 'JDU', 'ins': 'INS'},
    String closerUid = 'ins',
    int fuelLiterPrice = 595}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => out.add(await showDialog<ClosingResult>(
          context: context,
          builder: (_) => ClosingDialog(
            plannedMinutes: plannedMinutes,
            mode: mode,
            baptismTier: baptismTier,
            category: category,
            pricing: defaultPricing,
            hasPassenger: hasPassenger,
            amphibious: amphibious,
            fuelExpected: fuelExpected,
            crewNames: crewNames,
            closerUid: closerUid,
            fuelLiterPrice: fuelLiterPrice,
          ),
        )),
        child: const Text('ouvrir'),
      ),
    ),
  ));
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

/// Remplit les champs carburant obligatoires (et le départ s'il est affiché) ;
/// [added] non nul : pris à la cuve.
Future<void> fillFuel(WidgetTester tester, {String added = '0', String end = '30'}) async {
  final start = find.byKey(const Key('closing-fuel-start'));
  if (start.evaluate().isNotEmpty) await tester.enterText(start, '40');
  if (added != '0') {
    await chooseSource(tester, 'Depuis la cuve');
    await tester.enterText(find.byKey(const Key('fuel-tank')), added);
  }
  await tester.enterText(find.byKey(const Key('closing-fuel-end')), end);
}

Future<void> chooseSource(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
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
    await tester.enterText(find.byKey(const Key('closing-fuel-end')), '30');
    await submit(tester);
    expect(find.text('Carburant au départ invalide (0 à 100 L).'), findsOneWidget);
    expect(out, isEmpty);
    await tester.enterText(find.byKey(const Key('closing-fuel-start')), '42');
    await submit(tester);
    expect(out.single!.fuelStartExpected, isNull);
    expect(out.single!.fuelStart, 42);
  });

  testWidgets('rangé vide refusé ; plus de 100 L : refusé', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    await submit(tester);
    expect(find.text('Carburant rangé invalide (0 à 100 L).'), findsOneWidget);
    await fillFuel(tester, end: '101');
    await submit(tester);
    expect(find.text('Carburant rangé invalide (0 à 100 L).'), findsOneWidget);
    expect(out, isEmpty);
  });

  // --- plan 13 : provenance du carburant ajouté ---

  testWidgets('« Aucun » par défaut : aucun champ de litres, rien d\'ajouté', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    expect(find.text('Carburant ajouté'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Aucun')).selected, isTrue);
    expect(find.byKey(const Key('fuel-tank')), findsNothing);
    expect(find.byKey(const Key('fuel-personal')), findsNothing);
    expect(find.byKey(const Key('fuel-supplier')), findsNothing);
    await fillFuel(tester);
    await submit(tester);
    final r = out.single!;
    expect([r.fuelFromTank, r.fuelFromPersonal, r.fuelSupplierUid, r.fuelAdded], [0, 0, null, 0]);
  });

  testWidgets('« Depuis la cuve » : litres pris à la cuve seulement', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    await chooseSource(tester, 'Depuis la cuve');
    expect(find.widgetWithText(TextField, 'Litres pris à la cuve'), findsOneWidget);
    expect(find.byKey(const Key('fuel-personal')), findsNothing);
    expect(find.byKey(const Key('fuel-supplier')), findsNothing);
    await tester.enterText(find.byKey(const Key('fuel-tank')), '20');
    await tester.pump();
    expect(find.text('Carburant ajouté : 20 L'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('closing-fuel-end')), '45');
    await submit(tester);
    final r = out.single!;
    expect([r.fuelFromTank, r.fuelFromPersonal, r.fuelSupplierUid, r.fuelAdded], [20, 0, null, 20]);
  });

  testWidgets('« Bidon perso » : pilote par défaut = celui qui clôture, ligne de crédit',
      (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    await chooseSource(tester, 'Bidon perso');
    expect(find.byKey(const Key('fuel-tank')), findsNothing);
    expect(find.widgetWithText(TextField, 'Litres du bidon perso'), findsOneWidget);
    expect(find.text('Pilote ayant fourni le carburant'), findsOneWidget);
    expect(tester.widget<DropdownButtonFormField<String>>(find.byKey(const Key('fuel-supplier')))
        .initialValue, 'ins');
    await tester.enterText(find.byKey(const Key('fuel-personal')), '20');
    await tester.pump();
    expect(find.text('Crédit : 20 L × 595 = 11\u00a0900\u00a0FCFA pour INS'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('closing-fuel-end')), '45');
    await submit(tester);
    final r = out.single!;
    expect([r.fuelFromTank, r.fuelFromPersonal, r.fuelSupplierUid, r.fuelAdded], [0, 20, 'ins', 20]);
  });

  testWidgets('« Bidon perso » : celui qui clôture hors équipage → premier équipier ; '
      'autre pilote choisi ; prix du litre courant', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, closerUid: 'adm', fuelLiterPrice: 650);
    await chooseSource(tester, 'Bidon perso');
    expect(tester.widget<DropdownButtonFormField<String>>(find.byKey(const Key('fuel-supplier')))
        .initialValue, 'u1');
    await tester.enterText(find.byKey(const Key('fuel-personal')), '10');
    await tester.pump();
    expect(find.text('Crédit : 10 L × 650 = 6\u00a0500\u00a0FCFA pour JDU'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fuel-supplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('INS').last);
    await tester.pumpAndSettle();
    expect(find.text('Crédit : 10 L × 650 = 6\u00a0500\u00a0FCFA pour INS'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('closing-fuel-end')), '40');
    await submit(tester);
    expect(out.single!.fuelSupplierUid, 'ins');
  });

  testWidgets('« Bidon perso » sans équipier connu : pilote exigé', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, crewNames: const {});
    await chooseSource(tester, 'Bidon perso');
    await tester.enterText(find.byKey(const Key('fuel-personal')), '10');
    await tester.enterText(find.byKey(const Key('closing-fuel-end')), '40');
    await submit(tester);
    expect(find.text('Choisissez le pilote qui a fourni le carburant.'), findsOneWidget);
    expect(out, isEmpty);
  });

  testWidgets('« Les deux » : total affiché, plus de 100 L au total refusé, payload',
      (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    await chooseSource(tester, 'Les deux');
    await tester.enterText(find.byKey(const Key('fuel-tank')), '60');
    await tester.enterText(find.byKey(const Key('fuel-personal')), '50');
    await tester.pump();
    expect(find.text('Carburant ajouté : 110 L'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('closing-fuel-end')), '45');
    await submit(tester);
    expect(find.text('Carburant ajouté : 100 L au maximum au total.'), findsOneWidget);
    expect(out, isEmpty);
    await tester.enterText(find.byKey(const Key('fuel-tank')), '10');
    await tester.enterText(find.byKey(const Key('fuel-personal')), '10');
    await submit(tester);
    final r = out.single!;
    expect([r.fuelFromTank, r.fuelFromPersonal, r.fuelSupplierUid, r.fuelAdded], [10, 10, 'ins', 20]);
  });

  testWidgets('litres vides ou nuls refusés (1 à 100)', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    await chooseSource(tester, 'Les deux');
    await tester.enterText(find.byKey(const Key('closing-fuel-end')), '30');
    await tester.enterText(find.byKey(const Key('fuel-tank')), '0');
    await submit(tester);
    expect(find.text('Litres pris à la cuve invalides (1 à 100 L).'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('fuel-tank')), '5');
    await submit(tester);
    expect(find.text('Litres du bidon perso invalides (1 à 100 L).'), findsOneWidget);
    expect(out, isEmpty);
  });

  testWidgets('« Les deux » puis « Aucun » : litres saisis ignorés', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    await chooseSource(tester, 'Les deux');
    await tester.enterText(find.byKey(const Key('fuel-tank')), '10');
    await tester.enterText(find.byKey(const Key('fuel-personal')), '10');
    await chooseSource(tester, 'Aucun');
    await fillFuel(tester);
    await submit(tester);
    final r = out.single!;
    expect([r.fuelFromTank, r.fuelFromPersonal, r.fuelSupplierUid], [0, 0, null]);
  });

  testWidgets('alerte de consommation calculée sur le total ajouté', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    // 40 + 10 + 10 − 20 = 40 L en 60 min : 40 L/h.
    await chooseSource(tester, 'Les deux');
    await tester.enterText(find.byKey(const Key('fuel-tank')), '10');
    await tester.enterText(find.byKey(const Key('fuel-personal')), '10');
    await tester.enterText(find.byKey(const Key('closing-fuel-end')), '20');
    await submit(tester);
    expect(find.text('Consommation calculée : 40,0 L/h. Vérifiez les valeurs saisies.'),
        findsOneWidget);
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
        mode: 'baptism',
        baptismTier: 'local',
        plannedMinutes: 20,
        hasPassenger: true,
        category: null);
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

  testWidgets('baptême Nyonye : montant du forfait facturé hors app', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out,
        mode: 'baptism',
        baptismTier: 'nyonye',
        plannedMinutes: 20,
        hasPassenger: true,
        category: null);
    expect(find.text('Montant : 90\u00a0000\u00a0FCFA facturé hors app'), findsOneWidget);
  });

  testWidgets('clôture d\'un vol d\'instruction : aucune mention de l\'instruction', (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out);
    expect(find.textContaining('nstruction'), findsNothing);
  });

  testWidgets('vol technique de 30 min avec passager : aucun montant, non facturé (association)',
      (tester) async {
    final out = <ClosingResult?>[];
    await open(tester, out, mode: 'technical', hasPassenger: true);
    await tester.enterText(find.byKey(const Key('closing-minutes')), '30');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('closing-short-amount')), findsNothing);
    expect(find.text('Montant à facturer'), findsNothing);
    expect(find.byKey(const Key('closing-custom-check')), findsNothing);
    expect(find.text('Montant différent (facturé hors app)'), findsNothing);
    expect(find.text('Vol technique : non facturé (association)'), findsOneWidget);
    await fillFuel(tester, end: '35'); // 5 L en 30 min : 10 L/h, pas d'alerte
    await submit(tester);
    expect(out.single!.actualMinutes, 30);
    expect(out.single!.shortFlightAmount, isNull);
    expect(out.single!.customAmount, isNull);
  });
}
