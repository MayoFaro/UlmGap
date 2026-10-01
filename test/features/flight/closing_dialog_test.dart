import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/pricing.dart';
import 'package:ulmgap/core/profiles.dart';
import 'package:ulmgap/features/flight/closing_dialog.dart';

/// Ouvre le dialogue depuis un bouton et rend le résultat dans [out].
Future<void> open(WidgetTester tester, List<ClosingResult?> out, {bool amphibious = false}) async {
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
          ),
        )),
        child: const Text('ouvrir'),
      ),
    ),
  ));
  await tester.tap(find.text('ouvrir'));
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
}
