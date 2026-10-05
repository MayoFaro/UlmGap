import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/flight/flight_screen.dart';
import 'package:ulmgap/features/fuel/fuel_log_screen.dart';

import '../../support/fakes.dart';

void main() {
  final me = testUser();
  final now = DateTime(2026, 10, 15, 12);

  // Octobre (période par défaut) : old, new, legacy ; hors période : sep ;
  // exclus : open (non clôturé), other (autre appareil).
  FakeFlightApi seeded({bool waterLanding = true}) => FakeFlightApi()
    ..directory = [member('u1', 'JDU', 'eleve')]
    ..aircraft = [
      Aircraft.fromMap('a1', {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true, 'fuelLiters': 20}),
    ]
    ..flights = [
      testFlight(id: 'old', start: DateTime(2026, 10, 1, 9), isClosed: true, actualFlightMinutes: 60,
          fuelStartExpected: 40, fuelStart: 40, fuelAdded: 20, fuelEnd: 45, landings: 2),
      testFlight(id: 'new', start: DateTime(2026, 10, 2, 9), isClosed: true, actualFlightMinutes: 120,
          fuelStartExpected: 45, fuelStart: 30, fuelAdded: 0, fuelEnd: 20,
          landings: 1, waterLandings: waterLanding ? 1 : 0),
      testFlight(id: 'legacy', start: DateTime(2026, 10, 3, 9), isClosed: true, actualFlightMinutes: 45),
      testFlight(id: 'sep', start: DateTime(2026, 9, 20, 9), isClosed: true, actualFlightMinutes: 60,
          fuelStartExpected: 30, fuelStart: 30, fuelAdded: 0, fuelEnd: 18, landings: 1),
      testFlight(id: 'open', start: DateTime(2026, 10, 4, 9), fuelStart: 1, fuelAdded: 1, fuelEnd: 1),
      testFlight(id: 'other', aircraftId: 'a2', start: DateTime(2026, 10, 5, 9), isClosed: true,
          actualFlightMinutes: 60, fuelStart: 1, fuelAdded: 1, fuelEnd: 1),
    ];

  Widget host(FakeFlightApi api) => AppServices(
        auth: FakeAuthService(), users: FakeUserRepository(), flights: api,
        child: MaterialApp(home: FuelLogScreen(me: me, aircraftId: 'a1', now: () => now)),
      );

  String cell(WidgetTester tester, String id, String col) =>
      tester.widget<Text>(find.byKey(Key('fuel-$id-$col'))).data!;

  testWidgets('en-tête : titre, carburant actuel, consommation estimée (tous les vols)',
      (tester) async {
    await tester.pumpWidget(host(seeded()));
    await tester.pumpAndSettle();
    expect(find.text('Suivi carburant · F-JABC'), findsOneWidget);
    expect(find.text('Carburant actuel : 20 L'), findsOneWidget);
    // 15 + 10 + 12 = 37 L sur 4 h
    expect(find.text('Consommation estimée : 9,3 L/h (3 vols, 4 h 00)'), findsOneWidget);
  });

  testWidgets('tableau : vols clôturés de la période, du plus récent au plus ancien',
      (tester) async {
    await tester.pumpWidget(host(seeded()));
    await tester.pumpAndSettle();
    for (final id in ['old', 'new', 'legacy']) {
      expect(find.byKey(Key('fuel-$id-date')), findsOneWidget, reason: id);
    }
    for (final id in ['sep', 'open', 'other']) {
      expect(find.byKey(Key('fuel-$id-date')), findsNothing, reason: id);
    }
    double y(String id) => tester.getTopLeft(find.byKey(Key('fuel-$id-date'))).dy;
    expect(y('legacy'), lessThan(y('new')));
    expect(y('new'), lessThan(y('old')));
  });

  testWidgets('ligne : temps, carburant, conso par vol, atterrissages', (tester) async {
    await tester.pumpWidget(host(seeded()));
    await tester.pumpAndSettle();
    expect(cell(tester, 'old', 'date'), '01/10/2026');
    expect(cell(tester, 'old', 'crew'), 'JDU');
    expect(cell(tester, 'old', 'time'), '1 h 00');
    expect(cell(tester, 'old', 'start'), '40');
    expect(cell(tester, 'old', 'added'), '20');
    expect(cell(tester, 'old', 'end'), '45');
    expect(cell(tester, 'old', 'used'), '15');
    expect(cell(tester, 'old', 'rate'), '15,0');
    expect(cell(tester, 'old', 'landings'), '2');
    expect(cell(tester, 'old', 'water'), '0');
  });

  testWidgets('ajout mis en évidence ; rien d\'ajouté : case vide', (tester) async {
    await tester.pumpWidget(host(seeded()));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('fuel-old-added'))).style?.fontWeight,
        FontWeight.bold);
    expect(find.byKey(const Key('fuel-old-added-mark')), findsOneWidget);
    expect(cell(tester, 'new', 'added'), '');
    expect(find.byKey(const Key('fuel-new-added-mark')), findsNothing);
  });

  testWidgets('écart au départ et conso inhabituelle en orange', (tester) async {
    await tester.pumpWidget(host(seeded()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fuel-new-start-gap')), findsOneWidget);
    expect(find.byTooltip('Prévu : 45 L'), findsOneWidget);
    expect(find.byKey(const Key('fuel-old-start-gap')), findsNothing);
    expect(cell(tester, 'new', 'rate'), '5,0');
    expect(tester.widget<Text>(find.byKey(const Key('fuel-new-rate'))).style?.color,
        fuelWarningColor);
    expect(tester.widget<Text>(find.byKey(const Key('fuel-old-rate'))).style?.color,
        isNot(fuelWarningColor));
  });

  testWidgets('vol d\'avant le suivi carburant : temps de vol, « — » pour le carburant',
      (tester) async {
    await tester.pumpWidget(host(seeded()));
    await tester.pumpAndSettle();
    expect(cell(tester, 'legacy', 'time'), '0 h 45');
    for (final col in ['start', 'added', 'end', 'used', 'rate', 'landings']) {
      expect(cell(tester, 'legacy', col), '—', reason: col);
    }
  });

  testWidgets('totaux de la période', (tester) async {
    await tester.pumpWidget(host(seeded()));
    await tester.pumpAndSettle();
    expect(cell(tester, 'total', 'time'), '3 h 45');
    expect(cell(tester, 'total', 'added'), '20');
    expect(cell(tester, 'total', 'used'), '25');
    expect(cell(tester, 'total', 'rate'), '8,3'); // 25 L sur 3 h (vols avec carburant)
    expect(cell(tester, 'total', 'landings'), '3');
    expect(cell(tester, 'total', 'water'), '1');
  });

  testWidgets('colonne Am. : absente sans amerrissage sur un appareil non amphibie',
      (tester) async {
    await tester.pumpWidget(host(seeded(waterLanding: false)));
    await tester.pumpAndSettle();
    expect(find.text('Am.'), findsNothing);
    expect(find.byKey(const Key('fuel-old-water')), findsNothing);
  });

  testWidgets('période : septembre affiche ses vols seulement', (tester) async {
    await tester.pumpWidget(host(seeded()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('month-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Septembre').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fuel-sep-date')), findsOneWidget);
    expect(find.byKey(const Key('fuel-old-date')), findsNothing);
    expect(cell(tester, 'total', 'used'), '12');
  });

  testWidgets('aucun vol clôturé sur la période : message', (tester) async {
    await tester.pumpWidget(host(seeded()..flights = []));
    await tester.pumpAndSettle();
    expect(find.textContaining('Consommation estimée'), findsNothing);
    expect(find.text('Aucun vol clôturé sur cette période.'), findsOneWidget);
  });

  testWidgets('un appui sur une ligne ouvre la fiche du vol', (tester) async {
    await tester.pumpWidget(host(seeded()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fuel-old-date')));
    await tester.pumpAndSettle();
    expect(tester.widget<FlightScreen>(find.byType(FlightScreen)).flight!.id, 'old');
  });
}
