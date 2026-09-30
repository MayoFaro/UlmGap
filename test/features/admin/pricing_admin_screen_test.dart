import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    expect(fieldText(tester, 'flatFee-GAP'), '12000');
    expect(fieldText(tester, 'flatFee-GR'), '30000');
    expect(fieldText(tester, 'flatFee-MIL'), '50000');
    expect(fieldText(tester, 'flatFee-EXT'), '70000');
    expect(fieldText(tester, 'overtime-GAP'), '12000');
    expect(fieldText(tester, 'overtime-MIL'), '30000');
    expect(fieldText(tester, 'includedMinutes'), '75');
    expect(fieldText(tester, 'minPlannedMinutes'), '45');
    expect(fieldText(tester, 'fuelHourlyRate'), '12000');
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
}
