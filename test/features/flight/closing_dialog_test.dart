import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/pricing.dart';
import 'package:ulmgap/core/profiles.dart';
import 'package:ulmgap/features/flight/closing_dialog.dart';

/// Ouvre le dialogue depuis un bouton et rend le résultat dans [out].
Future<void> open(WidgetTester tester, List<ClosingResult?> out,
    {bool amphibious = false, int? fuelExpected = 40}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => out.add(await showDialog<ClosingResult>(
          context: context,
          builder: (_) => ClosingDialog(
            plannedMinutes: 60,
            mode: 'standard',
            category: UserCategory.gap,
            pricing: defaultPricing,
            hasPassenger: false,
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
    // après fillFuel, qui met 40 dans le départ affiché
    await tester.enterText(find.byKey(const Key('closing-fuel-start')), '25');
    await submit(tester);
    expect(out.single!.fuelStart, 25);
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
    await tester.enterText(find.byKey(const Key('closing-fuel-start')), '12');
    await submit(tester);
    expect(out.single!.fuelStartExpected, isNull);
    expect(out.single!.fuelStart, 12);
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
}
