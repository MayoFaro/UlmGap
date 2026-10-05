import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/money.dart';
import 'package:ulmgap/core/pricing.dart';
import 'package:ulmgap/core/profiles.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/admin/pricing_admin_screen.dart';

import '../../support/fakes.dart';

Widget host(FakeFinanceApi api) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      finance: api,
      child: const MaterialApp(home: PricingAdminScreen()),
    );

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

/// La liste de tarifs dépasse la hauteur par défaut du banc de test : on
/// agrandit la fenêtre pour que tous les champs soient construits (sinon un
/// `ListView` ne matérialise que les éléments visibles).
void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('préremplit les champs depuis watchPricing', (tester) async {
    _useTallView(tester);
    final api = FakeFinanceApi()..pricing = defaultPricing;
    await tester.pumpWidget(host(api));
    await tester.pump();

    expect(fieldText(tester, 'flatFee-GAP'), '12\u00a0000');
    expect(fieldText(tester, 'flatFee-GR'), '30\u00a0000');
    expect(fieldText(tester, 'flatFee-MIL'), '50\u00a0000');
    expect(fieldText(tester, 'flatFee-EXT'), '70\u00a0000');
    expect(fieldText(tester, 'overtime-GAP'), '12\u00a0000');
    expect(fieldText(tester, 'overtime-MIL'), '30\u00a0000');
    expect(fieldText(tester, 'includedMinutes'), '60');
    expect(fieldText(tester, 'toleranceMinutes'), '75');
    expect(fieldText(tester, 'minPlannedMinutes'), '45');
    expect(fieldText(tester, 'fuelHourlyRate'), '12\u00a0000');
  });

  testWidgets('Enregistrer envoie les nouvelles valeurs et confirme par une SnackBar',
      (tester) async {
    _useTallView(tester);
    final api = FakeFinanceApi()..pricing = defaultPricing;
    await tester.pumpWidget(host(api));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('flatFee-GAP')), '13000');
    await tester.enterText(find.byKey(const Key('fuelHourlyRate')), '15000');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    final sent = api.updatedPricing;
    expect(sent, isNotNull);
    expect(sent!.flatFee[UserCategory.gap], 13000);
    expect(sent.flatFee[UserCategory.ext], 70000); // inchangé
    expect(sent.fuelHourlyRate, 15000);
    expect(find.text('Tarifs enregistrés.'), findsOneWidget);
  });

  testWidgets('erreur serveur : la SnackBar affiche le message', (tester) async {
    _useTallView(tester);
    final api = FakeFinanceApi()
      ..pricing = defaultPricing
      ..failWith = Exception('refus serveur');
    await tester.pumpWidget(host(api));
    await tester.pump();

    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.textContaining('refus serveur'), findsOneWidget);
  });

  testWidgets('minutes : 0 refusé localement (1 au minimum, comme le serveur)', (tester) async {
    _useTallView(tester);
    final api = FakeFinanceApi()..pricing = defaultPricing;
    await tester.pumpWidget(host(api));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('includedMinutes')), '0');
    await tester.enterText(find.byKey(const Key('minPlannedMinutes')), '0');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(api.updatedPricing, isNull);
    expect(find.text('Entre 1 et 600 min.'), findsNWidgets(2));
  });

  testWidgets('montants : plus de 1 000 000 refusé localement (comme le serveur)',
      (tester) async {
    _useTallView(tester);
    final api = FakeFinanceApi()..pricing = defaultPricing;
    await tester.pumpWidget(host(api));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('flatFee-EXT')), '1000001');
    await tester.enterText(find.byKey(const Key('fuelHourlyRate')), '1000001');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(api.updatedPricing, isNull);
    expect(find.text('Entre 0 et ${formatFcfa(1000000)}.'), findsNWidgets(2));
  });

  testWidgets('crédit instruction et baptême : préremplis, modifiés et enregistrés', (tester) async {
    _useTallView(tester);
    final api = FakeFinanceApi()..pricing = defaultPricing;
    await tester.pumpWidget(host(api));
    await tester.pump();

    expect(fieldText(tester, 'instructionCredit'), '20\u00a0000');
    expect(fieldText(tester, 'baptismFee'), '70\u00a0000');
    expect(find.text('Crédit instruction (FCFA)'), findsOneWidget);
    expect(find.text('Baptême de l\'air (FCFA)'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('instructionCredit')), '25000');
    await tester.enterText(find.byKey(const Key('baptismFee')), '80000');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(api.updatedPricing!.instructionCredit, 25000);
    expect(api.updatedPricing!.baptismFees['local'], 80000);
  });

  testWidgets('Enregistrer envoie la tolérance modifiée', (tester) async {
    _useTallView(tester);
    final api = FakeFinanceApi()..pricing = defaultPricing;
    await tester.pumpWidget(host(api));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('toleranceMinutes')), '80');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(api.updatedPricing!.toleranceMinutes, 80);
  });

  testWidgets('tolérance inférieure au temps couvert refusée', (tester) async {
    _useTallView(tester);
    final api = FakeFinanceApi()..pricing = defaultPricing;
    await tester.pumpWidget(host(api));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('toleranceMinutes')), '50');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.text('La tolérance doit être au moins égale au temps couvert.'), findsOneWidget);
    expect(api.updatedPricing, isNull);
  });

  testWidgets('valeur personnalisée conservée en modifiant un autre champ', (tester) async {
    _useTallView(tester);
    final api = FakeFinanceApi()
      ..pricing = Pricing(
        flatFee: defaultPricing.flatFee,
        includedMinutes: defaultPricing.includedMinutes,
        minPlannedMinutes: defaultPricing.minPlannedMinutes,
        overtimeHourly: defaultPricing.overtimeHourly,
        fuelHourlyRate: defaultPricing.fuelHourlyRate,
        instructionCredit: 15000,
        baptismFees: const {'local': 65000, 'nyonye': 90000, 'awagne': 110000},
      );
    await tester.pumpWidget(host(api));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('fuelHourlyRate')), '15000');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(api.updatedPricing!.fuelHourlyRate, 15000);
    expect(api.updatedPricing!.instructionCredit, 15000);
    expect(api.updatedPricing!.baptismFees['local'], 65000);
  });
}
