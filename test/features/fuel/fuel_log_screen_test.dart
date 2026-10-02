import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/fuel/fuel_log_screen.dart';

import '../../support/fakes.dart';

void main() {
  final me = testUser();
  FakeFlightApi seeded() => FakeFlightApi()
    ..directory = [member('u1', 'JDU', 'eleve')]
    ..aircraft = [
      Aircraft.fromMap('a1', {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true, 'fuelLiters': 20}),
    ]
    ..flights = [
      testFlight(id: 'old', start: DateTime(2026, 10, 1, 9), isClosed: true, actualFlightMinutes: 60,
          fuelStartExpected: 40, fuelStart: 40, fuelAdded: 20, fuelEnd: 45),
      testFlight(id: 'new', start: DateTime(2026, 10, 2, 9), isClosed: true, actualFlightMinutes: 120,
          fuelStartExpected: 45, fuelStart: 30, fuelAdded: 0, fuelEnd: 20),
      testFlight(id: 'legacy', start: DateTime(2026, 9, 1, 9), isClosed: true, actualFlightMinutes: 60),
      testFlight(id: 'other', aircraftId: 'a2', isClosed: true, actualFlightMinutes: 60,
          fuelStart: 1, fuelAdded: 1, fuelEnd: 1),
    ];

  Widget host(FakeFlightApi api) => AppServices(
        auth: FakeAuthService(), users: FakeUserRepository(), flights: api,
        child: MaterialApp(home: FuelLogScreen(me: me, aircraftId: 'a1')),
      );

  testWidgets('titre, carburant actuel, consommation, vols du plus récent au plus ancien',
      (tester) async {
    await tester.pumpWidget(host(seeded()));
    await tester.pumpAndSettle();
    expect(find.text('Suivi carburant · F-JABC'), findsOneWidget);
    expect(find.text('Carburant actuel : 20 L'), findsOneWidget);
    // (40+20-45) + (30+0-20) = 25 L sur 3 h
    expect(find.text('Consommation estimée : 8,3 L/h (2 vols, 3 h 00)'), findsOneWidget);
    final lines = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();
    final iNew = lines.indexWhere((l) => l.contains('Départ 30 L'));
    final iOld = lines.indexWhere((l) => l.contains('Départ 40 L'));
    expect(iNew, lessThan(iOld));
    expect(find.text('Écart au départ : prévu 45 L, réel 30 L'), findsOneWidget);
    expect(find.textContaining('Départ 1 L'), findsNothing); // autre appareil
  });

  testWidgets('aucun vol avec carburant : consommation masquée', (tester) async {
    await tester.pumpWidget(host(seeded()..flights = []));
    await tester.pumpAndSettle();
    expect(find.textContaining('Consommation estimée'), findsNothing);
    expect(find.text('Aucun vol avec carburant.'), findsOneWidget);
  });
}
