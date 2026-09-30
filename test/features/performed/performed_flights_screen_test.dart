import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/performed/performed_flights_screen.dart';

import '../../support/fakes.dart';

final now = DateTime(2026, 10, 15, 12);

Widget host(AppUser me, List<Flight> flights, {void Function(Flight)? onOpen}) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      finance: FakeFinanceApi()..flights = flights,
      flights: FakeFlightApi()
        ..directory = [member('u1', 'DPS', 'instructeur'), member('u2', 'LDX', 'eleve')]
        ..aircraft = const [
          Aircraft(id: 'a1', registration: 'F-JABC', label: 'ULM 1', active: true),
          Aircraft(id: 'a2', registration: 'F-JXYZ', label: 'ULM 2', active: true),
        ],
      child: MaterialApp(
        home: PerformedFlightsScreen(me: me, now: () => now, onOpen: onOpen),
      ),
    );

Finder tileOf(String id) => find.byKey(Key('performed-$id'));

void main() {
  testWidgets('pilote : seulement ses vols validés, du jour ou passés, du mois', (tester) async {
    final me = testUser(uid: 'u2', profile: 'eleve');
    await tester.pumpWidget(host(me, [
      testFlight(id: 'mine', start: DateTime(2026, 10, 10, 9), crew: ['u1', 'u2'],
          isClosed: true, actualFlightMinutes: 75),
      testFlight(id: 'not-mine', start: DateTime(2026, 10, 11, 9), crew: ['u1'],
          isClosed: true, actualFlightMinutes: 60),
      testFlight(id: 'refused', start: DateTime(2026, 10, 9, 9), crew: ['u2'], status: 'refuse'),
      testFlight(id: 'expired', start: DateTime(2026, 10, 8, 9), crew: ['u2'], status: 'demande'),
      testFlight(id: 'deleted', start: DateTime(2026, 10, 7, 9), crew: ['u2'], deleted: true),
      testFlight(id: 'tomorrow', start: DateTime(2026, 10, 16, 9), crew: ['u2']),
    ]));
    await tester.pumpAndSettle();
    expect(tileOf('mine'), findsOneWidget);
    expect(find.text('Clôturé · 1 h 15'), findsOneWidget);
    for (final id in ['not-mine', 'refused', 'expired', 'deleted', 'tomorrow']) {
      expect(tileOf(id), findsNothing, reason: id);
    }
  });

  testWidgets('instructeur : voit aussi les vols des autres', (tester) async {
    final me = testUser(uid: 'u9', profile: 'instructeur');
    await tester.pumpWidget(host(me, [
      testFlight(id: 'a', start: DateTime(2026, 10, 10, 9), crew: ['u2']),
    ]));
    await tester.pumpAndSettle();
    expect(tileOf('a'), findsOneWidget);
  });

  testWidgets('vol du jour pas encore parti : à clôturer', (tester) async {
    final me = testUser(uid: 'u2', profile: 'eleve');
    await tester.pumpWidget(host(me, [
      testFlight(id: 'later', start: DateTime(2026, 10, 15, 14), crew: ['u2']),
    ]));
    await tester.pumpAndSettle();
    expect(tileOf('later'), findsOneWidget);
    expect(find.text('À clôturer'), findsOneWidget);
    expect(find.text('1 vol à clôturer'), findsOneWidget);
  });

  testWidgets('vol à clôturer hors période : compté, et visible avec « À clôturer seulement »',
      (tester) async {
    final me = testUser(uid: 'u2', profile: 'eleve');
    await tester.pumpWidget(host(me, [
      testFlight(id: 'this-month', start: DateTime(2026, 10, 12, 9), crew: ['u2']),
      testFlight(id: 'last-month', start: DateTime(2026, 9, 20, 9), crew: ['u2']),
      testFlight(id: 'closed', start: DateTime(2026, 10, 11, 9), crew: ['u2'],
          isClosed: true, actualFlightMinutes: 60),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('2 vols à clôturer'), findsOneWidget);
    expect(tileOf('this-month'), findsOneWidget);
    expect(tileOf('last-month'), findsNothing); // hors du mois en cours
    expect(tileOf('closed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('only-to-close')));
    await tester.pumpAndSettle();
    expect(tileOf('this-month'), findsOneWidget);
    expect(tileOf('last-month'), findsOneWidget);
    expect(tileOf('closed'), findsNothing);
    // Période désactivée tant que le filtre est coché.
    final from = tester.widget<OutlinedButton>(find.byKey(const Key('period-from')));
    expect(from.onPressed, isNull);
  });

  testWidgets('tri du plus récent au plus ancien', (tester) async {
    final me = testUser(uid: 'u2', profile: 'eleve');
    await tester.pumpWidget(host(me, [
      testFlight(id: 'old', start: DateTime(2026, 10, 2, 9), crew: ['u2']),
      testFlight(id: 'recent', start: DateTime(2026, 10, 12, 9), crew: ['u2']),
    ]));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(tileOf('recent')).dy,
        lessThan(tester.getTopLeft(tileOf('old')).dy));
  });

  testWidgets('filtre appareil', (tester) async {
    final me = testUser(uid: 'u2', profile: 'eleve');
    await tester.pumpWidget(host(me, [
      testFlight(id: 'on-a1', start: DateTime(2026, 10, 10, 9), crew: ['u2'], aircraftId: 'a1'),
      testFlight(id: 'on-a2', start: DateTime(2026, 10, 11, 9), crew: ['u2'],
          aircraftId: 'a2', aircraft: 'F-JXYZ'),
    ]));
    await tester.pumpAndSettle();
    expect(tileOf('on-a1'), findsOneWidget);
    expect(tileOf('on-a2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('aircraft-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ULM 2 (F-JXYZ)').last);
    await tester.pumpAndSettle();
    expect(tileOf('on-a1'), findsNothing);
    expect(tileOf('on-a2'), findsOneWidget);
  });

  testWidgets('un appui ouvre le vol', (tester) async {
    final me = testUser(uid: 'u2', profile: 'eleve');
    Flight? opened;
    await tester.pumpWidget(host(me, [
      testFlight(id: 'x', start: DateTime(2026, 10, 12, 9), crew: ['u2']),
    ], onOpen: (f) => opened = f));
    await tester.pumpAndSettle();
    await tester.tap(tileOf('x'));
    expect(opened?.id, 'x');
  });

  testWidgets('aucun vol : message vide', (tester) async {
    await tester.pumpWidget(host(testUser(uid: 'u2', profile: 'eleve'), []));
    await tester.pumpAndSettle();
    expect(find.text('Aucun vol effectué sur cette période.'), findsOneWidget);
  });
}
