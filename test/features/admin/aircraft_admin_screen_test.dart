import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/admin/aircraft_admin_screen.dart';

import '../../support/fakes.dart';

Widget host(FakeAdminApi api) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      admin: api,
      child: const MaterialApp(home: AircraftAdminScreen()),
    );

void main() {
  testWidgets('liste et création', (tester) async {
    final api = FakeAdminApi()
      ..aircraft = [
        Aircraft.fromMap('a1', {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true}),
      ];
    await tester.pumpWidget(host(api));
    await tester.pump();
    expect(find.text('ULM 1'), findsOneWidget);
    expect(find.text('F-JABC'), findsOneWidget);

    await tester.tap(find.byTooltip('Nouvel appareil'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('a-reg')), ' f-jxyz ');
    await tester.enterText(find.byKey(const Key('a-label')), 'ULM 2');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.upserted.single,
        {'registration': 'F-JXYZ', 'label': 'ULM 2', 'active': true, 'amphibious': false});
  });

  testWidgets('modification : transmet l\'id', (tester) async {
    final api = FakeAdminApi()
      ..aircraft = [
        Aircraft.fromMap('a1', {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true}),
      ];
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.text('ULM 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.upserted.single['id'], 'a1');
  });

  testWidgets('M6 : erreur et liste vide', (tester) async {
    await tester.pumpWidget(host(FakeAdminApi()..error = Exception('refus')));
    await tester.pump();
    expect(find.text('Impossible de charger les données. Vérifiez la connexion.'),
        findsOneWidget);

    await tester.pumpWidget(host(FakeAdminApi()));
    await tester.pump();
    expect(find.text('Aucun appareil.'), findsOneWidget);
  });

  testWidgets('plan 4b : appareil amphibie', (tester) async {
    final api = FakeAdminApi()
      ..aircraft = [
        Aircraft.fromMap(
            'a1', {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true, 'amphibious': true}),
      ];
    await tester.pumpWidget(host(api));
    await tester.pump();
    expect(find.text('F-JABC · amphibie'), findsOneWidget);
    await tester.tap(find.byTooltip('Nouvel appareil'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('a-reg')), 'F-JAMP');
    await tester.enterText(find.byKey(const Key('a-label')), 'ULM 3');
    await tester.tap(find.byKey(const Key('a-amphibious')));
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.upserted.single['amphibious'], isTrue);
  });
}
