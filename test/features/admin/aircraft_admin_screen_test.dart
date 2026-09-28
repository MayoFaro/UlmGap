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
    expect(api.upserted.single, {'registration': 'F-JXYZ', 'label': 'ULM 2', 'active': true});
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
}
